module ServerTag
    # The result of a DB search for HistoryEvent objects
    #
    # 'hits' is an array of HistoryEvent instances
    # 'total' is the number of history events in the DB
    class HistorySearchResult
        attr_accessor :hits, :total

        # Populates the HistoryEventSearchResult instance from an ElasticSearch::Hits instance
        def populate!(es_hits)
            @hits = es_hits.hits.map do |hit|
                he = HistoryEvent.new
                he.populate_from_db!(hit)
                he
            end

            @total = es_hits.total_entries
        end
    end
end
