require 'set'

module ServerTag
    class TagSet
        def initialize(tags=[])
            @_set = Set.new(tags.map {|tag|; _normalize_tag(tag)})
        end

        def _normalize_tag(tag)
            tag.downcase
        end
    end
end
