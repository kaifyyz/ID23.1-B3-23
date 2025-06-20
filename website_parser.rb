module WebsiteParser
  class Parser
    USER_AGENT = 'Ruby/WebsiteParser'
    PORTS_FILE = 'ports.txt'
    HTML_DIR = 'parsed_html'
    DEFAULT_CONNECT_TIMEOUT = 15
    DEFAULT_READ_TIMEOUT = 30
    MAX_REDIRECTS = 5
    LOG_FILE = 'website_parser.log'

    DEBUG_LEVELS = {
      none: 0,
      error: 1,
      info: 2,
      debug: 3,
      trace: 4
    }

    attr_reader :uri, :debug_info, :logger

    def initialize(url, progress_callback: nil, logger: nil, debug_level: :info)
      @url = ensure_url_scheme(url)
      @uri = URI(@url)
      @progress_callback = progress_callback
      @debug_level = DEBUG_LEVELS[debug_level] || DEBUG_LEVELS[:info]
      
      @logger = logger || Logger.new(LOG_FILE)
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}] #{severity}: #{msg}\n"
      end
      
      FileUtils.mkdir_p(HTML_DIR) unless File.directory?(HTML_DIR)
      @lemmatizer = Lemmatizer.new
      
      @debug_info = {
        connection_attempts: {},
        parsing_times: {},
        errors: []
      }
    end

    def parse(ports)
      results = []
      total_ports = ports.size
      
      ports.each_with_index do |port, index|
        update_progress(index, total_ports)
        
        begin
          Timeout.timeout(DEFAULT_CONNECT_TIMEOUT + DEFAULT_READ_TIMEOUT) do
            result = process_port(port)
            results << result
          end
        rescue SocketError => e
          debug_log(:error, "Network error on port #{port}: #{e.message}")
          results << create_error_result(port, "Network connection failed: #{e.message}")
        rescue OpenSSL::SSL::SSLError => e
          debug_log(:error, "SSL error on port #{port}: #{e.message}")
          results << create_error_result(port, "SSL connection error: #{e.message}")
        rescue Timeout::Error => e
          debug_log(:error, "Timeout on port #{port}: #{e.message}")
          results << create_error_result(port, "Connection timed out")
        rescue StandardError => e
          debug_log(:error, "Unexpected error on port #{port}: #{e.message}")
          results << create_error_result(port, e.message)
        end
      end
      
      results
    end
  
    def self.load_ports_from_file
      default_ports = [443, 21, 22, 23, 25, 53, 79, 80, 110, 111, 119, 139, 513, 8000, 8080, 8888]
      
      begin
        if File.exist?(PORTS_FILE)
          File.readlines(PORTS_FILE)
            .map(&:strip)
            .reject(&:empty?)
            .map(&:to_i)
        else
          debug_log(:warn, "Ports file not found. Using default ports list.")
          default_ports
        end
      rescue SystemCallError => e
        debug_log(:error, "Could not read ports file: #{e.message}")
        default_ports
      end
    end
  
    def debug_log(level, message)
      return unless DEBUG_LEVELS[level] <= @debug_level
      
      formatted_message = "[#{Time.now}][#{level.upcase}] #{message}"
      @logger.send(level, message)
      
      @debug_info[:errors] << formatted_message if level == :error
    end
  
    def get_debug_info
      {
        connection_stats: connection_stats,
        recent_errors: @debug_info[:errors].last(10),
        port_timings: @debug_info[:parsing_times],
        connection_attempts: @debug_info[:connection_attempts]
      }
    end
  
    def to_json_data(results)
      json_data = results.map do |result|
        {
          port: result[:port],
          timestamp: Time.now.iso8601,
          url: @url,
          error: result[:error],
          analysis: {
            title: result[:title],
            meta_tags: result[:meta_tags],
            structure_stats: {
              total_elements: result[:structure]&.length || 0,
              element_types: count_element_types(result[:structure])
            },
            tokens: {
              structure: result[:structure_tokens],
              html: result[:html_tokens],
              code: result[:code_tokens]
            },
            lemmas: {
              structure: result[:structure_lemmas],
              html: result[:html_lemmas],
              code: result[:code_lemmas]
            }
          }
        }
      end
      
      {
        analysis_metadata: {
          total_ports_analyzed: results.length,
          analysis_date: Time.now.iso8601,
          target_url: @url,
          successful_ports: results.count { |r| !r[:error] },
          failed_ports: results.count { |r| r[:error] }
        },
        results: json_data
      }
    end
  
    private
  
    def connection_stats
      {
        total_attempts: @debug_info[:connection_attempts].values.sum,
        successful_attempts: @debug_info[:connection_attempts].values.count { |v| v > 0 },
        average_parsing_time: calculate_average_parsing_time
      }
    end
  
    def calculate_average_parsing_time
      times = @debug_info[:parsing_times].values
      return 0 if times.empty?
      times.sum.to_f / times.size
    end
  
    def process_port(port)
      start_time = Time.now
      @debug_info[:connection_attempts][port] ||= 0
      @debug_info[:connection_attempts][port] += 1
  
      begin
        debug_log(:info, "Starting processing of port #{port}")
        
        result = perform_port_processing(port)
        
        parsing_time = Time.now - start_time
        @debug_info[:parsing_times][port] = parsing_time
        debug_log(:info, "Port #{port} processed in #{parsing_time.round(2)} seconds")
        
        result
      rescue => e
        handle_port_error(port, e)
      end
    end
  
    def perform_port_processing(port)
      @uri.port = port
      debug_log(:debug, "Connecting to #{@uri} through port #{port}")
      
      html = fetch_html_with_retry(port)
      validate_and_parse_html(port, html)
    end
  
    def fetch_html_with_retry(port, max_retries = 3)
      retries = 0
      begin
        html = fetch_html
        debug_log(:debug, "Successfully fetched HTML from port #{port}")
        html
      rescue => e
        retries += 1
        debug_log(:error, "Attempt #{retries} failed for port #{port}: #{e.message}")
        retry if retries < max_retries
        raise e
      end
    end
  
    def fetch_html
      raise 'Invalid URI' unless @uri.is_a?(URI)
  
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.open_timeout = DEFAULT_CONNECT_TIMEOUT
      http.read_timeout = DEFAULT_READ_TIMEOUT
  
      if @uri.scheme == 'https'
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.ca_file = OpenSSL::X509::DEFAULT_CERT_FILE
      end
  
      request = Net::HTTP::Get.new(@uri.request_uri)
      request['User-Agent'] = USER_AGENT
      request['Accept-Language'] = 'en-US,en;q=0.9'
      request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
  
      response = http.request(request)
      handle_http_response(response)
    end
  
    def handle_http_response(response)
      max_redirects = MAX_REDIRECTS
      
      while response.is_a?(Net::HTTPRedirection) && max_redirects > 0
        debug_log(:info, "Following redirect to #{response['location']}")
        @uri = URI(response['location'])
        response = fetch_html
        max_redirects -= 1
      end
  
      case response
      when Net::HTTPSuccess
        response.body.force_encoding('UTF-8')
      else
        debug_log(:error, "HTTP request failed: #{response.code} #{response.message}")
        nil
      end
    end
  
    def validate_and_parse_html(port, html)
      if html.nil? || html.empty?
        debug_log(:error, "Empty HTML content received from port #{port}")
        return create_error_result(port, "Empty HTML content")
      end
  
      html = html.to_s if html.respond_to?(:to_s)
      
      begin
        doc = Nokogiri::HTML(html)
        debug_log(:debug, "Successfully parsed HTML from port #{port}")
        
        process_parsed_document(port, doc, html)
      rescue => e
        debug_log(:error, "HTML parsing error on port #{port}: #{e.message}")
        create_error_result(port, "Unable to parse HTML: #{e.message}")
      end
    end
  
    def process_parsed_document(port, doc, html)
      begin
        save_html(html, port)
        
        structure = extract_structure(doc)
        
        {
          port: port,
          title: extract_title(doc),
          meta_tags: extract_meta_tags(doc),
          structure: structure,
          full_html: html,
          structure_tokens: tokenize_structure(structure),
          html_tokens: tokenize_html(html),
          code_tokens: tokenize_code(html),
          structure_lemmas: safe_process_lemmas { lemmatize_structure(structure) },
          html_lemmas: safe_process_lemmas { lemmatize_html(html) },
          code_lemmas: safe_process_lemmas { lemmatize_code(html) }
        }
      rescue => e
        debug_log(:error, "Data processing error on port #{port}: #{e.message}")
        debug_log(:error, e.backtrace.join("\n"))
        create_error_result(port, "Error processing data: #{e.message}")
      end
    end
  
    def safe_process_lemmas
      begin
        yield
      rescue => e
        debug_log(:error, "Lemmatization process failed: #{e.message}")
        [] # Return empty array if lemmatization fails
      end
    end
    
    def extract_title(doc)
      # Safely extract title with fallback to empty string
      doc.title.to_s.strip
    end
    
    def extract_meta_tags(doc)
      doc.css('meta').map do |meta|
        name = meta['name'] || meta['property'] || ''
        content = meta['content'] || ''
        
        # Ensure we're working with strings
        name = name.to_s
        content = content.to_s
        
        { 
          name: name,
          content: content
        }
      end.reject { |tag| tag[:name].empty? && tag[:content].empty? }
    end
    
    def extract_structure(doc)
      return [] unless doc&.at('html')
      
      structure = []
      traverse_node(doc.at('html'), structure)
      structure
    end
    
    def traverse_node(node, structure, depth = 0)
      return unless node
      
      if node.element?
        # Convert attributes to a safe hash format
        attributes = node.attributes.transform_values { |attr| attr.value.to_s }
        
        element = { 
          name: node.name, 
          attributes: attributes, 
          depth: depth 
        }
        structure << element
        
        node.children.each { |child| traverse_node(child, structure, depth + 1) }
      elsif node.text? && !node.content.to_s.strip.empty?
        structure << { text: node.content.to_s.strip, depth: depth }
      end
    end
    
    def tokenize_structure(structure)
      return [] unless structure
      
      tokens = []
      structure.each do |element|
        if element[:text]
          tokens.concat(tokenize_text(element[:text].to_s))
        elsif element[:name]
          tokens << { type: :tag_open, value: element[:name].to_s }
          element[:attributes]&.each do |name, value|
            tokens << { type: :attribute, value: "#{name}=\"#{value}\"" }
          end
          tokens << { type: :tag_close, value: element[:name].to_s }
        end
      end
      tokens
    end
  
    def tokenize_html(html)
      tokens = []
      scanner = StringScanner.new(html)
      
      until scanner.eos?
        if scanner.scan(/\s+/)
          tokens << { type: :whitespace, value: scanner.matched }
        elsif scanner.scan(/<[^>]+>/)
          tokens << { type: :tag, value: scanner.matched }
        elsif scanner.scan(/[^<]+/)
          tokens << { type: :text, value: scanner.matched }
        else
          scanner.getch
        end
      end
      tokens
    end
  
    def tokenize_code(html)
      tokens = []
      scanner = StringScanner.new(html)
  
      until scanner.eos?
        if scanner.scan(/\b(function|var|let|const|if|else|for|while|do|class|return)\b/)
          tokens << { type: :keyword, value: scanner.matched }
        elsif scanner.scan(/[a-zA-Z_]\w*/)
          tokens << { type: :identifier, value: scanner.matched }
        elsif scanner.scan(/[0-9]+(?:\.[0-9]+)?/)
          tokens << { type: :number, value: scanner.matched }
        elsif scanner.scan(/["'](?:\\.|[^"'])*["']/)
          tokens << { type: :string, value: scanner.matched }
        elsif scanner.scan(/[{}()\[\]]/)
          tokens << { type: :bracket, value: scanner.matched }
        elsif scanner.scan(/[+\-*\/=<>!&|;,.]/)
          tokens << { type: :operator, value: scanner.matched }
        elsif scanner.scan(/\s+/)
          tokens << { type: :whitespace, value: scanner.matched }
        else
          scanner.getch
        end
      end
      tokens
    end
  
    def tokenize_text(text)
      text.split(/\s+/).map { |word| { type: :word, value: word } }
    end
  
    def lemmatize_structure(structure)
      lemmas = []
      structure.each do |element|
        if element[:text]
          lemmas.concat(lemmatize_text(element[:text]))
        elsif element[:name]
          lemmas << { type: :tag_lemma, value: @lemmatizer.lemma(element[:name]) }
          element[:attributes]&.each do |name, value|
            lemmas << { type: :attribute_lemma, value: "#{@lemmatizer.lemma(name)}=#{@lemmatizer.lemma(value)}" }
          end
        end
      end
      lemmas
    end
  
    def lemmatize_html(html)
      tokens = tokenize_html(html)
      tokens.map do |token|
        case token[:type]
        when :text
          { type: :text_lemma, value: lemmatize_text(token[:value]).map { |l| l[:value] }.join(' ') }
        when :tag
          { type: :tag_lemma, value: @lemmatizer.lemma(token[:value].gsub(/[<>\/]/, '')) }
        else
          token
        end
      end
    end
  
    def lemmatize_code(code)
      tokens = tokenize_code(code)
      tokens.map do |token|
        case token[:type]
        when :identifier
          { type: :identifier_lemma, value: @lemmatizer.lemma(token[:value]) }
        when :string
          { type: :string_lemma, value: lemmatize_text(token[:value]).map { |l| l[:value] }.join(' ') }
        else
          token
        end
      end
    end
  
    def lemmatize_text(text)
      text.split(/\s+/).map do |word|
        { type: :word_lemma, value: @lemmatizer.lemma(word.downcase) }
      end
    end
  
    def update_progress(index, total_ports)
      return unless @progress_callback
      progress = ((index + 1).to_f / total_ports * 100).round
      @progress_callback.call(progress)
    end
  
    def handle_port_error(port, error)
      error_message = "#{error.class}: #{error.message}"
      debug_log(:error, "Port #{port} processing error: #{error_message}\n#{error.backtrace.join("\n")}")
      create_error_result(port, error_message)
    end
  
    def create_error_result(port, error_message)
      {
        port: port,
        error: error_message
      }
    end
  
    def log_error(port, message)
      @logger.error("Port #{port}: #{message}")
    end
  
    def ensure_url_scheme(url)
      url = "https://#{url}" unless url.start_with?('http://', 'https://')
      url
    end
    
    def fetch_html
      begin
        # Проверка корректности @uri
        raise 'Invalid URI' unless @uri.is_a?(URI)
    
        http = Net::HTTP.new(@uri.host, @uri.port)
        http.open_timeout = DEFAULT_CONNECT_TIMEOUT
        http.read_timeout = DEFAULT_READ_TIMEOUT
    
        if @uri.scheme == 'https'
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.ca_file = OpenSSL::X509::DEFAULT_CERT_FILE
        end
    
        request = Net::HTTP::Get.new(@uri.request_uri)
        request['User-Agent'] = USER_AGENT
        request['Accept-Language'] = 'en-US,en;q=0.9'
        request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    
        response = http.request(request)
    
        max_redirects = MAX_REDIRECTS
        while response.is_a?(Net::HTTPRedirection) && max_redirects > 0
          redirect_url = response['location']
          @uri = URI(redirect_url)
    
          http = Net::HTTP.new(@uri.host, @uri.port)
          http.use_ssl = true if @uri.scheme == 'https'
    
          response = http.request(Net::HTTP::Get.new(@uri.request_uri))
          max_redirects -= 1
        end
    
        case response
        when Net::HTTPSuccess
          if response.body.is_a?(String)
            response.body.force_encoding('UTF-8')
          else
            @logger.error "Received invalid response body"
            nil
          end
        else
          @logger.error "HTTP request failed: #{response.code} #{response.message}"
          nil
        end
      rescue => e
        # Выводим сообщение об ошибке и трассировку стека
        @logger.error "An error occurred: #{e.message}"
        @logger.error e.backtrace.join("\n")
        nil # Возвращаем nil или другое значение, если нужно
      end
    end
  
    def some_method
      begin
        # Ваш код, который может вызвать ошибку
        doc = Nokogiri::HTML(html)
        # Остальной код
      rescue => e
        @logger.error "An error occurred: #{e.message}"
        @logger.error e.backtrace.join("\n")
        nil # или другие действия для обработки ошибки
      end
    end
  
    def save_html(html, port)
      filename = "#{HTML_DIR}/#{@uri.host}_port_#{port}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.html"
      File.write(filename, html)
      @logger.info("HTML saved to file: #{filename}")
    end
  
    def extract_meta_tags(doc)
      doc.css('meta').map do |meta|
        { 
          name: (meta['name'] || meta['property'] || ''), 
          content: (meta['content'] || '')
        }
      end.reject { |tag| tag[:name].empty? && tag[:content].empty? }
    end
  
    def extract_structure(doc)
      structure = []
      traverse_node(doc.at('html'), structure)
      structure
    end
  
    def traverse_node(node, structure, depth = 0)
      if node.element?
        element = { name: node.name, attributes: node.attributes.to_h, depth: depth }
        structure << element
        node.children.each { |child| traverse_node(child, structure, depth + 1) }
      elsif node.text? && !node.content.strip.empty?
        structure << { text: node.content.strip, depth: depth }
      end
    end
  
    def tokenize_structure(structure)
      tokens = []
      structure.each do |element|
        if element[:text]
          tokens.concat(tokenize_text(element[:text]))
        elsif element[:name]
          tokens << { type: :tag_open, value: element[:name] }
          element[:attributes]&.each do |name, value|
            tokens << { type: :attribute, value: "#{name}=\"#{value}\"" }
          end
          tokens << { type: :tag_close, value: element[:name] }
        end
      end
      tokens
    end
  
    def tokenize_html(html)
      tokens = []
      scanner = StringScanner.new(html)
    
      until scanner.eos?
        if scanner.scan(/\s+/)
          tokens << { type: :whitespace, value: scanner.matched }
        elsif scanner.scan(/<[^>]+>/)
          tokens << { type: :tag, value: scanner.matched }
        elsif scanner.scan(/[^<]+/)
          tokens << { type: :text, value: scanner.matched }
        else
          scanner.getch
        end
      end
      tokens
    end
  
    def tokenize_code(code)
      tokens = []
      scanner = StringScanner.new(code)
  
      until scanner.eos?
        if scanner.scan(/\b(function|var|let|const|if|else|for|while|do|class|return)\b/)
          tokens << { type: :keyword, value: scanner.matched }
        elsif scanner.scan(/[a-zA-Z_]\w*/)
          tokens << { type: :identifier, value: scanner.matched }
        elsif scanner.scan(/[0-9]+(?:\.[0-9]+)?/)
          tokens << { type: :number, value: scanner.matched }
        elsif scanner.scan(/["'](?:\\.|[^"'])*["']/)
          tokens << { type: :string, value: scanner.matched }
        elsif scanner.scan(/[{}()\[\]]/)
          tokens << { type: :bracket, value: scanner.matched }
        elsif scanner.scan(/[+\-*\/=<>!&|;,.]/)
          tokens << { type: :operator, value: scanner.matched }
        elsif scanner.scan(/\s+/)
          tokens << { type: :whitespace, value: scanner.matched }
        else
          scanner.getch
        end
      end
      tokens
    end
  
    def tokenize_text(text)
      text.split(/\s+/).map { |word| { type: :word, value: word } }
    end
  
    def self.log_action(message)
      puts "[#{Time.now}] #{message}"
    end
  
    def log_action(message)
      self.class.log_action(message)
    end
  
    def lemmatize_structure(structure)
      lemmas = []
      structure.each do |element|
        if element[:text]
          lemmas.concat(lemmatize_text(element[:text]))
        elsif element[:name]
          lemmas << { type: :tag_lemma, value: @lemmatizer.lemma(element[:name].to_s) }
          element[:attributes]&.each do |name, value|
            # Convert both name and value to strings before lemmatization
            attr_name = name.to_s
            attr_value = value.respond_to?(:value) ? value.value : value.to_s
            lemmas << { 
              type: :attribute_lemma, 
              value: "#{@lemmatizer.lemma(attr_name)}=#{@lemmatizer.lemma(attr_value)}"
            }
          end
        end
      end
      lemmas
    end
  
    def lemmatize_html(html)
      tokens = tokenize_html(html)
      tokens.map do |token|
        case token[:type]
        when :text
          { type: :text_lemma, value: lemmatize_text(token[:value]).map { |l| l[:value] }.join(' ') }
        when :tag
          { type: :tag_lemma, value: @lemmatizer.lemma(token[:value].gsub(/[<>\/]/, '')) }
        else
          token
        end
      end
    end
  
    def lemmatize_code(code)
      tokens = tokenize_code(code)
      tokens.map do |token|
        case token[:type]
        when :identifier
          { type: :identifier_lemma, value: @lemmatizer.lemma(token[:value]) }
        when :string
          { type: :string_lemma, value: lemmatize_text(token[:value]).map { |l| l[:value] }.join(' ') }
        else
          token
        end
      end
    end
  
    def lemmatize_text(text)
      text.split(/\s+/).map do |word|
        { type: :word_lemma, value: @lemmatizer.lemma(word.downcase) }
      end
    end
  
  
    def count_element_types(structure)
      return {} unless structure
      
      element_counts = Hash.new(0)
      structure.each do |element|
        if element[:name]
          element_counts[element[:name]] += 1
        elsif element[:text]
          element_counts['text_nodes'] += 1
        end
      end
      element_counts
    end
  end
end
