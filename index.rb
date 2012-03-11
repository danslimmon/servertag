require 'rubygems'
require 'json'

require 'sinatra'

# Add '.' to our lib search path
$:.unshift(".")
require 'lib/rest'
require 'lib/models'
require 'lib/db_handler'
require 'lib/changelog'

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

include ServerTag

# Routes
#
######################## Error routes
error HTTPError do
    error_model = env["sinatra.error"].model

    status error_model.status
    v = View.new("httperror", request.accept)
    erb v.template_name, :locals => {:error => error_model}
end


######################## Host
# Host index page
get '/host' do
    handler = DBHandlerFactory.handler_for(Host)
    hosts = handler.all

    v = View.new("host_index", request.accept)
    erb v.template_name, :locals => {:hosts => hosts}
end


# REST entity
get '/host/:hostname' do |hostname|
    handler = DBHandlerFactory.handler_for(Host)
    host = handler.by_name(hostname)

    v = View.new("host", request.accept)
    erb v.template_name, :locals => {:host => host}
end

# REST: add tags to host
post '/host/:hostname/tags' do |hostname|
    input = RESTInput.new
    input.required!(RESTTags.new)
    input.populate!(request.body)

    changelog = ChangeLog.new

    handler = DBHandlerFactory.handler_for(Host)
    host = handler.by_name(hostname, :on_missing => :new)
    # If the host has no tags yet, we just created it, so we need to log that.
    changelog.create_host!(host) if host.tags.empty?

    new_tags = input.tags
    added_tags = host.add_tags!(new_tags)
    host.save
    # Log the added tags
    changelog.add_tags!(host, added_tags)

    he = HistoryEvent.new
    he.populate_from_change!(DateTime.now,
                             user,
                             "rest",
                             request.ip,
                             changelog)
    he.save

    status 204
    body ""
end


# REST: delete host
delete '/host/:hostname' do |hostname|
    handler = DBHandlerFactory.handler_for(Host)
    host = handler.by_name(hostname)

    changelog = ChangeLog.new
    changelog.remove_tags!(host, host.tags)
    host.remove!
    changelog.delete_host!(host)
    host.save

    he = HistoryEvent.new
    he.populate_from_change!(DateTime.now(),
                             user,
                             "rest",
                             request.ip,
                             changelog)
    he.save

    status 204
    body ""
end


# REST: delete tag from host
delete '/host/:hostname/tags/:tagname' do |hostname,tagname|
    handler = DBHandlerFactory.handler_for(Host)
    host = handler.by_name(hostname)

    changelog = ChangeLog.new
    removed_tags = host.remove_tags_by_name!(tagname)
    changelog.remove_tags!(host, removed_tags)
    if host.tags.empty?
        # If all tags are gone, then remove the host.
        changelog.delete_host!(host)
        host.remove!
    end
    host.save

    he = HistoryEvent.new
    he.populate_from_change!(DateTime.now(),
                             user,
                             "rest",
                             request.ip,
                             changelog)
    he.save

    status 204
    body ""
end

# REST: Search by tags
get '/search' do
    if params["tags"].nil? or params["tags"].empty?
        raise HTTPBadRequestError, "No tags provided to search on"
    end
    tags = params["tags"].split(",").map {|tagname|; Tag.new(tagname)}

    handler = DBHandlerFactory.handler_for(Host)
    hosts = handler.by_tags(tags)

    v = View.new("host_list", request.accept)
    erb v.template_name, :locals => {:hosts => hosts}
end


############################# History
get '/history' do
    # In HTML, this view gets its data from an AJAX call, so we don't
    # need to pass any data to the template.
    v = View.new("history", request.accept)
    erb v.template_name
end


############################# AJAX endpoints
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

    changelog = ChangeLog.new
    handler = DBHandlerFactory.handler_for(Host)
    host_names.each do |hostname|
        h = handler.by_name(hostname)

        added_tags = h.add_tags_by_name!(tag_names)
        changelog.add_tags!(h, added_tags)
        h.save

        hosts << h
    end

    he = HistoryEvent.new
    he.populate_from_change!(DateTime.now(),
                             user,
                             "web",
                             request.ip,
                             changelog)
    he.save

    v = View.new("ajax_tags_by_host", ["text/x-json"])
    status 200
    erb v.template_name, :content_type => v.content_type,
        :locals => {:hosts => hosts, :new_tag_names => tag_names}
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

    changelog = ChangeLog.new
    handler = DBHandlerFactory.handler_for(Host)
    host_names.each do |hostname|
        h = handler.by_name(hostname)

        removed_tags = h.remove_tags_by_name!(tag_names)
        changelog.remove_tags!(h, removed_tags)
        if h.tags.empty?
            # If all tags are gone, then remove the host.
            changelog.delete_host!(h)
            h.remove!
        end
        h.save

        hosts << h
    end

    he = HistoryEvent.new
    he.populate_from_change!(DateTime.now(),
                             user,
                             "web",
                             request.ip,
                             changelog)
    he.save

    v = View.new("ajax_tags_by_host", ["text/x-json"])
    status 200
    erb v.template_name, :content_type => v.content_type,
        :locals => {:hosts => hosts, :new_tag_names => []}
end

get '/ajax/history_table' do
    # Endpoint for dataTables jQuery plugin on the history page
    handler = DBHandlerFactory.handler_for(HistoryEvent)
    search_result = handler.most_recent(50)

    v = View.new("ajax_history", ["text/x-json"])
    status 200
    erb v.template_name, :content_type => v.content_type,
        :locals => {:events => search_result.hits}
end
