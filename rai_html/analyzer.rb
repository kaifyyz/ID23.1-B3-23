# rai_html/analyzer.rb
require "set"
module RAIHtml
  class Analyzer
    attr_reader :structure, :functionality, :base_url, :output_dir

    def initialize(txt_file_path, base_url = nil)
      @txt_file_path = txt_file_path
      @base_url = base_url
      @structure = {
        tags: [], attributes: [], meta_data: {}, content: {},
        predicted_content: {}, functional_content: {}, visual_content: {}
      }
      @current_tag = nil
      @tag_stack = []
      @html_builder = []
      @neural_network = initialize_neural_network
      @output_dir = 'website_analysis_output'
      @functionality = { css: [], javascript: [], images: [], interactive_elements: {}, forms: {}, navigational_elements: {} }
      @visual_structure = { html_structure: [], layout_elements: {}, containers: {}, content_blocks: {}, images: [] }

      FileUtils.mkdir_p(['mirrored_css', 'mirrored_js', 'mirrored_images', @output_dir])
    end

    def execute(functionality_json = 'site_functionality.json', visual_json = 'site_visual_structure.json', html_output = 'mirrored_site.html')
      extract_base_url if @base_url.nil?
      validate_connection
      perform_analysis
      save_results(functionality_json, visual_json, html_output)
    end

    def verify_index_html
      index_path = File.join(@output_dir, 'index.html')
      puts "Verifying index.html..."

      return puts "❌ Error: index.html not found at #{index_path}" unless File.exist?(index_path)

      content = File.read(index_path)
      checks = {
        'DOCTYPE declaration' => content.include?('<!DOCTYPE html>'),
        'HTML tag' => content.include?('<html'),
        'Head section' => content.include?('<head>'),
        'Body section' => content.include?('<body>'),
        'Title' => content.match(/<title>.*?<\/title>/),
        'CSS styles' => content.include?('<style>')
      }

      puts "Index.html verification results:"
      all_passed = checks.all? { |_, v| v }
      checks.each { |check, result| puts "  #{check}: #{result ? 'PASS' : 'FAIL'}" }
      puts all_passed ? "✅ Index.html passed all checks" : "❌ Index.html has issues"
    end

    private

    def extract_base_url
      puts "Extracting base URL from #{@txt_file_path}"
      begin
        lines = File.readlines(@txt_file_path, chomp: true)
        lines.each do |line|
          if line == 'attribute' && lines.include?('base') && line.include?('href=')
            href_line = lines[lines.index(line) + 1]
            if href_line.include?('=')
              url = href_line.split('=', 2)[1].gsub(/["'\\]/, '').strip
              @base_url = url if url.start_with?('http')
              puts "Found base URL from href: #{@base_url}"
              break
            end
          end

          if line == 'attribute' && line.include?('canonical')
            next_line = lines[lines.index(line) + 1]
            if next_line.include?('href=')
              url = next_line.split('=', 2)[1].gsub(/["'\\]/, '').strip
              @base_url = URI.parse(url).scheme + "://" + URI.parse(url).host if url.start_with?('http')
              puts "Found base URL from canonical: #{@base_url}"
              break
            end
          end
        end

        if @base_url.nil?
          lines.each do |line|
            if line.include?('http')
              urls = line.scan(/(https?:\/\/[^\s"']+)/)
              if urls.any?
                uri = URI.parse(urls[0][0])
                @base_url = "#{uri.scheme}://#{uri.host}"
                puts "Found base URL from content: #{@base_url}"
                break
              end
            end
          end
        end

        @base_url ||= "http://example.com"
        puts "Final base URL: #{@base_url}"
      rescue => e
        puts "Error extracting base URL: #{e.message}"
        @base_url = "http://example.com"
      end
    end

    def validate_connection
      begin
        URI.open(@base_url, open_timeout: 5, read_timeout: 5)
        puts "Successfully connected to #{@base_url}"
      rescue Net::OpenTimeout, Errno::ETIMEDOUT => e
        puts "Warning: Could not connect to #{@base_url} - downloads may fail: #{e.message}"
      rescue StandardError => e
        puts "Error connecting to #{@base_url}: #{e.message}"
      end
    end

    def perform_analysis
      read_and_analyze
      analyze_with_ai
      predict_missing_content
      download_css
      download_javascript
      download_images
      recreate_html
      prepare_separated_data
    end

    def save_results(functionality_json, visual_json, html_output)
      functionality_json = File.join(@output_dir, functionality_json)
      visual_json = File.join(@output_dir, visual_json)
      html_output = File.join(@output_dir, html_output)
      save_to_separated_json(functionality_json, visual_json, html_output)
    end

    def initialize_neural_network
      Rumale::NeuralNetwork::MLPClassifier.new(
        hidden_units: [100, 50],
        learning_rate: 0.03,
        max_iter: 2000,
        batch_size: 10,
        random_seed: 42,
        dropout_rate: 0.2
      )
    end

    def read_and_analyze
      puts "Reading file: #{@txt_file_path}"
      begin
        lines = File.readlines(@txt_file_path, chomp: true)
        process_data(lines)
      rescue Errno::ENOENT
        puts "Error: File #{@txt_file_path} not found."
        @structure[:error] = "File not found"
      end
    end

    def process_data(lines)
      puts "Total lines in input file: #{lines.length}"
      i = 0
      in_head = false
      while i < lines.length
        line = lines[i]
        puts "Processing line #{i}: #{line}"
        if line == 'tag_open'
          tag_name = lines[i + 1]
          puts "Opening tag: #{tag_name}"
          @structure[:tags] << { type: 'open', name: tag_name, position: i }
          @tag_stack.push(tag_name)
          @current_tag = tag_name
          @html_builder << "<#{tag_name}"
          in_head = true if tag_name == 'head'
          i += 1
        elsif line == 'attribute' && @current_tag
          attr_value = lines[i + 1]
          puts "Attribute for #{@current_tag}: #{attr_value}"
          if attr_value.include?('=')
            attr_parts = attr_value.split('=', 2)
            attr_name = attr_parts[0].gsub(/^"|"$/, '').strip
            attr_value = attr_parts[1].gsub(/["\\]/, '').strip
            @structure[:attributes] << { tag: @current_tag, name: attr_name, value: attr_value, in_head: in_head }
            @html_builder[-1] += " #{attr_name}=\"#{attr_value}\""

            if @current_tag == 'script' && attr_name == 'src'
              unless attr_value.match(/yandex|metrika|google|analytics|ads|tracker/i)
                @functionality[:javascript] << { url: attr_value, local_path: nil }
                puts "Detected JavaScript: #{attr_value}"
              else
                puts "Skipping tracking script: #{attr_value}"
              end
            end

            if (@current_tag == 'img' && attr_name == 'src') || (@current_tag == 'link' && attr_name == 'href' && @html_builder[-1].include?('rel="icon"'))
              unless attr_value.include?('var(')
                @functionality[:images] << { url: attr_value, local_path: nil }
                puts "Detected Image: #{attr_value}"
              else
                puts "Skipping invalid image URL with CSS variable: #{attr_value}"
              end
            end

            if @current_tag == 'link' && attr_name == 'href' && @html_builder[-1].include?('rel="stylesheet"')
              @functionality[:css] << { url: attr_value, local_path: nil }
              puts "Detected CSS: #{attr_value}"
            end

            if @current_tag == 'title'
              title_content = lines[i + 2] == 'word' ? lines[i + 3].strip : ''
              @structure[:title] = title_content if title_content
              puts "Title Content: #{title_content}"
            end

            if @current_tag == 'meta' && attr_name == 'name' && lines[i + 2] == 'attribute' && lines[i + 3].include?('content=')
              meta_name = attr_value
              meta_content = lines[i + 3].split('=', 2)[1].gsub(/["\\]/, '').strip
              @structure[:meta_data][meta_name] = meta_content
            end
          end
          i += 1
        elsif line == 'word' && @current_tag
          content = lines[i + 1].strip
          puts "Adding content to #{@current_tag}: #{content}"
          @structure[:content][@current_tag] ||= []
          @structure[:content][@current_tag] << content unless @structure[:content][@current_tag].include?(content)

          if ['button', 'a', 'form', 'input', 'select', 'option', 'textarea'].include?(@current_tag)
            @structure[:functional_content][@current_tag] ||= []
            @structure[:functional_content][@current_tag] << content
          else
            @structure[:visual_content][@current_tag] ||= []
            @structure[:visual_content][@current_tag] << content
          end

          if @html_builder.last.end_with?(">")
            @html_builder[-1] = @html_builder[-1][0..-2] + ">" + content
          else
            @html_builder[-1] += content
          end
          i += 1
        elsif line == 'tag_close'
          tag_name = lines[i + 1]
          puts "Closing tag: #{tag_name}"
          @structure[:tags] << { type: 'close', name: tag_name, position: i }
          if @tag_stack.last == tag_name
            @tag_stack.pop
          else
            puts "Warning: Unbalanced tag </#{tag_name}>, missing opening tag"
          end
          @current_tag = @tag_stack.last
          @html_builder << "</#{tag_name}>"
          in_head = false if tag_name == 'head'
          i += 1
        end
        i += 1
      end

      @html_builder.map! { |tag| tag.start_with?('<') && !tag.include?('>') ? "#{tag}>" : tag }
      puts "Final HTML Builder Content: #{@html_builder.inspect}"
    end

    def analyze_with_ai
      puts "Analyzing structure with Rumale..."
      open_tags = @structure[:tags].select { |t| t[:type] == 'open' }
      return if open_tags.empty?

      attr_features = []
      labels = []

      open_tags.each do |tag|
        attrs = @structure[:attributes].select { |a| a[:tag] == tag[:name] }
        attr_count = attrs.length
        event_handlers = attrs.count { |a| a[:name].start_with?('on') }
        has_id = attrs.any? { |a| a[:name] == 'id' } ? 1 : 0
        has_class = attrs.any? { |a| a[:name] == 'class' } ? 1 : 0
        content_length = (@structure[:content][tag[:name]] || []).join(' ').length
        interactive_score = 0
        interactive_score += 2 if ['button', 'a', 'input', 'select', 'form'].include?(tag[:name])
        interactive_score += 1 if ['div', 'span'].include?(tag[:name]) && 
                                attrs.any? { |a| a[:name] == 'class' && 
                                a[:value].to_s.match(/button|clickable|interactive|menu|nav/i) }
        interactive_score += 1 if event_handlers > 0
        interactive_score += 1 if attrs.any? { |a| a[:value].to_s.match(/button|click|submit|active/i) }

        is_interactive = ['script', 'button', 'a', 'form', 'input', 'select', 'textarea'].include?(tag[:name]) ||
                        event_handlers > 0 ||
                        interactive_score >= 2

        attr_features << [attr_count, event_handlers, has_id, has_class, content_length, interactive_score]
        labels << (is_interactive ? 1 : 0)
      end

      return if attr_features.empty? || labels.empty? || attr_features.length != labels.length

      begin
        puts "Training model with #{attr_features.length} examples..."
        features_array = Numo::DFloat.cast(attr_features)
        labels_array = Numo::Int32.cast(labels)

        if labels.count(1) < labels.count(0) * 0.2 || labels.count(0) < labels.count(1) * 0.2
          puts "Balancing dataset - interactive: #{labels.count(1)}, non-interactive: #{labels.count(0)}"
          minority_label = labels.count(1) < labels.count(0) ? 1 : 0
          minority_indices = labels.each_with_index.select { |l, _| l == minority_label }.map { |_, i| i }

          while labels.count(minority_label) < labels.count(1 - minority_label) * 0.5
            idx = minority_indices.sample
            attr_features << attr_features[idx]
            labels << labels[idx]
          end

          features_array = Numo::DFloat.cast(attr_features)
          labels_array = Numo::Int32.cast(labels)
        end

        @neural_network.fit(features_array, labels_array)
        puts "Neural network trained on #{attr_features.length} tags"
      rescue StandardError => e
        puts "Error training neural network: #{e.message}"
        puts e.backtrace
      end
    end

    def predict_missing_content
      @structure[:predicted_content] = {}
      empty_tags = @structure[:tags].select { |t| t[:type] == 'open' && !@structure[:content][t[:name]]&.any? }

      empty_tags.each do |tag|
        attrs = @structure[:attributes].select { |a| a[:tag] == tag[:name] }
        attr_count = attrs.length
        event_handlers = attrs.count { |a| a[:name].start_with?('on') }
        has_id = attrs.any? { |a| a[:name] == 'id' } ? 1 : 0
        has_class = attrs.any? { |a| a[:name] == 'class' } ? 1 : 0
        content_length = 0
        interactive_score = event_handlers > 0 ? 1 : 0
        interactive_score += 1 if ['button', 'a', 'input', 'select', 'form'].include?(tag[:name])
        interactive_score += 1 if attrs.any? { |a| a[:value].to_s.match(/button|click|submit|active/i) }

        features = [attr_count, event_handlers, has_id, has_class, content_length, interactive_score]

        begin
          prediction = @neural_network.predict(Numo::NArray[features])[0]
          if prediction == 1
            @structure[:predicted_content][tag[:name]] = "Interactive element"
            @structure[:functional_content][tag[:name]] ||= []
            @structure[:functional_content][tag[:name]] << "Interactive element"
          else
            @structure[:predicted_content][tag[:name]] = "Visual element"
            @structure[:visual_content][tag[:name]] ||= []
            @structure[:visual_content][tag[:name]] << "Visual element"
          end
        rescue StandardError => e
          puts "Error predicting for tag #{tag[:name]}: #{e.message}"
          if ['div', 'span', 'p', 'h1', 'h2', 'h3', 'img'].include?(tag[:name])
            @structure[:visual_content][tag[:name]] ||= []
            @structure[:visual_content][tag[:name]] << "Visual element"
          else
            @structure[:functional_content][tag[:name]] ||= []
            @structure[:functional_content][tag[:name]] << "Interactive element"
          end
        end
      end
    end

    def download_with_limits(url, type, index, options = {})
      max_size = options[:max_size] || 10 * 1024 * 1024
      timeout = options[:timeout] || 15
      retries = options[:retries] || 3
      user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36"

      return nil if url.nil? || url.empty?
      full_url = url.start_with?('http') ? url : URI.join(@base_url, url).to_s
      output_dir = File.join(@output_dir, "mirrored_#{type}")
      FileUtils.mkdir_p(output_dir)

      # Исправляем расширение для динамических CSS
      ext = File.extname(URI.parse(full_url).path)
      ext = ".css" if type == 'css' && full_url.include?('css.php') # Для динамических CSS
      ext = ".#{type}" if ext.nil? || ext.empty?
      local_filename = "#{type}_#{index}#{ext}"
      local_path = File.join(output_dir, local_filename)
      full_local_path = local_path # Исправлено: убираем дублирование @output_dir

      puts "Downloading #{type.upcase}: #{full_url}"
      attempt = 0
      while attempt < retries
        begin
          downloaded_size = 0
          URI.open(full_url, "User-Agent" => user_agent, "Accept" => "*/*", "Referer" => @base_url, open_timeout: timeout, read_timeout: timeout) do |remote_file|
            File.open(full_local_path, 'wb') do |local_file|
              while chunk = remote_file.read(65536)
                downloaded_size += chunk.bytesize
                if downloaded_size > max_size
                  local_file.close
                  File.delete(full_local_path) if File.exist?(full_local_path)
                  puts "#{type.upcase} file exceeds size limit (#{max_size / 1024 / 1024}MB): #{full_url}"
                  return nil
                end
                local_file.write(chunk)
              end
            end
          end

          relative_path = File.join(File.basename(output_dir), local_filename)
          puts "#{type.upcase} saved to: #{relative_path}"
          return relative_path
        rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
          attempt += 1
          if attempt < retries
            sleep_time = 2 * attempt
            puts "Timeout downloading #{type} #{full_url}, retrying in #{sleep_time}s (#{retries - attempt} attempts left)..."
            sleep(sleep_time)
          else
            puts "Failed to download #{type} after #{retries} attempts: #{e.message}"
            return nil
          end
        rescue StandardError => e
          puts "Error downloading #{type} #{full_url}: #{e.message}"
          return nil
        end
      end
      nil
    end

    def download_css
      puts "@functionality[:css]: #{@functionality[:css].inspect}"
      @functionality[:css].each_with_index do |css, index|
        css[:local_path] = download_with_limits(css[:url], 'css', index + 1, max_size: 2 * 1024 * 1024)
        if css[:local_path]
          @html_builder.map! do |line|
            line.include?(css[:url]) ? line.gsub(css[:url], css[:local_path]) : line
          end
        end
      end
    end

    def download_javascript
      downloaded_urls = {}
      puts "JavaScript files to download: #{@functionality[:javascript].inspect}"
      @functionality[:javascript].each_with_index do |js, index|
        # Извлекаем базовый URL без параметров
        base_url = js[:url].split('?').first
        if downloaded_urls.key?(base_url)
          js[:local_path] = downloaded_urls[base_url]
          update_html_builder(js[:url], js[:local_path])
          next
        end
        js[:local_path] = download_with_limits(js[:url], 'js', index + 1, max_size: 5 * 1024 * 1024)
        if js[:local_path]
          downloaded_urls[base_url] = js[:local_path]
          update_html_builder(js[:url], js[:local_path])
        end
      end
    end

    def download_images
      downloaded_urls = {}
      @functionality[:images].each_with_index do |img, index|
        if downloaded_urls.key?(img[:url])
          img[:local_path] = downloaded_urls[img[:url]]
          update_html_builder(img[:url], img[:local_path])
          next
        end
        img[:local_path] = download_with_limits(img[:url], 'img', index + 1, max_size: 8 * 1024 * 1024)
        if img[:local_path]
          downloaded_urls[img[:url]] = img[:local_path]
          update_html_builder(img[:url], img[:local_path])
        end
      end
    end

    def update_html_builder(old_url, new_path)
      @html_builder.map! do |line|
        line.include?(old_url) ? line.gsub(old_url, new_path) : line
      end
    end

    def recreate_html
      doc = Nokogiri::HTML::Document.new
      doc.encoding = 'UTF-8'
      unless doc.internal_subset # Добавляем DOCTYPE только если его нет
        begin
          doc.create_internal_subset('html', nil, nil)
        rescue StandardError => e
          puts "Warning: Could not create DOCTYPE: #{e.message}"
        end
      end

      html_node = Nokogiri::XML::Node.new('html', doc)
      html_node['lang'] = 'en'
      doc.add_child(html_node)
      head = Nokogiri::XML::Node.new('head', doc)
      html_node.add_child(head)

      meta_viewport = Nokogiri::XML::Node.new('meta', doc)
      meta_viewport['name'] = 'viewport'
      meta_viewport['content'] = 'width=device-width, initial-scale=1.0'
      head.add_child(meta_viewport)

      meta_charset = Nokogiri::XML::Node.new('meta', doc)
      meta_charset['charset'] = 'utf-8'
      head.add_child(meta_charset)

      title = Nokogiri::XML::Node.new('title', doc)
      title.content = @structure[:title] || 'Mirrored Site'
      head.add_child(title)

      favicon = @functionality[:images].find { |img| img[:url].to_s.include?('favicon') || img[:url].to_s.include?('icon') }
      if favicon && favicon[:local_path]
        link = Nokogiri::XML::Node.new('link', doc)
        link['rel'] = 'icon'
        link['href'] = favicon[:local_path]
        head.add_child(link)
      end

      @functionality[:css].each do |css|
        next unless css[:local_path] && !css[:local_path].empty?
        link = Nokogiri::XML::Node.new('link', doc)
        link['rel'] = 'stylesheet'
        link['href'] = css[:local_path]
        head.add_child(link)
      end

      style = Nokogiri::XML::Node.new('style', doc)
      style.content = <<~CSS
        body { font-family: Arial, sans-serif; margin: 0; padding: 0; line-height: 1.6; }
        img { max-width: 100%; height: auto; }
        @media (max-width: 768px) { body { font-size: 16px; } }
      CSS
      head.add_child(style)

      added_scripts = Set.new # Для отслеживания добавленных скриптов
      @functionality[:javascript].each do |js|
        next unless js[:local_path] && !js[:local_path].empty?
        script_url = js[:local_path]
        next if added_scripts.include?(script_url) # Пропускаем, если скрипт уже добавлен
        next if @html_builder.any? { |line| line.include?(script_url) } # Пропускаем, если скрипт уже есть в HTML

        script = Nokogiri::XML::Node.new('script', doc)
        script['src'] = script_url
        script['defer'] = 'defer'
        script['data-xf-init'] = 'disable-lazy-load'
        script.content = ''
        head.add_child(script)
        added_scripts.add(script_url)
      end

      body = Nokogiri::XML::Node.new('body', doc)
      html_node.add_child(body)

      debug_div = Nokogiri::XML::Node.new('div', doc)
      debug_div['style'] = 'padding: 5px; background: #f9f9f9; color: #666; font-size: 12px; text-align: center;'
      debug_div.content = "This is a mirrored site for analysis purposes - original URL: #{@base_url}"
      body.add_child(debug_div)

      noscript = Nokogiri::XML::Node.new('noscript', doc)
      noscript.inner_html = '<div style="color: red; padding: 10px; text-align: center;">JavaScript is disabled. Some functionality may not work.</div>'
      body.add_child(noscript)

      main_container = Nokogiri::XML::Node.new('div', doc)
      main_container['class'] = 'mirror-container'
      main_container['style'] = 'max-width: 1200px; margin: 0 auto; padding: 15px;'
      body.add_child(main_container)

      if @html_builder.empty?
        fallback = Nokogiri::XML::Node.new('div', doc)
        fallback.content = 'No content was parsed from the input file.'
        main_container.add_child(fallback)
        return doc.to_html
      end

      current_parent = main_container
      parent_stack = [main_container]
      @html_builder.each do |line|
        if line.start_with?('<') && !line.start_with?('</')
          tag_match = line.match(/<(\w+)([^>]*)>(.*)$/)
          if tag_match
            tag_name = tag_match[1]
            attrs_text = tag_match[2]
            content = tag_match[3]
            next if ['base', 'meta', 'title'].include?(tag_name) && current_parent != head
            next if ['html', 'body', 'head'].include?(tag_name)
            next if tag_name == 'script' && attrs_text.include?('src=') && @functionality[:javascript].any? { |js| attrs_text.include?(js[:url]) }
            next if tag_name == 'link' && attrs_text.include?('rel="stylesheet"') && @functionality[:css].any? { |css| attrs_text.include?(css[:url]) }

            new_node = Nokogiri::XML::Node.new(tag_name, doc)
            attrs = attrs_text.scan(/(\w+)=["']([^"']*)["']/)
            attrs.each do |name, value|
              value = value.gsub(/[\x00-\x1F\x7F]/, '')
              new_node[name] = value
            end

            new_node.content = content if content && !content.empty?
            current_parent.add_child(new_node)

            unless ['img', 'br', 'hr', 'meta', 'link', 'input', 'source'].include?(tag_name)
              parent_stack.push(current_parent)
              current_parent = new_node
            end
          end
        elsif line.start_with?('</')
          tag_name = line.match(/<\/(\w+)/)&.[](1)
          next if ['html', 'body', 'head', 'img', 'br', 'hr', 'meta', 'link', 'input', 'source'].include?(tag_name)
          current_parent = parent_stack.pop if !parent_stack.empty?
        elsif !line.strip.empty?
          text_node = Nokogiri::XML::Text.new(line, doc)
          current_parent.add_child(text_node)
        end
      end

      html_output = doc.to_html(indent: 2).gsub('&', '&').gsub(/<(\/?[a-z][a-z0-9]*[^>]*)>/i, '<\1>')
      @structure[:recreated_html] = html_output
      File.write(File.join(@output_dir, 'mirrored_site.html'), html_output)
      html_output
    end

    def prepare_separated_data
      puts "Preparing separated data for JSON files..."
      @structure[:tags].each do |tag|
        if tag[:type] == 'open'
          tag_attrs = @structure[:attributes].select { |a| a[:tag] == tag[:name] }
          is_interactive = ['button', 'a', 'input', 'select', 'textarea', 'form'].include?(tag[:name]) || 
                          tag_attrs.any? { |a| a[:name].start_with?('on') } || 
                          tag_attrs.any? { |a| a[:name] == 'role' && ['button', 'link', 'menu'].include?(a[:value]) }

          if is_interactive
            if tag[:name] == 'form' || tag_attrs.any? { |a| a[:name] == 'class' && a[:value].to_s.include?('form') }
              @functionality[:forms][tag[:name]] ||= []
              @functionality[:forms][tag[:name]] << {
                position: tag[:position],
                content: @structure[:content][tag[:name]],
                attributes: tag_attrs,
                children: find_children(tag)
              }
            elsif tag[:name] == 'nav' || tag_attrs.any? { |a| (a[:name] == 'class' || a[:name] == 'id') && a[:value].to_s.match(/nav|menu/) }
              @functionality[:navigational_elements][tag[:name]] ||= []
              @functionality[:navigational_elements][tag[:name]] << {
                position: tag[:position],
                content: @structure[:content][tag[:name]],
                attributes: tag_attrs,
                children: find_children(tag)
              }
            else
              @functionality[:interactive_elements][tag[:name]] ||= []
              @functionality[:interactive_elements][tag[:name]] << {
                position: tag[:position],
                content: @structure[:content][tag[:name]],
                attributes: tag_attrs
              }
            end
          end
        end
      end

      @structure[:tags].each do |tag|
        if tag[:type] == 'open'
          tag_attrs = @structure[:attributes].select { |a| a[:tag] == tag[:name] }
          next if @functionality[:interactive_elements][tag[:name]] ||
                  @functionality[:forms][tag[:name]] ||
                  @functionality[:navigational_elements][tag[:name]]

          case tag[:name]
          when 'div', 'section', 'article', 'main'
            @visual_structure[:containers][tag[:name]] ||= []
            @visual_structure[:containers][tag[:name]] << {
              position: tag[:position],
              attributes: tag_attrs,
              children_count: count_children(tag),
              content_summary: summarize_content(tag[:name])
            }
          when 'header', 'footer', 'aside', 'nav'
            @visual_structure[:layout_elements][tag[:name]] ||= []
            @visual_structure[:layout_elements][tag[:name]] << {
              position: tag[:position],
              attributes: tag_attrs,
              content_summary: summarize_content(tag[:name])
            }
          when 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'span', 'strong', 'em'
            @visual_structure[:content_blocks][tag[:name]] ||= []
            @visual_structure[:content_blocks][tag[:name]] << {
              position: tag[:position],
              content: @structure[:content][tag[:name]],
              attributes: tag_attrs
            }
          end
        end
      end

      @visual_structure[:html_structure] = generate_html_structure
      @visual_structure[:meta_data] = @structure[:meta_data]
      @visual_structure[:title] = @structure[:title]

      @functionality[:ai_analysis] = {
        interactive_elements_count: @functionality[:interactive_elements].values.flatten.length,
        forms_count: @functionality[:forms].values.flatten.length,
        navigation_elements_count: @functionality[:navigational_elements].values.flatten.length,
        js_files_count: @functionality[:javascript].length,
        css_files_count: @functionality[:css].length
      }

      @visual_structure[:ai_analysis] = {
        containers_count: @visual_structure[:containers].values.flatten.length,
        layout_elements_count: @visual_structure[:layout_elements].values.flatten.length,
        content_blocks_count: @visual_structure[:content_blocks].values.flatten.length,
        images_count: @visual_structure[:images].length
      }
    end

    def count_children(tag)
      start_pos = tag[:position]
      end_tag = @structure[:tags].find { |t| t[:type] == 'close' && t[:name] == tag[:name] && t[:position] > start_pos }
      return 0 unless end_tag
      @structure[:tags].count { |t| t[:type] == 'open' && t[:position] > start_pos && t[:position] < end_tag[:position] }
    end

    def find_children(tag)
      start_pos = tag[:position]
      end_tag = @structure[:tags].find { |t| t[:type] == 'close' && t[:name] == tag[:name] && t[:position] > start_pos }
      return [] unless end_tag
      @structure[:tags].select { |t| t[:type] == 'open' && t[:position] > start_pos && t[:position] < end_tag[:position] }
                    .map { |child_tag|
                      {
                        name: child_tag[:name],
                        attributes: @structure[:attributes].select { |a| a[:tag] == child_tag[:name] },
                        content: @structure[:content][child_tag[:name]]
                      }
                    }
    end

    def summarize_content(tag_name)
      content = @structure[:content][tag_name]
      return "No content" unless content&.any?
      content.length > 5 ? "#{content.first(3).join(' ')}... (#{content.length} items)" : content.join(' ')
    end

    def generate_html_structure
      structure = []
      tag_stack = []
      @structure[:tags].each_with_index do |tag, index|
        break if index >= 50
        if tag[:type] == 'open'
          node = {
            name: tag[:name],
            level: tag_stack.length,
            attributes: @structure[:attributes].select { |a| a[:tag] == tag[:name] }.map { |a| "#{a[:name]}=#{a[:value]}" }
          }
          structure << node
          tag_stack.push(tag[:name])
        elsif tag[:type] == 'close'
          tag_stack.pop if tag_stack.last == tag[:name]
        end
      end
      structure
    end

    def save_to_separated_json(functionality_json, visual_json, html_output)
      puts "Saving analysis results to JSON files..."
      File.write(functionality_json, JSON.pretty_generate(@functionality))
      puts "Saved functionality data to #{functionality_json}"
      File.write(visual_json, JSON.pretty_generate(@visual_structure))
      puts "Saved visual structure data to #{visual_json}"
      File.write(html_output, @structure[:recreated_html])
      puts "Saved recreated HTML to #{html_output}"
    end
  end
end