require 'rubygems'
require 'json'
require 'sqlite3'

require 'sinatra'

require 'lib/models'

#@DEBUG
#DB_PATH = "/home/dan/servertag/db.sqlite"
DB_PATH = "/tmp/db.sqlite"

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

class ServerTag
    class Schema
        # Makes sure the DB has the right tables, raising a 500 if not.
        def assert_tables_present(db)
            tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table';")
            schema_tables = %w{host_tag history}
            schema_tables.each do |tbl|
                unless tables.include?([tbl])
                    raise ServerTag::HTTPInternalServerError,
                        "Missing table '#{tbl}'. To initialize DB, POST to /initdb. THAT WILL NUKE ALL DATA IN THE DB!!"
                end
            end
        end

        # Initializes the tables in the given DB, nuking all data.
        def init_tables(db)
            # Contains a row for every tag/host pair that currently exists. E.g.:
            #     | host     | tag     |
            #     |----------|---------|
            #     | web14    | web     |
            #     | web14    | prod    |
            #     | build1   | dev     |
            db.execute("DROP TABLE IF EXISTS host_tag;")
            db.execute("CREATE TABLE host_tag (host STRING, tag STRING,
                                               PRIMARY KEY(host, tag));")

            # Contains a row for every tag changed on every host ever. E.g.:
            #     | datetime            | user    | remote_host | host    | tag     | action  |
            #     |---------------------|---------|-------------|---------|---------|---------|
            #     | 2012-02-01 11:32:55 | dan     | 10.0.64.16  | queue7  | up      | remove  |
            # 'action' is either 'add' or 'remove'.
            db.execute("DROP TABLE IF EXISTS history;")
            db.execute("CREATE TABLE history (datetime STRING, user STRING, remote_host STRING,
                        host STRING, tag STRING, action STRING);")
        end
    end

    class DatabaseConnectionFactory
        def self.get(validate=true)
            db = SQLite3::Database.new(DB_PATH)

            if validate
                s = Schema.new
                s.assert_tables_present(db)
            end

            db
        end
    end

    class WhereClause
        def initialize(criteria)
            @criteria = criteria
        end

        def render
            conditions = @criteria.keys.map do |db_column|
                "#{db_column.to_s} = :#{db_column.to_s}"
            end
            return "" if conditions.empty?

            "WHERE " + conditions.join(" AND ")
        end
    end


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


    class Model
    end


    class HostTag < Model
        attr_accessor :host
        attr_accessor :tag

        def initialize(host, tag)
            @host = host
            @tag = tag
            @_exists = true
        end

        # Factory method for HostTag instances pulled from the DB
        def self.find_all(db, criteria)
            query = "SELECT host, tag FROM host_tag";

            criteria.each_key do |db_column|
                # Fail if there are any criteria we can't use
                unless [:host, :tag].include?(db_column)
                    raise "Invalid column name '#{html_escape(db_column)}'"
                end
            end
            wc = ServerTag::WhereClause.new(criteria)
            query += " " + wc.render
            query += ";"

            host_tags = []
            db.execute(query, criteria).each do |row|
                host_tags << HostTag.new(row[0], row[1])
            end
            host_tags
        end

        # Deletes the host/tag pair
        def remove!
            @_exists = false
        end

        # Writes the HostTag to the DB
        def save(db)
            if @_exists
                db.execute("INSERT OR IGNORE INTO host_tag (host, tag) VALUES (:host, :tag);",
                           :host => @host, :tag => @tag)
            else
                db.execute("DELETE FROM host_tag WHERE host = :host AND tag = :tag;",
                           :host => @host, :tag => @tag)
            end
        end
    end


    # Represents an action performed by a user.
    #
    # 'action' is either 'add' or 'remove'
    class HistoryEvent < Model
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


    class HTTPErrorModel < Model
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
    erb error_model.template(request.accept), :locals => {:error => error_model}
end


# Accessing by host
get '/host/:hostname' do |hostname|
    db = ServerTag::DatabaseConnectionFactory.get
    host_tags = ServerTag::HostTag.find_all(db, :host => hostname)

    v = ServerTag::View.new("host", request.accept)
    erb v.template_name, :locals => {:hostname => hostname, :host_tags => host_tags}
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

    db = ServerTag::DatabaseConnectionFactory.get
    post_obj["tags"].each do |tag|
        ht = ServerTag::HostTag.new(hostname, tag)
        ht.save(db)

        he = ServerTag::HistoryEvent.new(request.env["REMOTE_USER"],
                                         request.env["REMOTE_ADDR"],
                                         hostname, tag, "add")
        he.save(db)
    end

    status 204
    body ""
end


delete '/host/:hostname/:tagname' do |hostname,tagname|
    db = ServerTag::DatabaseConnectionFactory.get
    ht = ServerTag::HostTag.new(hostname, tagname)
    ht.remove!
    ht.save(db)

    he = ServerTag::HistoryEvent.new(request.env["REMOTE_USER"],
                                     request.env["REMOTE_ADDR"],
                                     hostname, tagname, "remove")
    he.save(db)

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


# DB initialization
post '/initdb' do
    db = ServerTag::DatabaseConnectionFactory.get(validate=false)
    s = ServerTag::Schema.new
    s.init_tables(db)

    status 204
    body ""
end


# Home page
get '/' do
    erb "index.html".to_sym
end
