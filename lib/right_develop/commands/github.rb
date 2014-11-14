puts "Requiring yaml"
require 'yaml'
puts "Requiring github_api..."
require 'github_api'
puts "Requiring pry..."
require 'pry'
puts "Requiring json..."
require 'json'
puts "Requiring travis..."
require 'travis'
require 'byebug'


def write_file(client, repos)
	File.open(OUTFILE, 'w') do |file|
		file.puts("This page is generated automatically from a script. The only actions that make sense are to update the Readme.md files from the corresponding repos, and adding new notes in the notes column IN RED, and they will be provided to the script that generates the page")
		file.puts("Last generated at "+Time.now.strftime("%b %d %Y, %H:%M"))
		file.puts("h2. Active in TravisCI repositories")
		file.puts("This repositories had been activated in Travis either because it was requested by their teams, or because there were jobs in Jenkins related to them")
		file.puts("h3. Active public repositories")
		print_and_flush("Writing public enabled repos")
		write_file_table(file, client, repos.select{|r| r[:type]==:public_enabled}, DOMAINPUBLIC, EXTRAPUBLIC)
		file.puts("h3. Active private repositories")
		print_and_flush("Writing private enabled repos")
		write_file_table(file, client, repos.select{|r| r[:type]==:private_enabled}, DOMAINPRIVATE, EXTRAPRIVATE)
		file.puts("h2. Inactive in TravisCI repositories")
		file.puts("This repositories are not active in Travis CI")
		file.puts("h3. Inactive public repositories")
		print_and_flush("Writing public disable repos")
		write_file_table(file, client, repos.select{|r| r[:type]==:public_disabled}, DOMAINPUBLIC, EXTRAPUBLIC)
		file.puts("h3. Inactive private repositories")
		print_and_flush("Writing private disabled repos")
		write_file_table(file, client, repos.select{|r| r[:type]==:private_disabled}, DOMAINPRIVATE, EXTRAPRIVATE)
		puts
	end
end

def write_file_table(outf, client, repos, domain, extra)
	outf.puts "||repo (links to GH)||Last build badge||Master branch badge||README badges||Tests||Maintained||Notes||"
	print_and_flush(" (Fetching maintainers ")
	repos.each do |r|
		repo=r[:repo]
		extra == "" ? extrabranch = "?branch=master" : extrabranch = extra + "&branch=master"
		outf.puts   " |[#{repo.name}|https://github.com/#{repo.owner.login}/#{repo.name}]" + \
					" |[!https://#{domain}/#{repo.owner.login}/#{repo.name}.svg#{extra}!|https://#{domain}/#{repo.owner.login}/#{repo.name}]" + \
					" |[!https://#{domain}/#{repo.owner.login}/#{repo.name}.svg#{extrabranch}!|https://#{domain}/#{repo.owner.login}/#{repo.name}]" + \
					" |" + r[:badge] + \
					" |" + r[:test_dirs] + \
					" |" + r[:maintainer] + \
					" |#{NOTES[repo.name]} |"
	end
	puts(" )")
end

def print_and_flush(str)
  print str
  $stdout.flush
end

def repo_activated?(repo)
	# At the moment of writing this, there was no API to check if repo is active or not
	# repo.active? shows false until there has been an initial build
	# Since all active repos have their setting (build only if theres a .travis.yml)
	return true if repo.active?
	return true if repo.settings.to_h["builds_only_with_travis_yml"] == true
	return false
end


# fetch the README
def fetch_readme(client, repo)
	begin
  		Base64.decode64(client.repos.contents.readme(repo.owner.login, repo.name).content)
	rescue Github::Error::NotFound =>e
  		nil
  	end
end

# Check if there is /spec/spec_helper
def spec_helper(client, repo)
	found = nil
	begin
		res = client.repos.contents.find(repo.owner.login, repo.name, "/.travis.yml")
		if found.nil?
			found = ".travis.yml"
		else
			found += ", .travis.yml"
		end
	rescue Github::Error::NotFound =>e
		nil
	end
	begin
		res = client.repos.contents.find(repo.owner.login, repo.name, "/spec")
		if found.nil?
			found = "/spec"
		else
			found += ", /spec"
		end
	rescue Github::Error::NotFound =>e
		nil
	end
	begin
		res = client.repos.contents.find(repo.owner.login, repo.name, "/test")
		if found.nil?
			found = "/test"
		else
			found += ", /test"
		end
	rescue Github::Error::NotFound =>e
		nil
	end
	begin
		res = client.repos.contents.find(repo.owner.login, repo.name, "/features")
		if found.nil?
			found = "/features"
		else
			found += ", /features"
		end
	rescue Github::Error::NotFound =>e
		nil
	end
	if found.nil?
		return "No test dirs found"
	else 
		return found + " found"
	end
end

def get_maintained_string(readme)
	return "No Readme" if readme.nil?

	m = /Maintained by[\n[:space:]]*[^\n]+/i.match(readme)
	return m.to_s.strip.gsub("\n"," ") unless m.nil?

	m = /Maintaine/i.match(readme)	
	if m.nil?
		return "No maintainer info"
	else
		return "Non parsable maintainer info"
	end
end

def get_badge(readme, reponame)
	return "No Readme" if readme.nil?

	# m = /\[[^\[]*\.svg[^\]]*\]/.match(readme)
	#m = /http[s]*:\/\/.*travis.*\.svg[^\]\)]*/.match(readme)
	m = readme.scan(/http[s]*:\/\/.*(?:travis-ci.com|travis-ci.org|codeclimate.com|gemnasium.com|img.shields.io).*#{reponame}\.(?:svg|png)[^\]\)\"[:space:]$]*/)
	if not m.empty?
		str = ""
		m.each do |ma|
			badge = ma.strip.gsub("\n"," ")
			str += "[!#{badge}!|#{badge}]"
		end
		return str
	end

	m = /\.svg/.match(readme)	
	if m.nil?
		return"No badge found in README"
	else
		return "Unparsable badge found in README"
	end
end

def get_repo_data(client, repos)
	while not repos.empty?
		print_and_flush(".")
		repo=repos.pop
		break if repo.nil?
		while not repo.keys.include?(:type)
			begin
				readme = fetch_readme(client, repo[:repo])
				repo[:badge] = get_badge(readme, repo[:repo].name) 
				repo[:test_dirs] = spec_helper(client, repo[:repo])
				repo[:maintainer] = get_maintained_string(readme)

				if client.organizations.teams.team_repo?(GRAVEYARD_ID, repo[:repo].owner.login, repo[:repo].name)
					repo[:type] = :graveyard
				elsif repo[:repo].private
					travis_repo = Travis::Pro::Repository.find(repo[:repo].full_name)
					repo[:type] = (repo_activated?(travis_repo) ? :private_enabled : :private_disabled)
				else
					travis_repo = Travis::Repository.find(repo[:repo].full_name)
					repo[:type] = (repo_activated?(travis_repo) ? :public_enabled : :public_disabled)
				end
			rescue Github::Error::Forbidden => e
				if e.message.include?("rate limit exceeded")
					puts "Too fast, we hitted the rate limit, sleeping for 5 min..."
					sleep 300
				else
					raise
				end
			rescue Travis::Client::NotFound => e 
				puts "\nWARNING!! The repo #{repo[:repo].full_name} couldn't be found in Travis, maybe its a recent repo in GitHub? In that case you should tell Travis to resfresh the list of repos"
				# Then the repo is not enabled in Travis for sure
				repo[:type] = (repo[:repo].private ? :private_disabled : :public_disabled)
			end
		end
	end
end


##################################################
##################################################

CONFIG_FILE = "~/.right_develop/github.yml"

THREADS = 10
RS_ORG_ID = 27964
GRAVEYARD_ID = 1034593
DOMAINPRIVATE = "magnum.travis-ci.com"
DOMAINPUBLIC = "travis-ci.org"


if ARGV.map(&:upcase).include?("DEBUG")
	DEBUG = true
	OUTFILE = "wookie.markup.debug"
else
	DEBUG = false
	OUTFILE = "wookie.markup"
end

begin
  tokens = YAML.load_file(File.expand_path(CONFIG_FILE))
rescue Errno::ENOENT => e
	puts "Config file " + CONFIG_FILE + " not found"
end

abort "Missing github key in " + CONFIG_FILE unless tokens.keys.include?("github") 

abort "Missing github/token key in " + CONFIG_FILE unless tokens["github"].keys.include?("token") 
TOKEN_GITHUB = tokens["github"]["token"]

abort "Missing travis key in " + CONFIG_FILE unless tokens.keys.include?("travis") 
abort "Missing travis/public_repos_token key in " + CONFIG_FILE unless tokens["travis"].keys.include?("public_repos_token") 
TOKEN_TRAVIS_API_ORG = tokens["travis"]["public_repos_token"]
abort "Missing travis/private_repos_token key in " + CONFIG_FILE unless tokens["travis"].keys.include?("private_repos_token") 
TOKEN_TRAVIS_API_PRO = tokens["travis"]["private_repos_token"]
abort "Missing travis/private_badges_token key in " + CONFIG_FILE unless tokens["travis"].keys.include?("private_badges_token") 
TOKEN_TRAVIS_BADGE = tokens["travis"]["private_badges_token"]

EXTRAPUBLIC = ""
EXTRAPRIVATE = "?token=#{TOKEN_TRAVIS_BADGE}"


puts "Loading notes..."
notes = File.read("./github.notes.txt")
NOTES = Hash[*notes.split(/;|\n/)]
p NOTES if DEBUG


puts "Connecting to Github..." 
github = Github.new oauth_token: TOKEN_GITHUB, org: "rightscale", auto_pagination: ( DEBUG ? false : true)
puts "Connecting to Travis..."
Travis.access_token = TOKEN_TRAVIS_API_ORG # Public repos
puts "Connecting to Travis PRO..."
Travis::Pro.access_token = TOKEN_TRAVIS_API_PRO # private repos

puts "Getting list of repositories..."
github_repos = github.repositories.list

# public_repos_enabled = []
# public_repos_disabled = []
# private_repos_enabled = []
# private_repos_disabled = []
# graveyard_repos = []
repos = []

c=1
github_repos.each do |repo|
	print_and_flush("\n" + c.to_s + " Processing repo #{repo.full_name} ")
	c+=1
	break unless c <= (DEBUG ? 10 : 100000)

	repos.push({:repo => repo})

	# if github.organizations.teams.team_repo?(GRAVEYARD_ID, repo.owner.login, repo.name)
	# 	print_and_flush(" (graveyard repo)")
	# 	repos.push({:repo => repo, :type => :graveyard})
	# elsif repo.private
	# 	travis_repo = Travis::Pro::Repository.find(repo.full_name)
	# 	print_and_flush(".")
	# 	repo_activated?(travis_repo) ? repos.push({:repo => repo, :type => :private_enabled}) : repos.push({:repo => repo, :type => :private_disabled})
	# else
	# 	travis_repo = Travis::Repository.find(repo.full_name)
	# 	print_and_flush(".")
	# 	repo_activated?(travis_repo) ? repos.push({:repo => repo, :type => :public_enabled}) : repos.push({:repo => repo, :type => :public_disabled})
	# end

end

puts "\nSorting repositories by name..."
# public_repos_enabled.sort!{ |a,b| a.name <=> b.name}
# public_repos_disabled.sort!{ |a,b| a.name <=> b.name}
# private_repos_enabled.sort!{ |a,b| a.name <=> b.name}
# private_repos_disabled.sort!{ |a,b| a.name <=> b.name}
repos.sort!{ |a,b| a[:repo].name <=> b[:repo].name}

# all_repos = { public_enabled: public_repos_enabled, private_enabled: private_repos_enabled,
# 				public_disabled: public_repos_disabled, private_disabled: private_repos_disabled }

print_and_flush "Getting repo data"
repos_to_process=repos.dup
threads = (1..THREADS).map do |i|
	thread = Thread.new(i) do |i|
		get_repo_data(github, repos_to_process)
	end
	sleep 1
	thread
end
threads.each {|t| t.join}
puts " DONE!"

puts "Writing file..."
write_file(github, repos)
