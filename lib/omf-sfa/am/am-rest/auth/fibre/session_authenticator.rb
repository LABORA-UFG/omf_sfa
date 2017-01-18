
require 'omf_common/lobject'
require 'omf-sfa/am/am-rest/auth/fibre/am_authorizer'
require 'rack'


module OMF::SFA::AM::Rest::FibreAuth
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

      # Check if credential was informed and if is valid
      headers = get_request_headers(env)
      unless headers.has_key? 'Ch-Credential'
        raise OMF::SFA::AM::Rest::ChCredentialMissing.new('The Clearing House credential was not passed in the ' +
                                                              'CH-Credential header')
      end
      credential = OMF::SFA::AM::PrivilegeCredential.unmarshal_base64(headers['Ch-Credential'])
      unless credential.valid_at?
        raise OMF::SFA::AM::Rest::ChCredentialNotValid.new('The Clearing House credential have expired or not valid ' +
                                                               'yet. Check dates')
      end
      accepted_cred_types = ['slice', 'user']
      unless accepted_cred_types.include?(credential.type)
        raise OMF::SFA::AM::Rest::ChCredentialNotValid.new("The credential type '#{credential.type}' is not accepted " +
                                                               "to do broker rest requests, please enter with a " +
                                                               "slice or user credential")
      end

      # Option method don't require any authorization
      if method == 'OPTIONS'
        status, headers, body = @app.call(env)
        return [status, headers, body]
      end

      req.session[:authorizer] = OMF::SFA::AM::Rest::FibreAuth::AMAuthorizer.create_for_rest_request(
          credential,
          @opts[:am_manager]
      )

      status, headers, body = @app.call(env)
      [status, headers, body]
    rescue OMF::SFA::AM::InsufficientPrivilegesException => ex
      return create_error_return(401, ex.to_s)
    rescue OMF::SFA::AM::Rest::EmptyBodyException, OMF::SFA::AM::Rest::UnsupportedBodyFormatException => ex
      return create_error_return(400, ex.to_s)
    # Exceptions that extends RackException
    rescue OMF::SFA::AM::Rest::ChCredentialMissing, OMF::SFA::AM::Rest::ChCredentialNotValid => ex
      warn ex.to_s
      return ex.reply
    end

    ##
    # get request headers based on call env
    #
    def get_request_headers(env)
      headers = Hash[*env.select {|k,v| k.start_with? 'HTTP_'}
                          .collect {|k,v| [k.sub(/^HTTP_/, ''), v]}
                          .collect {|k,v| [k.split('_').collect(&:capitalize).join('-'), v]}
                          .sort
                          .flatten]
    end

    ##
    # generate Rack error return that can happens while authorization is performed
    #
    def create_error_return(code, message)
      warn "ERROR: #{message}"
      [
          code,
          {
              'Content-Type' => 'application/json',
              'Access-Control-Allow-Origin' => '*',
              'Access-Control-Allow-Methods' => 'GET, PUT, POST, OPTIONS'
          },
          JSON.pretty_generate(
              {
                  :error => {
                      :reason => message,
                  }
              }
          )
      ]
    end

  end # class
end # module




