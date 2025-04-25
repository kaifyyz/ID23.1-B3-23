# RAIHtml.rb
require 'rumale'
require 'json'
require 'nokogiri'
require 'numo/narray'
require 'open-uri'
require 'fileutils'
require 'uri'
require 'webrick'
require 'zlib'

require_relative 'rai_html/analyzer'
require_relative 'rai_html/server'
require_relative 'rai_html/html_generator'

module RAIHtml
  class Main
    def initialize(txt_file_path, base_url = nil)
      @analyzer = Analyzer.new(txt_file_path, base_url)
      @server = Server.new(@analyzer.output_dir)
      @html_generator = HtmlGenerator.new(@analyzer)
    end

    def execute
      @analyzer.execute
      @html_generator.create_index_html
      @analyzer.verify_index_html
    end

    def start_server(port = 8000)
      @server.start(port)
    end

    def output_dir
      @analyzer.output_dir
    end
  end
end

# Command-line interface
if __FILE__ == $0
  if ARGV.length < 1
    puts "Usage: ruby #{$0} <txt_file_path> [base_url] [--server]"
    exit 1
  end

  txt_file_path = ARGV[0]
  base_url = ARGV[1] unless ARGV[1] == '--server'
  start_server = ARGV.include?('--server')

  begin
    analyzer = RAIHtml::Main.new(txt_file_path, base_url)
    analyzer.execute

    if start_server
      puts "\nStarting local server..."
      analyzer.start_server
    else
      puts "\nTo view results, open: #{File.join(Dir.pwd, analyzer.output_dir, 'index.html')}"
    end
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace
    exit 1
  end
end