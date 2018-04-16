require 'omf_rc'
require 'omf_common'

module OmfRc::ResourceProxy::VirtualMachine
  include OmfRc::ResourceProxyDSL

  register_proxy :virtual_machine, :create_by => :am_controller

  property :vm_desc, access: :init_only
  property :label, access: :init_only

  hook :before_ready do |resource|
    @manager = resource.creation_opts[:manager]
    @authorizer = resource.creation_opts[:authorizer]
  end

  # Request public keys of users that can access the virtual machine
  request :user_public_keys do |resource|
    vm_desc = resource.normalize_hash(resource.property[:vm_desc])
    vm = resource.get_resource

    debug "Getting user public keys of virtual machine with desc '#{vm_desc}'"
    if vm[:resource].nil?
      vm[:error]
    else
      keys = []
      vm[:resource].account.users.each do |user|
        user.keys.each do |key|
          keys << {
              :is_base64 => key.is_base64,
              :ssh_key => key.ssh_key
          }
        end
      end
      keys
    end
  end

  request :ram do |resource|
    vm_desc = resource.normalize_hash(resource.property[:vm_desc])
    vm = resource.get_resource

    debug "Getting RAM of virtual machine with desc '#{vm_desc}'"
    if vm[:resource].nil?
      vm[:error]
    else
      debug "RAM VALUE IS #{vm[:resource].ram_in_mb}"
      vm[:resource].ram_in_mb
    end
  end

  request :cpu do |resource|
    vm_desc = resource.normalize_hash(resource.property[:vm_desc])
    vm = resource.get_resource

    debug "Getting CPU of virtual machine with desc '#{vm_desc}'"
    if vm[:resource].nil?
      vm[:error]
    else
      vm[:resource].cpu_cores
    end
  end

  request :disk_image do |resource|
    vm_desc = resource.normalize_hash(resource.property[:vm_desc])
    vm = resource.get_resource

    debug "Getting Disk Image of virtual machine with desc '#{vm_desc}'"
    if vm[:resource].nil?
      vm[:error]
    else
      vm[:resource].disk_image.path
    end
  end

  # All virtual machine params will be configured here, to enhance the performance, not overriding one attribute
  # in database by time
  configure_all do |resource, conf_props, conf_result|
    vm_desc = resource.normalize_hash(resource.property[:vm_desc])
    debug "Configuring virtual machine with desc '#{vm_desc[:or]}' and opts '#{conf_props}'"

    update_attrs = {}
    update_attrs[:status] = conf_props[:status] unless conf_props[:status].nil?
    update_attrs[:mac_address] = conf_props[:mac_address] unless conf_props[:mac_address].nil?
    update_attrs[:ip_address] = conf_props[:ip_address] unless conf_props[:ip_address].nil?

    debug "Setting new props of virtual machine with desc '#{vm_desc[:or]}' to '#{update_attrs}'"
    begin
      vm_resource = @manager.update_resource(vm_desc, "sliver_type", @authorizer, update_attrs)
    rescue OMF::SFA::AM::UnknownResourceException => error
      error_msg = "Virtual machine not found: #{vm_desc[:or]}"
      resource.inform_error(error_msg)
    rescue OMF::SFA::AM::InsufficientPrivilegesException => error
      error_msg = "You have no permission to update the virtual machine #{vm_desc[:or]}"
      resource.inform_error(error_msg)
    rescue OMF::SFA::AM::FormatException, Exception => error
      resource.inform_error(error.to_s)
    end

    unless vm_resource.nil?
      update_attrs.each { |k, v| conf_result[k] = vm_resource[k.to_sym] }

      # Update mac_address in the vm_desc
      resource.property[:vm_desc]['or']['mac_address'] = update_attrs[:mac_address] unless update_attrs[:mac_address].nil?
    end
  end

  work :normalize_hash do |resource, hash|
    new_hash = {}
    hash.keys.each do |k|
      ks    = k.to_sym
      new_hash[ks] = hash[k]
      new_hash[ks] = resource.normalize_hash(new_hash[ks]) if new_hash[ks].kind_of? Hash
    end
    new_hash
  end

  work :get_resource do |resource|
      vm_desc = resource.normalize_hash(resource.property[:vm_desc])
      error_msg = nil
      res = nil
      begin
        res = @manager.find_resource(vm_desc, "sliver_type", @authorizer)
      rescue OMF::SFA::AM::UnknownResourceException => error
        error_msg = "Virtual machine not found: #{vm_desc[:or]}"
        resource.inform_error(error_msg)
      rescue OMF::SFA::AM::InsufficientPrivilegesException => error
        error_msg = "You have no permission to update the virtual machine #{vm_desc[:or]}"
        resource.inform_error(error_msg)
      rescue OMF::SFA::AM::FormatException, Exception => error
        error_msg = error.to_s
        resource.inform_error(error_msg)
      end
      {:resource => res, :error => error_msg}
  end
end