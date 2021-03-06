# NOTE: do not include right_develop's gemspec in its Gemfile; this is a Jewelerized
# project and gemspec-in-gemfile is not appropriate. It causes a loop in the dependency
# solver and Jeweler ends up generating a needlessly large gemspec.

source 'https://rubygems.org'

gemspec

# Gems used by the CI harness
gem 'right_support', '~> 2.14'

# Gems used by reusable spec helpers
gem "builder", "~> 3.0"

# Gems used by the command-line Git tools
gem 'trollop', ['>= 1.0', '< 3.0']
gem 'right_git', '>= 1.0'

# Gems used by S3 tools
gem 'right_aws', '>= 2.1.0'

# testing server and client
gem 'rack'

gem 'rake', '< 12', :group=>[:development, :test]

# Gems used during RightDevelop development that should be called out in the gemspec
group :development do
  gem 'rdoc', '>= 2.4.2'
  gem 'pry'
  gem 'pry-byebug'
end

# Gems that are only used locally by this repo to run tests and should NOT be
# called out in the gemspec.
group :test do
  gem 'rspec', '~> 2.0'
  gem 'cucumber', ['~> 1.0', '< 1.3.3'] # Cuke >= 1.3.3 depends on RubyGems > 2.0 without specifyin that in its gemspec
  gem 'nokogiri', '1.7.1'  # required by cucumber
  gem 'coveralls', :require => false
  gem 'mime-types'
  gem 'rest-client', '~> 1.6.0' # can't use 1.7 because it doesn't support 1.8

  gem 'libxml-ruby', '~> 2.7', :platforms => [:mri]  # for sax parser
  gem 'activesupport'                                # unit tests
end
