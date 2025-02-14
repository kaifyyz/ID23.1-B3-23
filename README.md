require 'fox16'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'openssl'

include Fox

class WebsiteParser
  USER_AGENT = 'Ruby/Nokogiri'
  DEFAULT_PORTS = [443,21,22,23,25,53,79,80,110,111,119,139,513,8000,8080,8888]

  def initialize(url)
    @url = ensure_url_scheme(url)
    @uri = URI(@url)
  end

  def parse(ports = DEFAULT_PORTS)
    results = []
    ports.each do |port|
      begin
        @uri.port = port
        log_action("Пытаюсь подключиться к #{@uri} через порт #{port}")
        html = fetch_html
        doc = Nokogiri::HTML(html)
        results << {
          port: port,
          title: doc.title,
          meta_tags: extract_meta_tags(doc),
          structure: extract_structure(doc),
          full_html: html
        }
      rescue StandardError => e
        results << {
          port: port,
          error: "Ошибка при обработке #{@uri} через порт #{port}: #{e.message}"
        }
      end
    end
    results
  end

  private

  def ensure_url_scheme(url)
    url.start_with?('http://', 'https://') ? url : "https://#{url}"
  end

  def fetch_html
    log_action("Загрузка HTML с #{@uri}")
    response = Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https', verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
      request = Net::HTTP::Get.new(@uri)
      request['User-Agent'] = USER_AGENT
      http.request(request)
    end
    
    case response
    when Net::HTTPSuccess
      response.body.force_encoding('UTF-8')
    else
      raise "HTTP запрос не удался: #{response.code} #{response.message}"
    end
  end

  def extract_meta_tags(doc)
    doc.css('meta').map do |meta|
      { name: (meta['name'] || meta['property']), content: meta['content'] }
    end
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

  def log_action(message)
    puts "[#{Time.now}] #{message}"
  end
end

class CLIInterface
  def initialize
    @parser = nil
  end

  def run
    loop do
      print "Введите команду (или 'help' для списка команд): "
      command = gets.chomp
      process_command(command)
    end
  end

  private

  def process_command(command)
    case command.downcase
    when 'exit'
      puts "Выход из программы..."
      exit
    when 'help'
      display_help
    when /^parse\s+(.+)$/
      url = $1
      parse_url(url)
    else
      puts "Неизвестная команда. Введите 'help' для списка команд."
    end
  end

  def display_help
    puts "Доступные команды:"
    puts "  parse <url> - Парсинг указанного URL"
    puts "  exit - Выход из программы"
    puts "  help - Показать это сообщение"
  end

  def parse_url(url)
    @parser = WebsiteParser.new(url)
    results = @parser.parse
    display_results(results)
  end

  def display_results(results)
    results.each do |result|
      if result[:error]
        puts result[:error]
      else
        puts "Порт: #{result[:port]}"
        puts "Заголовок: #{result[:title]}"
        puts "Мета-теги:"
        result[:meta_tags].each { |tag| puts "  #{tag[:name]}: #{tag[:content]}" }
        puts "Структура страницы:"
        result[:structure].each do |element|
          if element[:text]
            puts "  #{'  ' * element[:depth]}#{element[:text]}"
          else
            puts "  #{'  ' * element[:depth]}<#{element[:name]}>"
          end
        end
        puts "Полный HTML доступен (не отображается из-за объема)"
      end
      puts "-" * 50
    end
  end
end

class GUIInterface < FXMainWindow
  def initialize(app)
    super(app, "Website Parser", :width => 600, :height => 400)
    @parser = nil

    
    main_frame = FXVerticalFrame.new(self, :opts => LAYOUT_FILL)

    # Создаем поле ввода URL и кнопку парсинга
    input_frame = FXHorizontalFrame.new(main_frame)
    FXLabel.new(input_frame, "URL:")
    @url_input = FXTextField.new(input_frame, 40)
    @parse_button = FXButton.new(input_frame, "Анализировать")

    # Создаем область для отображения результатов
    @result_text = FXText.new(main_frame, :opts => LAYOUT_FILL)
    @result_text.editable = false

    # Обработчик нажатия кнопки
    @parse_button.connect(SEL_COMMAND) do
      url = @url_input.text
      if url.empty?
        FXMessageBox.warning(self, MBOX_OK, "Ошибка", "Пожалуйста, введите URL")
      else
        @parser = WebsiteParser.new(url)
        results = @parser.parse
        display_results(results)
      end
    end
  end

  def create
    super
    show(PLACEMENT_SCREEN)
  end

  private

  def display_results(results)
    @result_text.text = ""
    results.each do |result|
      if result[:error]
        @result_text.appendText("#{result[:error]}\n")
      else
        @result_text.appendText("Порт: #{result[:port]}\n")
        @result_text.appendText("Заголовок: #{result[:title]}\n")
        @result_text.appendText("Мета-теги:\n")
        result[:meta_tags].each { |tag| @result_text.appendText("  #{tag[:name]}: #{tag[:content]}\n") }
        @result_text.appendText("Структура страницы:\n")
        result[:structure].each do |element|
          if element[:text]
            @result_text.appendText("  #{'  ' * element[:depth]}#{element[:text]}\n")
          else
            @result_text.appendText("  #{'  ' * element[:depth]}<#{element[:name]}>\n")
          end
        end
        @result_text.appendText("Полный HTML доступен (не отображается из-за объема)\n")
      end
      @result_text.appendText("-" * 50 + "\n")
    end
  end
end

# Выбор интерфейса в зависимости от аргументов командной строки
if ARGV.include?('--cli')
  CLIInterface.new.run
else
  FXApp.new do |app|
    GUIInterface.new(app)
    app.create
    app.run
  end
end
