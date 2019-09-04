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

      @am_rc_uid = 'am_controller'
      @am_rc_topic = nil
      @rc_instance = nil

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
          self.create_rc

          # start checker thread
          Thread.new {
            info "AM controller (RC) checker started!"
            self.subscribe_rc
            wait_time = 50

            while true
              sleep(wait_time)
              debug "AM Controller (RC) Checker: Getting RC status..."
              begin
                rc_is_fine = false
                @am_rc_topic.request([:rc_status]) do |msg|
                  if msg.itype != "ERROR" and msg.properties[:rc_status] == 'FINE'
                    debug "AM Controller (RC) Checker: RC status is FINE :)"
                    rc_is_fine = true
                  end
                end
                sleep(10)
                unless rc_is_fine
                  error "AM Controller (RC) Checker: RC is not fine after 10s, sending restart..."
                  self.create_rc
                end
              rescue
                error "Could not get AM Controller (RC) status, sending restart..."
                self.create_rc
              end
            end
          }

          puts "AM Resource Controller ready."
        end
      end
    end

    def set_rc_instance(rc_instance)
      @rc_instance = rc_instance
    end

    def subscribe_rc()
      OmfCommon.comm.subscribe(@am_rc_uid) do |am_topic|
        am_topic.on_subscribed do
          debug "AM Controller (RC) checker: Subscribed on RC topic."
          @am_rc_topic = am_topic
        end
      end
    end

    def create_rc()
      if @am_rc_topic
        begin
          @am_rc_topic.release(@am_rc_topic)
        end
        begin
          topics = OmfCommon::Comm::Topic.name2inst
          for name, topic in topics
            if topic.id.to_s == @am_rc_uid.to_s
              debug "AM Controller (RC) Checker: Remove old RC topic: #{name}"
              topic.unsubscribe(topic.id, {:delete => true})
              OmfCommon::Comm::Topic.name2inst.delete(name)
            end
          end
          sleep(10)
          self.subscribe_rc
        end
      end
      OmfRc::ResourceFactory.create(:am_controller, {uid: @am_rc_uid, certificate: @cert},
                                    {manager: @manager, authorizer: @authorizer, controller: self})
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

