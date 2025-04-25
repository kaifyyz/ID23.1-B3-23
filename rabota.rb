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
require 'openai'
require 'base64'
require 'wicked_pdf'
require_relative 'website_parser'

include Fox

class GUIInterface < FXMainWindow
  def initialize(app)
    super(app, "Website Parser", width: 900, height: 600)
    
    @parser = nil
    @ports = WebsiteParser::Parser.load_ports_from_file

    main_frame = FXVerticalFrame.new(self, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(245, 247, 250)
    end
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
    control_frame = FXVerticalFrame.new(parent, opts: LAYOUT_FILL_X) do |frame|
      frame.backColor = FXRGB(245, 247, 250) 
    end

    url_frame = FXHorizontalFrame.new(control_frame, opts: LAYOUT_FILL_X)
    FXLabel.new(url_frame, "URL:", opts: LAYOUT_CENTER_Y) do |label|
      label.textColor = FXRGB(151, 2, 2) 
    end
    @url_input = FXTextField.new(url_frame, 40, opts: LAYOUT_FILL_X | FRAME_SUNKEN | FRAME_THICK) do |field|
      field.backColor = FXRGB(255, 255, 255)
      field.textColor = FXRGB(0, 0, 0) 
    end

    search_frame = FXHorizontalFrame.new(control_frame, opts: LAYOUT_FILL_X)
    FXLabel.new(search_frame, "Искать порт:", opts: LAYOUT_CENTER_Y) do |label|
      label.textColor = FXRGB(151, 2, 2) 
    end
    @port_search = FXTextField.new(search_frame, 20, opts: FRAME_SUNKEN | FRAME_THICK) do |field|
      field.backColor = FXRGB(255, 255, 255)
      field.textColor = FXRGB(0, 0, 0) 
    end
    @search_button = FXButton.new(search_frame, "Искать", opts: BUTTON_NORMAL | LAYOUT_RIGHT) do |button|
      button.backColor = FXRGB(151, 2, 2) 
      button.textColor = FXRGB(255, 255, 255) 
    end

    ports_frame = FXHorizontalFrame.new(control_frame, opts: LAYOUT_FILL_X)
    FXLabel.new(ports_frame, "Порты:", opts: LAYOUT_CENTER_Y) do |label|
      label.textColor = FXRGB(151, 2, 2) 
    end
    @port_list = FXList.new(ports_frame, opts: LIST_EXTENDEDSELECT | LAYOUT_FILL_X | FRAME_SUNKEN | FRAME_THICK) do |list|
      list.backColor = FXRGB(255, 255, 255)
      list.textColor = FXRGB(0, 0, 0) 
    end
    @port_list.numVisible = 5

    button_frame = FXHorizontalFrame.new(control_frame, opts: LAYOUT_FILL_X)
    @parse_button = FXButton.new(button_frame, "Анализировать", opts: BUTTON_NORMAL | LAYOUT_CENTER_X) do |button|
      button.backColor = FXRGB(151, 2, 2) 
      button.textColor = FXRGB(255, 255, 255) 
    end
    @json_button = FXButton.new(button_frame, "Экспортировать в JSON", opts: BUTTON_NORMAL | LAYOUT_CENTER_X) do |button|
      button.backColor = FXRGB(151, 2, 2) 
      button.textColor = FXRGB(255, 255, 255)
      button.disable
    end
  end

  def create_progress_panel(parent)
    progress_frame = FXHorizontalFrame.new(parent, opts: LAYOUT_FILL_X | FRAME_SUNKEN) do |frame|
      frame.backColor = FXRGB(245, 247, 250)
    end
    @progress_bar = FXProgressBar.new(progress_frame, nil, 0, PROGRESSBAR_NORMAL | LAYOUT_FILL_X | LAYOUT_FILL_Y) do |bar|
      bar.backColor = FXRGB(255, 255, 255)
      bar.barColor = FXRGB(146, 2, 2) 
    end
    @progress_label = FXLabel.new(progress_frame, "0%", nil, LAYOUT_CENTER_Y | LAYOUT_RIGHT) do |label|
      label.textColor = FXRGB(151, 2, 2) 
    end
  end

  def create_tab_book(parent)
    @tab_book = FXTabBook.new(parent, opts: LAYOUT_FILL | TABBOOK_NORMAL) do |book|
      book.backColor = FXRGB(245, 247, 250) 
    end
    create_basic_tabs
    create_tokenization_tabs
    create_lemmatization_tabs
  end

  def create_basic_tabs
    # Structure tab
    tab_structure = FXTabItem.new(@tab_book, "Structure", nil)
    frame_structure = FXVerticalFrame.new(@tab_book, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(151, 2, 2) 
    end
    @structure_text = FXText.new(frame_structure, opts: LAYOUT_FILL | TEXT_WORDWRAP) do |text|
      text.backColor = FXRGB(255, 255, 255) 
      text.textColor = FXRGB(0, 0, 0) 
      text.editable = false
    end
  
    # HTML tab
    tab_html = FXTabItem.new(@tab_book, "HTML Code", nil)
    frame_html = FXVerticalFrame.new(@tab_book, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(151, 2, 2)
    end
    @html_text = FXText.new(frame_html, opts: LAYOUT_FILL | TEXT_WORDWRAP) do |text|
      text.backColor = FXRGB(255, 255, 255)
      text.textColor = FXRGB(0, 0, 0) 
      text.editable = false
    end
  
    # Meta tab
    tab_meta = FXTabItem.new(@tab_book, "Meta Information", nil)
    frame_meta = FXVerticalFrame.new(@tab_book, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(151, 2, 2) 
    end
    @meta_text = FXText.new(frame_meta, opts: LAYOUT_FILL | TEXT_WORDWRAP) do |text|
      text.backColor = FXRGB(255, 255, 255) 
      text.textColor = FXRGB(0, 0, 0) 
      text.editable = false
    end
  end
  
  def create_tokenization_tabs
    # Structure tokens tab
    tab_structure_tokens = FXTabItem.new(@tab_book, "Structure Tokens", nil)
    frame_structure_tokens = FXVerticalFrame.new(@tab_book, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(151, 2, 2)
    end
    @structure_tokens_text = FXText.new(frame_structure_tokens, opts: LAYOUT_FILL | TEXT_WORDWRAP) do |text|
      text.backColor = FXRGB(255, 255, 255) 
      text.textColor = FXRGB(0, 0, 0) 
      text.editable = false
    end
  
    # HTML tokens tab
    tab_html_tokens = FXTabItem.new(@tab_book, "HTML Tokens", nil)
    frame_html_tokens = FXVerticalFrame.new(@tab_book, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(151, 2, 2) 
    end
    @html_tokens_text = FXText.new(frame_html_tokens, opts: LAYOUT_FILL | TEXT_WORDWRAP) do |text|
      text.backColor = FXRGB(255, 255, 255) 
      text.textColor = FXRGB(0, 0, 0) 
      text.editable = false
    end
  
    # Code tokens tab
    tab_code_tokens = FXTabItem.new(@tab_book, "Code Tokens", nil)
    frame_code_tokens = FXVerticalFrame.new(@tab_book, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(151, 2, 2) 
    end
    @code_tokens_text = FXText.new(frame_code_tokens, opts: LAYOUT_FILL | TEXT_WORDWRAP) do |text|
      text.backColor = FXRGB(255, 255, 255) 
      text.textColor = FXRGB(0, 0, 0 ) 
      text.editable = false
    end
  end
  
  def create_lemmatization_tabs
    # Structure lemmas tab
    tab_structure_lemmas = FXTabItem.new(@tab_book, "Structure Lemmas", nil)
    frame_structure_lemmas = FXVerticalFrame.new(@tab_book, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(151, 2, 2) 
    end
    @structure_lemmas_text = FXText.new(frame_structure_lemmas, opts: LAYOUT_FILL | TEXT_WORDWRAP) do |text|
      text.backColor = FXRGB(255, 255, 255) 
      text.textColor = FXRGB(0, 0, 0) 
      text.editable = false
    end
  
    # HTML lemmas tab
    tab_html_lemmas = FXTabItem.new(@tab_book, "HTML Lemmas", nil)
    frame_html_lemmas = FXVerticalFrame.new(@tab_book, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(151, 2, 2) # background color
    end
    @html_lemmas_text = FXText.new(frame_html_lemmas, opts: LAYOUT_FILL | TEXT_WORDWRAP) do |text|
      text.backColor = FXRGB(255, 255, 255)
      text.textColor = FXRGB(0, 0, 0) 
      text.editable = false
    end
  
    # Code lemmas tab
    tab_code_lemmas = FXTabItem.new(@tab_book, "Code Lemmas", nil)
    frame_code_lemmas = FXVerticalFrame.new(@tab_book, opts: LAYOUT_FILL) do |frame|
      frame.backColor = FXRGB(151, 2, 2)
    end
    @code_lemmas_text = FXText.new(frame_code_lemmas, opts: LAYOUT_FILL | TEXT_WORDWRAP) do |text|
      text.backColor = FXRGB(255, 255, 255)
      text.textColor = FXRGB(0, 0, 0) 
      text.editable = false
    end
  end

  def create_handlers
    @search_button.connect(SEL_COMMAND) do
      search_ports
    end

    @parse_button.connect(SEL_COMMAND) do
      parse_website
    end

    @json_button.connect(SEL_COMMAND) do
      export_json
    end
  end

  def search_ports
    search_term = @port_search.text.strip
    if search_term.empty?
      populate_port_list(@ports)
    else
      filtered_ports = @ports.select { |port| port.to_s.include?(search_term) }
      populate_port_list(filtered_ports)
    end
  end

  def parse_website
    url = @url_input.text
    selected_ports = []
    @port_list.each do |item|
      selected_ports << item.text.to_i if item.selected?
    end
    
    if url.empty?
      FXMessageBox.warning(self, MBOX_OK, "Ошибка", "Введите URL")
      return
    elsif selected_ports.empty?
      FXMessageBox.warning(self, MBOX_OK, "Ошибка", "Выберите один из портов")
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
        @parser = WebsiteParser::Parser.new(url, progress_callback: progress_callback)
        @current_results = @parser.parse(selected_ports)
        
        getApp.addChore do
          update_results_display(@current_results)
          @parse_button.enable
          @json_button.enable
          @progress_bar.progress = 100
          @progress_label.text = "100%"
          FXMessageBox.information(self, MBOX_OK, "Успех", "Анализ веб-сайта завершен!")
        end
      rescue StandardError => e
        getApp.addChore do
          @parse_button.enable
          @json_button.disable
          FXMessageBox.error(self, MBOX_OK, "Ошибка", "Не удалось выполнить парсинг веб-сайта: #{e.message}")
        end
      end
    end
  end

  def export_json
    return unless @current_results && @parser
    
    begin
      json_data = @parser.to_json_data(@current_results)
      
      # Create a save dialog
      dialog = FXFileDialog.new(self, "Сохранить JSON")
      dialog.patternList = ["JSON Files (*.json)"]
      dialog.filename = "website_analysis_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
      
      if dialog.execute != 0
        File.open(dialog.filename, 'w') do |file|
          file.write(JSON.pretty_generate(json_data))
        end
        FXMessageBox.information(self, MBOX_OK, "Успех", "JSON данные экспортированы успешно!")
      end
    rescue StandardError => e
      FXMessageBox.error(self, MBOX_OK, "Ошибка", "Ошибка экспорта JSON: #{e.message}")
    end
  end
  
  def clear_all_text_components
    [@structure_text, @html_text, @meta_text,
    @structure_tokens_text, @html_tokens_text, @code_tokens_text,
    @structure_lemmas_text, @html_lemmas_text, @code_lemmas_text].each do |component|
      component.setText("")
    end
  end
  
  def update_results_display(results)
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
    # Метод для отображения ошибок в каждой вкладке
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
    # Используем потоковую обработку для больших объемов данных
    getApp.addChore do
      display_structure_data(port, result)
      display_html_data(port, result)
      display_meta_data(port, result)
      display_tokens_data(port, result)
      display_lemmas_data(port, result)
    end
  end

  def display_structure_data(port, result)
    @structure_text.appendText(format_section(
      "Структура порта #{port}", 
      format_structure(result[:structure])
    ))
  end

  def display_html_data(port, result)
    @html_text.appendText(format_section(
      "HTML порта #{port}", 
      result[:full_html].to_s
    ))
  end

  def display_meta_data(port, result)
    @meta_text.appendText(format_section(
      "Мета-теги порта #{port}", 
      format_meta_tags(result[:meta_tags])
    ))
  end

  def display_tokens_data(port, result)
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
    return "Токены не найдены\n" unless tokens&.any?

    tokens.map do |token| 
      "#{token[:type]}: #{token[:value]}"
    end.join("\n")
  end

  def format_lemmas(lemmas)
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

  def update_results_display(results)
    results.each do |result|
      port = result[:port]
      puts "Processing result for port #{port}"
      
      if result[:error]
        puts "Error: #{result[:error]}"
        append_error_info(result)
        next
      end
      # Update structure tab
      @structure_text.appendText("Port #{port} Structure:\n")
      @structure_text.appendText(format_structure(result[:structure]))
      @structure_text.appendText("\n\n")
  
      # Update HTML tab
      @html_text.appendText("Port #{port} HTML:\n")
      @html_text.appendText(result[:full_html].to_s)
      @html_text.appendText("\n\n")
  
      # Update meta tab
      @meta_text.appendText("Port #{port} Meta Tags:\n")
      @meta_text.appendText(format_meta_tags(result[:meta_tags]))
      @meta_text.appendText("\n\n")
  
      # Update tokens tabs
      @structure_tokens_text.appendText("Port #{port} Structure Tokens:\n")
      @structure_tokens_text.appendText(format_tokens(result[:structure_tokens]))
      @structure_tokens_text.appendText("\n\n")
  
      @html_tokens_text.appendText("Port #{port} HTML Tokens:\n")
      @html_tokens_text.appendText(format_tokens(result[:html_tokens]))
      @html_tokens_text.appendText("\n\n")
  
      @code_tokens_text.appendText("Port #{port} Code Tokens:\n")
      @code_tokens_text.appendText(format_tokens(result[:code_tokens]))
      @code_tokens_text.appendText("\n\n")
  
      # Update lemmas tabs
      @structure_lemmas_text.appendText("Port #{port} Structure Lemmas:\n")
      @structure_lemmas_text.appendText(format_lemmas(result[:structure_lemmas]))
      @structure_lemmas_text.appendText("\n\n")
  
      @html_lemmas_text.appendText("Port #{port} HTML Lemmas:\n")
      @html_lemmas_text.appendText(format_lemmas(result[:html_lemmas]))
      @html_lemmas_text.appendText("\n\n")
  
      @code_lemmas_text.appendText("Port #{port} Code Lemmas:\n")
      @code_lemmas_text.appendText(format_lemmas(result[:code_lemmas]))
      @code_lemmas_text.appendText("\n\n")
    end
  end

  def update_text_components(structure, html, meta, structure_tokens, html_tokens, 
                          code_tokens, structure_lemmas, html_lemmas, code_lemmas)
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
    error_message = "Port #{result[:port]}: #{result[:error]}\n\n"
    [@structure_text, @html_text, @meta_text,
    @structure_tokens_text, @html_tokens_text, @code_tokens_text,
    @structure_lemmas_text, @html_lemmas_text, @code_lemmas_text].each do |component|
      component.appendText(error_message)
    end
  end

  def format_structure(structure, indent = 0)
    return "" unless structure
  
    output = ""
    structure.each do |element|
      if element[:text]
        output << "  " * indent
        output << "Text: #{element[:text]}\n"
      elsif element[:name]
        output << "  " * indent
        output << "Element: #{element[:name]}\n"
        
        if element[:attributes]&.any?
          output << "  " * (indent + 1)
          output << "Attributes: #{format_attributes(element[:attributes])}\n"
        end
      end
    end
    output
  end
  
  def format_attributes(attributes)
    attributes.map { |name, value| "#{name}=\"#{value}\"" }.join(", ")
  end
  
  def format_meta_tags(meta_tags)
    return "No meta tags found\n" unless meta_tags&.any?
  
    output = ""
    meta_tags.each do |tag|
      output << "#{tag[:name]}: #{tag[:content]}\n"
    end
    output
  end
  
  def format_tokens(tokens)
    return "No tokens found\n" unless tokens&.any?
  
    output = ""
    tokens.each do |token|
      output << "#{token[:type]}: #{token[:value]}\n"
    end
    output
  end
  
  def populate_port_list(ports)
    @port_list.clearItems
    ports.each do |port|
      @port_list.appendItem(port.to_s)
    end
  end
end
  
  # Main application entry point
if __FILE__ == $0
  application = FXApp.new("WebsiteParser", "Anthropic")
  GUIInterface.new(application)
  application.create
  application.run
end