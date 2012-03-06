require 'rubygems'
require 'json'

require 'sinatra'

require 'lib/models'
require 'lib/db_handler'

configure do
    set :show_exceptions, false
end

user = ""
use Rack::Auth::Basic, "ServerTag" do |username, password|
    user = username
    [username, password] == ['dan', 'crap']
end

helpers do
    include Rack::Utils
end

module ServerTag
    class View
        # Initializes given the base name of the template and the type of data to return.
        #
        # 'accept' may be an array like Sinatra's 'request.accept' or a single symbol such
        # as :json or :html.
        def initialize(base_name, accept)
            @base_name = base_name
            @accept = accept
        end
        
        def template_name
            "#{@base_name}.#{_template_infix}".to_sym
        end

        def content_type
            @accept.each do |type|
                if %w{text/html text/x-json application/json}.include?(type)
                    return type
                end
            end

            # Default is HTML.
            "text/html"
        end

        # Determines the type part of the template name from our content-type
        #
        # E.g. if content_type is "text/html", will return "html".
        def _template_infix
            infix_map = {"text/x-json" => "json",
                         "application/json" => "json",
                         "text/html" => "html"}
            infix_map.default = "html"
            return infix_map[content_type]
        end
    end


    class HTTPErrorModel
        attr_accessor :status, :name, :message

        def initialize(status, name, message)
            @status = status
            @name = name
            @message = message
        end
    end

    class HTTPError < Exception; end

    class HTTPBadRequestError < HTTPError
        def model; HTTPErrorModel.new(400, "Bad Request", self.message); end
    end
    class HTTPNotFoundError < HTTPError
        def model; HTTPErrorModel.new(404, "Not Found", self.message); end
    end
    class HTTPInternalServerError < HTTPError
        def model; HTTPErrorModel.new(500, "Internal Server Error", self.message); end
    end
end


# Routes
#
# Error routes
error ServerTag::HTTPError do
    error_model = env["sinatra.error"].model

    status error_model.status
    v = ServerTag::View.new("httperror", request.accept)
    erb v.template_name, :locals => {:error => error_model}
end


######################## Host
get '/host' do
    handler = ServerTag::DBHandlerFactory.handler_for(ServerTag::Host)
    hosts = handler.all

    v = ServerTag::View.new("host_index", request.accept)
    erb v.template_name, :locals => {:hosts => hosts}
end


get '/host/:hostname' do |hostname|
    host = ServerTag::Host.find_by_name(hostname)

    v = ServerTag::View.new("host", request.accept)
    erb v.template_name, :locals => {:hostname => host.name, :tags => host.tags}
end


post '/host/:hostname' do |hostname|
    begin
        post_obj = JSON.load(request.body)
        raise unless post_obj.key?("tags")
        raise unless post_obj["tags"].is_a?(Array)
    rescue
        raise ServerTag::HTTPBadRequestError,
                "Malformed input: expected JSON hash with a 'tags' array."
    end

    begin
        h = ServerTag::Host.find_by_name(hostname)
    rescue ServerTag::HTTPNotFoundError,
        h = ServerTag::Host.new
        h.name = hostname
        h.tags = []
    end

    new_tag_names = post_obj["tags"]
    h.add_tags!(new_tags)
    h.save

    status 204
    body ""
end


delete '/host/:hostname' do |hostname|
    h = ServerTag::Host.find_by_name(hostname)
    h.remove!
    h.save

    status 204
    body ""
end


delete '/host/:hostname/:tagname' do |hostname,tagname|
    h = ServerTag::Host.find_by_name(hostname)
    h.tags.reject! {|tag|; tag == tagname.downcase}
    h.save

    status 204
    body ""
end


############################# History
get '/history' do
    # In HTML, this view gets its data from an AJAX call, so we don't
    # need to pass any data to the template.
    v = ServerTag::View.new("history", request.accept)
    erb v.template_name
end


# Home page
get '/' do
    erb "index.html".to_sym
end

# AJAX endpoints
post '/ajax/add_tags' do
    # Accepts a list of hosts and a list of tags; adds the tags to the hosts.
    #
    # Returns the resulting list of tags for each host, like so:
    #   {'results': [
    #     {
    #       hostname: 'cleon',
    #       tags: [
    #         {name: 'foo', exclusive: false, just_added: true},
    #         {name: 'env:prod', exclusive: true, just_added: false}
    #       ]
    #     },
    #     {
    #       hostname: 'swan',
    #       tags: [
    #         {name: 'foo', exclusive: false, just_added: true},
    #         {name: 'env:stg', exclusive: true, just_added: false},
    #         {name: 'bar', exclusive: false, just_added: false}
    #       ]
    #     }
    #   ]} 
    host_names = params["hosts"]
    tag_names = params["tags"]
    hosts = []

    changed_tags = {}
    handler = ServerTag::DBHandlerFactory.handler_for(ServerTag::Host)
    host_names.each do |hostname|
        h = handler.by_name(hostname)

        changed_tags[h.name] = h.add_tags!(tag_names)
        h.save

        hosts << h
    end

    he = ServerTag::HistoryEvent.new(DateTime.now(),
                                     user,
                                     "web",
                                     request.ip,
                                     :add,
                                     changed_tags)
    he.save

    v = ServerTag::View.new("ajax_tags_by_host", ["text/x-json"])
    erb v.template_name, :content_type => v.content_type,
        :locals => {:hosts => hosts, :new_tag_names => tag_names}
    status 200
end

post '/ajax/remove_tags' do
    # Accepts a list of hosts and a list of tags; removes the tags from the hosts.
    #
    # Returns the resulting list of tags for each host, like so:
    #   {'results': [
    #     {
    #       hostname: 'cleon',
    #       tags: [
    #         {name: 'env:prod', exclusive: true, just_added: false}
    #       ]
    #     },
    #     {
    #       hostname: 'swan',
    #       tags: [
    #         {name: 'env:stg', exclusive: true, just_added: false},
    #         {name: 'bar', exclusive: false, just_added: false}
    #       ]
    #     }
    #   ]} 
    host_names = params["hosts"]
    tag_names = params["tags"]
    hosts = []

    changed_tags = {}
    handler = ServerTag::DBHandlerFactory.handler_for(ServerTag::Host)
    host_names.each do |hostname|
        h = handler.by_name(hostname)

        changed_tags[h.name] = h.remove_tags!(tag_names)
        h.save

        hosts << h
    end

    he = ServerTag::HistoryEvent.new(DateTime.now(),
                                     user,
                                     "web",
                                     request.ip,
                                     :remove,
                                     changed_tags)
    he.save

    v = ServerTag::View.new("ajax_tags_by_host", ["text/x-json"])
    erb v.template_name, :content_type => v.content_type
    status 200
end
