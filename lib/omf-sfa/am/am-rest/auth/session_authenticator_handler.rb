
require 'omf_common/lobject'
require 'omf-sfa/am/am-rest/session_authenticator'
require 'omf-sfa/am/am-rest/auth/fibre/session_authenticator'
require 'omf-sfa/am/am-rest/auth/dummy/session_authenticator'


module OMF::SFA::AM::Rest::Auth
  class SessionAuthenticatorHandler < OMF::Common::LObject

    @@config = OMF::Common::YAML.load('omf-sfa-am', :path => [File.dirname(__FILE__) + '/../../../../../etc/omf-sfa'])[:omf_sfa_am]

    def initialize(app, opts = {})
      auth_type = @@config[:rest_authorization][:type]

      @app = app
      @opts = opts
      case auth_type
        when 'fibre'
          @session_auth = OMF::SFA::AM::Rest::FibreAuth::SessionAuthenticator.new(@app, @opts)
        when 'dummy'
          @session_auth = OMF::SFA::AM::Rest::DummyAuth::SessionAuthenticator.new(@app, @opts)
        else
          @session_auth = OMF::SFA::AM::Rest::SessionAuthenticator.new(@app, @opts)
      end
    end

    def call(env)
      @session_auth.call(env)
    end

  end # class
end # module