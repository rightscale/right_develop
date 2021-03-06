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

# ancestor
require 'right_develop/testing/clients/rest'

require 'rest_client'

module RightDevelop::Testing::Client::Rest::Request

  # Provides a middle-ware layer that intercepts transmition of the request and
  # escapes out of the execute call with a stubbed response using throw/catch.
  class Playback < ::RightDevelop::Testing::Client::Rest::Request::Base

    HALT_TRANSMIT = :halt_transmit

    # exceptions
    PLAYBACK_ERROR = ::RightDevelop::Testing::Recording::Metadata::PlaybackError

    class PeerResetConnectionError < PLAYBACK_ERROR; end

    # fake Net::HTTPResponse
    class FakeNetHttpResponse
      attr_reader :code, :body, :delay_seconds, :elapsed_seconds, :call_count

      def initialize(response_hash, response_metadata)
        @delay_seconds = response_metadata.delay_seconds
        @elapsed_seconds = Integer(response_hash[:elapsed_seconds] || 0)
        @code = response_metadata.http_status.to_s
        @headers = response_metadata.headers.inject({}) do |h, (k, v)|
          h[k] = Array(v)  # expected to be an array
          h
        end
        @body = response_metadata.body  # optional
        @call_count = Integer(response_hash[:call_count]) || 1
      end

      def [](key)
        if header = @headers[key.downcase]
          header.join(', ')
        else
          nil
        end
      end

      def to_hash; @headers; end
    end

    attr_reader :throttle

    def initialize(args)
      if args[:throttle]
        args = args.dup
        @throttle = Integer(args.delete(:throttle))
        if @throttle < 0 || @throttle > 100
          raise ::ArgumentError, 'throttle must be a percentage between 0 and 100'
        end
      else
        @throttle = 0
      end
      super(args)
    end

    # Overrides log_request to interrupt transmit before any connection is made.
    #
    # @raise [Symbol] always throws HALT_TRANSMIT
    def log_request
      super
      throw(HALT_TRANSMIT, HALT_TRANSMIT)
    end

    RETRY_DELAY = 0.5
    MAX_RETRIES = 240  # = 120 seconds; a socket usually times out in 60-120 seconds

    # Overrides transmit to catch halt thrown by log_request.
    #
    # @param [URI[ uri of some kind
    # @param [Net::HTTP] req of some kind
    # @param [RestClient::Payload] of some kind
    #
    # @return
    def transmit(uri, req, payload, &block)
      caught = catch(HALT_TRANSMIT) { super }
      if caught == HALT_TRANSMIT
        response = nil
        try_counter = 0
        while response.nil?
          with_state_lock do |state|
            response = catch(METADATA_CLASS::HALT) do
              fetch_response(state)
            end
          end
          case response
          when METADATA_CLASS::RetryableFailure
            try_counter += 1
            if try_counter >= MAX_RETRIES
              message =
                "Released thread id=#{::Thread.current.object_id} after " <<
                "#{try_counter} attempts to satisfy a retryable condition:\n" <<
                response.message
              raise PLAYBACK_ERROR, message
            end
            if 1 == try_counter
              message = "Blocking thread id=#{::Thread.current.object_id} " <<
                        'until a retryable condition is satisfied...'
              logger.debug(message)
            end
            response = nil
            sleep RETRY_DELAY
          else
            if try_counter > 0
              message = "Released thread id=#{::Thread.current.object_id} " <<
                        'after a retryable condition was satisfied.'
              logger.debug(message)
            end
          end
        end

        # delay, if throttled, to simulate server response time.
        if @throttle > 0 && response.elapsed_seconds > 0
          delay = (Float(response.elapsed_seconds) * @throttle) / 100.0
          logger.debug("throttle delay = #{delay}")
          sleep delay
        end

        # there may be a configured response delay (in addition to throttling)
        # which allows for other responses to complete before the current
        # response thread is unblocked. the response delay is absolute and not
        # subject to the throttle factor.
        if (delay = response.delay_seconds) > 0
          logger.debug("configured response delay = #{delay}")
          sleep delay
        end
        log_response(response)
        process_result(response, &block)
      else
        raise PLAYBACK_ERROR,
              'Unexpected RestClient::Request#transmit returned without calling RestClient::Request#log_request'
      end
    end

    # @see RightDevelop::Testing::Client::Rest::Request::Base.handle_timeout
    def handle_timeout
      raise ::NotImplementedError, 'Timeout is unexpected for stubbed API call.'
    end

    protected

    # @see RightDevelop::Testing::Client::Rest::Request::Base#recording_mode
    def recording_mode
      :playback
    end

    def fetch_response(state)
      # response must exist in the current epoch (i.e. can only enter next epoch
      # after a valid response is found) or in a past epoch. the latter was
      # allowed due to multithreaded requests causing the epoch to advance
      # (in a non-throttled playback) before all requests for a past epoch have
      # been made. the current epoch is always preferred over past.
      file_path = nil
      past_epochs = state[:past_epochs] ||= []
      try_epochs = [state[:epoch]] + past_epochs
      first_tried_path = nil
      first_tried_epoch = nil
      last_tried_epoch = nil
      try_epochs.each do |epoch|
        file_path = response_file_path(epoch)
        break if ::File.file?(file_path)
        first_tried_path = file_path unless first_tried_path
        first_tried_epoch = epoch unless first_tried_epoch
        last_tried_epoch = epoch
        file_path = nil
      end
      if file_path
        response_hash = RightSupport::Data::Mash.new(::YAML.load_file(file_path))
        if response_hash[:peer_reset_connection]
          raise PeerResetConnectionError, 'Connection reset by peer'
        end
        @response_metadata = create_response_metadata(
          state,
          response_hash[:http_status],
          response_hash[:headers],
          response_hash[:body])
        result = FakeNetHttpResponse.new(response_hash, response_metadata)
      else
        msg = <<EOF
Unable to locate response file(s) in epoch range [#{first_tried_epoch} - #{last_tried_epoch}]:
#{first_tried_path.inspect}
request checksum_data = #{request_metadata.checksum_data.inspect}
state = #{state.inspect}
EOF
        raise PLAYBACK_ERROR, msg
      end

      # defer any verbose debug logging (i.e. the current state) until after
      # metadata has been successfully loaded because a retryable missing
      # variable may occur a couple hundred times before the condition is
      # satisfied, if ever.
      logger.debug("BEGIN playback state = #{state.inspect}") if logger.debug?
      logger.debug("Played back response from #{file_path.inspect}.")

      # determine if epoch is done, which it is if every known request has been
      # responded to for the current epoch. there is a steady state at the end
      # of time when all responses are given but there is no next epoch.
      unless state[:end_of_time]

        # list epochs once.
        unless epochs = state[:epochs]
          epochs = []
          ::Dir[::File.join(fixtures_dir, '*')].each do |path|
            if ::File.directory?(path)
              name = ::File.basename(path)
              epochs << Integer(name) if name =~ /^\d+$/
            end
          end
          state[:epochs] = epochs.sort!
        end

        # current epoch must be listed.
        current_epoch = state[:epoch]
        unless current_epoch == epochs.first
          raise PLAYBACK_ERROR,
                "Unable to locate current epoch directory: #{::File.join(fixtures_dir, current_epoch.to_s).inspect}"
        end

        # sorted epochs reveal the future.
        if next_epoch = epochs[1]
          # list all responses in current epoch once.
          unless remaining = state[:remaining_responses]
            # use all configured route subdirectories when building remaining
            # responses hash.
            #
            # note that any unknown route fixtures would cause playback to spin
            # on the same epoch forever. we could specifically select known
            # route directories but it is just easier to find all here.
            search_path = ::File.join(
              @fixtures_dir,
              current_epoch.to_s,
              '*/response/**/*.yml')
            remaining = state[:remaining_responses] = ::Dir[search_path].inject({}) do |h, path|
              h[path] = { call_count: 0 }
              h
            end
            if remaining.empty?
              raise PLAYBACK_ERROR,
                    "Unable to determine remaining responses from #{search_path.inspect}"
            end
            logger.debug("Pending responses for epoch = #{current_epoch}: #{remaining.inspect}")
          end

          # may have been reponded before in same epoch; only care if this is
          # the first time response was used unless playback is throttled.
          #
          # when playback is not throttled, there is no time delay (beyond the
          # time needed to compute response) and the minimum number of calls per
          # response is one.
          #
          # when playback is throttled (non-zero) we must satisfy the call count
          # before advancing epoch. the point of this is to force the client to
          # repeat the request the recorded number of times before the state
          # appears to change.
          #
          # note that the user can achieve minimum delay while checking call
          # count by setting @throttle = 1
          if response_data = remaining[file_path]
            response_data[:call_count] += 1
            exhausted_response =
              (0 == @throttle) ||
              (response_data[:call_count] >= result.call_count)
            if exhausted_response
              remaining.delete(file_path)
              if remaining.empty?
                # time marches on.
                past_epochs.unshift(epochs.shift)
                state[:epoch] = next_epoch
                state.delete(:remaining_responses)  # reset responses for next epoch
                if logger.debug?
                  message = <<EOF

A new epoch = #{state[:epoch]} begins due to
  verb = #{request_metadata.verb}
  uri = \"#{request_metadata.uri}\"
  throttle = #{@throttle}
  call_count = #{@throttle == 0 ? '<ignored>' : "#{response_data[:call_count]} >= #{result.call_count}"}
EOF
                  logger.debug(message)
                end
              end
            end
          end
        else
          # the future is now; no need to add final epoch to past epochs.
          state.delete(:remaining_responses)
          state.delete(:epochs)
          state[:end_of_time] = true
        end
      end
      logger.debug("END playback state = #{state.inspect}") if logger.debug?
      result
    end

  end # Base
end # RightDevelop::Testing::Client::Rest
