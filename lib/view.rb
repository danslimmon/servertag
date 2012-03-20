module ServerTag
    class View
        # Initializes given the base name of the template and the type of data to return.
        #
        # 'accept' may be an array like Sinatra's 'request.accept' or a single symbol such
        # as :json or :html.
        def initialize(base_name, accept)
            @base_name = base_name
            @accept = accept
        end
        
        def template_name
            "#{@base_name}.#{_template_infix}".to_sym
        end

        # Determines whether sinatra's layout functionality should be used.
        def layout?
            content_type == "text/html"
        end

        def content_type
            @accept.each do |type|
                if %w{text/html text/x-json application/json}.include?(type)
                    return type
                end
            end

            # Default is HTML.
            "text/html"
        end

        # Determines the type part of the template name from our content-type
        #
        # E.g. if content_type is "text/html", will return "html".
        def _template_infix
            infix_map = {"text/x-json" => "json",
                         "application/json" => "json",
                         "text/html" => "html"}
            infix_map.default = "html"
            return infix_map[content_type]
        end
    end
end
