
require 'omf_common/lobject'
require 'omf-sfa/am/am-rest/auth/dummy/am_authorizer'
require 'rack'


module OMF::SFA::AM::Rest::DummyAuth
  class SessionAuthenticator < OMF::Common::LObject

    @@store = {}
    @@active = false
    @@expire_after = 2592000

    def self.active?
      @@active
    end

    def self.authenticated?
      self[:authenticated]
    end

    def self.authenticate
      self[:authenticated] = true
      self[:valid_until] = Time.now + @@expire_after
    end

    def self.logout
      self[:authenticated] = false
    end

    def self.[](key)
      (@@store[key] || {})[:value]
    end

    def self.[]=(key, value)
      @@store[key] = {:value => value, :time => Time.now } # add time for GC
    end

    #
    # opts -
    #   :no_session - Array of regexp to ignore
    #
    def initialize(app, opts = {})
      @app = app
      @opts = opts
      @opts[:no_session] = (@opts[:no_session] || []).map { |s| Regexp.new(s) }
      if @opts[:expire_after]
        @@expire_after = @opts[:expire_after]
      end
      @@active = true
    end


    def call(env)
      req = ::Rack::Request.new(env)
      method = req.request_method

      # Option method don't require any authorization
      if method == 'OPTIONS'
        status, headers, body = @app.call(env)
        return [status, headers, body]
      end

      req.session[:authorizer] = OMF::SFA::AM::Rest::DummyAuth::AMAuthorizer.create_for_rest_request(
          @opts[:am_manager]
      )

      status, headers, body = @app.call(env)
      [status, headers, body]
    rescue OMF::SFA::AM::InsufficientPrivilegesException => ex
      return create_error_return(401, ex.to_s)
    rescue OMF::SFA::AM::Rest::EmptyBodyException, OMF::SFA::AM::Rest::UnsupportedBodyFormatException => ex
      return create_error_return(400, ex.to_s)
    end

  end # class
end # module




