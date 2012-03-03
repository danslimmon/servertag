module ServerTag
    # Abstract for models.
    class Model
        attr_accessor :es_id
    end

    class Host < Model
        def initialize
            @_removed = false
            @_db_handler = DBHandlerFactory.handler_for(Host)
            super
        end

        # Raises an error unless the given hostname follows the rules for
        # hostnames.
        def self.assert_valid_hostname(hostname)
            unless hostname =~ /^[a-z0-9-]+$/
                raise HTTPBadRequestError.new(
                    "Invalid hostname specified: '#{hostname}'")
            end
        end

        def _assert_savable
            Host.assert_valid_hostname(@name) 
            unless @tags.is_a?(Array)
                raise HTTPInternalServerError.new(
                    "Tried to save invalid host to DB:\n\n#{self.inspect}")
            end
        end

        def <=>(other_host)
            @name <=> other_host.name
        end

        def tag_names
            @tags.map {|tag|; tag.name}
        end

        def tags
            @tags
        end

        def set_tags!(tag_names)
            @tags = tag_names.map {|tag_name|; Tag.new(tag_name)}.uniq
        end

        def add_tags!(tag_names)
            new_tags = tag_names.map {|tag_name|; Tag.new(tag_name)}
            new_prefixes = new_tags.
                select {|tag|; tag.exclusive}.
                map {|tag|; tag.prefix}
            @tags.reject! do |current_tag|
                # Remove any exclusive tags that have the same prefix as one of
                # the new ones.
                current_tag.exclusive and new_prefixes.include?(current_tag.prefix)
            end
            @tags = (@tags + new_tags).uniq
        end

        def remove_tags!(tag_names_to_remove)
            # We convert to Tag instances to get the name normalization done
            # before comparing
            tag_names_to_remove = tag_names_to_remove.map {|tagname|; Tag.new(tagname).name}
            @tags.reject! {|tag|; tag_names_to_remove.include?(tag.name)}
        end

        def name
            @name
        end

        def name=(new_name)
            @name = new_name.downcase
        end

        # Returns the Host instance as a hash for return values of AJAX calls.
        #
        # If passed, new_tag_names determines the value of each Tag hash's 'just_added'
        # attribute.
        def to_hash(new_tag_names=[])
            {
                "hostname" => @name,
                "tags" => @tags.sort.map {|tag|; tag.to_hash(new_tag_names)}
            }
        end

        def remove!
            @_removed = true
        end

        def save
            _assert_savable

            if @_removed
                @_db_handler.delete(self)
            else
                @_db_handler.index(self)
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

        def self.assert_valid_tagname(tagname)
            unless tagname =~ /^[A-Za-z0-9\-_:]+$/
                raise HTTPBadRequestError.new(
                    "Invalid tag name specified: '#{tagname}'")
            end
        end

        def <=>(other_tag)
            @name <=> other_tag.name
        end

        # Must override this and #hash to get uniqueness checking
        def eql?(other_tag)
            @name == other_tag.name
        end

        def hash
            @name.hash
        end

        def _normalize(tag_name)
            tag_name.downcase
        end

        # Returns the Tag instance as a hash, for return values for AJAX calls
        def to_hash(new_tag_names=[])
            {
                "name" => @name,
                "exclusive" => @exclusive,
                "just_added" => new_tag_names.include?(@name)
            }
        end
    end

    class NullTag < Tag
        def initialize
            super("")
        end
    end

    # Something a user has done in a request, e.g. adding some tags to a host.
    class HistoryEvent < Model
        attr_accessor :datetime, :user, :user_agent, :remote_host, :action_group

        def initialize(datetime, user, user_agent, remote_host, action_group)
            @datetime = datetime
            @user = user
            @user_agent = user_agent
            @remote_host = remote_host
            @action_group = action_group
            super
        end

        def _es_object_type; "history_event"; end

        def save
            _populate_client!

            @_client.index({:name => @name, :tags => _tag_names}, :id => @es_id)
        end
    end
end
