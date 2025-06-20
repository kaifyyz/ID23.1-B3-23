require 'fox16'
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
require 'selenium-webdriver' # Добавлено для совместимости
require_relative 'website_parser'

include Fox

class GUIInterface < FXMainWindow
  def initialize(app)
    super(app, "Website Parser", :width => 1000, :height => 700) # Увеличенное окно для современного вида
    @parser = nil
    @ports = WebsiteParser::Parser.load_ports_from_file

    # Определение констант современной темы
    @theme = {
      primary_color: FXRGB(30, 144, 255), # Ярко-синий для акцентов
      secondary_color: FXRGB(45, 45, 45), # Темно-серый для фона
      text_color: FXRGB(255, 255, 255), # Белый текст для темной темы
      text_color_alt: FXRGB(0, 0, 0), # Черный для светлого фона
      background_color: FXRGB(50, 50, 50), # Чуть более светлый темный фон
      highlight_color: FXRGB(100, 100, 100), # Для эффектов наведения
      font: FXFont.new(app, "Roboto,140,normal") # Современный шрифт, 14px
    }

    # Применение темы к главному окну
    self.backColor = @theme[:background_color]

    main_frame = FXVerticalFrame.new(self, :opts => LAYOUT_FILL, :padLeft => 10, :padRight => 10, :padTop => 10, :padBottom => 10)
    main_frame.backColor = @theme[:background_color] # Установка фона после создания
    create_control_panel(main_frame)
    create_progress_panel(main_frame)
    create_tab_book(main_frame)
    create_handlers
  end

  def create
    super
    show(PLACEMENT_SCREEN)
  end

  private

  def create_control_panel(parent)
    # Создание панели управления
    control_frame = FXVerticalFrame.new(parent, :opts => LAYOUT_FILL_X|FRAME_SUNKEN, :padLeft => 10, :padRight => 10, :padTop => 10, :padBottom => 10)
    control_frame.backColor = @theme[:secondary_color] # Установка фона после создания

    # Секция ввода URL
    url_frame = FXHorizontalFrame.new(control_frame, :opts => LAYOUT_FILL_X, :padBottom => 10)
    url_frame.backColor = @theme[:secondary_color]
    url_label = FXLabel.new(url_frame, "URL:", :opts => LAYOUT_CENTER_Y)
    url_label.font = @theme[:font]
    url_label.textColor = @theme[:text_color]
    
    @url_input = FXTextField.new(url_frame, 40, :opts => LAYOUT_FILL_X|FRAME_SUNKEN|FRAME_THICK)
    @url_input.backColor = FXRGB(255, 255, 255)
    @url_input.textColor = @theme[:text_color_alt]
    @url_input.font = @theme[:font]
    @url_input.setFocus # Автофокус на поле ввода
    @url_input.connect(SEL_FOCUSIN) { @url_input.backColor = FXRGB(240, 240, 240) } # Выделение при фокусе
    @url_input.connect(SEL_FOCUSOUT) { @url_input.backColor = FXRGB(255, 255, 255) }

    # Секция поиска порта
    search_frame = FXHorizontalFrame.new(control_frame, :opts => LAYOUT_FILL_X, :padBottom => 10)
    search_frame.backColor = @theme[:secondary_color]
    search_label = FXLabel.new(search_frame, "Поиск порта:", :opts => LAYOUT_CENTER_Y)
    search_label.font = @theme[:font]
    search_label.textColor = @theme[:text_color]
    
    @port_search = FXTextField.new(search_frame, 20, :opts => FRAME_SUNKEN|FRAME_THICK)
    @port_search.backColor = FXRGB(255, 255, 255)
    @port_search.textColor = @theme[:text_color_alt]
    @port_search.font = @theme[:font]
    
    @search_button = FXButton.new(search_frame, "Найти\tПоиск портов", :opts => BUTTON_NORMAL|LAYOUT_RIGHT)
    style_button(@search_button)

    # Секция списка портов
    ports_frame = FXHorizontalFrame.new(control_frame, :opts => LAYOUT_FILL_X)
    ports_frame.backColor = @theme[:secondary_color]
    ports_label = FXLabel.new(ports_frame, "Порты:", :opts => LAYOUT_CENTER_Y)
    ports_label.font = @theme[:font]
    ports_label.textColor = @theme[:text_color]
    
    @port_list = FXList.new(ports_frame, :opts => LIST_EXTENDEDSELECT|LAYOUT_FILL_X|FRAME_SUNKEN|FRAME_THICK)
    @port_list.numVisible = 5
    @port_list.backColor = FXRGB(255, 255, 255)
    @port_list.textColor = @theme[:text_color_alt]
    @port_list.font = @theme[:font]
    @port_list.selBackColor = @theme[:primary_color] 
    @port_list.selTextColor = @theme[:text_color]
    
    populate_port_list(@ports)

    # Секция кнопок действий
    button_frame = FXHorizontalFrame.new(control_frame, :opts => LAYOUT_FILL_X, :padTop => 10)
    button_frame.backColor = @theme[:secondary_color]
    @parse_button = FXButton.new(button_frame, "Анализировать\tНачать анализ сайта", :opts => BUTTON_NORMAL|LAYOUT_CENTER_X)
    style_button(@parse_button)
    
    @json_button = FXButton.new(button_frame, "Экспорт JSON\tЭкспортировать результаты в JSON", :opts => BUTTON_NORMAL|LAYOUT_CENTER_X)
    style_button(@json_button)
    @json_button.disable
  end

  def create_progress_panel(parent)
    # Создание панели прогресса
    progress_frame = FXHorizontalFrame.new(parent, :opts => LAYOUT_FILL_X|FRAME_SUNKEN, :padLeft => 5, :padRight => 5, :padTop => 5, :padBottom => 5)
    progress_frame.backColor = @theme[:secondary_color] # Установка фона после создания
    @progress_bar = FXProgressBar.new(progress_frame, nil, 0, :opts => PROGRESSBAR_NORMAL|LAYOUT_FILL_X|LAYOUT_FILL_Y)
    @progress_bar.total = 100
    @progress_bar.progress = 0
    @progress_bar.barBGColor = @theme[:background_color]
    @progress_bar.barColor = @theme[:primary_color] 
    @progress_bar.textColor = @theme[:text_color]
    
    @progress_label = FXLabel.new(progress_frame, "0%", :opts => LAYOUT_CENTER_Y|LAYOUT_RIGHT)
    @progress_label.font = @theme[:font]
    @progress_label.textColor = @theme[:text_color]
  end

  def create_tab_book(parent)
    # Создание книги вкладок
    @tab_book = FXTabBook.new(parent, :opts => LAYOUT_FILL|TABBOOK_NORMAL)
    @tab_book.backColor = @theme[:secondary_color] # Установка фона после создания
    create_basic_tabs
    create_tokenization_tabs
    create_lemmatization_tabs
  end

  def create_basic_tabs
    # Вкладка структуры
    tab_structure = FXTabItem.new(@tab_book, "Структура", nil)
    style_tab(tab_structure)
    frame_structure = FXVerticalFrame.new(@tab_book, :opts => LAYOUT_FILL)
    frame_structure.backColor = FXRGB(255, 255, 255)
    @structure_text = FXText.new(frame_structure, :opts => LAYOUT_FILL|TEXT_WORDWRAP)
    style_text_area(@structure_text)

    # Вкладка HTML
    tab_html = FXTabItem.new(@tab_book, "HTML Код", nil)
    style_tab(tab_html)
    frame_html = FXVerticalFrame.new(@tab_book, :opts => LAYOUT_FILL)
    frame_html.backColor = FXRGB(255, 255, 255)
    @html_text = FXText.new(frame_html, :opts => LAYOUT_FILL|TEXT_WORDWRAP)
    style_text_area(@html_text)

    # Вкладка мета-информации
    tab_meta = FXTabItem.new(@tab_book, "Мета-информация", nil)
    style_tab(tab_meta)
    frame_meta = FXVerticalFrame.new(@tab_book, :opts => LAYOUT_FILL)
    frame_meta.backColor = FXRGB(255, 255, 255)
    @meta_text = FXText.new(frame_meta, :opts => LAYOUT_FILL|TEXT_WORDWRAP)
    style_text_area(@meta_text)
  end

  def create_tokenization_tabs
    # Вкладка токенов структуры
    tab_structure_tokens = FXTabItem.new(@tab_book, "Токены структуры", nil)
    style_tab(tab_structure_tokens)
    frame_structure_tokens = FXVerticalFrame.new(@tab_book, :opts => LAYOUT_FILL)
    frame_structure_tokens.backColor = FXRGB(255, 255, 255)
    @structure_tokens_text = FXText.new(frame_structure_tokens, :opts => LAYOUT_FILL|TEXT_WORDWRAP)
    style_text_area(@structure_tokens_text)

    # Вкладка HTML токенов
    tab_html_tokens = FXTabItem.new(@tab_book, "HTML Токены", nil)
    style_tab(tab_html_tokens)
    frame_html_tokens = FXVerticalFrame.new(@tab_book, :opts => LAYOUT_FILL)
    frame_html_tokens.backColor = FXRGB(255, 255, 255)
    @html_tokens_text = FXText.new(frame_html_tokens, :opts => LAYOUT_FILL|TEXT_WORDWRAP)
    style_text_area(@html_tokens_text)

    # Вкладка токенов кода
    tab_code_tokens = FXTabItem.new(@tab_book, "Токены кода", nil)
    style_tab(tab_code_tokens)
    frame_code_tokens = FXVerticalFrame.new(@tab_book, :opts => LAYOUT_FILL)
    frame_code_tokens.backColor = FXRGB(255, 255, 255)
    @code_tokens_text = FXText.new(frame_code_tokens, :opts => LAYOUT_FILL|TEXT_WORDWRAP)
    style_text_area(@code_tokens_text)
  end

  def create_lemmatization_tabs
    # Вкладка лемм структуры
    tab_structure_lemmas = FXTabItem.new(@tab_book, "Леммы структуры", nil)
    style_tab(tab_structure_lemmas)
    frame_structure_lemmas = FXVerticalFrame.new(@tab_book, :opts => LAYOUT_FILL)
    frame_structure_lemmas.backColor = FXRGB(255, 255, 255)
    @structure_lemmas_text = FXText.new(frame_structure_lemmas, :opts => LAYOUT_FILL|TEXT_WORDWRAP)
    style_text_area(@structure_lemmas_text)

    # Вкладка HTML лемм
    tab_html_lemmas = FXTabItem.new(@tab_book, "HTML Леммы", nil)
    style_tab(tab_html_lemmas)
    frame_html_lemmas = FXVerticalFrame.new(@tab_book, :opts => LAYOUT_FILL)
    frame_html_lemmas.backColor = FXRGB(255, 255, 255)
    @html_lemmas_text = FXText.new(frame_html_lemmas, :opts => LAYOUT_FILL|TEXT_WORDWRAP)
    style_text_area(@html_lemmas_text)

    # Вкладка лемм кода
    tab_code_lemmas = FXTabItem.new(@tab_book, "Леммы кода", nil)
    style_tab(tab_code_lemmas)
    frame_code_lemmas = FXVerticalFrame.new(@tab_book, :opts => LAYOUT_FILL)
    frame_code_lemmas.backColor = FXRGB(255, 255, 255)
    @code_lemmas_text = FXText.new(frame_code_lemmas, :opts => LAYOUT_FILL|TEXT_WORDWRAP)
    style_text_area(@code_lemmas_text)
  end

  # Метод для стилизации кнопок
  def style_button(button)
    button.font = @theme[:font]
    button.backColor = @theme[:primary_color]
    button.textColor = @theme[:text_color]
    button.shadowColor = FXRGB(0, 0, 0)
    button.hiliteColor = @theme[:highlight_color]
    button.padLeft = 15
    button.padRight = 15
    button.padTop = 8
    button.padBottom = 8
    button.connect(SEL_ENTER) { button.backColor = @theme[:highlight_color] } # Эффект наведения
    button.connect(SEL_LEAVE) { button.backColor = @theme[:primary_color] }
  end

  # Метод для стилизации вкладок
  def style_tab(tab)
    tab.font = @theme[:font]
    tab.textColor = @theme[:text_color]
    tab.backColor = @theme[:secondary_color]
    tab.connect(SEL_ENTER) { tab.backColor = @theme[:highlight_color] } # Эффект наведения
    tab.connect(SEL_LEAVE) { tab.backColor = @theme[:secondary_color] }
  end

  # Метод для стилизации текстовых областей
  def style_text_area(text_area)
    text_area.editable = false
    text_area.backColor = FXRGB(255, 255, 255)
    text_area.textColor = @theme[:text_color_alt]
    text_area.font = FXFont.new(getApp, "Roboto,120,normal") # Меньший шрифт для текстовых областей
    text_area.selBackColor = @theme[:primary_color]
    text_area.selTextColor = @theme[:text_color]
  end

  def create_handlers
    # Обработчик для кнопки поиска
    @search_button.connect(SEL_COMMAND) do
      search_ports
    end

    # Обработчик для кнопки анализа
    @parse_button.connect(SEL_COMMAND) do
      parse_website
    end

    # Обработчик для кнопки экспорта JSON
    @json_button.connect(SEL_COMMAND) do
      export_json
    end
  end

  def search_ports
    # Поиск портов по введенному запросу
    search_term = @port_search.text.strip
    if search_term.empty?
      populate_port_list(@ports)
    else
      filtered_ports = @ports.select { |port| port.to_s.include?(search_term) }
      populate_port_list(filtered_ports)
    end
  end

  def parse_website
    # Анализ веб-сайта
    url = @url_input.text
    selected_ports = []
    @port_list.each do |item|
      selected_ports << item.text.to_i if item.selected?
    end
    
    if url.empty?
      FXMessageBox.warning(self, MBOX_OK, "Ошибка", "Введите URL")
      return
    elsif selected_ports.empty?
      FXMessageBox.warning(self, MBOX_OK, "Ошибка", "Выберите хотя бы один порт")
      return
    end
    
    @parse_button.disable
    clear_all_text_components
    @progress_bar.progress = 0
    @progress_label.text = "0%"
    
    progress_callback = lambda do |progress|
      getApp.addChore do
        @progress_bar.progress = progress
        @progress_label.text = "#{progress}%"
      end
    end

    Thread.new do
      begin
        @parser = WebsiteParser::Parser.new(url, :progress_callback => progress_callback)
        @current_results = @parser.parse(selected_ports)
        
        getApp.addChore do
          update_results_display(@current_results)
          @parse_button.enable
          @json_button.enable
          @progress_bar.progress = 100
          @progress_label.text = "100%"
          FXMessageBox.information(self, MBOX_OK, "Успех", "Анализ сайта завершен!")
        end
      rescue StandardError => e
        getApp.addChore do
          @parse_button.enable
          @json_button.disable
          FXMessageBox.error(self, MBOX_OK, "Ошибка", "Не удалось проанализировать сайт: #{e.message}")
        end
      end
    end
  end

  def export_json
    # Экспорт результатов в JSON
    return unless @current_results && @parser
    
    begin
      json_data = @parser.to_json_data(@current_results)
      
      # Создание диалога сохранения
      dialog = FXFileDialog.new(self, "Сохранить JSON анализ")
      dialog.patternList = ["JSON файлы (*.json)"]
      dialog.filename = "website_analysis_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
      
      if dialog.execute != 0
        File.open(dialog.filename, 'w') do |file|
          file.write(JSON.pretty_generate(json_data))
        end
        FXMessageBox.information(self, MBOX_OK, "Успех", "JSON данные успешно экспортированы!")
      end
    rescue StandardError => e
      FXMessageBox.error(self, MBOX_OK, "Ошибка", "Не удалось экспортировать JSON: #{e.message}")
    end
  end
  
  def clear_all_text_components
    # Очистка всех текстовых компонентов
    [@structure_text, @html_text, @meta_text,
    @structure_tokens_text, @html_tokens_text, @code_tokens_text,
    @structure_lemmas_text, @html_lemmas_text, @code_lemmas_text].each do |component|
      component.setText("")
    end
  end
  
  def update_results_display(results)
    # Обновление отображения результатов
    results.each do |result|
      port = result[:port]
      
      if result[:error]
        display_error_for_port(port, result[:error])
        next
      end
      
      display_port_data(port, result)
    end

    getApp.addChore do
      FXMessageBox.information(self, MBOX_OK, "Успех", "Анализ завершен!")
    end
  end

  def display_error_for_port(port, error_message)
    # Отображение ошибок для каждого порта
    error_text = "Порт #{port}: #{error_message}\n\n"
    text_components = [
      @structure_text, @html_text, @meta_text,
      @structure_tokens_text, @html_tokens_text, @code_tokens_text,
      @structure_lemmas_text, @html_lemmas_text, @code_lemmas_text
    ]

    text_components.each do |component|
      getApp.addChore do
        component.appendText(error_text)
      end
    end
  end

  def display_port_data(port, result)
    # Потоковая обработка данных порта
    getApp.addChore do
      display_structure_data(port, result)
      display_html_data(port, result)
      display_meta_data(port, result)
      display_tokens_data(port, result)
      display_lemmas_data(port, result)
    end
  end

  def display_structure_data(port, result)
    # Отображение данных структуры
    @structure_text.appendText(format_section(
      "Структура порта #{port}", 
      format_structure(result[:structure])
    ))
  end

  def display_html_data(port, result)
    # Отображение HTML данных
    @html_text.appendText(format_section(
      "HTML порта #{port}", 
      result[:full_html].to_s
    ))
  end

  def display_meta_data(port, result)
    # Отображение мета-тегов
    @meta_text.appendText(format_section(
      "Мета-теги порта #{port}", 
      format_meta_tags(result[:meta_tags])
    ))
  end

  def display_tokens_data(port, result)
    # Отображение токенов
    tokens_mapping = {
      structure: result[:structure_tokens],
      html: result[:html_tokens],
      code: result[:code_tokens]
    }

    tokens_mapping.each do |type, tokens|
      component = instance_variable_get("@#{type}_tokens_text")
      component.appendText(format_section(
        "Токены #{type.capitalize} порта #{port}", 
        format_tokens(tokens)
      ))
    end
  end

  def display_lemmas_data(port, result)
    # Отображение лемм
    lemmas_mapping = {
      structure: result[:structure_lemmas],
      html: result[:html_lemmas],
      code: result[:code_lemmas]
    }

    lemmas_mapping.each do |type, lemmas|
      component = instance_variable_get("@#{type}_lemmas_text")
      component.appendText(format_section(
        "Леммы #{type.capitalize} порта #{port}", 
        format_lemmas(lemmas)
      ))
    end
  end

  def format_section(title, content)
    # Форматирование секции с заголовком
    "=== #{title} ===\n#{content}\n\n"
  end

  def format_tokens(tokens)
    # Форматирование токенов
    return "Токены не найдены\n" unless tokens&.any?

    tokens.map do |token| 
      "#{token[:type]}: #{token[:value]}"
    end.join("\n")
  end

  def format_lemmas(lemmas)
    # Форматирование лемм
    return "Леммы не найдены\n" unless lemmas&.any?

    lemmas.map do |lemma|
      case lemma[:type]
      when :word_lemma, :text_lemma
        lemma[:value]
      when :tag_lemma, :identifier_lemma, :attribute_lemma, :string_lemma
        "#{lemma[:type]}: #{lemma[:value]}"
      else
        lemma.inspect
      end
    end.join("\n")
  end

  def update_text_components(structure, html, meta, structure_tokens, html_tokens, 
                            code_tokens, structure_lemmas, html_lemmas, code_lemmas)
    # Обновление текстовых компонентов
    @structure_text.setText(structure)
    @html_text.setText(html)
    @meta_text.setText(meta)
    @structure_tokens_text.setText(structure_tokens)
    @html_tokens_text.setText(html_tokens)
    @code_tokens_text.setText(code_tokens)
    @structure_lemmas_text.setText(structure_lemmas)
    @html_lemmas_text.setText(html_lemmas)
    @code_lemmas_text.setText(code_lemmas)
  end

  def append_error_info(result)
    # Добавление информации об ошибке
    error_message = "Порт #{result[:port]}: #{result[:error]}\n\n"
    [@structure_text, @html_text, @meta_text,
    @structure_tokens_text, @html_tokens_text, @code_tokens_text,
    @structure_lemmas_text, @html_lemmas_text, @code_lemmas_text].each do |component|
      component.appendText(error_message)
    end
  end

  def format_structure(structure, indent = 0)
    # Форматирование структуры
    return "" unless structure
  
    output = ""
    structure.each do |element|
      if element[:text]
        output << "  " * indent
        output << "Текст: #{element[:text]}\n"
      elsif element[:name]
        output << "  " * indent
        output << "Элемент: #{element[:name]}\n"
        
        if element[:attributes]&.any?
          output << "  " * (indent + 1)
          output << "Атрибуты: #{format_attributes(element[:attributes])}\n"
        end
      end
    end
    output
  end
  
  def format_attributes(attributes)
    # Форматирование атрибутов
    attributes.map { |name, value| "#{name}=\"#{value}\"" }.join(", ")
  end
  
  def format_meta_tags(meta_tags)
    # Форматирование мета-тегов
    return "Мета-теги не найдены\n" unless meta_tags&.any?
  
    output = ""
    meta_tags.each do |tag|
      output << "#{tag[:name]}: #{tag[:content]}\n"
    end
    output
  end
  
  def format_tokens(tokens)
    # Форматирование токенов (дубликат метода, оставлен для совместимости)
    return "Токены не найдены\n" unless tokens&.any?
  
    output = ""
    tokens.each do |token|
      output << "#{token[:type]}: #{token[:value]}\n"
    end
    output
  end
  
  def populate_port_list(ports)
    # Заполнение списка портов
    @port_list.clearItems
    ports.each do |port|
      @port_list.appendItem(port.to_s)
    end
  end
end

if __FILE__ == $0
  # Запуск приложения
  application = FXApp.new("WebsiteParser", "xAI")
  GUIInterface.new(application)
  application.create
  application.run
end
