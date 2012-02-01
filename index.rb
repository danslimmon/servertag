require 'rubygems'

require 'json'
require 'sqlite3'

require 'sinatra'

#@DEBUG
#DB_PATH = "/home/dan/servertag/db.sqlite"
DB_PATH = "/tmp/db.sqlite"

configure do
    set :show_exceptions, false
end


class ServerTag
    class Schema
        # Makes sure the DB has the right tables, raising a 500 if not.
        def assert_tables_present(db)
            tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table';")
            schema_tables = %w{host_tag history}
            schema_tables.each do |tbl|
                unless tables.include?(tbl)
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
            db.execute("CREATE TABLE host_tag (host STRING, tag STRING);")

            # Contains a row for every tag changed on every host ever. E.g.:
            #     | datetime            | user    | host    | tag     | action  |
            #     |---------------------|---------|---------|---------|---------|
            #     | 2012-02-01 11:32:55 | dan     | queue7  | up      | remove  |
            # 'action' is either 'add' or 'remove'.
            db.execute("DROP TABLE IF EXISTS history;")
            db.execute("CREATE TABLE history (datetime STRING, user STRING,
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

    class Model
        # Returns the name of the template for a host, given the list of accepted types.
        def template(accepted_types)
            # The following converts, e.g., 'ServerTag::Host' to 'host'.
            class_name = self.class.to_s.split("::")[-1].downcase
            accepted_types.each do |type|
                if %q{text/x-json application/json}.include?(type)
                    return "#{class_name}.json".to_sym
                end
            end
            # Default is HTML
            return "#{class_name}.html".to_sym
        end
    end


    class Host < Model
        attr_accessor :name
        attr_accessor :tags

        def initialize(hostname); @name = hostname; @tags = []; end

        # Adds the given tags to the host instance.
        def add_tags!(new_tags); @tags += new_tags; end

        # Removes the given tags from the host
        def remove_tags!(tags_to_remove)
            @tags.reject! do |tag|
                tags_to_remove.include?(tag)
            end
        end
    end


    class Tag < Model
        attr_accessor :name
        attr_accessor :hosts

        def initialize(tagname); @name = tagname; @hosts = []; end

        # Adds the given hosts to the tag instance.
        def add_hosts!(new_hosts); @hosts += new_hosts; end

        # Removes the given hosts from the tag
        def remove_hosts!(hosts_to_remove)
            @hosts.reject! do |host|
                hosts_to_remove.include?(host)
            end
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

    rows = db.execute("SELECT DISTINCT tag FROM host_tag WHERE host = :hostname",
                      "hostname" => hostname)
    tags = rows.map do |row|
        row[0]
    end
    h = ServerTag::Host.new(hostname)
    h.add_tags!(tags)

    erb h.template(request.accept), :locals => {:host => h}
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
        db.execute("INSERT INTO host_tag (host, tag) VALUES (:hostname, :tag)",
                   "hostname" => hostname,
                   "tag" => tag)
    end

    204
end


# By tag
get '/tag/:tagname' do |tagname|
    db = ServerTag::DatabaseConnectionFactory.get
    rows = db.execute("SELECT DISTINCT host FROM host_tag WHERE tag = :tagname",
                      "tagname" => tagname)
    hosts = rows.map do |row|
        row[0]
    end
    t = ServerTag::Tag.new(tagname)
    t.add_hosts!(hosts)

    erb t.template(request.accept), :locals => {:tag => t}
end


# DB initialization
post '/initdb' do
    db = ServerTag::DatabaseConnectionFactory.get(validate=false)
    s = ServerTag::Schema.new
    s.init_tables(db)

    status 204
    body ""
end
