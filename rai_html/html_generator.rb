module RAIHtml
  class HtmlGenerator
    def initialize(analyzer)
      @analyzer = analyzer
      @structure = analyzer.structure
      @functionality = analyzer.functionality
      @base_url = analyzer.base_url
    end

    def create_index_html
      index_path = File.join(@analyzer.output_dir, 'index.html')
      html_content = generate_html_content
      File.write(index_path, html_content)
      puts "Created index.html at #{index_path}"
      
      # Generate sample JSON files if they don't exist (for testing)
      create_sample_json_files unless @functionality.nil? && @structure.nil?
    end
    
    def create_sample_json_files
      # Save functionality JSON
      functionality_path = File.join(@analyzer.output_dir, 'site_functionality.json')
      File.write(functionality_path, JSON.pretty_generate(@functionality)) unless @functionality.nil?
      
      # Save visual structure JSON
      structure_path = File.join(@analyzer.output_dir, 'site_visual_structure.json')
      File.write(structure_path, JSON.pretty_generate(@structure)) unless @structure.nil?
    end

    private

    def generate_html_content
      css_count = @functionality && @functionality[:css] ? @functionality[:css].length : 0
      js_count = @functionality && @functionality[:javascript] ? @functionality[:javascript].length : 0
      img_count = @functionality && @functionality[:images] ? @functionality[:images].length : 0
      site_title = @structure && @structure[:title] ? @structure[:title] : 'Unknown Site'

      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Website Analysis Results - #{site_title}</title>
          <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.4/css/all.min.css">
          <style>
            :root {
              --primary-color: #4285f4;
              --secondary-color: #34a853;
              --dark-color: #202124;
              --light-color: #f8f9fa;
              --border-color: #dadce0;
            }

            * { box-sizing: border-box; }

            body {
              font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
              line-height: 1.6;
              color: var(--dark-color);
              background-color: var(--light-color);
              margin: 0;
              padding: 0;
            }

            .header {
              background-color: var(--primary-color);
              color: white;
              padding: 20px;
              text-align: center;
              box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            }

            .container {
              max-width: 1400px;
              margin: 0 auto;
              padding: 20px;
            }

            .dashboard {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
              gap: 20px;
              margin-bottom: 30px;
            }

            .stat-card {
              background: white;
              border-radius: 8px;
              padding: 20px;
              box-shadow: 0 2px 10px rgba(0,0,0,0.05);
              transition: transform 0.3s;
            }

            .stat-card:hover {
              transform: translateY(-5px);
              box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            }

            .stat-card h3 {
              margin-top: 0;
              color: var(--primary-color);
              font-size: 18px;
              display: flex;
              align-items: center;
            }

            .stat-card h3 i {
              margin-right: 10px;
            }

            .stat-value {
              font-size: 32px;
              font-weight: bold;
              margin: 10px 0;
              color: var(--dark-color);
            }

            .panels {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(600px, 1fr));
              gap: 20px;
            }

            .panel {
              background: white;
              border-radius: 8px;
              padding: 20px;
              box-shadow: 0 2px 10px rgba(0,0,0,0.05);
            }

            .panel h2 {
              margin-top: 0;
              color: var(--primary-color);
              border-bottom: 1px solid var(--border-color);
              padding-bottom: 10px;
              display: flex;
              align-items: center;
            }

            .panel h2 i {
              margin-right: 10px;
            }

            .json-viewer {
              height: 500px;
              overflow: auto;
              background: #f5f5f5;
              border-radius: 4px;
              padding: 15px;
              position: relative;
              font-family: 'Courier New', monospace;
              font-size: 14px;
            }

            .json-viewer.loading::before {
              content: 'Loading...';
              position: absolute;
              top: 50%;
              left: 50%;
              transform: translate(-50%, -50%);
            }

            .action-buttons {
              display: flex;
              flex-wrap: wrap;
              gap: 10px;
              margin-top: 15px;
            }

            .btn {
              display: inline-flex;
              align-items: center;
              background: var(--primary-color);
              color: white;
              border: none;
              padding: 10px 15px;
              border-radius: 4px;
              text-decoration: none;
              font-weight: 500;
              transition: background 0.3s;
              cursor: pointer;
            }

            .btn i {
              margin-right: 8px;
            }

            .btn:hover {
              background: #3367d6;
            }

            .btn.secondary {
              background: var(--secondary-color);
            }

            .btn.secondary:hover {
              background: #2d9249;
            }

            footer {
              text-align: center;
              padding: 20px;
              margin-top: 40px;
              border-top: 1px solid var(--border-color);
              color: #70757a;
            }

            @media (max-width: 768px) {
              .panels {
                grid-template-columns: 1fr;
              }

              .dashboard {
                grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
              }

              .json-viewer {
                height: 300px;
              }
            }

            /* JSON Syntax Highlighting */
            .json-key { color: #0451a5; }
            .json-string { color: #a31515; }
            .json-number { color: #098658; }
            .json-boolean { color: #0000ff; }
            .json-null { color: #0000ff; }
            .collapsible { cursor: pointer; user-select: none; margin-right: 5px; }
            .collapsible.collapsed::before { content: '►'; }
            .collapsible.expanded::before { content: '▼'; }
            
            /* Error message styling */
            .error-message {
              color: #d32f2f;
              background-color: #ffebee;
              padding: 10px;
              border-radius: 4px;
              margin: 10px 0;
              border-left: 4px solid #d32f2f;
            }
          </style>
        </head>
        <body>
          <div class="header">
            <h1>Website Analysis Results</h1>
            <p>Analyzed Site: <strong>#{site_title}</strong></p>
            <p>URL: <a href="#{@base_url}" target="_blank" style="color: white; text-decoration: underline;">#{@base_url}</a></p>
            <a href="mirrored_site.html" class="btn" style="margin-top: 10px;"><i class="fas fa-external-link-alt"></i> View Mirrored Site</a>
          </div>

          <div class="container">
            <div class="dashboard">
              <div class="stat-card">
                <h3><i class="fas fa-file-code"></i> CSS Files</h3>
                <div class="stat-value">#{css_count}</div>
              </div>
              <div class="stat-card">
                <h3><i class="fas fa-file-code"></i> JavaScript Files</h3>
                <div class="stat-value">#{js_count}</div>
              </div>
              <div class="stat-card">
                <h3><i class="fas fa-image"></i> Images</h3>
                <div class="stat-value">#{img_count}</div>
              </div>
            </div>

            <div class="panels">
              <div class="panel">
                <h2><i class="fas fa-sitemap"></i> Site Functionality</h2>
                <div class="json-viewer loading" id="functionalityViewer">Loading functionality data...</div>
                <div class="action-buttons">
                  <button class="btn" id="expandAllBtn"><i class="fas fa-expand-arrows-alt"></i> Expand All</button>
                  <button class="btn secondary" id="collapseAllBtn"><i class="fas fa-compress-arrows-alt"></i> Collapse All</button>
                </div>
              </div>
              <div class="panel">
                <h2><i class="fas fa-eye"></i> Visual Structure</h2>
                <div class="json-viewer loading" id="visualViewer">Loading visual structure data...</div>
                <div class="action-buttons">
                  <button class="btn" id="expandAllBtnVisual"><i class="fas fa-expand-arrows-alt"></i> Expand All</button>
                  <button class="btn secondary" id="collapseAllBtnVisual"><i class="fas fa-compress-arrows-alt"></i> Collapse All</button>
                </div>
              </div>
            </div>
          </div>

          <footer>
            <p>Generated on #{Time.now.strftime('%B %d, %Y at %H:%M')} | Web Analysis Tool v1.0</p>
          </footer>

          <script>
            // Initialize JSON viewers with loading state
            const functionalityViewer = document.getElementById('functionalityViewer');
            const visualViewer = document.getElementById('visualViewer');
            
            // Load functionality data directly (without using service workers)
            function loadFunctionalityData() {
              const xhr = new XMLHttpRequest();
              xhr.open('GET', 'site_functionality.json', true);
              xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                  functionalityViewer.classList.remove('loading');
                  if (xhr.status === 200) {
                    try {
                      const data = JSON.parse(xhr.responseText);
                      functionalityViewer.innerHTML = formatJSON(data);
                    } catch (error) {
                      functionalityViewer.innerHTML = '<div class="error-message">Error parsing JSON: ' + error.message + '</div>';
                    }
                  } else {
                    functionalityViewer.innerHTML = '<div class="error-message">Error loading data: ' + xhr.status + ' ' + xhr.statusText + '</div>';
                  }
                }
              };
              xhr.send();
            }
            
            // Load visual structure data directly (without using service workers)
            function loadVisualStructureData() {
              const xhr = new XMLHttpRequest();
              xhr.open('GET', 'site_visual_structure.json', true);
              xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                  visualViewer.classList.remove('loading');
                  if (xhr.status === 200) {
                    try {
                      const data = JSON.parse(xhr.responseText);
                      visualViewer.innerHTML = formatJSON(data);
                    } catch (error) {
                      visualViewer.innerHTML = '<div class="error-message">Error parsing JSON: ' + error.message + '</div>';
                    }
                  } else {
                    visualViewer.innerHTML = '<div class="error-message">Error loading data: ' + xhr.status + ' ' + xhr.statusText + '</div>';
                  }
                }
              };
              xhr.send();
            }
            
            // Load data when page loads
            window.addEventListener('DOMContentLoaded', function() {
              loadFunctionalityData();
              loadVisualStructureData();
            });

            // Toggle JSON viewers for functionality
            document.getElementById('expandAllBtn').addEventListener('click', function() {
              const collapsedElements = document.querySelectorAll('#functionalityViewer .collapsible.collapsed');
              collapsedElements.forEach(el => el.click());
            });

            document.getElementById('collapseAllBtn').addEventListener('click', function() {
              const expandedElements = document.querySelectorAll('#functionalityViewer .collapsible.expanded');
              expandedElements.forEach(el => el.click());
            });

            // Toggle JSON viewers for visual structure
            document.getElementById('expandAllBtnVisual').addEventListener('click', function() {
              const collapsedElements = document.querySelectorAll('#visualViewer .collapsible.collapsed');
              collapsedElements.forEach(el => el.click());
            });

            document.getElementById('collapseAllBtnVisual').addEventListener('click', function() {
              const expandedElements = document.querySelectorAll('#visualViewer .collapsible.expanded');
              expandedElements.forEach(el => el.click());
            });

            // Function to format JSON with syntax highlighting and collapsible nodes
            function formatJSON(obj) {
              const jsonLinesByType = {
                'string': value => `<span class="json-string">"${escapeHTML(value)}"</span>`,
                'number': value => `<span class="json-number">${value}</span>`,
                'boolean': value => `<span class="json-boolean">${value}</span>`,
                'null': () => `<span class="json-null">null</span>`,
                'undefined': () => `<span class="json-null">undefined</span>`,
                'object': function(value, indent) {
                  if (value === null) return jsonLinesByType['null']();
                  if (Array.isArray(value)) return formatArray(value, indent);
                  return formatObject(value, indent);
                }
              };

              function escapeHTML(str) {
                if (typeof str !== 'string') return str;
                return str.replace(/&/g, '&amp;')
                        .replace(/</g, '&lt;')
                        .replace(/>/g, '&gt;')
                        .replace(/"/g, '&quot;')
                        .replace(/'/g, '&#39;');
              }

              function formatObject(obj, indent = 0) {
                if (!obj || Object.keys(obj).length === 0) return '{}';

                const indentStr = '  '.repeat(indent);
                const childIndentStr = '  '.repeat(indent + 1);

                let result = '{\n';
                const keys = Object.keys(obj);

                for (let i = 0; i < keys.length; i++) {
                  const key = keys[i];
                  const value = obj[key];
                  const valueType = typeof value;
                  const isLast = i === keys.length - 1;

                  result += `${childIndentStr}<span class="json-key">"${escapeHTML(key)}"</span>: `;

                  if (valueType === 'object' && value !== null && (Object.keys(value).length > 0 || Array.isArray(value) && value.length > 0)) {
                    result += `<span class="collapsible expanded" onclick="this.classList.toggle('expanded'); this.classList.toggle('collapsed'); this.nextElementSibling.style.display = this.nextElementSibling.style.display === 'none' ? 'inline' : 'none';">▼</span>`;
                    result += `<span>${jsonLinesByType[valueType](value, indent + 1)}</span>`;
                  } else {
                    result += jsonLinesByType[valueType](value, indent + 1);
                  }

                  result += isLast ? '\n' : ',\n';
                }

                result += `${indentStr}}`;
                return result;
              }

              function formatArray(arr, indent = 0) {
                if (!arr || arr.length === 0) return '[]';

                const indentStr = '  '.repeat(indent);
                const childIndentStr = '  '.repeat(indent + 1);

                let result = '[\n';

                for (let i = 0; i < arr.length; i++) {
                  const value = arr[i];
                  const valueType = typeof value;
                  const isLast = i === arr.length - 1;

                  result += childIndentStr;

                  if (valueType === 'object' && value !== null && (Object.keys(value).length > 0 || Array.isArray(value) && value.length > 0)) {
                    result += `<span class="collapsible expanded" onclick="this.classList.toggle('expanded'); this.classList.toggle('collapsed'); this.nextElementSibling.style.display = this.nextElementSibling.style.display === 'none' ? 'inline' : 'none';">▼</span>`;
                    result += `<span>${jsonLinesByType[valueType](value, indent + 1)}</span>`;
                  } else {
                    result += jsonLinesByType[valueType](value, indent + 1);
                  }

                  result += isLast ? '\n' : ',\n';
                }

                result += `${indentStr}]`;
                return result;
              }

              try {
                return jsonLinesByType['object'](obj);
              } catch (error) {
                return '<div class="error-message">Error formatting JSON: ' + error.message + '</div>';
              }
            }
          </script>
        </body>
        </html>
      HTML
    end
  end
end