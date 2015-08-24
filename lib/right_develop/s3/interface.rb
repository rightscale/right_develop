#
# Copyright (c) 2013 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'right_aws_api'

module RightDevelop
  module S3

    # Provides a Ruby OOP interface to Amazon S3.
    #
    # Note: filters are used as options for multiple storage actions below and
    # refers to an array of Regexp or wildcard-style filter strings
    # (e.g. '*.txt'). they are used to match file paths relative to a given
    # subdirectory or else from the root of the bucket or directory on disk).
    class Interface
      NO_SLASHES_REGEXP = /^[^\/]+$/
      DEFAULT_ENDPOINT = 'https://s3.amazonaws.com'

      DEFAULT_OPTIONS = {
        :filters => nil,
        :subdirectory => nil,
        :recursive => true,
        :aws_access_key_id => nil,
        :aws_secret_access_key => nil,
        :logger => nil
      }.freeze

      # @option options [String] :aws_access_key_id defaults to using env var value
      # @option options [String] :aws_secret_access_key defaults to using env var value
      # @option options [Logger] :logger or nil to log to STDOUT
      def initialize(options={})
        options = DEFAULT_OPTIONS.merge(options)

        aws_access_key_id  = options[:aws_access_key_id]
        aws_secret_access_key = options[:aws_secret_access_key]
        unless aws_access_key_id && aws_secret_access_key
          raise ::ArgumentError,
                'Missing one or both mandatory options - :aws_access_key_id and :aws_secret_access_key'
        end

        @logger = options[:logger] || Logger.new(STDOUT)
        @s3 = ::RightScale::CloudApi::AWS::S3::Manager.new(
          aws_access_key_id,
          aws_secret_access_key,
          DEFAULT_ENDPOINT,
          :logger => @logger)
      end

      attr_accessor :logger

      # Lists the files in the given bucket.
      #
      # @param [String] bucket to query
      # @option options [String] :subdirectory to start from or nil
      # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
      # @option options [Array] :filters for returned paths or nil or empty
      # @return [Array] list of relative file paths or empty
      def list_files(bucket, options={})
        options = DEFAULT_OPTIONS.dup.merge(options)
        prefix = normalize_subdirectory_path(options[:subdirectory])
        filters = normalize_filters(options)
        files = []
        trivial_filters = filters.select { |filter| filter.is_a?(String) }
        if trivial_filters.empty?
          incrementally_list_bucket(bucket, 'prefix' => prefix) do |keys|
            incremental_files = keys.map do |details|
              details['Key'][(prefix.length)..-1]
            end
            files += filter_files(incremental_files, filters)
          end
        else
          trivial_filters.each do |filename|
            begin
              # use head to query file existence.
              files << filename if @s3.HeadObject(:Bucket => bucket, :Object => "#{prefix}#{filename}")
            rescue RightScale::CloudApi::HttpError => e
              # do nothing if file not found
              raise unless '404' == e.code
            end
          end
        end
        files
      end

      # Downloads all files from the given bucket to the given directory.
      #
      # @param [String] bucket for download
      # @param [String] to_dir_path source directory to upload
      # @option options [String] :subdirectory to start from or nil
      # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
      # @option options [Array] :filters for returned paths or nil or empty
      # @return [Fixnum] count of uploaded files
      def download_files(bucket, to_dir_path, options={})
        options = DEFAULT_OPTIONS.dup.merge(options)
        prefix = normalize_subdirectory_path(options[:subdirectory])
        files = list_files(bucket, options)
        if files.empty?
          logger.info("No files found in \"#{bucket}/#{prefix}\"")
        else
          logger.info("Downloading #{files.count} files...")
          prefix = normalize_subdirectory_path(options[:subdirectory])
          downloaded = 0
          files.each do |path|
            key = "#{prefix}#{path}"
            to_file_path = File.join(to_dir_path, path)

            # AWS creates separate keys for folders created with its console
            # since it can be an empty folder we should create corresponding folder
            # in order to keep folder structure and proceed to the next key
            if path[-1] == '/'
              FileUtils.mkdir_p(to_file_path) unless File.directory?(to_file_path)
              next
            end

            parent_path = File.dirname(to_file_path)
            FileUtils.mkdir_p(parent_path) unless File.directory?(parent_path)

            disk_file = to_file_path

            process_or_skip_file(disk_file, bucket, key) do
              logger.info("Downloading #{bucket}/#{key}")
              ::File.open(to_file_path, 'wb') do |f|
                @s3.GetObject(:Bucket => bucket, :Object => key) { |chunk| f.write(chunk) }
              end
              downloaded += 1
            end

            logger.info("Downloaded to \"#{to_file_path}\"")
          end
        end

        downloaded
      end

      # Uploads all files from the given directory (ignoring any empty
      # directories) to the given bucket.
      #
      # @param [String] bucket for upload
      # @param [String] from_dir_path source directory to upload
      # @option options [String] :subdirectory to start from or nil
      # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
      # @option options [Array] :filters for returned paths or nil or empty
      # @option options [String] :visibility for uploaded files, defaults to 'public-read'
      # @return [Fixnum] count of downloaded files
      def upload_files(bucket, from_dir_path, options={})
        Dir.chdir(from_dir_path) do
          logger.info("Working in #{Dir.pwd.inspect}")
          options = DEFAULT_OPTIONS.dup.merge(options)
          prefix = normalize_subdirectory_path(options[:subdirectory])
          filters = normalize_filters(options)
          pattern = options[:recursive] ? '**/*' : '*'
          files = Dir.glob(pattern).select { |path| File.file?(path) }
          filter_files(files, filters)
          access = normalize_access(options)
          uploaded = 0
          files.each do |path|
            key = "#{prefix}#{path}"

            process_or_skip_file(path, bucket, key) do
              @s3.PutObject(:Bucket => bucket, :Object => key, :body => File.read(path), :headers => {'x-amz-acl' => access})
              uploaded += 1
            end
          end

          uploaded
        end
      end

      # Deletes all files from the given bucket.
      #
      # @param [String] bucket for delete
      # @option options [String] :subdirectory to start from or nil
      # @option options [TrueClass|FalseClass] :recursive true if recursive (default)
      # @option options [Regexp] :filter for files to delete or nil
      # @return [Fixnum] count of deleted files
      def delete_files(bucket, options={})
        options = DEFAULT_OPTIONS.dup.merge(options)
        prefix = normalize_subdirectory_path(options[:subdirectory])
        # Perhaps we should care about files ordering.
        files = list_files(bucket, options)
        if files.empty?
          logger.info("No files found in \"#{bucket}/#{prefix}\"")
        else
          logger.info("Deleting #{files.count} files...")
          files.each do |path|
            @s3.DeleteObject(:Bucket => bucket, :Object => "#{prefix}#{path}")
            logger.info("Deleted \"#{bucket}/#{prefix}#{path}\"")
          end
        end
        files.size
      end

      protected

      def process_or_skip_file(file, bucket, key)
        file_md5 = File.exist?(file) && Digest::MD5.hexdigest(File.read(file))
        return unless file_md5

        # if file exists and its content is the same we should skip it
        @s3.HeadObject(:Bucket => bucket, :Object => key, :headers => {'If-Match' => file_md5})
        logger.info("Skipping #{bucket}/#{key} (identical contents)")

      rescue RightScale::CloudApi::HttpError => e
        if %w(404 412).include? e.code
          # file does not exist or its content has changed, so we can do whatever we want
          yield if block_given?
        else
          raise
        end
      end

      # Normalizes a relative file path for use with S3.
      #
      # @param [String] subdirectory
      def normalize_file_path(path)
        # remove leading and trailing slashes and change any multiple slashes to single.
        return (path || '').gsub("\\", '/').gsub(/^\/+/, '').gsub(/\/+$/, '').gsub(/\/+/, '/')
      end

      # Normalizes subdirectory path for use with S3.
      #
      # @param [String] path
      # @return [String] normalized path
      def normalize_subdirectory_path(path)
        path = normalize_file_path(path)
        path += '/' unless path.empty?
        return path
      end

      def incrementally_list_bucket(bucket, options = {}, &block)
        # TODO add support for max-keys
        options = options.merge({'Bucket' => bucket})
        response = @s3.ListObjects(options)['ListBucketResult']

        yield Array(response['Contents'])

        if response['IsTruncated'] == 'true'
          # FIXME check max-keys
          options['marker'] = decide_marker(response)
          incrementally_list_bucket(bucket, options, &block)
        end
      end

      def decide_marker(response)
        return response['NextMarker'] if response['NextMarker']
        last_prefix = Array(response['CommonPrefixes']).last
        last_key = response['Contents'].last
        if last_key
          last_key['Key']
        else
          last_prefix
        end
      end

      # Normalizes storage filters from options.
      #
      # @option options [Array] :filters for returned paths or nil or empty
      def normalize_filters(options)
        initial_filters = Array(options[:filters])
        normalized_filters = nil

        # support trivial filters as simple string array for direct lookup of
        # one or more S3 object (since listing entire buckets can be slow).
        # recursion always requires a listing so that cannot be trivial.
        if !options[:recursive] && initial_filters.size == 1
          # filter is trivial unless it contains wildcards. more than one
          # non-wildcard filenames delimited by semicolon can be trivial.
          filter = initial_filters.first
          unless filter.to_s.match /[?*]/
            normalized_filters = filter.split(';').uniq
          end
        end
        unless normalized_filters
          normalized_filters = []
          normalized_filters << NO_SLASHES_REGEXP unless options[:recursive]
          initial_filters.each do |filter|
            if filter.kind_of?(String)
              # split on semicolon (;) and OR the result into one regular expression.
              # example: "*.tar;*.tgz;*.zip" -> /^.*\.tar|.*\.tgz|.*\.zip$/
              #
              # convert wildcard-style filter string (e.g. '*.txt') to Regexp.
              escaped = Regexp.escape(filter).gsub("\\*", '.*').gsub("\\?", '.').gsub(';', '|')
              regexp = Regexp.compile("^#{escaped}$")
              filter = regexp
            end
            normalized_filters << filter unless normalized_filters.index(filter)
          end
        end
        return normalized_filters
      end

      # Normalizes access from options (for uploading files).
      #
      # Note: access strings are AWS S3-style but can easily be mapped to any
      # bucket storage implementation which supports ACLs.
      #
      # @option options [String] :access requested ACL or nil for public-read
      # @return @return [String] normalized access
      def normalize_access(options)
        access = options[:access].to_s.empty? ? nil : options[:access]
        return access || 'public-read'
      end

      # Filters the given list of file paths using the given filters, if any.
      #
      # @param [Array] files to filter
      # @param [Array] filters for matching or empty
      # @return [Array] filtered files
      def filter_files(files, filters)
        return files if filters.empty?

        # select each path only if it matches all filters.
        return files.select { |path| filters.all? { |filter| filter.match(path) } }
      end

    end  # Interface
  end  # Buckets
end  # RightDevelop
