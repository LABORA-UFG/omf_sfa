require 'omf_rc'
require 'omf-sfa/am/am-amqp/resource-proxies/am_controller'
require 'omf_common'
require 'omf-sfa/am/default_authorizer'
require 'omf-sfa/resource'
require 'pp'

module OMF::SFA::AM::AMQP

  class AMController
    include OMF::Common::Loggable

    def initialize(opts)
      @manager = opts[:am][:manager]
      @authorizer = create_authorizer

      EM.next_tick do
        OmfCommon.comm.on_connected do |comm|
          auth = opts[:amqp][:auth]

          entity_cert = File.expand_path(auth[:entity_cert])
          entity_key = File.expand_path(auth[:entity_key])
          # if entity cert contains the private key just add the entity cert else add the entity_key too
          pem_file = File.open(entity_cert).each_line.any? { |line| line.chomp == '-----BEGIN RSA PRIVATE KEY-----'} ? File.read(entity_cert) : "#{File.read(entity_cert)}#{File.read(entity_key)}"
          @cert = OmfCommon::Auth::Certificate.create_from_pem(pem_file)
          @cert.resource_id = OmfCommon.comm.local_topic.address
          OmfCommon::Auth::CertificateStore.instance.register(@cert)

          trusted_roots = File.expand_path(auth[:root_cert_dir])
          OmfCommon::Auth::CertificateStore.instance.register_default_certs(trusted_roots)

          OmfRc::ResourceFactory.create(:am_controller, {uid: 'am_controller', certificate: @cert}, {manager: @manager, authorizer: @authorizer})

          puts "AM Resource Controller ready."
        end
      end
    end

    # This is temporary until we use an amqp authorizer
    def create_authorizer
      auth = {}
      [
        # ACCOUNT
        :can_create_account?,
        :can_view_account?,
        :can_renew_account?,
        :can_close_account?,
        # RESOURCE
        :can_create_resource?,
        :can_view_resource?,
        :can_release_resource?,
        :can_modify_resource?,
        # LEASE
        :can_create_lease?,
        :can_view_lease?,
        :can_modify_lease?,
        :can_release_lease?,
      ].each do |m| auth[m] = true end
      OMF::SFA::AM::DefaultAuthorizer.new(auth)
    end

  end # AMController
end # module

