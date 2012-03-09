require 'json'

module ServerTag
    # REST input element representing a list of tags
    class RESTTags
        def name; "tags"; end

        # Takes the array that was in the JSON blob and returns an array of Tag instances
        def process(tag_names)
            tag_names.map do |t|
                Tag.new(t)
            end
        end
    end

    # REST input element representing the client used
    class RESTClient
        def name; "client"; end

        # Processes the string that was in the JSON blob
        def process(client)
            if client.empty?
                raise HTTPBadRequestError, "REST client name may not be empty"
            end

            client
        end
    end

    # Represents the input to a REST call.
    #
    # Synopsis:
    #     input = ServerTag::RESTInput.new
    #     input.required!(ServerTag::RESTClient.new)
    #     input.required!(ServerTag::RESTTags.new)
    #     input.optional!(ServerTag::RestHost.new)
    #     input.populate!(request.body)
    #
    #     puts "Client was '#{input.client}' and tags were #{input.tags.inspect}"
    #
    # If an optional element was not present at the populate! call, it will evaluate to nil.
    class RESTInput
        def initialize
            @_resource_hash = nil
            @_cleaned_resource_hash = {}
            @_required = []
            @_optional = []
        end

        def required!(element)
            @_required << element
        end

        def optional!(element)
            @_optional << element
        end

        def populate!(json_blob)
            begin
                @_resource_hash = JSON.load(json_blob)
            rescue
                raise HTTPBadRequestError, "Malformatted JSON blob"
            end

            _process_required!
            _process_optional!
        end

        def _process_required!
            @_required.each do |element|
                unless @_resource_hash.key?(element.name)
                    raise HTTPBadRequestError, "Missing element '#{element.name}' from JSON blob"
                end

                @_cleaned_resource_hash[element.name] = element.process(@_resource_hash[element.name])
            end
        end

        def _process_optional!
            @_optional.each do |element|
                if @_resource_hash.key?(element.name)
                    @_cleaned_resource_hash[element.name] = element.process(@_resource_hash[element.name])
                else
                    @_cleaned_resource_hash[element.name] = nil
                end
            end
        end

        def method_missing(sym, *args)
            @_cleaned_resource_hash.fetch(sym.to_s)
        end
    end
end
