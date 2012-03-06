require 'rubberband'

module ServerTag
    # Builds you a DBHandler for a given Model class.
    class DBHandlerFactory
        def self.handler_for(model_cls)
            if model_cls == Host
                return HostHandler.new
            elsif model_cls == HistoryEvent
                return HistoryEventHandler.new
            end

            raise "DB handler requested for unknown model #{model_cls}"
        end
    end

    # Handles database operations for the Host model.
    class HostHandler
        # Returns an ES client
        def _client
            ElasticSearch.new('127.0.0.1:9200', :index => "servertag", :type => "host")
        end

        # Converts an ElasticSearch hit to a Host instance.
        def _convert_hit(es_hit)
            h = Host.new
            h.name, h.es_id = es_hit.name, es_hit._id
            h.set_tags!(es_hit.tags)

            h
        end

        # Returns all Host instances in the DB.
        def all
            hits = _client.search("name:*").hits
            hits.map {|hit|; _convert_hit(hit)}
        end

        # Returns the first (and hopefully only) host with the given name.
        def by_name(hostname)
            Host.assert_valid_hostname(hostname)

            hits = _client.search("name:#{hostname}").hits
            raise HTTPNotFoundError.new("No such host: '#{hostname}'") if hits.empty?
            
            _convert_hit(hits[0])
        end

        # Returns all hosts that have the given tag.
        def by_tag(tag)
            hits = _client.search("tags:#{tag.name}").hits
            hits.map {|h|; _convert_hit(h)}
        end

        def remove(host)
            _client.delete(host.es_id)
        end

        def index(host)
            _client.index(host.to_db_hash, :id => host.es_id)
        end
    end

    # Handles database operations for the HistoryEvent model.
    class HistoryEventHandler
        # Returns an ES client
        def _client
            ElasticSearch.new('127.0.0.1:9200', :index => "servertag", :type => "history_event")
        end

        # Converts an ElasticSearch hit to a HistoryEvent instance.
        def _convert_hit(es_hit)
            he = HistoryEvent.new

            he.es_id = es_hit.es_id
            he.datetime = es_hit.datetime
            he.user = es_hit.user
            he.client = es_hit.client
            he.remote_host = es_hit.remote_host
            he.message = es_hit.message

            he
        end

        # Returns the most recent 'n' HistoryEvent instances in the DB.
        def most_recent(n)
            hits = _client.search("*:*",
                                  :sort => {:datetime => {:order => :desc}},
                                  :size => n).hits
            hits.map {|hit|; _convert_hit(hit)}
        end

        # Indexes the given HistoryEvent instance.
        def index(he)
            _client.index(he.to_db_hash)
        end
    end
end
