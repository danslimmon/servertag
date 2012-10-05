require 'lib/db_handler'

module ServerTag
    # Abstract for models.
    class Model
        attr_accessor :es_id
        attr_accessor :es_version
    end

    class Host < Model
        def initialize
            @name = ""
            @tags = []

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

        def set_tags_by_name!(tag_names)
            @tags = tag_names.map {|tag_name|; Tag.new(tag_name)}.uniq
        end

        # Adds the given Tag instances to the Host. Returns the list of (names of) tags that were added.
        #
        # (The return value doesn't contain any tags that were already present)
        def add_tags!(new_tags)
            # Maintain exclusivity
            new_prefixes = new_tags.
                select {|tag|; tag.exclusive}.
                map {|tag|; tag.prefix}
            @tags.reject! do |current_tag|
                # Remove any exclusive tags that have the same prefix as one of
                # the new ones.
                current_tag.exclusive and new_prefixes.include?(current_tag.prefix)
            end

            rval = new_tags - @tags
            @tags = (@tags + new_tags).uniq
            return rval
        end

        # Adds the named tags to the host.
        #
        # Returns the list of Tag instances that were added (and not the ones
        # that were already there)
        def add_tags_by_name!(tag_names)
            tags = tag_names.map {|tag_name|; Tag.new(tag_name)}
            return add_tags!(tags)
        end

        # Removes the given Tag instances from the Host. Returns the list of Tags that were added.
        #
        # (The return value doesn't contain any tags that were already present)
        def remove_tags!(tags_to_remove)
            rval = tags_to_remove.select {|tag|; @tags.include?(tag)}
            @tags.reject! {|tag|; tags_to_remove.include?(tag)}
            return rval
        end

        # Removes the named tags from the host.
        #
        # Returns the list of Tag instances that were removed (and not the ones
        # that weren't there in the first place)
        def remove_tags_by_name!(tag_names_to_remove)
            tags_to_remove = tag_names_to_remove.map {|tagname|; Tag.new(tagname)}
            return remove_tags!(tags_to_remove)
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

        def to_rest_hash
            {
                :hostname => @name,
                :tags => tag_names
            }
        end

        def to_db_hash
            {:name => @name,
             :tags => tag_names}
        end

        def remove!
            @_removed = true
        end

        # Saves the Host instance to the DB.
        def save
            _assert_savable

            if @_removed
                @_db_handler.remove(self)
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

        # Allow sorting
        def <=>(other_tag); @name <=> other_tag.name; end

        # Must override these to get uniqueness checking
        def eql?(other_tag); @name == other_tag.name; end
        def hash; @name.hash; end

        # Overriding this for Array#include?
        def ==(other_tag); @name == other_tag.name; end

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
        # 'datetime' will be a Ruby DateTime instance
        #
        # 'changelog' will be a ChangeLog object describing the change.
        def populate_from_change!(datetime, user, client, remote_host, changelog)
            @datetime = datetime.new_offset(0)
            @user = user
            @client = client
            @remote_host = remote_host
            @diffs = changelog.diffs
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

        def to_db_hash
            {:datetime => @datetime.strftime("%FT%T"),
             :user => @user,
             :client => @client,
             :remote_host => @remote_host,
             :diffs => @diffs}
        end

        def save
            # Don't want to log a history event if nothing changed.
            return nil if @diffs.empty?
            @_db_handler.index(self)
        end
    end
end
