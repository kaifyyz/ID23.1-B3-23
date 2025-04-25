# rai_html/server.rb
module RAIHtml
  class Server
    def initialize(output_dir)
      @output_dir = output_dir
    end

    def start(port = 8000)
      server = WEBrick::HTTPServer.new(
        Port: port,
        DocumentRoot: Dir.pwd,
        AccessLog: [],
        Logger: WEBrick::Log.new(File.join(@output_dir, "server.log")),
        ReadTimeout: 300,
        RequestTimeout: 300,
        DoNotReverseLookup: true,
        MaxClients: 100
      )

      mime_types = WEBrick::HTTPUtils::DefaultMimeTypes.merge({
        "js" => "application/javascript",
        "css" => "text/css",
        "json" => "application/json",
        "svg" => "image/svg+xml"
      })

      server.mount_proc '/' do |req, res|
        res.set_redirect(WEBrick::HTTPStatus::Found, "/#{@output_dir}/index.html")
      end

      server.mount_proc "/#{@output_dir}" do |req, res|
        handle_request(req, res, mime_types)
      end

      trap('INT') { server.shutdown }
      trap('TERM') { server.shutdown }

      puts "Server running at http://localhost:#{port}/"
      puts "Press Ctrl+C to stop"
      server.start
    end

    private

    def handle_request(req, res, mime_types)
      requested_path = req.path.sub(/^\/#{@output_dir}\//, '')
      requested_path = "index.html" if requested_path.empty? || requested_path == "/"
      local_path = File.join(Dir.pwd, @output_dir, requested_path)

      if File.exist?(local_path) && !File.directory?(local_path)
        file_size = File.size(local_path)
        ext = File.extname(local_path).gsub(/^\./, '').downcase
        res.content_type = mime_types[ext] || 'application/octet-stream'

        if ['text/html', 'text/css', 'application/javascript', 'application/json'].include?(res.content_type)
          if req['Accept-Encoding']&.include?('gzip')
            res['Content-Encoding'] = 'gzip'
            res.chunked = true
            res.body = proc do |socket|
              gz = Zlib::GzipWriter.new(socket)
              File.open(local_path, 'rb') { |file| gz.write(file.read) }
              gz.close
            end
          else
            stream_file(res, local_path, file_size)
          end
        else
          stream_file(res, local_path, file_size)
        end
      else
        res.status = 404
        res.content_type = 'text/html'
        res.body = "<html><body><h1>404 Not Found</h1><p>File not found: #{req.path}</p></body></html>"
      end
    end

    def stream_file(response, file_path, file_size)
      response.chunked = true
      response.body = if file_size > 1024 * 1024
        proc do |socket|
          File.open(file_path, 'rb') do |file|
            while chunk = file.read(65536)
              socket.write(chunk)
            end
          end
        end
      else
        File.read(file_path, mode: 'rb')
      end
    end
  end
end