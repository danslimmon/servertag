require 'rubygems'
require 'json'

require 'sinatra'

require 'lib/models'


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
        def initialize(base_name, accept)
            @base_name = base_name
            @accept = accept
        end
        
        def template_name
            "#{@base_name}.#{_data_type}".to_sym
        end

        def _data_type
            @accept.each do |type|
                if %q{text/x-json application/json}.include?(type)
                    return "json"
                end
            end
            # Default is HTML
            return "html"
        end
    end


    # Represents an action performed by a user.
    #
    # 'action' is either 'add' or 'remove'
    class HistoryEvent
        attr_accessor :datetime, :user, :remote_host, :host, :tag, :action

        def initialize(user, remote_host, host, tag, action, datetime="now");
            @user = user
            @remote_host = remote_host
            @host = host
            @tag = tag
            @action = action
            @datetime = datetime
        end

        # Saves the given HistoryEvent to the DB.
        def save(db)
            db.execute("INSERT INTO history (datetime, user, remote_host, host, tag, action)
                            VALUES (datetime(:datetime), :user, :remote_host,
                                    :host, :tag, :action);",
                       "datetime" => @datetime,
                       "user" => @user,
                       "remote_host" => @remote_host,
                       "host" => @host,
                       "tag" => @tag,
                       "action" => @action
                      )
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


# Accessing by host
get '/host' do
    hosts = ServerTag::Host.all

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

    new_tags = post_obj["tags"].map {|tag|; tag.downcase}
    h.tags = [h.tags, new_tags].flatten.uniq
    h.save

    status 204
    body ""
end


delete '/host/:hostname/:tagname' do |hostname,tagname|
    h = ServerTag::Host.find_by_name(hostname)
    h.tags.reject! {|tag|; tag == tagname}
    h.save

    status 204
    body ""
end


# Accessing by tag
get '/tag/:tagname' do |tagname|
    db = ServerTag::DatabaseConnectionFactory.get
    host_tags = ServerTag::HostTag.find_all(db, :tag => tagname)

    v = ServerTag::View.new("tag", request.accept)
    erb v.template_name, :locals => {:tagname => tagname, :host_tags => host_tags}
end


# History
get '/history' do
    db = ServerTag::DatabaseConnectionFactory.get
    rows = db.execute("SELECT datetime, user, remote_host, host, tag, action
                       FROM history
                       LIMIT :limit",
                      lim)
    he = ServerTag::History.new
end


# Home page
get '/' do
    erb "index.html".to_sym
end
