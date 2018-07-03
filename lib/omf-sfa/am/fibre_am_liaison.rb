require 'omf_common'
require 'omf-sfa/am/am_manager'
require 'omf-sfa/am/nitos_am_liaison'
require "net/https"
require "uri"
require 'json'
require 'open3'

DEFAULT_REST_END_POINT = {url: "https://localhost:4567", user: "root", token: "1234556789abcdefghij"}

module OMF::SFA::AM

  extend OMF::SFA::AM

  # This class implements the AM Liaison
  #
  class FibreAMLiaison < NitosAMLiaison

    def initialize(opts)
      super
      @default_sliver_type = OMF::SFA::Model::SliverType.find(urn: @config[:provision][:default_sliver_type_urn])
      @pubsub = OMF::SFA::AM::AMServer.pubsub_config
      @rest_end_points = @config[:REST_end_points]
    end

    def list_all_resources
      endpoints = @config[:SFA_end_points]
      nodes = Array.new()
      endpoints.each { |server|
        stdout, stdeerr, status = Open3.capture3("/media/arquivos/idea-projects/geni-tools/src/omni.py -a #{server[:url]} listresources")
        nodes.append(/<node[\s\S]*<\/node>/s.match(stdeerr).to_s)
      }
      return nodes
    end

    def create_account(account)
      warn "Am liaison: create_account: Not implemented."
    end

    def close_account(account)
      warn "Am liaison: close_account: Not implemented."
    end

    def configure_keys(keys, account)
      warn "Am liaison: configure_keys: Not implemented."
    end

    def create_resource(resource, lease, component)
      warn "Am liaison: create_resource: Not implemented."
    end

    def release_resource(resource, new_res, lease, component)
      warn "Am liaison: release_resource: Not implemented."
    end

    def start_resource_monitoring(resource, lease, oml_uri=nil)
      warn "Am liaison: start_resource_monitoring: Not implemented."
    end

    def on_lease_start(lease)
      warn "Am liaison: on_lease_start: Not implemented."
    end

    def on_lease_end(lease)
      debug "FibreAMLiaison: on_lease_end: #{lease.inspect}"
      for component in lease.components
        if component.type == "OMF::SFA::Model::Node" and component.account_id != 2
          debug "Component: #{component.to_hash}"
          sliver_type = component.sliver_type
          if sliver_type
            vm_topic = "#{vm_topic}fed-#{@pubsub[:server].gsub('.', '-')}-" if @pubsub[:federate]
            vm_topic = "#{vm_topic}#{sliver_type.label}"
            stop_vm(vm_topic)
          end
        end
      end
    end

    def stop_vm(vm_topic)
      OmfCommon.comm.subscribe(vm_topic) do |vm_rc|
        debug "Stopping VM #{vm_topic}"
        unless vm_rc.error?
          vm_rc.on_subscribed do
            vm_rc.configure(action: :stop)
          end
        end
      end
    end

    def provision(leases)
      warn "Am liaison: on_provision: Not implemented."
    end
  end # OMF::SFA::AM
end

