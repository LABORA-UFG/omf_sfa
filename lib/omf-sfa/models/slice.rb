require 'omf-sfa/models/resource'
require 'omf-sfa/models/component'

module OMF::SFA::Model
  class Slice < Resource
    many_to_one :accounts
    many_to_many :components, :left_key=>:slice_id, :right_key=>:component_id,
    :join_table=>:components_slices

    extend OMF::SFA::Model::Base::ClassMethods
    include OMF::SFA::Model::Base::InstanceMethods

    def self.include_nested_attributes_to_json
      sup = super
      [:components].concat(sup)
    end

    def to_hash
      values[:components] = []
      values[:links] = []
      values[:nodes] = []
      values[:vms] = []
      self.components.each do |component|
        if component.respond_to?(:sliver_type) && !component.sliver_type.nil?
          values[:vms] << component.to_hash_brief
        elsif component.resource_type == 'node'
          values[:nodes] << component.to_hash_brief
        elsif component.resource_type == 'link'
          values[:links] << component.to_hash_brief
        else
          values[:components] << component.to_hash_brief
        end
      end
      values[:account] = self.account ? self.account.to_hash_brief : nil
      values.reject! { |k, v| v.nil? or (v.kind_of? Array and v.length == 0)}
      excluded = self.class.exclude_from_json
      values.reject! { |k, v| excluded.include?(k)}
      values
    end

    def to_hash_brief
      values[:account] = self.account.to_hash_brief unless self.account.nil?
      super
    end

    ## REST requests treatment
    def self.handle_rest_resource_creation(body_opts, authorizer, scheduler)
      # Check parameters
      slice_resources = body_opts[:resources]
      account_urn = body_opts[:account]
      raise OMF::SFA::AM::Rest::BadRequestException.new "You need to inform an account." if account_urn.nil?
      raise OMF::SFA::AM::Rest::BadRequestException.new "You need to inform the resources array that will be in the slice." if slice_resources.nil? or !slice_resources.kind_of? Array
      raise OMF::SFA::AM::Rest::BadRequestException.new "The slice could not have empty resources." if slice_resources.length == 0

      # Validate account using the authorizer
      account = OMF::SFA::Model::Account.first({:urn => account_urn})
      raise OMF::SFA::AM::Rest::BadRequestException.new "The account '#{account_urn}' doesn't not exists." unless account
      raise OMF::SFA::AM::Rest::BadRequestException.new "You have no permission to create a slice in this account." unless authorizer.can_operate_slice?(account)

      # Check if already exists a slice for the account
      created_slice = self.first({:account_id => account.id})
      raise OMF::SFA::AM::Rest::BadRequestException.new "The account '#{account_urn}' already have a slice, please use the PUT method to modify it." if created_slice

      # Validate resources
      begin
        slice_model_resources, vms = self.validate_slice_resources(slice_resources, scheduler.get_nil_account().id)
      rescue => ex
        raise OMF::SFA::AM::Rest::BadRequestException.new ex.to_s
      end

      # All OK, proceed with creation...
      new_slice = nil
      begin
        new_slice = self.create({:account_id => account.id, :name => account.urn.split(':').last})
      rescue => ex
        raise OMF::SFA::AM::Rest::BadRequestException.new "Slice description is invalid: #{ex.to_s}"
      end

      new_slice = self.insert_components_to_slice(new_slice, slice_model_resources, vms, scheduler)
      new_slice
    end

    def self.handle_rest_resource_update(body_opts, authorizer, scheduler)
      # Check parameters
      slice_resources = body_opts[:resources]
      account_urn = body_opts[:account]
      raise OMF::SFA::AM::Rest::BadRequestException.new "You need to inform an account." if account_urn.nil?
      raise OMF::SFA::AM::Rest::BadRequestException.new "You need to inform the resources array that will be in the slice." if slice_resources.nil? or !slice_resources.kind_of? Array
      raise OMF::SFA::AM::Rest::BadRequestException.new "The slice could not have empty resources." if slice_resources.length == 0

      # Check if slice exists
      slice = OMF::SFA::Model::Account.join(OMF::SFA::Model::Slice.select_all, account_id: :id)
                  .filter(Sequel.qualify("Class", "urn") => account_urn).first
      raise OMF::SFA::AM::Rest::BadRequestException.new "The slice doesn't not exists: #{account_urn}" unless slice

      # Check authorization
      raise OMF::SFA::AM::Rest::BadRequestException.new "You have no permission to modify this slice." unless authorizer.can_operate_slice?(slice.account)

      # Validate resources
      begin
        slice_model_resources, vms = self.validate_slice_resources(slice_resources, scheduler.get_nil_account().id)
      rescue => ex
        raise OMF::SFA::AM::Rest::BadRequestException.new ex.to_s
      end

      # Remove all actual components
      slice = self.remove_components_of_slice(slice)

      # Insert new components
      slice = self.insert_components_to_slice(slice, slice_model_resources, vms, scheduler)
      slice
    end

    def self.handle_rest_resource_release(body_opts, authorizer, scheduler)
      account_urn = body_opts[:account]
      raise OMF::SFA::AM::Rest::BadRequestException.new "You need to inform an account." if account_urn.nil?

      # Check if slice exists
      slice = OMF::SFA::Model::Account.join(OMF::SFA::Model::Slice.select_all, account_id: :id)
                  .filter(Sequel.qualify("Class", "urn") => account_urn).first
      raise OMF::SFA::AM::Rest::BadRequestException.new "The slice doesn't not exists: #{account_urn}" unless slice

      # Check authorization
      raise OMF::SFA::AM::Rest::BadRequestException.new "You have no permission to modify this slice." unless
          authorizer.can_operate_slice?(slice.account) and authorizer.can_release_resource?(slice)

      # Remove all actual components
      slice = self.remove_components_of_slice(slice)

      # Destroy slice
      slice.destroy

      return slice
    end

    ##
    # Validates the resources passed in the POST/PUT method to create/edit the slice
    #
    def self.validate_slice_resources(resources, default_account_id)
      slice_model_resources = []
      vms = []
      not_found_resources = []
      resources.each do |slice_resource|
        # Virtual machine validation is different...
        if slice_resource[:type] == 'virtual_machine'
          # Check params
          raise "Invalid VM resource: #{slice_resource}" unless
              [:type, :hypervisor, :name, :cpu_cores, :ram_in_mb, :disk_image].all? { |s| slice_resource.key? s }

          # Check if hypervisor and disk images is available, if not, skip VM addition...
          hypervisor = OMF::SFA::Model::Node.first({:urn => slice_resource[:hypervisor], :account_id => default_account_id})
          disk_image = OMF::SFA::Model::DiskImage.first({:urn => slice_resource[:disk_image]})

          unless hypervisor
            not_found_resources << slice_resource[:hypervisor]
            next
          end
          unless disk_image
            not_found_resources << slice_resource[:disk_image]
            next
          end

          # Add vm in the creation list
          vms << {
              :hypervisor => hypervisor,
              :name => slice_resource[:name],
              :cpu_cores => slice_resource[:cpu_cores],
              :ram_in_mb => slice_resource[:ram_in_mb],
              :disk_image => disk_image
          }
          next
        end

        # Validate other resource types
        raise "Invalid resource: #{slice_resource}" if slice_resource[:type].nil? or (slice_resource[:urn].nil? &&
            slice_resource[:uuid].nil? && slice_resource[:name].nil?)

        # Search resource
        resource_obj = nil
        if slice_resource[:urn]
          resource_obj = OMF::SFA::Model::Resource.where({:urn => slice_resource[:urn], :account_id => default_account_id})
        end
        if slice_resource[:uuid]
          resource_obj = resource_obj.or({:uuid => slice_resource[:uuid], :account_id => default_account_id}) unless resource_obj.nil?
          resource_obj = OMF::SFA::Model::Resource.where({:uuid => slice_resource[:uuid], :account_id => default_account_id}) unless resource_obj
        end
        if slice_resource[:name]
          resource_obj = resource_obj.or({:name => slice_resource[:name], :account_id => default_account_id}) unless resource_obj.nil?
          resource_obj = OMF::SFA::Model::Resource.where({:name => slice_resource[:name], :account_id => default_account_id}) unless resource_obj
        end

        resource_obj = resource_obj.first unless resource_obj.nil?
        # Skip resource addition if resource does not exists.
        unless resource_obj
          not_found_resources << slice_resource
          next
        end
        slice_model_resources << resource_obj
      end

      return slice_model_resources, vms, not_found_resources
    end

    ##
    # Insert components to the slices
    #
    def self.insert_components_to_slice(slice, model_resources, vms, scheduler)
      # Add model resources to the slice
      model_resources.each do |comp|
        begin
          slice.add_component(comp)
        end
      end

      # Create VMs and add then to the slice
      vms.each do |vm|
        begin
          res_desc = {
              uuid: vm[:hypervisor].uuid,
              account_id: slice.account.id
          }
          hypervisor_type = vm[:hypervisor][:type].to_s.split('::').last
          sliver_info = {
              :exclusive => false,
              :sliver_type => {
                  :name => 'virtual_machine',
                  :label => slice.account.urn + ':' + vm[:name],
                  :disk_image => vm[:disk_image].urn,
                  :cpu_cores => vm[:cpu_cores],
                  :ram_in_mb => vm[:ram_in_mb]
              }
          }
          sliver_type_vm = scheduler.create_child_resource(res_desc, hypervisor_type, sliver_info)
          slice.add_component(sliver_type_vm)
        rescue => ex
          remove_components_of_slice(slice)
          raise OMF::SFA::AM::Rest::BadRequestException.new "#{ex.to_s}"
        end
      end

      slice.save
      slice
    end

    ##
    # Remove all components of slice
    #
    def self.remove_components_of_slice(slice)
      # Remove all actual components
      slice.components.each do |component|
        if component.respond_to?(:sliver_type) && !component.sliver_type.nil? && component.sliver_type.name == 'virtual_machine'
          debug "Virtual machine slice resource... Removing it! #{component}"
          slice.remove_component(component)
          component.sliver_type.delete
          component.delete
        end
      end
      slice.remove_all_components
      slice.save
      slice
    end
  end
end
