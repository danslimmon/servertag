require "rake"

spec = Gem::Specification.new do |s|
    s.name = "servertag-server"
    s.version = "0.1"
    s.summary = "Tool for keeping track of servers by tagging them"
    s.description = %q!ServerTag lets you define hosts and attach arbitrary tags (strings) to
them. Then you can search for hosts with given tags.
    
This is the server gem. If you only need to talk to an existing servertag server,
you should install servertag-client instead.!

    s.add_dependency("sinatra", ">= 1.3.2")
    s.add_dependency("thin", ">= 1.3.1")
    s.add_dependency("rubberband", ">= 0.1.6")

    s.requirements << "libcurl development headers (curl-devel on RedHat)"

    s.authors = ["Dan Slimmon"]
    s.email = "dan@danslimmon.com"
    s.homepage = "https://github.com/danslimmon/servertag/"
    s.license = "Creative Commons Share-Alike"
    
    s.executables = ["servertag-server"]
    s.files = FileList['lib/**/*.rb', 'bin/*'].to_a
end
