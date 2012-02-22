require 'rubberband'


module ServerTag
    class Host
        attr_accessor :es_id

        def initialize
            @_client = nil
            @_removed = false
        end

        def self.find_by_name(hostname)
            _assert_valid_hostname(hostname)
            client = _new_client

            hits = client.search("name:#{hostname}").hits
            raise HTTPNotFoundError.new("No such host: '#{hostname}'") if hits.empty?
            
            _hit_to_host(hits[0])
        end

        def self.find_by_tag(tag)
            client = _new_client
            hits = client.search("tags:#{tag.name}").hits
            hits.map {|h|; _hit_to_host(h)}
        end
        
        def self.all
            client = _new_client
            hits = client.search("name:*").hits
            hits.map {|hit|; _hit_to_host(hit)}
        end

        # Converts an elasticsearch hit instance to a Host instance.
        def self._hit_to_host(es_hit)
            h = Host.new
            h.name, h.es_id = es_hit.name, es_hit._id
            h.add_tags!(es_hit.tags)

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

        def add_tags!(tag_names)
            @tags = tag_names.map {|tag_name|; Tag.new(tag_name)}
        end

        def name
            @name
        end

        def name=(new_name)
            @name = new_name.downcase
        end

        def remove!
            @_removed = true
        end

        def save
            _assert_savable
            _populate_client!

            if @_removed
                @_client.delete(@es_id)
            else
                @_client.index({:name => @name, :tags => _tag_names}, :id => @es_id)
            end
        end
    end

    class HistoryEvent
        attr_accessor :es_id

        def initialize(message)
            @_client = nil
        end

        def self.search_for_terms(terms)
            client = _new_client
            hits = client.search("message:*").hits
            hits.map {|hit|; _hit_to_event(hit)}
        end

        # Converts an elasticsearch hit instance to a HistoryEvent instance.
        def self._hit_to_event(es_hit)
            he = HistoryEvent.new
            he.message, he.es_id = es_hit.message, es_hit._id

            he
        end

        def self._new_client
            ElasticSearch.new('127.0.0.1:9200', :index => "servertag", :type => "history_event")
        end

        def _assert_savable
            if @message.empty?
                raise HTTPInternalServerError.new(
                    "Tried to save invalid history event to DB:\n\n#{self.inspect}")
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

        def _tag_names
            @tags.map {|tag|; tag.name}
        end

        def add_tags!(new_tag_names)
            @tags = new_tag_names.map {|tag_name|; Tag.new(tag_name)}
            puts @tags.inspect
        end

        def name
            @name
        end

        def name=(new_name)
            @name = new_name.downcase
        end

        def remove!
            @_removed = true
        end

        def save
            _assert_savable
            _populate_client!

            if @_removed
                @_client.delete(@es_id)
            else
                @_client.index({:name => @name, :tags => _tag_names}, :id => @es_id)
            end
        end
    end

    class Tag
        attr_accessor :name, :exclusive, :prefix, :suffix

        def initialize(tag_name)
            @name = _normalize(tag_name)
            @exclusive = false
            @prefix = nil
            @suffix = nil

            unless (tag_name =~ /(.+):(.+)/).nil?
                @exclusive = true
                @prefix = $1
                @suffix = $2
            end
        end

        def <=>(other_tag)
            @name <=> other_tag.name
        end

        def _normalize(tag_name)
            tag_name.downcase
        end
    end

    class NullTag < Tag
        def initialize
            super("")
        end
    end
end
