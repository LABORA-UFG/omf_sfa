
require 'omf_common/lobject'
require 'omf-sfa/am'
require 'nokogiri'
require 'active_support/inflector' # for classify method
require "net/https"
require "json"


module OMF::SFA::AM

  class AMManagerException < Exception; end
  class UnknownResourceException < AMManagerException; end
  class UnavailableResourceException < AMManagerException; end
  class UnknownAccountException < AMManagerException; end
  class FormatException < AMManagerException; end
  class ClosedAccountException < AMManagerException; end
  class InsufficientPrivilegesException < AMManagerException; end
  class UnavailablePropertiesException < AMManagerException; end
  class MissingImplementationException < Exception; end
  class UknownLeaseException < Exception; end
  class CentralBrokerException < Exception

    def initialize(*exceptions)
      mensagens = exceptions.collect {|exception|
        hash = JSON.parse(exception.reply[2])
        hash
      }
      super(mensagens.to_json)
    end

  end

  # The manager is where all the AM related policies and
  # resource management is concentrated. Testbeds with their own
  # ways of dealing with resources and components should only
  # need to extend this class.
  #
  class CentralAMManager < AMManager

    SFA_NAMESPACE_URI = "http://www.geni.net/resources/rspec/3"

    # Create an instance of this manager
    #
    # @param [Scheduler] scheduler to use for creating new resource
    #
    def initialize(scheduler)
      super
      opts = scheduler.options
      @subauthorities = opts[:central_broker][:subauthorities]
      @@sfa_namespaces = {}
      @@sfa_namespaces[:omf]  = 'http://schema.mytestbed.net/sfa/rspec/1'
      @@sfa_namespaces[:ol]   = 'http://nitlab.inf.uth.gr/schema/sfa/rspec/1'
      @@sfa_namespaces[:flex] = 'http://nitlab.inf.uth.gr/schema/sfa/rspec/lte/1'
    end

    ###
    # Method to pass REST requisitions to other subathorities
    #
    def pass_request(request_path, opts, rest_handler)
      get_params = opts[:req].params.symbolize_keys!
      method = opts[:req].request_method
      authorizer = opts[:req].session[:authorizer]
      begin
        body_params, format = rest_handler.parse_body(opts)
      rescue Exception => ex
        error "Error occured while parsing body: #{ex}"
        body_params = {}
        format = 'json'
      end

      debug "===== Request received: ======"
      debug request_path
      debug method
      debug get_params
      debug body_params
      debug "===== Done request info ======="

      # Get subauthorities
      subauthorities = {}
      if get_params[:component_manager_id]
        splitted_cm = get_params[:component_manager_id].split("+")
        if splitted_cm.length == 4
          cm_subauth = @subauthorities[splitted_cm[1]]
          unless cm_subauth.nil?
            subauthorities[splitted_cm[1].to_sym] = cm_subauth
          end
        end
        get_params.delete(:component_manager_id)
      else
        subauthorities = @subauthorities
      end

      raise OMF::SFA::AM::Rest::BadRequestException.new 'No subauthorities found to make this request.' unless subauthorities.length > 0

      # Recreate the request url
      pos_url = request_path
      get_params.each { |key, value|
        append_key = if pos_url == request_path then '?' else '&' end
        pos_url += "#{append_key}#{key}=#{value}"
      }

      # Iterate and make the request for all subauthorities
      all_responses = []
      tds = []
      subauthorities.each do |subauth, subauth_opts|
        tds << Thread.new {
          url = "#{subauth_opts[:address]}/resources/#{pos_url}"
          debug "Making #{method} request to subauth: #{subauth} - #{url}"
          http, request = prepare_request(method, url, authorizer, subauth_opts, body_params)

          begin
            out = http.request(request)
            response = JSON.parse(out.body, symbolize_names: true)
            subauth_urn = "urn:publicid:IDN+#{subauth}+authority+cm"
            exception = response[:exception] || nil
            exception[:component_manager_id] = subauth_urn unless exception.nil?
            error = response[:error] || nil
            error[:component_manager_id] = subauth_urn unless error.nil?
            single_resource = if !response[:resource_response].nil? && !response[:resource_response][:resource].nil? then response[:resource_response][:resource] else nil end
            resources = if !response[:resource_response].nil? && !response[:resource_response][:resources].nil? then response[:resource_response][:resources] else [] end
            resources << single_resource unless single_resource.nil?
            unless resources.nil?
              resources.each { |res|
                res[:component_manager_id] = subauth_urn
              }
            end

            am_return = {}
            am_return[:resources] = resources
            am_return[:exception] = exception unless exception.nil?
            am_return[:error] = error unless error.nil?
            all_responses << am_return
          rescue Errno::ECONNREFUSED
            error "connection to #{url} refused."
          end
        }
        tds.each {|td| td.join}
      end

      # join all subauthorities responses...
      final_response = {:resources => []}
      all_responses.each { |sub_response|
        # Join exceptions
        unless final_response[:exception].nil? or final_response[:exception].kind_of? Array
          aux_ex = final_response[:exception]
          final_response[:exception] = []
          final_response[:exception] << aux_ex
        end
        final_response[:exception] = sub_response[:exception] unless (sub_response[:exception].nil? or final_response[:exception].kind_of? Array)
        final_response[:exception] << sub_response[:exception] if final_response[:exception].kind_of? Array

        # Join errors
        unless final_response[:error].nil? or final_response[:error].kind_of? Array
          aux_ex = final_response[:error]
          final_response[:error] = []
          final_response[:error] << aux_ex
        end
        final_response[:error] = sub_response[:error] unless (sub_response[:error].nil? or final_response[:error].kind_of? Array)
        final_response[:error] << sub_response[:error] if final_response[:error].kind_of? Array

        # Join resources
        sub_response[:resources].each { |res|
          final_response[:resources] << res
        }
      }
      # Remove list and set resource if the result is only one (Brokes CH keys integration)
      #if final_response[:resources].length == 1
      #  final_response[:resource] = final_response.delete(:resources).first
      #end

      final_response[:resources] = aggregate_special_cases(final_response[:resources])
      final_response
    end

    def aggregate_special_cases(resources)
      new_resources = []
      first_key_managers = {}
      resources.each { |resource|
        if resource[:resource_type] == 'slice' || resource[:resource_type] == 'account' || resource[:resource_type] == 'lease'
          first_key_managers[resource[:resource_type].to_sym] = {} if first_key_managers[resource[:resource_type].to_sym].nil?
          included_res = {}
          already_included = false
          new_resources.each { |included_resource|
            if included_resource[:name] == resource[:name]
              included_res = included_resource
              already_included = true
            end
          }

          resource.each { |key, value|
            if key == :component_manager_id
              next
            end

            unless value.kind_of? Hash or value.kind_of? Array
              if included_res[key.to_sym].nil?
                first_key_managers[resource[:resource_type].to_sym][key.to_sym] = resource[:component_manager_id]
              end
              included_res[key.to_sym] = value if included_res[key.to_sym].nil? or value == included_res[key.to_sym]
              if value != included_res[key.to_sym]
                unless included_res[key.to_sym].kind_of? Array
                  aux_array = []
                  aux_array << {:data => included_res[key.to_sym], :component_manager_id => first_key_managers[resource[:resource_type].to_sym][key.to_sym]}
                  included_res[key.to_sym] = aux_array
                end
                included_res[key.to_sym] << {:data => value, :component_manager_id => resource[:component_manager_id]}
              end
              next
            end

            included_res[key.to_sym] = [] if included_res[key.to_sym].nil?
            if value.kind_of? Hash
              value[:component_manager_id] = resource[:component_manager_id]
              included_res[key.to_sym] << value
            end

            if value.kind_of? Array
              value.each { |val|
                included_res[key.to_sym] << {:data => val, :component_manager_id => resource[:component_manager_id]} unless val.kind_of? Hash
                if val.kind_of? Hash
                  val[:component_manager_id] = resource[:component_manager_id]
                  included_res[key.to_sym] << val
                end
              }
            end
          }

          unless already_included
            included_res[:name] = resource[:name]
            new_resources << included_res
          end
          next
        end

        new_resources << resource
      }
      info "KEY MANAGERS #{first_key_managers}"
      new_resources
    end

    ### ACCOUNTS: creating, finding, and releasing accounts

    # Return the account described by +account_descr+. Create if it doesn't exist.
    #
    # @param [Hash] properties of account
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Account] The requested account
    # @raise [UnknownResourceException] if requested account cannot be created
    # @raise [InsufficientPrivilegesException] if permission is not granted
    #
    def find_or_create_account(account_descr, authorizer)
      debug "central find_or_create_account: '#{account_descr.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Return the account described by +account_descr+.
    #
    # @param [Hash] properties of account
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Account] The requested account
    # @raise [UnknownResourceException] if requested account cannot be found
    # @raise [InsufficientPrivilegesException] if permission is not granted
    #
    def find_account(account_descr, authorizer)
      debug "central find__account: '#{account_descr.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Return all accounts visible to the requesting user
    #
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Array<Account>] The visible accounts (maybe empty)
    #
    def find_all_accounts(authorizer)
      debug "central find_all_accounts"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Renew account described by +account_descr+ hash until +expiration_time+.
    #
    # @param [Hash] properties of account or account object
    # @param [Time] time until account should remain valid
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Account] The requested account
    # @raise [UnknownResourceException] if requested account cannot be found
    # @raise [InsufficientPrivilegesException] if permission is not granted
    #
    def renew_account_until(account_descr, expiration_time, authorizer)
      debug "central renew_account_until: #{account_descr} - #{expiration_time}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Close the account described by +account+ hash.
    #
    # Make sure that all associated components are freed as well
    #
    # @param [Hash] properties of account
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Account] The closed account
    # @raise [UnknownResourceException] if requested account cannot be found
    # @raise [UnavailableResourceException] if requested account is closed
    # @raise [InsufficientPrivilegesException] if permission is not granted
    #
    def close_account(account_descr, authorizer)
      debug "central close_account: #{account_descr}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    ### USERS

    # Return the user described by +user_descr+. Create if it doesn't exist.
    # Reset its keys if an array of ssh-keys is given
    #
    # Note: This is an unprivileged  operation as creating a user doesn't imply anything
    # else beyond opening a record.
    #
    # @param [Hash] properties of user
    # @return [User] The requested user
    # @raise [UnknownResourceException] if requested user cannot be created
    #
    def find_or_create_user(user_descr, keys = nil)
      debug "central find_or_create_user: '#{user_descr.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Return the user described by +user_descr+.
    #
    # @param [Hash] properties of user
    # @return [User] The requested user
    # @raise [UnknownResourceException] if requested user cannot be found
    #
    def find_user(user_descr)
      debug "central find_user: '#{user_descr.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    ### LEASES: creating, finding, and releasing leases

    # Return the lease described by +lease_descr+.
    #
    # @param [Hash] properties of lease
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Lease] The requested lease
    # @raise [UnknownResourceException] if requested lease cannot be found
    # @raise [InsufficientPrivilegesException] if permission is not granted
    #
    def find_lease(lease_descr, authorizer)
      debug "central find_lease: '#{lease_descr.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Return the lease described by +lease_descr+. Create if it doesn't exist.
    #
    # @param [Hash] lease_descr properties of lease
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Lease] The requested lease
    # @raise [UnknownResourceException] if requested lease cannot be created
    # @raise [InsufficientPrivilegesException] if permission is not granted
    #
    def find_or_create_lease(lease_descr, authorizer)
      debug "central find_or_create_lease: '#{lease_descr.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Find al leases if no +account+ and +status+ is given
    #
    # @param [Account] filter the leases by account
    # @param [Status] filter the leases by their status ['pending', 'accepted', 'active', 'past', 'cancelled']
    # @param [Authorizer] Authorization context
    # @return [Lease] The requested leases
    #
    def find_all_leases(account = nil, status = ['pending', 'accepted', 'active', 'past', 'cancelled'], authorizer=nil, period=nil)
      debug "central find_all_leases: account: #{account.inspect} status: #{status}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Modify lease described by +lease_descr+ hash
    #
    # @param [Hash] lease properties like ":valid_from" and ":valid_until"
    # @param [Lease] lease to modify
    # @param [Authorizer] Authorization context
    # @return [Lease] The requested lease
    #
    def modify_lease(lease_properties, lease, authorizer)
      debug "central modify_lease: '#{lease_properties.inspect}' - '#{lease.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # cancel +lease+
    #
    # This implementation simply frees the lease record
    # and destroys any child components if attached to the lease
    #
    # @param [Lease] lease to release
    # @param [Authorizer] Authorization context
    #
    def release_lease(lease, authorizer)
      debug "central release_lease: lease:'#{lease.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Release an array of leases.
    #
    # @param [Array<Lease>] Leases to release
    # @param [Authorizer] Authorization context
    def release_leases(leases, authorizer)
      debug "central release_leases: leases:'#{leases.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # This method finds all the leases of the specific account and
    # releases them.
    #
    # @param [Account] Account who owns the leases
    # @param [Authorizer] Authorization context
    #
    def release_all_leases_for_account(account, authorizer)
      debug "central release_all_leases_for_account:'#{account.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end


    ### RESOURCES creating, finding, and releasing resources


    # Find a resource. If it doesn't exist throws +UnknownResourceException+
    # If it's not visible to requester throws +InsufficientPrivilegesException+
    #
    # @param [Hash, Resource] describing properties of the requested resource
    # @param [String] The type of resource we are trying to find
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Resource] The resource requested
    # @raise [UnknownResourceException] if no matching resource can be found
    # @raise [FormatException] if the resource description is not Hash
    # @raise [InsufficientPrivilegesException] if the resource is not visible to the requester
    #
    #
    def find_resource(resource_descr, resource_type, authorizer)
      debug "central find_resource: descr: '#{resource_descr.inspect}' resource_type: #{resource_type}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Find resources associated with another resource. If it doesn't exist throws +UnknownResourceException+
    # If it's not visible to requester throws +InsufficientPrivilegesException+
    #
    # @param [Hash, Resource] describing properties of the requested resource
    # @param [String] The type of resource we are trying to find
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Resource] The resource requested
    # @raise [UnknownResourceException] if no matching resource can be found
    # @raise [FormatException] if the resource description is not Hash
    # @raise [InsufficientPrivilegesException] if the resource is not visible to the requester
    #
    #
    def find_associated_resources(resource_descr, resource_type, target_type,authorizer)
      debug "central find_associated_resources: descr: '#{resource_descr.inspect}' resource_type: #{resource_type}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Find all the resources that fit the description. If it doesn't exist throws +UnknownResourceException+
    # If it's not visible to requester throws +InsufficientPrivilegesException+
    #
    # @param [Hash] describing properties of the requested resource
    # @param [String] The type of resource we are trying to find
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Resource] The resource requested
    # @raise [UnknownResourceException] if no matching resource can be found
    # @raise [FormatException] if the resource description is not Hash
    # @raise [InsufficientPrivilegesException] if the resource is not visible to the requester
    #
    #
    def find_all_resources(resource_descr, resource_type, authorizer)
      debug "central find_all_resources: descr: '#{resource_descr.inspect}' resource_type: #{resource_type}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Find all components matching the resource description that are not leased for the given timeslot.
    # If it doesn't exist, or is not visible to requester
    # throws +UnknownResourceException+.
    #
    # @param [Hash] description of components
    # @param [String] The type of components we are trying to find
    # @param [String, Time] beggining of the timeslot
    # @param [String, Time] ending of the timeslot
    # @return [Array] All availlable components
    # @raise [UnknownResourceException] if no matching resource can be found
    #
    def find_all_available_components(component_descr = {}, component_type, valid_from, valid_until, authorizer)
      debug "central find_all_available_components: descr: '#{component_descr.inspect}', from: '#{valid_from}', until: '#{valid_until}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Find a number of components matching the resource description that are not leased for the given timeslot.
    # If it doesn't exist, or is not visible to requester
    # throws +UnknownResourceException+.
    #
    # @param [Hash] description of components
    # @param [String] The type of components we are trying to find
    # @param [String, Time] beggining of the timeslot
    # @param [String, Time] ending of the timeslot
    # @param [Array] array of component uuids that are not eligible to be returned by this function
    # @param [Integer] number of available components to be returned by this function
    # @return [Array] All availlable components
    # @raise [UnknownResourceException] if no matching resource can be found
    #
    def find_available_components(component_descr, component_type, valid_from, valid_until, non_valid_component_uuids = [], nof_requested_components = 1, authorizer)
      debug "central find_all_available_components: descr: '#{component_descr.inspect}', from: '#{valid_from}', until: '#{valid_until}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Find all resources for a specific account. Return the managed resources
    # if no account is given
    #
    # @param [Account] Account for which to find all associated resources
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Array<Resource>] The resource requested
    #
    def find_all_resources_for_account(account = nil, authorizer)
      debug "central find_all_resources_for_account: #{account.inspect}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Find all components for a specific account. Return the managed components
    # if no account is given
    #
    # @param [Account] Account for which to find all associated component
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Array<Component>] The component requested
    #
    def find_all_components_for_account(account = _get_nil_account, authorizer)
      debug "central find_all_components_for_account: #{account.inspect} #{account.kind_of? Hash} #{account[:urn]}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Find all components
    #
    # @param [Hash] Properties used for filtering the components
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Array<Component>] The components requested
    #
    def find_all_components(comp_descr, authorizer)
      debug "central find_all_components: #{comp_descr.inspect}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Find or Create a resource. If an account is given in the resource description
    # a child resource is created. Otherwise a managed resource is created.
    #
    # @param [Hash] Describing properties of the resource
    # @param [String] Type to create
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Resource] The resource requested
    # @raise [UnknownResourceException] if no resource can be created
    #
    def find_or_create_resource(resource_descr, resource_type, authorizer)
      debug "central find_or_create_resource: resource '#{resource_descr.inspect}' type: '#{resource_type}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Create a resource. If an account is given in the resource description
    # a child resource is created. The parent resource should be already present and managed
    # This will provide a copy of the actual physical resource.
    # Otherwise a managed resource is created which belongs to the 'nil_account'
    #
    # @param [Hash] Describing properties of the requested resource
    # @param [String] Type to create
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Resource] The resource requested
    # @raise [UnknownResourceException] if no resource can be created
    #
    def create_resource(resource_descr, type_to_create, authorizer)
      debug "central create_resource: resource '#{resource_descr.inspect}' type: '#{resource_type}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Create a new resource
    #
    # @param [Hash] Describing properties of the requested resource
    # @param [String] Type to create
    # @param [Authorizer] Defines context for authorization decisions
    # @return [OResource] The resource created
    # @raise [UnknownResourceException] if no resource can be created
    #
    def create_new_resource(resource_descr, type_to_create, authorizer)
      debug "create_new_resource: resource_descr: #{resource_descr}, type_to_create: #{type_to_create}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    ##
    # Method used in rest requests to update a resource
    #
    def update_a_resource(resource_descr, type_to_create, authorizer)
      debug "update_a_resource: resource_descr: #{resource_descr}, type_to_create: #{type_to_create}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    ##
    # Update internal resources in AMQP layer
    #
    def update_resource(resource_desc, resource_type, authorizer, new_attributes)
      debug "update_resource: resource_descr: #{resource_desc}, type: #{resource_type}, new_attrs: #{new_attributes}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    ##
    # Method used in rest requests to release a resource
    #
    def release_a_resource(resource_descr, type_to_release, authorizer)
      debug "release_a_resource: resource_descr: #{resource_descr}, type_to_create: #{type_to_release}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    def filter_components_by_subauthority(resources_descr, subauth)
      options = resources_descr.clone
      components = resources_descr[:components]
      components = components.select {|component|
        component[:urn].include? subauth
      }
      options[:components] = components
      options
    end

    def filter_resources_by_subauthority(resources, subauth)
      resources = [resources] if resources.is_a? Hash
      selected_resources = resources.select {|resource|
        resource[:urn].include? subauth
      }
      selected_resources.collect {|resource|
        tmp = {:uuid => resource[:uuid]}
        tmp
      }
    end

    # Find or create a resource for an account. If it doesn't exist,
    # is already assigned to someone else, or cannot be created, throws +UnknownResourceException+.
    #
    # @param [Hash] describing properties of the requested resource
    # @param [String] Type to create if not already exist
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Resource] The resource requested
    # @raise [UnknownResourceException] if no matching resource can be found
    #
    def find_or_create_resource_for_account(resource_descr, type_to_create, authorizer)
      debug "central find_or_create_resource_for_account: r_descr:'#{resource_descr}' type:'#{type_to_create}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Release 'resource'.
    #
    # This implementation simply frees the resource record.
    #
    # @param [Resource] Resource to release
    # @param [Authorizer] Authorization context
    # @raise [InsufficientPrivilegesException] if the resource is not allowed to be released
    #
    def release_resource(resource, authorizer=nil)
      debug "central release_resource: '#{resource.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # Release an array of resources.
    #
    # @param [Array<Resource>] Resources to release
    # @param [Authorizer] Authorization context
    def release_resources(resources, authorizer=nil)
      debug "central release_resources: '#{resources.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    # This method finds all the components of the specific account and
    # detaches them.
    #
    # @param [Account] Account who owns the components
    # @param [Authorizer] Authorization context
    #
    def release_all_components_for_account(account, authorizer)
      debug "central release_all_components_for_account: '#{account.inspect}'"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    def create_resources_from_rspec(descr_el, clean_state, authorizer)
      debug "central create_resources_from_rspec: descr_el: '#{descr_el}' clean_state: '#{clean_state}'"
      raise 'NOT IMPLEMENTED YET!'
    end

    # Update the resources described in +resource_el+. Any resource not already assigned to the
    # requesting account will be added. If +clean_state+ is true, the state of all described resources
    # is set to the state described with all other properties set to their default values. Any resources
    # not mentioned are released. Returns the list
    # of resources requested or throw an error if ANY of the requested resources isn't available.
    #
    # Find or create a resource. If it doesn't exist, is already assigned to
    # someone else, or cannot be created, throws +UnknownResourceException+.
    #
    # @param [Element] RSpec fragment describing resource and their properties
    # @param [Boolean] Set all properties not mentioned to their defaults
    # @param [Authorizer] Defines context for authorization decisions
    # @return [OResource] The resource requested
    # @raise [UnknownResourceException] if no matching resource can be found
    # @raise [FormatException] if RSpec elements are not known
    #
    # @note Throws exception if a contained resource doesn't exist, but will not roll back any
    # already performed modifications performed on other resources.
    #
    def update_resources_from_rspec(descr_el, clean_state, authorizer)
      debug "central update_resources_from_rspec: descr_el:'#{descr_el}' clean_state:'#{clean_state}'"
      leases = {}
      descr_leases = {}
      if descr_el.namespaces.values.include?(OL_NAMESPACE)
        descr_leases = descr_el.xpath('//ol:lease', 'ol' => OL_NAMESPACE)
      end
      resources = []
      nodes = []
      descr_el.xpath('//xmlns:node').each do |node|
        raise FormatException.new "At least one of the requested components do not belong in a known subauthority." if node['component_manager_id'].nil?
        raise FormatException.new "component_manager_id is mandatory for resources '#{node['name']}'" if node['component_manager_id'].nil?
        nd = {component_id: node['component_id'], component_manager_id: node['component_manager_id']}
        # nd = find_resource({urn: node['component_id'], component_manager_id: node['component_manager_id']}, 'nodes' , authorizer)
        # raise FormatException.new "component #{node['component_id']} does not exist in any of the supported subauthorities." if nd.nil? || nd.empty?
        nodes << nd
        leases[node['component_manager_id']] = [] if leases[node['component_manager_id']].nil?

        node.xpath('child::ol:lease_ref|child::ol:lease', 'ol' => OL_NAMESPACE).each do |lease|
          l = descr_leases.select {|dl| lease['id_ref'] == dl['client_id']}
          next if l.nil? || l.empty?
          l = l.first

          ex_lease = leases[node['component_manager_id']].select {|ls| ls[:client_id] == l['client_id']}
          unless ex_lease.nil? || ex_lease.empty?
            ex_lease.first[:components] << {urn: node['component_id']}
          else
            new_lease = {}
            new_lease[:id] = l['id'] if l['id']
            new_lease[:client_id] = l['client_id']
            new_lease[:valid_from] = l['valid_from']
            new_lease[:valid_until] = l['valid_until']
            new_lease[:component_manager_id] = node['component_manager_id']
            new_lease[:components] = []
            new_lease[:components] << {urn: node['component_id']}
            leases[node['component_manager_id']] << new_lease
          end
        end
      end

      leases.each do |subauthority, ls|
        account = find_account({urn: authorizer.account[:urn], component_manager_id: subauthority}, authorizer)
        if account.nil? || account.empty?
          domain = subauthority.split('+')[1]
          subauth = @subauthorities[domain]
          raise UnknownResourceException.new "At least one of the requested components do not belong in a known subauth." if subauth.nil? || subauth.empty?

          url = "#{subauth[:address]}resources/accounts"

          options        = {}
          options[:name] = authorizer.account[:name]
          options[:urn]  = authorizer.account[:urn]

          http, request = prepare_request("POST", url, authorizer, subauthority, options)

          begin
            out = http.request(request)
            o = JSON.parse(out.body, symbolize_names: true)
            account = o[:resource_response][:resource] || o[:resource_response][:resources].first
          rescue Errno::ECONNREFUSED
            debug "connection to #{url} refused."
          end
        end

        ls.each do |lease|
          lease[:account]       = {}
          lease[:account][:urn] = account[:urn]
        end
      end


      l = self.update_leases_from_rspec(leases, authorizer)

      l.each do |lease_id, lease|
        resources << lease
      end

      nodes.each do |node|
        nd = find_resource({urn: node[:component_id], component_manager_id: node[:component_manager_id]}, 'nodes' , authorizer)
        resources << nd
      end

      resources
    end

    # Update a single resource described in +resource_el+. The respective account is
    # extracted from +opts+. Any mentioned resources not already available to the requesting account
    # will be created. If +clean_state+ is set to true, all state of a resource not specifically described
    # will be reset to it's default value. Returns the resource updated.
    #
    def update_resource_from_rspec(resource_el, leases, clean_state, authorizer)
      debug "central update_resource_from_rspec: resource_el:'#{resource_el}' leases: #{leases} clean_state:'#{clean_state}'"
      []
    end

    # Update the leases described in +leases+. Any lease not already assigned to the
    # requesting account will be added. If +clean_state+ is true, the state of all described leases
    # is set to the state described with all other properties set to their default values. Any leases
    # not mentioned are canceled. Returns the list
    # of leases requested or throw an error if ANY of the requested leases isn't available.
    #
    # @param [Element] RSpec fragment describing leases and their properties
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Hash{String => Lease}] The leases requested
    # @raise [UnknownResourceException] if no matching lease can be found
    # @raise [FormatException] if RSpec elements are not known
    #
    def update_leases_from_rspec(leases, authorizer)
      debug "central update_leases_from_rspec: leases:'#{leases.inspect}'"
      leases_hash = {}
      return {} if leases.nil? || leases.empty?
      leases.each do |subauthority, ls|
        ls.each do |lease|
          lease[:component_manager_id] = subauthority
          l = update_lease_from_rspec(lease, authorizer)
          leases_hash.merge!(l)
        end
      end
      leases_hash
    end

    # Create or Modify leases through RSpecs
    #
    # When a UUID is provided, then the corresponding lease is modified. Otherwise a new
    # lease is created with the properties described in the RSpecs.
    #
    # @param [Nokogiri::XML::Node] RSpec fragment describing lease and its properties
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Lease] The requested lease
    # @raise [UnavailableResourceException] if no matching resource can be found or created
    # @raise [FormatException] if RSpec elements are not known
    #
    def update_lease_from_rspec(lease_el, authorizer)
      debug "central update_lease_from_rspec: leases:'#{lease_el.inspect}'"
      if (lease_el[:valid_from].nil? || lease_el[:valid_until].nil?)
        raise UnavailablePropertiesException.new "Cannot create lease without ':valid_from' and 'valid_until' properties"
      end

      begin
        raise UnavailableResourceException unless UUID.validate(lease_el[:id])
        lease = find_lease({:uuid => lease_el[:id]}, authorizer)
        return { lease_el[:id] => lease }
      rescue UnavailableResourceException
        domain = lease_el[:component_manager_id].split('+')[1]
        subauthority = @subauthorities[domain]
        raise UnknownResourceException.new "At least one of the requested components do not belong in a known subauthority." if subauthority.nil? || subauthority.empty?

        url = "#{subauthority[:address]}resources/leases"

        options               = {}
        options[:name]        = lease_el[:client_id] if lease_el[:client_id]
        options[:urn]         = lease_el[:urn]  if lease_el[:urn]
        options[:account]     = lease_el[:account]
        options[:valid_from]  = lease_el[:valid_from]
        options[:valid_until] = lease_el[:valid_until]
        options[:components]  = lease_el[:components]

        http, request = prepare_request("POST", url, authorizer,subauthority, options)

        begin
          out = http.request(request)
          o = JSON.parse(out.body, symbolize_names: true)
          if o[:exception]
            error "lease '#{lease_el[:client_id]}' failed: code: #{o[:exception][:code]} msg: #{o[:exception][:reason]}"
            raise UnavailableResourceException.new "Cannot create '#{lease_el[:client_id]}', #{o[:exception][:reason]}"
          else
            o = o[:resource_response][:resource] || o[:resource_response][:resources]
            o[:component_manager_id] = lease_el[:component_manager_id]
          end
          lease = {("#{lease_el[:component_manager_id]}_#{lease_el[:client_id]}") => o}
        rescue Errno::ECONNREFUSED
          debug "connection to #{url} refused."
        end
        lease
      end
    end

    def sfa_response_xml(resources, opts)
      debug "central sfa_response_xml: resources:'#{resources.inspect}' opts:'#{opts.inspect}'"

      doc = Nokogiri::XML::Document.new
      root = doc.add_child(Nokogiri::XML::Element.new('rspec', doc))
      root.add_namespace(nil, SFA_NAMESPACE_URI)
      root.add_namespace('xsi', "http://www.w3.org/2001/XMLSchema-instance")
      root.set_attribute('type', opts[:type])

      @@sfa_namespaces.each do |prefix, urn|
        root.add_namespace(prefix.to_s, urn)
      end

      case opts[:type].downcase
        when 'advertisement'
          root['xsi:schemaLocation'] = "#{SFA_NAMESPACE_URI} #{SFA_NAMESPACE_URI}/ad.xsd " +
              "#{@@sfa_namespaces[:ol]} #{@@sfa_namespaces[:ol]}/ad-reservation.xsd" +
              "#{@@sfa_namespaces[:flex]} #{@@sfa_namespaces[:flex]}/ad.xsd"

          now = Time.now
          root.set_attribute('generated', now.iso8601)
          root.set_attribute('expires', (now + (opts[:valid_for] || 600)).iso8601)
        when 'manifest'
          root['xsi:schemaLocation'] = "#{SFA_NAMESPACE_URI} #{SFA_NAMESPACE_URI}/manifest.xsd " +
              "#{@@sfa_namespaces[:ol]} #{@@sfa_namespaces[:ol]}/request-reservation.xsd" +
              "#{@@sfa_namespaces[:flex]} #{@@sfa_namespaces[:flex]}/ad.xsd"

          now = Time.now
          root.set_attribute('generated', now.iso8601)
        else
          raise "Unknown SFA response type: '#{opts[:type]}'"
      end

      _to_sfa_xml(resources, root, opts).to_xml
    end

    def configure_user_keys(users, authorizer)
      debug "configure_user_keys called: #{users}"
      raise 'Method not implemented because the Central Manager just need to pass the same requisition to the other' \
                ' brokers and create the concatenated results'
    end

    private

    def prepare_request(type, url, authorizer, subauthority=nil, options=nil, header=nil)
      debug "PREPARE REQUEST CALLED: #{url}"
      header = {"Content-Type" => "application/json", "Accept" => "application/json"} if header.nil?
      type = type.capitalize

      pem = File.read(subauthority[:cert]) unless subauthority.nil?
      pkey = File.read(subauthority[:key]) unless subauthority.nil?

      uri              = URI.parse(url)
      http             = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = true
      http.read_timeout = 500
      http.cert        = OpenSSL::X509::Certificate.new(pem) unless type == "Get"
      http.key         = OpenSSL::PKey::RSA.new(pkey) unless type == "Get"
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      request          = eval("Net::HTTP::#{type}").new(uri.request_uri, header)
      if authorizer.instance_of? OMF::SFA::AM::Rest::FibreAuth::AMAuthorizer
        request['CH-Credential'] = authorizer.ch_key
      end
      request.body     = options.to_json unless options.nil?
      [http, request]
    end

    def check_error_messages(out)
      if out.code.start_with? "4" #to catch erros of type 400, 401, ...
        hash = JSON.parse out.body
        raise OMF::SFA::AM::Rest::NotAuthorizedException.new hash['exception']['reason']
      end
    end

    def find_subauthority_info(subauth_name)
      @subauthorities.each do |subauth, opts|
        return opts if subauth == subauth_name
      end
      nil
    end

    def find_subauthority_from_urn(urn)
      domain = urn.split('+')[1]
      @subauthorities.each do |subauth, opts|
        return opts if opts[domain] == domain
      end

      @subauthorities.each do |subauth, opts|
        return opts if domain.include?(opts[:domain])
      end

      nil
    end

    def find_domains_from_components(components)
      domains = {}

      @subauthorities.each do |subauth, opts|
        domains[opts[:domain]] = []
      end

      components.each do |component|
        domain = component[:urn].split('+')[1]
        if domains[domain.to_sym]
          domains[domain.to_sym] << component
        else
          dom = domains.select{|k,v| domain.to_s.include?(k)} # check if one subauthority contains the domain (e.g. omf:nitos and omf:nitos.indoor)
          unless dom.empty?
            domains[dom.keys.first.to_sym] << component
          end
        end
      end

      domains
    end

    def _to_sfa_xml(resources, root, opts = {})
      if resources.kind_of? Enumerable
        resources.each do |resource|
          to_sfa_xml(root, resource, opts)
        end
      else
        return root.document if resources.nil? || resources.empty?
        to_sfa_xml(root, resources, opts)
      end
      root.document
    end

    def find_key(key, subauthority)
      url = "#{subauthority[:address]}resources/keys"

      uri               = URI.parse(url)
      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 500
      http.verify_mode  = OpenSSL::SSL::VERIFY_NONE
      request           = Net::HTTP::Get.new(uri.request_uri)

      user_keys = []
      begin
        out = http.request(request)
        o = JSON.parse(out.body, symbolize_names: true)[:resource_response][:resources]

        o.each do |k|
          return k if k[:ssh_key] == key
        end
      rescue Errno::ECONNREFUSED
        debug "connection to #{url} refused."
      end
      nil
    end

    def to_sfa_xml(root, resource, opts)
      case resource[:resource_type]
        when 'node'
          new_element = root.add_child(Nokogiri::XML::Element.new('node', root.document))
          new_element.set_attribute('component_id', resource[:urn])
          new_element.set_attribute('component_manager_id', resource[:component_manager_id])
          new_element.set_attribute('component_name', resource[:name])
          new_element.set_attribute('exclusive', resource[:exclusive])
          new_element.set_attribute('monitored', resource[:monitored]) if resource[:monitored]
          new_child = new_element.add_child(Nokogiri::XML::Element.new('available', new_element.document))
          new_child.set_attribute('now', resource[:available])
          new_child = new_element.add_child(Nokogiri::XML::Element.new('hardware_type', new_element.document))
          new_child.set_attribute('name', resource[:hardware_type])
          resource[:interfaces].each do |iface|
            new_child = new_element.add_child(Nokogiri::XML::Element.new('interface', new_element.document))
            new_child.set_attribute('component_id', iface[:urn])
            new_child.set_attribute('component_name', iface[:name])
            new_child.set_attribute('role', iface[:role])
            iface[:ips].each do |ip|
              new_child2 = new_child.add_child(Nokogiri::XML::Element.new('ip', new_child.document))
              new_child2.set_attribute('address', ip[:address])
              new_child2.set_attribute('type', ip[:type])
              new_child2.set_attribute('netmask', ip[:netmask])
            end unless iface[:ips].nil?
          end if resource[:interfaces]
          if resource[:location]
            new_child = new_element.add_child(Nokogiri::XML::Element.new('location', new_element.document))
            new_child.set_attribute('city', resource[:location][:city])
            new_child.set_attribute('country', resource[:location][:country])
            new_child.set_attribute('latitude', resource[:location][:latitude])
            new_child.set_attribute('longitude', resource[:location][:longitude])
            new_child2 = new_child.add_child(Nokogiri::XML::Element.new('ol:position_3d', new_child.document))
            new_child2.set_attribute('x', resource[:location][:position_3d_x])
            new_child2.set_attribute('y', resource[:location][:position_3d_y])
            new_child2.set_attribute('z', resource[:location][:position_3d_z])
          end
          if opts[:type].downcase == 'manifest' && resource[:gateway]
            new_child = new_element.add_child(Nokogiri::XML::Element.new('login', new_element.document))
            new_child.set_attribute('authentication', "ssh-keys")
            new_child.set_attribute('hostname', resource[:gateway])
            new_child.set_attribute('port', "22")
            new_child.set_attribute('username', opts[:account][:name])
          end
          resource[:leases].each do |lease|
            new_child = new_element.add_child(Nokogiri::XML::Element.new('ol:lease_ref', new_element.document))
            new_child.set_attribute('id_ref', lease[:uuid])
          end unless resource[:leases].nil?
        when 'lease'
          new_element = root.add_child(Nokogiri::XML::Element.new('ol:lease', root.document))
          new_element.set_attribute('id', resource[:uuid])
          new_element.set_attribute('sliver_id', resource[:urn])
          new_element.set_attribute('valid_from', resource[:valid_from])
          new_element.set_attribute('valid_until', resource[:valid_until])
        else
          #just ignoring for now
      end
    end

  end # class
end # OMF::SFA::AM
