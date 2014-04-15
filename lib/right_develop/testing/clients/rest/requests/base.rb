#
# Copyright (c) 2014 RightScale Inc
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

# ancestor
require 'right_develop/testing/clients/rest'

require 'rest_client'
require 'right_support'
require 'yaml'

module RightDevelop::Testing::Client::Rest::Request

  # Base class for record/playback request implementations.
  class Base < ::RestClient::Request

    include ::RightDevelop::Testing::Client::ChecksumMixin

    HIDDEN_CREDENTIAL_NAMES = %w(
      email password user username globalsession accesstoken refreshtoken
    )
    HIDDEN_CREDENTIAL_VALUE = 'HIDDEN_CREDENTIAL'

    attr_reader :fixtures_dir, :logger, :route_record_dir, :state_file_path
    attr_reader :request_timestamp, :response_timestamp

    def initialize(args)
      args = args.dup
      unless @fixtures_dir = args.delete(:fixtures_dir)
        raise ::ArgumentError, 'fixtures_dir is required'
      end
      unless @logger = args.delete(:logger)
        raise ::ArgumentError, 'logger is required'
      end
      unless @route_record_dir = args.delete(:route_record_dir)
        raise ::ArgumentError, 'route_record_dir is required'
      end
      unless @state_file_path = args.delete(:state_file_path)
        raise ::ArgumentError, 'state_file_path is required'
      end

      super(args)

      if @block_response
        raise ::NotImplementedError,
              'block_response not supported for record/playback'
      end
      if @raw_response
        raise ::ArgumentError, 'raw_response not supported for record/playback'
      end
    end

    # Overrides log_request to capture start-time for network request.
    #
    # @return [Object] undefined
    def log_request
      result = super
      @request_timestamp = ::Time.now.to_i
      result
    end

    # Overrides log_response to capture end-time for network request.
    #
    # @param [RestClient::Response] to capture
    #
    # @return [Object] undefined
    def log_response(response)
      @response_timestamp = ::Time.now.to_i
      super
    end

    protected

    # Holds the state file lock for block.
    #
    # @yield [state] gives exclusive state access to block
    # @yieldparam [Hash] state
    # @yieldreturn [Object] anything
    #
    # @return [Object] block result
    def with_state_lock
      result = nil
      ::File.open(state_file_path, ::File::RDWR | File::CREAT, 0644) do |f|
        f.flock(::File::LOCK_EX)
        state_yaml = f.read
        if state_yaml.empty?
          state = { epoch: 0 }
        else
          state = ::YAML.load(state_yaml)
        end
        result = yield(state)
        f.seek(0)
        f.truncate(0)
        f.puts(::YAML.dump(state))
      end
      result
    end

    # Computes the metadata used to identify where the request/response should
    # be stored-to/retrieved-from. Recording the request is not strictly
    # necessary (because the request maps to a MD5 used for response-only) but
    # it adds human-readability and the ability to manually customize some or
    # all responses.
    #
    # @return [Hash] metadata for storing/retrieving request and response
    def compute_record_metadata
      # use rest-client method to parse URL (again).
      uri = parse_url(@url)
      query_file_name = self.method.to_s.upcase
      unless (query_string = uri.query.to_s).empty?
        # try to keep it human-readable by CGI-escaping the only illegal *nix
        # file character = '/'.
        query_string = normalize_query_string(query_string).gsub('/', '%2F')
        query_file_name << '_' << query_string
      end

      # payload is an I/O object but we can quickly get body from .string if it
      # is a StringIO object. assume it always is a string unless streaming a
      # large file, in which case we don't support it currently.
      stream = @payload.instance_variable_get(:@stream)
      if stream && stream.respond_to?(:string)
        body = stream.string
      else
        # assume payload is too large to buffer or else it would be StringIO.
        # we could compute the MD5 by streaming if we really wanted to, but...
        raise ::NotImplementedError,
              'Non-string payload streams are not currently supported.'
      end

      # JSON data may be hash-ordered inconsistently between invocations.
      # attempt to sort JSON data before creating a key.
      normalized_headers = normalize_headers(headers)
      normalized_body = normalize_body(normalized_headers, body)
      normalized_body_token = normalized_body.empty? ? empty_checksum_value : ::Digest::MD5.hexdigest(normalized_body)
      query_file_name = "#{normalized_body_token}_#{query_file_name}"

      # make URI relative to target server (eliminate proxy server detail).
      uri.scheme = nil
      uri.host = nil
      uri.port = nil
      uri.user = nil
      uri.password = nil

      # result
      {
        uri:                   uri,
        normalized_headers:    normalized_headers,
        normalized_body:       normalized_body,
        normalized_body_token: normalized_body_token,
        query_file_name:       query_file_name,
        relative_path:         uri.path,
      }
    end

    # Sort the given query string fields because order of parameters should not
    # matter but multiple invocations might shuffle the parameter order.
    # Also attempts to obfuscate any user credentials.
    #
    # @param [String] query_string to normalize
    #
    # @return [String] normalized query string
    def normalize_query_string(query_string)
      query = []
      ::CGI.parse(query_string).sort.each do |k, v|
        # right-hand-side of CGI.parse hash is always an array
        normalized_key = normalized_parameter_name(k)
        v.sort.each do |item|
          # top-level obfuscation (FIX: deeper?)
          if HIDDEN_CREDENTIAL_NAMES.include?(normalized_key)
            item = HIDDEN_CREDENTIAL_VALUE if item.is_a?(::String)
          end
          query << "#{k}=#{item}"
        end
      end
      query.join('&')
    end

    # Deep-sorts the given JSON string and attempts to obfuscate any user
    # credentails.
    #
    # Note that if the payload contains arrays that contain hashes then those
    # hashes are not sorted due to a limitation of deep_sorted_json.
    #
    # FIX: deep_sorted_json could traverse arrays and sort sub-hashes if
    # necessary.
    #
    # @param [String] json to normalize
    #
    # @return [String] normalized JSON string
    def normalize_json(json)
      # top-level obfuscation (FIX: deeper?)
      hash = ::JSON.load(json).inject({}) do |h, (k, v)|
        normalized_key = normalized_parameter_name(k)
        if HIDDEN_CREDENTIAL_NAMES.include?(normalized_key)
          v = HIDDEN_CREDENTIAL_VALUE if v.is_a?(::String)
        end
        h[k] = v
        h
      end
      ::RightSupport::Data::HashTools.deep_sorted_json(hash, pretty = false)
    end

    # Converts header/payload keys to a form consistent with parameter passing
    # logic. The various layers of Net::HTTP, RestClient and Rack all seem to
    # have different conventions for header/parameter names.
    def normalized_parameter_name(key)
      key.to_s.gsub('-', '').gsub('_', '').downcase
    end

    def normalize_headers(headers)
      result = headers.inject({}) do |h, (k, v)|
        # value is in raw form as array of sequential header values
        h[k.to_s.gsub('-', '_').upcase] = v
        h
      end

      # eliminate headers that interfere with playback.
      ['CONNECTION', 'STATUS'].each { |key| result.delete(key) }

      # obfuscate any cookies as they won't be needed for playback.
      [/COOKIE/].each do |header_regex|
        result.keys.each do |k|
          if header_regex.match(k) && (cookies = result[k])
            if cookies.is_a?(::String)
              cookies = cookies.split(';').map { |c| c.strip }
            end
            result[k] = cookies.map do |cookie|
              if offset = cookie.index('=')
                cookie_name = cookie[0..(offset-1)]
                "#{cookie_name}=#{HIDDEN_CREDENTIAL_VALUE}"
              else
                cookie
              end
            end
          end
        end
      end

      # other obfuscation.
      [/AUTHORIZATION/].each do |header_regex|
        result.keys.each do |k|
          result[k] = HIDDEN_CREDENTIAL_VALUE if header_regex.match(k)
        end
      end
      result
    end

    def normalize_body(normalized_headers, body)
      if result = body.to_s
        # content type may be an array or an array of strings needing to be split.
        #
        # example: ["application/json; charset=utf-8"]
        content_type = normalized_headers['CONTENT_TYPE']
        content_type = Array(content_type).join(';').split(';').map { |ct| ct.strip }
        content_type.each do |ct|
          if ct.start_with?('application/')
            case ct.strip
            when 'application/x-www-form-urlencoded'
              result = normalize_query_string(body)
              normalize_content_length(normalized_headers, result)
            when 'application/json'
              result = normalize_json(body)
              normalize_content_length(normalized_headers, result)
            end
            break
          end
        end
      end
      result
    end

    def normalize_content_length(normalized_headers, normalized_body)
      if normalized_headers['CONTENT_LENGTH']
        normalized_headers['CONTENT_LENGTH'] = normalized_body.length
      end
      true
    end

    def relative_request_dir(record_metadata)
      ::File.join('requests', record_metadata[:relative_path])
    end

    def relative_response_dir(record_metadata)
      ::File.join('responses', record_metadata[:relative_path])
    end

    def request_file_path(state, record_metadata)
      ::File.join(
        @fixtures_dir,
        state[:epoch].to_s,
        @route_record_dir,
        relative_request_dir(record_metadata),
        record_metadata[:query_file_name] + '.yml')
    end

    def response_file_path(state, record_metadata)
      ::File.join(
        @fixtures_dir,
        state[:epoch].to_s,
        @route_record_dir,
        relative_response_dir(record_metadata),
        record_metadata[:query_file_name] + '.yml')
    end

  end # Base

end # RightDevelop::Testing::Client::Rest
