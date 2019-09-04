require 'omf_rc'
require 'omf_common'
require 'omf-sfa/am/am-amqp/resource-proxies/vm_inventory'

module OmfRc::ResourceProxy::AMController
  include OmfRc::ResourceProxyDSL

  register_proxy :am_controller

  hook :before_ready do |resource|
    #logger.debug "creation opts #{resource.creation_opts}"
    @manager = resource.creation_opts[:manager]
    @authorizer = resource.creation_opts[:authorizer]
    @am_amqp_controller = resource.creation_opts[:controller]
    @am_amqp_controller.set_rc_instance(resource)
  end

  hook :before_create do |resource, new_resource_type, new_resource_options|
    if new_resource_type.to_sym == :vm_inventory
      debug "Creating virtual machine with params #{new_resource_options.to_yaml}"

      # Checks if the resource exists
      # The user need to pass label or mac address of VM to find it.
      vm_desc = {:or => {}}
      if new_resource_options[:label]
        vm_desc[:or][:label] = new_resource_options[:label]
        new_resource_options[:uid] = "am_controller_#{new_resource_options[:label]}"
      end
      if new_resource_options[:mac_address]
        vm_desc[:or][:mac_address] = new_resource_options[:mac_address]
      end

      begin
        resource = @manager.find_resource(vm_desc, "sliver_type", @authorizer)
        new_resource_options[:uid] = "am_controller_#{resource.label}" if new_resource_options[:mac_address]
      rescue Exception => error
        raise "Could not create virtual machine: #{error.to_s}"
      end

      debug "VM DESCRIPTION IN BEFORE_CREATE: #{vm_desc}"
      debug "CHILDREN: #{@children}"
      new_resource_options[:vm_desc] = vm_desc
    else
      raise "Can't create resource type #{new_resource_type}"
    end
  end

  hook :after_create do |resource|
    debug "VM_INVENTORY: RESOURCE CREATED"
  end

  request :rc_status do |resource|
    "FINE"
  end

  request :resources do |resource|
    resources = @manager.find_all_resources_for_account(@manager._get_nil_account, @authorizer)
    OMF::SFA::Resource::OResource.resources_to_hash(resources)
  end

  request :components do |resource|
    components = @manager.find_all_components_for_account(@manager._get_nil_account, @authorizer)
    OMF::SFA::Resource::OResource.resources_to_hash(components)
  end

  request :nodes do |resource|
    nodes = @manager.find_all_components({:type => "OMF::SFA::Resource::Node"}, @authorizer)
    res = OMF::SFA::Resource::OResource.resources_to_hash(nodes, {max_levels: 3})
    res
  end

  request :leases do |resource|
    leases = @manager.find_all_leases(@authorizer)

    #this does not work because resources_to_hash and to_hash methods only works for
    #oproperties and account is not an oprop in lease so we need to add it
    res = OMF::SFA::Resource::OResource.resources_to_hash(leases)
    leases.each_with_index do |l, i=0|
      res[:resources][i][:resource][:account] = l.account.to_hash
    end
    res
  end

  request :slices do |resource|
    accounts = @manager.find_all_accounts(@authorizer)
    OMF::SFA::Resource::OResource.resources_to_hash(accounts)
  end

  configure :resource do |resource, value|
    debug "CONFIGURE :resource #{value}"
    "Not Implemented yet!"
  end

  def handle_create_message(message, obj, response)
    # Makes default treatment (With some bonus :D) to some resources creation
    debug "HANDLE_CREATE_MESSAGE = #{message[:type].to_sym}"
    if message[:type].to_sym == :vm_inventory
      handle_create_with_options(message, obj, response)
      return
    end

    puts "Create #{message.inspect}## #{obj.inspect}## #{response.inspect}"
    @manager = obj.creation_opts[:manager]
    @authorizer = obj.creation_opts[:authorizer]
    @scheduler = @manager.get_scheduler

    opts = message.properties
    puts "opts #{opts.inspect}"
    new_props = opts.reject { |k| [:type, :uid, :hrn, :property, :instrument].include?(k.to_sym) }
    type = message.rtype.camelize

    # new_props.each do |key, value|
    #   puts "checking prop: '#{key}': '#{value}': '#{type}'"
    #   if value.kind_of? Array
    #     value.each_with_index do |v, i|
    #       if v.kind_of? Hash
    #         puts "Array: #{v.inspect}"
    #         model = eval("OMF::SFA::Resource::#{type}.#{key}").model
    #         new_props[key][i] = (k = eval("#{model}").first(v)) ? k : v
    #       end
    #     end
    #   elsif value.kind_of? Hash
    #       puts "Hash: #{value.inspect}"
    #       model = eval("OMF::SFA::Resource::#{type}.#{key}").model
    #       new_props[key] = (k = eval("#{model}").first(value)) ? k : value
    #   end
    # end

    debug "Message rtype #{message.rtype}"
    debug "Message new properties #{new_props.class} #{new_props.inspect}"

    new_res = create_resource(type, new_props)

    debug "NEW RES #{new_res.inspect}"
    new_res.to_hash.each do |key, value|
      response[key] = value
    end
    self.inform(:creation_ok, response)
  end

  private
  def handle_create_with_options(message, obj, response)
    new_name = message[:name] || message[:hrn]
    msg_props = message.properties.merge({ hrn: new_name })
    creation_opts = {
        manager: obj.creation_opts[:manager],
        authorizer: obj.creation_opts[:authorizer]
    }

    obj.create(message[:type], msg_props, creation_opts, &lambda do |new_obj|
      begin
        response[:res_id] = new_obj.resource_address
        response[:uid] = new_obj.uid

        # Getting property status, for preparing inform msg
        add_prop_status_to_response(new_obj, msg_props.keys, response)

        if (cred = new_obj.certificate)
          response[:cert] = cred.to_pem_compact
        end
        # self here is the parent
        self.inform(:creation_ok, response)
      rescue  => e
        err_resp = message.create_inform_reply_message(nil, {}, src: resource_address)
        err_resp[:reason] = e.to_s
        error "Encountered exception: #{e.message}, returning ERROR message"
        debug e.message
        debug e.backtrace.join("\n")
        return self.inform(:error, err_resp)
      end
    end)
  end

  private
  def create_resource(type, props)
    puts "Creating resource of type '#{type}' with properties '#{props.inspect}' @ '#{@scheduler.inspect}'"
    if type == "Lease" #Lease is a unigue case, needs special treatment
      #res = eval("OMF::SFA::Resource::#{type}").create(props)

      res_descr = {name: props[:name]}
      if comps = props[:components]
        #props.reject!{ |k| k == :components}
        props.tap { |hs| hs.delete(:components) }
      end

      #TODO when authorization is done remove the next line in order to change what authorizer does with his account
      @authorizer.account = props[:account]

      l = @scheduler.create_resource(res_descr, type, props, @authorizer)

      comps.each_with_index do |comp, i|
        if comp[:type].nil?
          comp[:type] = comp.model.to_s.split("::").last
        end
        c = @scheduler.create_resource(comp, comp[:type], {}, @authorizer)
        @scheduler.lease_component(l, c)
      end
      l
    else
      res = eval("OMF::SFA::Resource::#{type}").create(props)
      @manager.manage_resource(res.cmc) if res.respond_to?(:cmc) && !res.cmc.nil?
      @manager.manage_resource(res)
    end
  end

  #def handle_release_message(message, obj, response)
  #  puts "I'm not releasing anything"
  #end
end
