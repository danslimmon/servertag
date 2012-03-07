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

        # Adds the named tags to the Host. Returns the list of (names of) tags that were added.
        #
        # (So the return value doesn't contain any tags that were already present)
        def add_tags!(tag_names)
            new_tags = tag_names.map {|tag_name|; Tag.new(tag_name)}

            # Maintain exclusivity
            new_prefixes = new_tags.
                select {|tag|; tag.exclusive}.
                map {|tag|; tag.prefix}
            @tags.reject! do |current_tag|
                # Remove any exclusive tags that have the same prefix as one of
                # the new ones.
                current_tag.exclusive and new_prefixes.include?(current_tag.prefix)
            end

            rval = (new_tags - @tags).map {|t|; t.name}
            @tags = (@tags + new_tags).uniq
            return rval
        end

        def remove_tags!(tag_names_to_remove)
            # We convert to Tag instances to get the name normalization done
            # before comparing
            tags_to_remove = tag_names_to_remove.map {|tagname|; Tag.new(tagname).name}
            
            rval = tag_names_to_remove.select {|tagname|; tag_names.include?(tagname)}
            @tags.reject! {|tag|; tag_names_to_remove.include?(tag.name)}
            return rval
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
        def to_ajax_hash(new_tag_names=[])
            {
                "hostname" => @name,
                "tags" => @tags.sort.map {|tag|; tag.to_ajax_hash(new_tag_names)}
            }
        end

        def remove!
            @_removed = true
        end

        def to_db_hash
            {:name => @name,
             :tags => tag_names}
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
        def to_ajax_hash(new_tag_names=[])
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

    # Something a user has done in a request, e.g. adding some tags to some hosts.
    #
    # 'datetime' is always stored in UTC. It's someone else's job to switch it to
    # local time if desired.
    #
    # 'type' is either :add or :remove
    # 'changed_tags' is a hash mapping each host name to the lists of tag namse that
    #   changed on that host.
    class HistoryEvent < Model
        attr_accessor :datetime, :user, :client, :remote_host, :diffs

        def initialize
            @_db_handler = DBHandlerFactory.handler_for(HistoryEvent)
            super()
        end
        
        # Populates the HistoryEvent instance with change data provided by the user.
        #
        # 'datetime' will be a Ruby DateTime instance, 'type' will be either :add or
        # :remove, and 'changed_tags' will be the list of tags that were added or
        # removed.
        def populate_from_change!(datetime, user, client, remote_host, type, changed_tags)
            @datetime = datetime.new_offset(0)
            @user = user
            @client = client
            @remote_host = remote_host
            @diffs = _generate_diffs(type, changed_tags)
        end

        # Populates the HistoryEvent with data from our DB (an ElasticSearch hit instance)
        def populate_from_db!(es_hit)
            @datetime = DateTime.parse(es_hit.datetime)
            @user = es_hit.user
            @client = es_hit.client
            @remote_host = es_hit.remote_host
            @diffs = es_hit.diffs

            @es_id = es_hit._id
        end

        # Generates message parts for the history event given the type of event and the changed tag
        # names.
        def _generate_diffs(type, changed_by_host)
            # 'changed_by_tag' is a hash indexed by _array of tagnames_ where the value
            # is the array of hostnames on which that exact change was made.
            #
            # We need to do it this way because we want to say shit like "Added tags 'foo' and
            # 'bar' to host 'cleon'. Added tag 'foo' to host 'swan'.
            changed_by_tags = {}
            changed_by_tags.default = []
            changed_by_host.each_pair do |hostname,tagnames|
                changed_by_tags[tagnames] = changed_by_tags[tagnames] + [hostname]
            end

            diffs = []
            changed_by_tags.each_pair do |tagnames,hostnames|
                diffs << {:add => "Added tag(s) %s to host(s) %s",
                          :remove => "Removed tag(s) %s from host(s) %s"}[type] %
                         [_pp_list(tagnames), _pp_list(hostnames)]
            end
            diffs
        end

        # Pretty-prints the list of strings.
        #
        # E.g. _pp_list(['alpha', 'bravo', 'charlie']) yields "'alpha', 'bravo', and 'charlie'".
        def _pp_list(a)
            s = ""
            s += a[0..-2].map {|w|; "'#{w}'"}.join(", ")
            # Oxford comma
            s += "," if a.length > 2
            s += " and " if a.length > 1
            s += "'#{a[-1]}'"

            s
        end

        def to_db_hash
            {:datetime => @datetime.strftime("%FT%T"),
             :user => @user,
             :client => @client,
             :remote_host => @remote_host,
             :diffs => @diffs}
        end

        def save
            @_db_handler.index(self)
        end
    end
end
