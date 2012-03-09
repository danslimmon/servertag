module ServerTag
    # Describes a change that was made to hosts and tags.
    #
    # You initialize one and then call methods to indicate changes. Then
    # you can call diffs() to return a list of strings that describes the
    # change, for insertion into the history DB. Synopsis:
    #
    #   ci = ChangeLog.new
    #   ci.create_host!(host)
    #   ci.add_tags!(host, tags)
    #   puts ci.diffs.join("\n")
    class ChangeLog
        def initialize
            # Lists of hostnames
            @_hosts_created = []
            @_hosts_deleted = []
            # Each of these is a hash indexed by host name, where the value is
            # the corresponding list of tag names.
            @_tags_added = {}
            @_tags_removed = {}
        end

        # Adds a "create host" action.
        #
        # This only logs the creation, not any of the tags that were added.
        def create_host!(host)
            @_hosts_created << host.name
        end

        # Adds a "delete host" action.
        def delete_host!(host)
            @_hosts_deleted << host.name
        end

        # Logs the addition of tags to a host.
        def add_tags!(host, tag_names)
            if @_tags_added.key?([host.name])
                @_tags_added[host.name] += tag_names
            else
                @_tags_added[host.name] = tag_names
            end
        end

        # Logs the removal of tags from a host.
        def remove_tags!(host, tag_names)
            if @_tags_removed.key?([host.name])
                @_tags_removed[host.name] += tag_names
            else
                @_tags_removed[host.name] = tag_names
            end
        end

        def diffs
            rslt = []

            @_hosts_created.each do |host|
                rslt << "Created host '#{host}'"
            end
            rslt += _tag_diffs(:add, @_tags_added)

            @_hosts_deleted.each do |host|
                rslt << "Deleted host '#{host}'"
            end
            rslt += _tag_diffs(:remove, @_tags_removed)
        end

        # Generates diff strings given the type of action and the changed tag names.
        #
        # 'changed_by_host' should probably be @_tags_added or @_tags_removed
        def _tag_diffs(type, changed_by_host)
            changed_by_tags = {}
            changed_by_tags.default = []
            changed_by_host.each_pair do |hostname,tagnames|
                changed_by_tags[tagnames] = changed_by_tags[tagnames] + [hostname]
            end
            changed_by_tags.delete([])

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
    end
end
