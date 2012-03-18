require "rake"

spec = Gem::Specification.new do |s|
    s.name = "servertag"
    s.version = "0.1"
    s.summary = "Tool for keeping track of servers by tagging them"
    s.description = %q!ServerTag lets you define hosts and attach arbitrary tags (strings) to
them. Then you can search for hosts with given tags.!

    s.authors = ["Dan Slimmon"]
    s.email = "dan@danslimmon.com"
    s.homepage = "https://github.com/danslimmon/servertag/"
    s.license = "Creative Commons Share-Alike"
    
    s.executables = ["st"]
    s.files = FileList['lib/**/*.rb', 'bin/*'].to_a
end
