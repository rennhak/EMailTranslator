#!/usr/bin/ruby
#!/usr/bin/ruby1.9.1

#####
#
# This script is an intelligent wrapper for various translation API services such as Google
# translate etc.
#
# (c) 2010-2011, Bjoern Rennhak
#
############


# = Libraries
require 'rubygems'
require 'optparse' 
require 'optparse/time' 
require 'ostruct'

# = Translation
require 'to_lang' # google translate


# = EMailTranslator is the main class which handles commandline interface and other central tasks
class EMailTranslator # {{{

  def initialize options = nil, pipe_input = nil

    @options      = options
    @pipe_input   = pipe_input.to_s.chomp

    @services     = %w[ google ]

    # Minimal configuration
    @config               = OpenStruct.new


    unless( options.nil? )

      # File.open( "/tmp/dump", "w" ) { |f| f.write @pipe_input  }
      
      message :success, "Starting #{__FILE__} run"
      message :info, "Colorizing output as requested" if( @options.colorize )

      message :info, "Translating from (#{@options.from}) - to (#{@options.to}) - message (#{@options.message}) - pipe_input (#{@pipe_input})"

      ####
      #
      # Main Control Flow
      #
      ##########


      #### FIXME: This is messy quickhack mode, rewrite this properly

      # Remove email header
      pi      = @pipe_input.split( "\n" )

      header  = []
      header_end = false
      pi.collect! do |line|
        ret_val = line

        unless( header_end )
          # header
          header << line
          ret_val = nil
        end

        if( header_end == false )
          header_end = true if( line =~ %r{content-type}i )
        end

        ret_val
      end

      pi.compact!

      # remove email addresses and urls
      pi = pi.join("\n")
      urls = pi.split(/\s+/).find_all { |u| u =~ /^https?:/ }
      urls.each { |u| pi.gsub!( u, "<URL WAS NOT SENT TO TRANSLATION SERVICE SEE ORIGINAL MESSAGE>" ) }


      # THIS IS NOT WORKING RELIABLY
      # matching this is not nice, need to hack something together for the RFC
      # http://www.buildingwebapps.com/articles/79182-validating-email-addresses-with-ruby
      email_regex = Regexp.new( /^[a-zA-Z][\w\.-]*[a-zA-Z0-9](@[a-zA-Z0-9][\w\.-]*[a-zA-Z0-9]\.[a-zA-Z][a-zA-Z\.]*[a-zA-Z])$/  )
      emails = pi.scan( email_regex ).uniq.to_a
      emails.each { |e| pi.gsub!( e.to_s, "<DOMAIN WAS NOT SENT TO TRANSLATION SERVICE SEE ORIGINAL MESSAGE>" ) }

      pi = pi.split( "\n" )


      # Google API expects HTML Tags to preserve e.g. newlines
      @pipe_input = pi.join( "<br>" )

      # File.open( "/tmp/header", "w" ) { |f| f.write header.join("\n").to_s }
      # File.open( "/tmp/body", "w" ) { |f| f.write @pipe_input }
      
      google_translate_init if( @options.service == "google" )
      puts ""
      puts "-------- TRANSLATION BEGIN ---------"
      puts ""
      
      result = translate( ( ( @pipe_input.nil? ) ? ( @options.message ) : ( @pipe_input ) ), @options.from, @options.to )
      result.gsub!( "<br>", "\n" )

      File.open( "/tmp/translated", "w" ) { |f| f.write result.to_s }

      puts result

      puts ""
      puts "-------- TRANSLATION END   ---------"
      puts ""

      message :success, "Finished #{__FILE__} run"
    end

  end # of initialize }}}


  # = The function 'parse_cmd_arguments' takes a number of arbitrary commandline arguments and parses them into a proper data structure via optparse
  # @param args Ruby's STDIN.ARGS from commandline
  # @returns Ruby optparse package options hash object
  def parse_cmd_arguments( args ) # {{{

    options               = OpenStruct.new

    # Define default options
    options.encoding      = "UTF-8"
    options.verbose       = false
    options.colorize      = false
		options.debug					= false

    pristine_options      = options.dup

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{__FILE__.to_s} [options]"

      #opts.separator ""
      #opts.separator "General options:"

      opts.separator ""
      opts.separator "Specific options:"

      # Boolean switch.
      opts.on("-v", "--verbose", "Run verbosely") do |v|
        options.verbose = v
      end

      # Boolean switch.
      opts.on("-q", "--quiet", "Run quietly, don't output anything except results") do |q|
        options.quiet = q
      end

      # Boolean switch.
      opts.on( "--debug", "Print verbose output and more debugging") do |d|
        options.debug = d
      end

      opts.separator ""
      opts.separator "Common options:"

      
      # Boolean switch.
      opts.on("-c", "--colorize", "Colorizes the output of the script for easier reading") do |c|
        options.colorize = c
      end

      opts.on( "-u", "--use-service NAME", @services, "Use this service for translation (OPT: #{ @services.collect { |n| n.to_s }.join(', ') })" ) do |s|
        options.service = s
      end

      opts.on( "-k", "--key STRING", "API Key for the webservice" ) do |k|
        options.key = k
      end

      opts.on( "-m", "--message STRING", "Message which should be translated" ) do |m|
        options.message = m
      end

      opts.on( "-f", "--from LANG", "Translate from this language, e.g. english" ) do |f|
        options.from = f
      end

      opts.on( "-t", "--to LANG", "Translate to this language, e.g. german" ) do |t|
        options.to = t
      end


      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      # Another typical switch to print the version.
      opts.on_tail("--version", "Show version") do
        puts OptionParser::Version.join('.')
        exit
      end
    end

    opts.parse!(args)

    # Show opts if we have no cmd arguments
    if( options == pristine_options )
      puts opts
      puts ""
      puts "(EE) You need To define at least API key and languages ..  '#{__FILE__}'\n\n"
    	exit
		end

    options
  end # of parse_cmd_arguments }}}


  # = The function colorize takes a message and wraps it into standard color commands such as for bash.
  # @param color String, of the colorname in plain english. e.g. "LightGray", "Gray", "Red", "BrightRed"
  # @param message String, of the message which should be wrapped
  # @returns String, colorized message string
  # WARNING: Might not work for your terminal
  # FIXME: Implement bold behavior
  # FIXME: This method is currently b0rked
  def colorize color, message # {{{

    # Black       0;30     Dark Gray     1;30
    # Blue        0;34     Light Blue    1;34
    # Green       0;32     Light Green   1;32
    # Cyan        0;36     Light Cyan    1;36
    # Red         0;31     Light Red     1;31
    # Purple      0;35     Light Purple  1;35
    # Brown       0;33     Yellow        1;33
    # Light Gray  0;37     White         1;37

    colors  = { 
      "Gray"        => "\e[1;30m",
      "LightGray"   => "\e[0;37m",
      "Cyan"        => "\e[0;36m",
      "LightCyan"   => "\e[1;36m",
      "Blue"        => "\e[0;34m",
      "LightBlue"   => "\e[1;34m",
      "Green"       => "\e[0;32m",
      "LightGreen"  => "\e[1;32m",
      "Red"         => "\e[0;31m",
      "LightRed"    => "\e[1;31m",
      "Purple"      => "\e[0;35m",
      "LightPurple" => "\e[1;35m",
      "Brown"       => "\e[0;33m",
      "Yellow"      => "\e[1;33m",
      "White"       => "\e[1;37m"
    }
    nocolor    = "\e[0m"

    colors[ color ] + message + nocolor
  end # of def colorize }}}


  # = The function message will take a message as argument as well as a level (e.g. "info", "ok", "error", "question", "debug") which then would print 
  #   ( "(--) msg..", "(II) msg..", "(EE) msg..", "(??) msg..")
  # @param level Ruby symbol, can either be :info, :success, :error or :question
  # @param msg String, which represents the message you want to send to stdout (info, ok, question) stderr (error)
  # Helpers: colorize
  def message level, msg # {{{

    symbols = {
      :info      => "(--)",
      :success   => "(II)",
      :error     => "(EE)",
      :question  => "(??)",
			:debug		 => "(++)"
    }

    raise ArugmentError, "Can't find the corresponding symbol for this message level (#{level.to_s}) - is the spelling wrong?" unless( symbols.key?( level )  )

    unless( @options.quiet )
      if( @options.colorize )
        if( level == :error )
          STDERR.puts colorize( "LightRed", "#{symbols[ level ].to_s} #{msg.to_s}" )
        else
          STDOUT.puts colorize( "LightGreen", "#{symbols[ level ].to_s} #{msg.to_s}" ) if( level == :success )
          STDOUT.puts colorize( "LightCyan", "#{symbols[ level ].to_s} #{msg.to_s}" ) if( level == :question )
          STDOUT.puts colorize( "Brown", "#{symbols[ level ].to_s} #{msg.to_s}" ) if( level == :info )
          STDOUT.puts colorize( "LightBlue", "#{symbols[ level ].to_s} #{msg.to_s}" ) if( level == :debug and @options.debug )
        end
      else
        if( level == :error )
          STDERR.puts "#{symbols[ level ].to_s} #{msg.to_s}" 
        else
          STDOUT.puts "#{symbols[ level ].to_s} #{msg.to_s}" if( level == :success )
          STDOUT.puts "#{symbols[ level ].to_s} #{msg.to_s}" if( level == :question )
          STDOUT.puts "#{symbols[ level ].to_s} #{msg.to_s}" if( level == :info )
          STDOUT.puts "#{symbols[ level ].to_s} #{msg.to_s}" if( level == :debug and @options.debug )
        end
      end # of if( @config.colorize )

    end # of unless( @options.quiet )

  end # of def message }}}


  # = The function google_tranlsate_init initializes the google tranlate api/ to_lang gem
  def google_translate_init key = @options.key # {{{
    # here we could e.g. direct json calls instead
    ToLang.start key
  end # of def google_tranlsate_init }}}


  # = The translate function is a simple wrapper which takes input arguments and translates
  # according to from and to
  # @param from String, indicator from which language we want to translate in natural english, e.g. like in the to_lang gem
  # @param to String, indicator to which language we want to translate in natural english, e.g. like in the to_lang gem
  # @returns String, with the translated result
  def translate message, from = "japanese", to = "english" # {{{
    # message.translate( to, from )
    
    # old version:
    eval "\"#{message}\".from_#{from}_to_#{to}"

    #message.split( "\n" ) do |m|
    #  eval "\"#{m}\".from_#{from}_to_#{to}"
    #end
  end # of def translate }}}


end # of class EMailTranslator }}}


# = Direct invocation
if __FILE__ == $0


  # Is input currently from tty or from pipe?
  if( STDIN.tty? )
    # tty mode
    options = EMailTranslator.new.parse_cmd_arguments( ARGV )
    emt     = EMailTranslator.new( options )
  else
    # pipe mode
    input     = STDIN.read
    options = EMailTranslator.new.parse_cmd_arguments( ARGV )
    emt     = EMailTranslator.new( options, input )
  end # of if( STDIN.tty? )

end # of if __FILE__ == $0
