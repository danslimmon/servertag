require 'rubberband'


module ServerTag
    class Host
        attr_accessor :es_id

        def initialize
            @_client = nil
        end

        def self.find_by_name(hostname)
            _assert_valid_hostname(hostname)
            client = _new_client

            hits = client.search("name:#{hostname}").hits
            raise HTTPNotFoundError.new("No such host: '#{hostname}'") if hits.empty?
            
            _hit_to_host(hits[0])
        end
        
        def self.all
            client = _new_client
            hits = client.search("name:*").hits
            hits.map {|hit|; _hit_to_host(hit)}
        end

        # Converts an elasticsearch hit instance to a Host instance.
        def self._hit_to_host(es_hit)
            h = Host.new
            h.name, h.tags, h.es_id = es_hit.name, es_hit.tags, es_hit._id

            h
        end

        def self._new_client
            ElasticSearch.new('127.0.0.1:9200', :index => "servertag", :type => "host")
        end

        def self._assert_valid_hostname(hostname)
            unless hostname =~ /^[a-z0-9-]+$/
                raise HTTPBadRequestError.new(
                    "Invalid hostname specified: '#{hostname}'")
            end
        end

        def _assert_savable
            if @name.empty? or not @tags.is_a?(Array)
                raise HTTPInternalServerError.new(
                    "Tried to save invalid host to DB:\n\n#{self.inspect}")
            end
        end

        def <=>(other_host)
            @name <=> other_host.name
        end

        def _populate_client!
            @_client = Host._new_client() if @_client.nil?
        end

        def tags
            @tags
        end

        def tags=(new_tags)
            @tags = new_tags.map {|tag|; tag.downcase}
        end

        def name
            @name
        end

        def name=(new_name)
            @name = new_name.downcase
        end

        def save
            _assert_savable
            _populate_client!

            @_client.index({:name => @name, :tags => @tags}, :id => @es_id)
        end
    end
end
