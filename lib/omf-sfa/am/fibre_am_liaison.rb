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
      @nil_account = opts[:nil_account]
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
      debug "configure_keys: keys:'#{keys.inspect}', account:'#{account.inspect}'"

      new_keys = []
      keys.each do |k|
        if k.kind_of?(OMF::SFA::Model::Key)
          new_keys << k.ssh_key unless new_keys.include?(k.ssh_key)
        elsif k.kind_of?(String)
          new_keys << k unless new_keys.include?(k)
        end
      end

      OmfCommon.comm.subscribe('user_factory') do |user_rc|
        unless user_rc.error?

          user_rc.create(:user, hrn: 'existing_user', username: account.name) do |reply_msg|
            if reply_msg.success?
              u = reply_msg.resource

              u.on_subscribed do

                u.configure(auth_keys: new_keys) do |reply|
                  if reply.success?
                    release_proxy(user_rc, u)
                  else
                    error "Configuration of the public keys failed - #{reply[:reason]}"
                  end
                end
              end
            else
              error ">>> Resource creation failed - #{reply_msg[:reason]}"
            end
          end
        else
          raise UnknownResourceException.new "Cannot find resource's pubsub topic: '#{user_rc.inspect}'"
        end
      end
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
      slice = OMF::SFA::Model::Slice.first({account_id: lease.account.id})
      domain = OMF::SFA::Model::Constants.default_domain.gsub('.', '-')
      fed_prefix = if @pubsub[:federate] then "fed-#{domain}-" else "" end

      for component in lease.components
        if component.type == "OMF::SFA::Model::Node" and component.account_id != @nil_account.id
          debug "Component: #{component.to_hash}"
          sliver_type = component.sliver_type
          fed_prefix = if @pubsub[:federate] then "fed-#{@pubsub[:server].gsub('.', '-')}-" else "" end
          if sliver_type
            vm_topic = "#{fed_prefix}#{sliver_type.label}"
            stop_vm(vm_topic)
          end
        end
      end

      slice_name = "#{fed_prefix}#{slice.name}_#{domain}"
      slice_name = convert_to_valid_variable_name(slice_name)

      release_flowvisor_slice(slice_name)
    end

    def convert_to_valid_variable_name(name)
      # Remove invalid characters
      name = re.sub(/[^0-9a-zA-Z_\-\.]/, '', name)

      name = name.gsub('-', '_')
      name = name.gsub('.', '_')

      # Remove leading characters until we find a letter or underscore
      name = re.gsub(/^[^a-zA-Z_]+/, '', name)
      name
    end

    def release_flowvisor_slice(slice)
      OmfCommon.comm.subscribe(slice) do |slice_topic|
        debug "Releasing slice #{slice}"
        slice_topic.on_subscribed do
          slice_topic.release_self()
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

    def update_vms_state(lease)
      debug "FibreAMLiaison: update_vms_state: #{lease.inspect}"
      for component in lease.components
        if component.type == "OMF::SFA::Model::Node" and component.account_id != @nil_account.id
          sliver_type = component.sliver_type
          if sliver_type
            debug "Component: #{component.to_hash}"
            vm_topic = "#{vm_topic}fed-#{@pubsub[:server].gsub('.', '-')}-" if @pubsub[:federate]
            vm_topic = "#{vm_topic}#{sliver_type.label}"
            _update_vms_state(vm_topic)
          end
        end
      end
    end

    def _update_vms_state(vm_topic)
      OmfCommon.comm.subscribe(vm_topic) do |vm_rc|
        debug "Looking for VM state: #{vm_topic}"
        unless vm_rc.error?
          vm_rc.on_subscribed do
            vm_rc.configure(:update_state)
          end
        end
      end
    end

    def provision(leases)
      warn "Am liaison: on_provision: Not implemented."
    end
  end # OMF::SFA::AM
end

