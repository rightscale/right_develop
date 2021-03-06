# RightDevelop

[![Build Status](https://travis-ci.org/rightscale/right_develop.svg?branch=master)](https://travis-ci.org/rightscale/right_develop)

[![Coverage Status](https://img.shields.io/coveralls/rightscale/right_develop.svg)](https://coveralls.io/r/rightscale/right_develop)

This is a library of reusable testing tools to aid TDD, CI and other best practices. It consists of
Rake tasks, command-line tools and Ruby classes. 

Maintained by the RightScale Engineering Team.

# What Does It Do?

## Continuous Integration

RightScale uses a mixture of CI applications and testing frameworks; we value consistent behavior and output formatting between environments. To help promote consistency, we've written a CI harness.

To use our CI harness, just add the following to your Rakefile (or into lib/tasks/ci.rake):

	require 'right_develop'
	RightDevelop::CI::RakeTask.new

### Integrating CI with Rails

For stateful apps, it is generally necessary to run some sort of database setup step prior to running tests.
Rails accomplishes this with the reusable "db:test:prepare" task which is declared as a dependency to the "spec"
task, ensuring that the DB is prepared before running tests.

RightDevelop has a similar hook; the ci:prep task is executed before running any ci:* task. If you need to perform
app-specific CI setup, you can hook into it like this:

	task 'ci:prep' => ['db:my_special_setup_task']

Unfortunately, db:test:prepare does some things that aren't so useful in the CI environment, such as verifying
that the development DB exists and is fully migrated. The development DB is irrelevant when running tests, and if someone
has failed to commit changes to schema.rb then we _want_ the tests to break. Therefore, to setup a Rails app properly,
use the following dependency:

	# Make sure we run the Rails DB-setup stuff before any CI run. Avoid using db:test:prepare
	# because it also checks for pending migrations in the dev database, which is not useful to us.
	task 'ci:prep' => ['db:test:purge', 'db:test:load', 'db:schema:load']


### Customizing your CI Harness

You can override various aspects of the CI harness' behavior by passing a block to the constructor which
tweaks various instance variables of the resulting Rake task:

	RightDevelop::CI::RakeTask.new do |task|
	  task.ci_namespace  = :my_happy_ci
	  task.rspec_name    = :important                       # run as my_happy_ci:important
	  task.rspec_desc    = "important specs with CI output" # or use cucumber_{name,desc} for Cucumber
	  task.rspec_pattern = "spec/important/**/*_spec.rb"    # only run the important specs for CI
	  task.rspec_opts    = ["-t", "important"]              # alternatively, only run tasks tagged as important
	  task.output_path   = "ci_results"                     # use ci_results as the base dir for all output files
	  task.rspec_output  = "happy_specs.xml"                # write to ci_results/rspec/happy_specs.xml
	end

### Keeping the CI Harness Out of Production

We recommend that you don't install RightDevelop -- or other test-only gems such as rspec -- when you deploy
your code to production. This improves the startup time and performance of your app, and prevents instability
due to potential bugs in test code.

To prevent RightDevelop from shipping to production, simply put it in the "development" group of your Gemfile:

	group :development do
	  gem 'right_develop'
	end

And ensure that you deploy your code using Bundler's --without flag:

	bundle install --deployment --without=development

And finally, modify your Rakefile so you can tolerate the absence of the RightDevelop rake classes. For this,
you can use RightSupport's Kernel#require_succeeds? extension to conditionally instantiate the Rake tasks:

	require 'right_support'

	if require_succeeds?('right_develop')
	  RightDevelop::CI::RakeTask.new
	end
