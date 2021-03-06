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

# fixup RACK_ENV
require 'right_develop'
require 'rack'
require 'rack/commonlogger'

require ::File.expand_path('../../lib/config', __FILE__)
require ::File.expand_path('../../lib/logger', __FILE__)
require ::File.expand_path('../../app/base', __FILE__)
require ::File.expand_path('../../app/admin', __FILE__)
require ::File.expand_path('../../app/echo', __FILE__)
require ::File.expand_path('../../app/playback', __FILE__)
require ::File.expand_path('../../app/record', __FILE__)

# HACK: monkey-patch Rack::CommonLogger#log to be silent in favor of our own
# brand of request/response logging.
#
# note that it is nearly impossible to remove the CommonLogger middleware from
# the stack.
module Rack
  class CommonLogger

    private

    # override log() but not the call(env) method as that method has the strange
    # side-effect of changing the [headers, body] to be instances of
    # Rack::Utils::HeaderHash and Rack::BodyProxy
    def log(env, status, header, began_at)
      nil  # log nothing
    end
  end
end

module RightDevelop::Testing::Server::MightApi

  # attempt to read stdin for configuration or else expect relative file path.
  # note the following .fcntl call returns zero when data is available on $stdin
  config_yaml = ($stdin.tty? || 0 != $stdin.fcntl(::Fcntl::F_GETFL, 0)) ? '' : $stdin.read
  config_hash = config_yaml.empty? ? nil : ::YAML.load(config_yaml)
  if config_hash
    Config.from_hash(config_hash)
  else
    Config.from_file(Config::DEFAULT_CONFIG_PATH)
  end

  # ensure fixture dir exists as result of configuration for better
  # synchronization of any state file locking.
  case Config.mode
  when :admin, :echo
    # do nothing
  when :playback, :record
    ::FileUtils.mkdir_p(Config.fixtures_dir)
  else
    fail 'Unexpected mode'
  end

  # ready.
  logger.info("MightApi initialized in #{Config.mode} mode.")
end
