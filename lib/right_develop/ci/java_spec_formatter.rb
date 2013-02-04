# Copyright (c) 2012- RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and the licensee.

require 'time'

require 'builder'

# Try to load RSpec 2.x - 1.x formatters
['rspec/core/formatters', 'spec/runner/formatter/base_text_formatter'].each do |f|
  begin
    require f
  rescue LoadError
    # no-op, we will raise later
  end
end

module RightDevelop::CI
  if defined?(::RSpec::Core)
    # RSpec 2.x
    class JavaSpecFormatter < RSpec::Core::Formatters::BaseFormatter
      def initialize(*args)
        super(*args)
        @test_results = []
      end

      def example_passed(example)
        @test_results << example
      end

      def example_failed(example)
        @test_results << example
      end

      def example_pending(example)
        @test_results << example
      end

      def failure_details_for(example)
        exception = example.exception
        exception.nil? ? "" : "#{exception.message}\n#{format_backtrace(exception.backtrace, example).join("\n")}"
      end

      def classname_for(example)
        klass = example.example_group.described_class || tr.example_group.top_level_description
        "rspec.#{klass}"
      end

      def dump_summary(duration, example_count, failure_count, pending_count)
        builder = Builder::XmlMarkup.new :indent => 2
        builder.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
        builder.testsuite :errors => 0, :failures => failure_count, :skipped => pending_count, :tests => example_count, :time => duration, :timestamp => Time.now.iso8601 do
          builder.properties
          @test_results.each do |test|
            classname        = classname_for(test)
            full_description = test.full_description
            time             = test.metadata[:execution_result][:run_time]

            # The full description always begins with the classname, but this is useless info when
            # generating the XML report.
            if full_description.start_with?(classname)
              full_description = full_description[classname.length..-1].strip
            end

            builder.testcase(:classname => classname, :name => full_description, :time => time) do
              case test.metadata[:execution_result][:status]
              when "failed"
                builder.failure :message => "failed #{full_description}", :type => "failed" do
                  builder.cdata! failure_details_for test
                end
              when "pending" then
                builder.skipped
              end
            end
          end
        end
        output.puts builder.target!
      end
    end
  elsif defined?(::Spec::Runner)
    # RSpec 1.x
    class JavaSpecFormatter < Spec::Runner::Formatter::BaseTextFormatter
      def initialize(*args)
        super(*args)
        @current_example_group = nil
        @test_times = {}
        @test_groups = {}
        @test_results = {}
        @test_failures = {}
      end

      def example_group_started(example)
        @current_example_group = example
      end

      def example_started(example)
        @test_groups[example] = @current_example_group
        @example_started_at = Time.now
      end

      def example_passed(example)
        @test_times[example] = Time.now - @example_started_at
        @test_results[example] = 'passed'
      end

      def example_failed(example, counter, failure)
        @test_times[example] = Time.now - @example_started_at
        @test_results[example] = 'failed'
        @test_failures[example] = failure
      end

      def example_pending(example, message, deprecated_pending_location=nil)
        @test_times[example] = Time.now - @example_started_at
        @test_results[example] = 'pending'
      end

      def dump_summary(duration, example_count, failure_count, pending_count)
        builder = Builder::XmlMarkup.new :indent => 2
        builder.instruct! :xml, :version => "1.0", :encoding => "UTF-8"
        builder.testsuite :errors => 0, :failures => failure_count, :skipped => pending_count, :tests => example_count, :time => duration, :timestamp => Time.now.iso8601 do
          builder.properties
          @test_results.each_pair do |test, result|
            classname        = classname_for(test)
            full_description = test.description

            # The full description always begins with the classname, but this is useless info when
            # generating the XML report.
            if full_description.start_with?(classname)
              full_description = full_description[classname.length..-1].strip
            end

            builder.testcase(:classname => classname, :name => full_description, :time => @test_times[test]) do
              case result
              when "failed"
                builder.failure :message => "failed #{full_description}", :type => "failed" do
                  builder.cdata! failure_details_for(test)
                end
              when "pending" then
                builder.skipped
              end
            end
          end
        end
        output.puts builder.target!
      end

      def dump_failure(counter, failure)
        # no-op; our summary contains everything
      end

      def dump_pending()
        # no-op; our summary contains everything
      end

      private

      def failure_details_for(example)
        exception = @test_failures[example].exception
        exception.nil? ? "" : "#{exception.message}\n#{format_backtrace(exception.backtrace)}"
      end

      def classname_for(example)
        # Take our best guess, by looking at the description of the example group
        # and assuming the first word is a class name
        group = @test_groups[example]
        klass = group.description.split(/\s+/).first
        "rspec.#{klass}"
      end
    end
  else
    raise LoadError, "Cannot define RightDevelop::CI::JavaSpecFormatter: unsupported RSpec version"
  end
end
