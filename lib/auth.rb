require 'digest/sha1'

module ServerTag
    class AuthMethodFactory
        # Returns an appropriate AuthMethod subclass instance depending on the "auth"
        # hash from the server config.
        def self.from_config_hash(config_hash)
            if config_hash["method"] == "none"
                meth = NoAuth.new
            elsif config_hash["method"] == "htpasswd"
                meth = HTPasswdAuth.new
            end

            meth.populate!(config_hash)
            meth
        end
    end

    class AuthMethod
        # Returns a boolean indicating whether the user should be allowed access
        def auth_valid?(username, password); raise NotImplementedError; end

        # Given the "auth"
        def populate!(config_hash); raise NotImplementedError; end
    end

    class NoAuth < AuthMethod
        def auth_valid?(username, password)
            true
        end

        def populate!(config_hash); end
    end

    # Base auth on an htpasswd-style file (SHA1 password hashes only)
    #
    # Doesn't work before Ruby 1.9
    class HTPasswdAuth < AuthMethod
        def auth_valid?(username, password)
            password = Digest::SHA1.base64digest(password)

            htpasswd_file = File.read("/home/httpd/local/htpasswd")
            htpasswd_array = htpasswd_file.split("\n")
            htpasswd_record = htpasswd_array.grep(/#{username}:/)[0].split(":{SHA}")

            [username, password] == htpasswd_record
        end

        def populate!(config_hash)
            raise "No htpasswd file specified" unless config_hash.key?("path")
            raise "htpasswd file missing; should be at '#{config_hash["path"]}'" unless File.exists?(config_hash["path"])
            raise "htpasswd file at '#{config_hash["path"]}' not readable" unless File.readable?(config_hash["path"])

            @_path = config_hash["path"]
        end
    end
end
