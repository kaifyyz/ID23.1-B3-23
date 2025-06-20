require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'openssl'
require 'fileutils'
require 'thread'
require 'timeout'
require 'strscan'
require 'lemmatizer'
require 'logger'
require 'json'
require 'selenium-webdriver' # Для обработки JavaScript

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
      @url = ensure_url_scheme(url) # Используем метод для добавления схемы
      @uri = URI(@url)
      @progress_callback = progress_callback
      @debug_level = DEBUG_LEVELS[debug_level] || DEBUG_LEVELS[:info]
      
      # Инициализация логгера
      @logger = logger || Logger.new(LOG_FILE)
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}] #{severity}: #{msg}\n"
      end
      
      FileUtils.mkdir_p(HTML_DIR) unless File.directory?(HTML_DIR)
      @lemmatizer = Lemmatizer.new
      
      # Инициализация Selenium WebDriver для обработки JavaScript
      @driver = initialize_webdriver
      @debug_info = {
        connection_attempts: {},
        parsing_times: {},
        errors: []
      }
    end

    def parse(ports)
      # Анализ портов
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
          debug_log(:error, "Сетевая ошибка на порте #{port}: #{e.message}")
          results << create_error_result(port, "Ошибка сетевого соединения: #{e.message}")
        rescue OpenSSL::SSL::SSLError => e
          debug_log(:error, "Ошибка SSL на порте #{port}: #{e.message}")
          results << create_error_result(port, "Ошибка SSL-соединения: #{e.message}")
        rescue Timeout::Error => e
          debug_log(:error, "Тайм-аут на порте #{port}: #{e.message}")
          results << create_error_result(port, "Истекло время ожидания соединения")
        rescue Selenium::WebDriver::Error::WebDriverError => e
          debug_log(:error, "Ошибка WebDriver на порте #{port}: #{e.message}")
          results << create_error_result(port, "Ошибка обработки JavaScript: #{e.message}")
        rescue StandardError => e
          debug_log(:error, "Непредвиденная ошибка на порте #{port}: #{e.message}")
          results << create_error_result(port, e.message)
        end
      end
      
      results
    ensure
      @driver.quit if @driver # Закрытие WebDriver
    end
  
    def self.load_ports_from_file
      # Загрузка списка портов из файла
      default_ports = [443, 21, 22, 23, 25, 53, 79, 80, 110, 111, 119, 139, 513, 8000, 8080, 8888]
      
      begin
        if File.exist?(PORTS_FILE)
          File.readlines(PORTS_FILE)
              .map(&:strip)
              .reject(&:empty?)
              .map(&:to_i)
        else
          debug_log(:warn, "Файл портов не найден. Используется стандартный список портов.")
          default_ports
        end
      rescue SystemCallError => e
        debug_log(:error, "Не удалось прочитать файл портов: #{e.message}")
        default_ports
      end
    end
  
    def debug_log(level, message)
      # Логирование отладочной информации
      return unless DEBUG_LEVELS[level] <= @debug_level
      
      formatted_message = "[#{Time.now}][#{level.upcase}] #{message}"
      @logger.send(level, message)
      
      @debug_info[:errors] << formatted_message if level == :error
    end
  
    def get_debug_info
      # Получение отладочной информации
      {
        connection_stats: connection_stats,
        recent_errors: @debug_info[:errors].last(10),
        port_timings: @debug_info[:parsing_times],
        connection_attempts: @debug_info[:connection_attempts]
      }
    end
  
    def to_json_data(results)
      # Формирование JSON-данных для результатов
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
              code: result[:code_tokens],
              js: result[:js_tokens] # Добавлено для JavaScript-токенов
            },
            lemmas: {
              structure: result[:structure_lemmas],
              html: result[:html_lemmas],
              code: result[:code_lemmas],
              js: result[:js_lemmas] # Добавлено для JavaScript-лемм
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
  
    def initialize_webdriver
      # Инициализация Selenium WebDriver
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless') # Без графического интерфейса
      options.add_argument('--disable-gpu')
      options.add_argument('--no-sandbox')
      options.add_argument("--user-agent=#{USER_AGENT}")
      Selenium::WebDriver.for(:chrome, options: options)
    rescue StandardError => e
      debug_log(:error, "Ошибка инициализации WebDriver: #{e.message}")
      nil
    end
  
    def connection_stats
      # Статистика соединений
      {
        total_attempts: @debug_info[:connection_attempts].values.sum,
        successful_attempts: @debug_info[:connection_attempts].values.count { |v| v > 0 },
        average_parsing_time: calculate_average_parsing_time
      }
    end
  
    def calculate_average_parsing_time
      # Расчет среднего времени обработки
      times = @debug_info[:parsing_times].values
      return 0 if times.empty?
      times.sum.to_f / times.size
    end
  
    def process_port(port)
      # Обработка порта
      start_time = Time.now
      @debug_info[:connection_attempts][port] ||= 0
      @debug_info[:connection_attempts][port] += 1
  
      begin
        debug_log(:info, "Начало обработки порта #{port}")
        
        result = perform_port_processing(port)
        
        parsing_time = Time.now - start_time
        @debug_info[:parsing_times][port] = parsing_time
        debug_log(:info, "Порт #{port} обработан за #{parsing_time.round(2)} секунд")
        
        result
      rescue => e
        handle_port_error(port, e)
      end
    end
  
    def perform_port_processing(port)
      # Выполнение обработки порта
      @uri.port = port
      debug_log(:debug, "Подключение к #{@uri} через порт #{port}")
      
      html = fetch_html_with_retry(port)
      validate_and_parse_html(port, html)
    end
  
    def fetch_html_with_retry(port, max_retries = 3)
      # Повторная попытка получения HTML
      retries = 0
      begin
        html = fetch_dynamic_html(port)
        debug_log(:debug, "Успешно получен HTML с порта #{port}")
        html
      rescue => e
        retries += 1
        debug_log(:error, "Попытка #{retries} не удалась для порта #{port}: #{e.message}")
        retry if retries < max_retries
        raise e
      end
    end
  
    def fetch_dynamic_html(port)
      # Получение HTML с учетом JavaScript
      return fetch_html unless @driver # Падение на статический метод, если WebDriver не инициализирован
      
      @uri.port = port
      @driver.navigate.to(@uri.to_s)
      
      # Ожидание загрузки JavaScript (до 10 секунд)
      Selenium::WebDriver::Wait.new(timeout: 10).until do
        @driver.execute_script('return document.readyState') == 'complete'
      end
      
      # Получение HTML после выполнения JavaScript
      html = @driver.page_source
      html.force_encoding('UTF-8')
      html
    rescue Selenium::WebDriver::Error::WebDriverError => e
      debug_log(:error, "Ошибка WebDriver при загрузке страницы: #{e.message}")
      nil
    end
  
    def fetch_html
      # Статическое получение HTML через Net::HTTP
      raise 'Недопустимый URI' unless @uri.is_a?(URI)
  
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
      # Обработка HTTP-ответа
      max_redirects = MAX_REDIRECTS
      
      while response.is_a?(Net::HTTPRedirection) && max_redirects > 0
        debug_log(:info, "Следование редиректу на #{response['location']}")
        @uri = URI(response['location'])
        response = fetch_html
        max_redirects -= 1
      end
  
      case response
      when Net::HTTPSuccess
        response.body.force_encoding('UTF-8')
      else
        debug_log(:error, "HTTP-запрос не удался: #{response.code} #{response.message}")
        nil
      end
    end
  
    def validate_and_parse_html(port, html)
      # Валидация и разбор HTML
      if html.nil? || html.empty?
        debug_log(:error, "Получен пустой HTML с порта #{port}")
        return create_error_result(port, "Пустой HTML-контент")
      end
  
      html = html.to_s if html.respond_to?(:to_s)
      
      begin
        doc = Nokogiri::HTML(html)
        debug_log(:debug, "Успешно разобран HTML с порта #{port}")
        
        process_parsed_document(port, doc, html)
      rescue => e
        debug_log(:error, "Ошибка разбора HTML на порте #{port}: #{e.message}")
        create_error_result(port, "Не удалось разобрать HTML: #{e.message}")
      end
    end
  
    def process_parsed_document(port, doc, html)
      # Обработка разобранного документа
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
          js_tokens: tokenize_javascript(html), # Добавлено для токенов JavaScript
          structure_lemmas: safe_process_lemmas { lemmatize_structure(structure) },
          html_lemmas: safe_process_lemmas { lemmatize_html(html) },
          code_lemmas: safe_process_lemmas { lemmatize_code(html) },
          js_lemmas: safe_process_lemmas { lemmatize_javascript(html) } # Добавлено для лемм JavaScript
        }
      rescue => e
        debug_log(:error, "Ошибка обработки данных на порте #{port}: #{e.message}")
        debug_log(:error, e.backtrace.join("\n"))
        create_error_result(port, "Ошибка обработки данных: #{e.message}")
      end
    end
  
    def safe_process_lemmas
      # Безопасная обработка лемматизации
      begin
        yield
      rescue => e
        debug_log(:error, "Ошибка процесса лемматизации: #{e.message}")
        []
      end
    end
    
    def extract_title(doc)
      # Извлечение заголовка страницы
      doc.title.to_s.strip
    end
    
    def extract_meta_tags(doc)
      # Извлечение мета-тегов
      doc.css('meta').map do |meta|
        name = meta['name'] || meta['property'] || ''
        content = meta['content'] || ''
        
        name = name.to_s
        content = content.to_s
        
        { 
          name: name,
          content: content
        }
      end.reject { |tag| tag[:name].empty? && tag[:content].empty? }
    end
    
    def extract_structure(doc)
      # Извлечение структуры документа
      return [] unless doc&.at('html')
      
      structure = []
      traverse_node(doc.at('html'), structure)
      structure
    end
    
    def traverse_node(node, structure, depth = 0)
      # Рекурсивный обход узлов документа
      return unless node
      
      if node.element?
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
      # Токенизация структуры
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
      # Токенизация HTML
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
      # Токенизация кода (CSS/JavaScript)
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
  
    def tokenize_javascript(html)
      # Токенизация JavaScript из HTML
      tokens = []
      doc = Nokogiri::HTML(html)
      scripts = doc.css('script').map(&:content).join("\n")
      scanner = StringScanner.new(scripts)
      
      until scanner.eos?
        if scanner.scan(/\b(function|var|let|const|if|else|for|while|do|class|return|async|await)\b/)
          tokens << { type: :js_keyword, value: scanner.matched }
        elsif scanner.scan(/[a-zA-Z_]\w*/)
          tokens << { type: :js_identifier, value: scanner.matched }
        elsif scanner.scan(/[0-9]+(?:\.[0-9]+)?/)
          tokens << { type: :js_number, value: scanner.matched }
        elsif scanner.scan(/["'](?:\\.|[^"'])*["']/)
          tokens << { type: :js_string, value: scanner.matched }
        elsif scanner.scan(/[{}()\[\]]/)
          tokens << { type: :js_bracket, value: scanner.matched }
        elsif scanner.scan(/[+\-*\/=<>!&|;,.]/)
          tokens << { type: :js_operator, value: scanner.matched }
        elsif scanner.scan(/\s+/)
          tokens << { type: :js_whitespace, value: scanner.matched }
        else
          scanner.getch
        end
      end
      tokens
    end
  
    def lemmatize_javascript(html)
      # Лемматизация JavaScript
      tokens = tokenize_javascript(html)
      tokens.map do |token|
        case token[:type]
        when :js_identifier
          { type: :js_identifier_lemma, value: @lemmatizer.lemma(token[:value]) }
        when :js_string
          { type: :js_string_lemma, value: lemmatize_text(token[:value]).map { |l| l[:value] }.join(' ') }
        else
          token
        end
      end
    end
  
    def tokenize_text(text)
      # Токенизация текста
      text.split(/\s+/).map { |word| { type: :word, value: word } }
    end
  
    def lemmatize_structure(structure)
      # Лемматизация структуры
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
      # Лемматизация HTML
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
      # Лемматизация кода
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
      # Лемматизация текста
      text.split(/\s+/).map do |word|
        { type: :word_lemma, value: @lemmatizer.lemma(word.downcase) }
      end
    end
  
    def update_progress(index, total_ports)
      # Обновление прогресса
      return unless @progress_callback
      progress = ((index + 1).to_f / total_ports * 100).round
      @progress_callback.call(progress)
    end
  
    def handle_port_error(port, error)
      # Обработка ошибок порта
      error_message = "#{error.class}: #{error.message}"
      debug_log(:error, "Ошибка обработки порта #{port}: #{error_message}\n#{error.backtrace.join("\n")}")
      create_error_result(port, error_message)
    end
  
    def create_error_result(port, error_message)
      # Создание результата с ошибкой
      {
        port: port,
        error: error_message
      }
    end
  
    def save_html(html, port)
      # Сохранение HTML в файл
      filename = "#{HTML_DIR}/#{@uri.host}_port_#{port}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.html"
      File.write(filename, html)
      debug_log(:info, "HTML сохранен в файл: #{filename}")
    end
  
    def count_element_types(structure)
      # Подсчет типов элементов
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

    def ensure_url_scheme(url)
      # Добавление схемы к URL, если она отсутствует
      url.start_with?('http://') || url.start_with?('https://') ? url : "https://#{url}"
    end
  end
end
