module ServerTag
    class Config
        attr_accessor :db_server, :auth_method

        # Returns the paths to search for config files, by increasing specificity.
        def _config_paths
            [
                File.join("", "etc", "servertag", "server"),
                File.join(ENV["HOME"], ".servertag", "server")
            ]
        end

        def assert_valid
            raise "No DB server specified (add a 'db_server' attribute to your server config file)" if @db_server.nil?
            raise "No authentication method specified (add an 'auth' attribute to your server config file)" if @auth_method.nil?
            true
        end

        # Parses any config files and sets instance attributes accordingly.
        def parse_config!
            paths = _config_paths()
            config = {}
            paths.each do |path|
                if File.readable?(path)
                    config.merge!(JSON.load(open(path).read))
                end
            end

            if config.key?("db_server")
                @db_server = config["db_server"]
            end

            if config.key?("auth")
                @auth_method = AuthMethodFactory.from_config_hash(config["auth"])
            end

            assert_valid

            nil
        end
    end
end
