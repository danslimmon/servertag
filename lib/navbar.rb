module ServerTag
    # A link in the navbar.
    class NavbarLink
        attr_accessor :path, :title

        def initialize(key, path, title, active_page)
            @_key = key
            @path = path
            @title = title
            @_is_active = (key == active_page)
        end

        def active?; @_is_active; end
    end

    # A navbar like we display at the top of every HTML page.
    class Navbar
        def initialize(active_page)
            @_active_page = active_page
        end

        def links
            [
                NavbarLink.new(:host_index, "/", "Host List", @_active_page),
                NavbarLink.new(:history, "/history", "History", @_active_page)
            ]
        end
    end
end
