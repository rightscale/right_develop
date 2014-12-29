# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: right_develop 3.1.11 ruby lib

Gem::Specification.new do |s|
  s.name = "right_develop"
  s.version = "3.1.11"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Tony Spataro"]
  s.date = "2014-12-29"
  s.description = "A toolkit of development tools created by RightScale."
  s.email = "support@rightscale.com"
  s.executables = ["right_develop"]
  s.extra_rdoc_files = [
    "LICENSE",
    "README.md"
  ]
  s.files = [
    ".coveralls.yml",
    ".travis.yml",
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "Rakefile",
    "TODO.md",
    "VERSION",
    "bin/right_develop",
    "lib/right_develop.rb",
    "lib/right_develop/ci.rb",
    "lib/right_develop/ci/formatters/rspec_v1.rb",
    "lib/right_develop/ci/formatters/rspec_v2.rb",
    "lib/right_develop/ci/formatters/rspec_v3.rb",
    "lib/right_develop/ci/java_cucumber_formatter.rb",
    "lib/right_develop/ci/java_spec_formatter.rb",
    "lib/right_develop/ci/rake_task.rb",
    "lib/right_develop/ci/util.rb",
    "lib/right_develop/commands.rb",
    "lib/right_develop/commands/git.rb",
    "lib/right_develop/commands/server.rb",
    "lib/right_develop/git.rb",
    "lib/right_develop/git/rake_task.rb",
    "lib/right_develop/net.rb",
    "lib/right_develop/parsers.rb",
    "lib/right_develop/parsers/sax_parser.rb",
    "lib/right_develop/parsers/xml_post_parser.rb",
    "lib/right_develop/s3.rb",
    "lib/right_develop/s3/interface.rb",
    "lib/right_develop/s3/rake_task.rb",
    "lib/right_develop/testing.rb",
    "lib/right_develop/testing/clients.rb",
    "lib/right_develop/testing/clients/rest.rb",
    "lib/right_develop/testing/clients/rest/requests.rb",
    "lib/right_develop/testing/clients/rest/requests/base.rb",
    "lib/right_develop/testing/clients/rest/requests/playback.rb",
    "lib/right_develop/testing/clients/rest/requests/record.rb",
    "lib/right_develop/testing/recording.rb",
    "lib/right_develop/testing/recording/config.rb",
    "lib/right_develop/testing/recording/metadata.rb",
    "lib/right_develop/testing/servers/might_api/.gitignore",
    "lib/right_develop/testing/servers/might_api/Gemfile",
    "lib/right_develop/testing/servers/might_api/Gemfile.lock",
    "lib/right_develop/testing/servers/might_api/app/admin.rb",
    "lib/right_develop/testing/servers/might_api/app/base.rb",
    "lib/right_develop/testing/servers/might_api/app/echo.rb",
    "lib/right_develop/testing/servers/might_api/app/playback.rb",
    "lib/right_develop/testing/servers/might_api/app/record.rb",
    "lib/right_develop/testing/servers/might_api/config.ru",
    "lib/right_develop/testing/servers/might_api/config/init.rb",
    "lib/right_develop/testing/servers/might_api/lib/config.rb",
    "lib/right_develop/testing/servers/might_api/lib/logger.rb",
    "lib/right_develop/utility.rb",
    "lib/right_develop/utility/git.rb",
    "lib/right_develop/utility/shell.rb",
    "lib/right_develop/utility/versioning.rb",
    "right_develop.gemspec",
    "right_develop.rconf"
  ]
  s.homepage = "https://github.com/rightscale/right_develop"
  s.licenses = ["MIT"]
  s.rubygems_version = "2.2.2"
  s.summary = "Reusable dev & test code."

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<right_support>, ["< 3.0.0", ">= 2.8.31"])
      s.add_runtime_dependency(%q<builder>, ["~> 3.0"])
      s.add_runtime_dependency(%q<trollop>, ["< 3.0", ">= 1.0"])
      s.add_runtime_dependency(%q<right_git>, [">= 1.0"])
      s.add_runtime_dependency(%q<right_aws>, [">= 2.1.0"])
      s.add_runtime_dependency(%q<rack>, [">= 0"])
      s.add_development_dependency(%q<rake>, ["~> 10.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 2.0"])
      s.add_development_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_development_dependency(%q<github_api>, ["~> 0.9.7"])
    else
      s.add_dependency(%q<right_support>, ["< 3.0.0", ">= 2.8.31"])
      s.add_dependency(%q<builder>, ["~> 3.0"])
      s.add_dependency(%q<trollop>, ["< 3.0", ">= 1.0"])
      s.add_dependency(%q<right_git>, [">= 1.0"])
      s.add_dependency(%q<right_aws>, [">= 2.1.0"])
      s.add_dependency(%q<rack>, [">= 0"])
      s.add_dependency(%q<rake>, ["~> 10.0"])
      s.add_dependency(%q<jeweler>, ["~> 2.0"])
      s.add_dependency(%q<rdoc>, [">= 2.4.2"])
      s.add_dependency(%q<github_api>, ["~> 0.9.7"])
    end
  else
    s.add_dependency(%q<right_support>, ["< 3.0.0", ">= 2.8.31"])
    s.add_dependency(%q<builder>, ["~> 3.0"])
    s.add_dependency(%q<trollop>, ["< 3.0", ">= 1.0"])
    s.add_dependency(%q<right_git>, [">= 1.0"])
    s.add_dependency(%q<right_aws>, [">= 2.1.0"])
    s.add_dependency(%q<rack>, [">= 0"])
    s.add_dependency(%q<rake>, ["~> 10.0"])
    s.add_dependency(%q<jeweler>, ["~> 2.0"])
    s.add_dependency(%q<rdoc>, [">= 2.4.2"])
    s.add_dependency(%q<github_api>, ["~> 0.9.7"])
  end
end

