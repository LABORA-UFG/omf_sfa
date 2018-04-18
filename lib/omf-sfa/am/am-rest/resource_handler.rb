require 'omf-sfa/am/am-rest/rest_handler'
require 'omf-sfa/am/am_manager'
require 'uuid'

module OMF::SFA::AM::Rest

  # Handles an individual resource
  #
  class ResourceHandler < RestHandler

    # Return the handler responsible for requests to +path+.
    # The default is 'self', but override if someone else
    # should take care of it
    #
    def find_handler(path, opts)
      #opts[:account] = @am_manager.get_default_account
      opts[:resource_uri] = path.join('/')

      if path.size == 0 || path.size == 1
        debug "find_handler: path: '#{path}'"
        return self
      elsif path.size == 2 && opts[:req].request_method == 'GET' #/resources/type1/UUID-OR-URN
        opts[:source_resource_uri] = path[0]
        opts[:source_resource_uuid] = path[1]
        debug "find_handler: path: '#{path}'"
        return self
      elsif path.size == 3 #/resources/type1/UUID/type2
        opts[:source_resource_uri] = path[0]
        opts[:source_resource_uuid] = path[1]
        opts[:target_resource_uri] = path[2]
        # raise OMF::SFA::AM::Rest::BadRequestException.new "'#{opts[:source_resource_uuid]}' is not a valid UUID." unless UUID.validate(opts[:source_resource_uuid])
        require 'omf-sfa/am/am-rest/resource_association_handler'
        return OMF::SFA::AM::Rest::ResourceAssociationHandler.new(@am_manager, opts)
      else
        raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL: #{path}"
      end
    end

    # List a resource
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the requested resource.
    def on_get(resource_uri, opts)
      debug "on_get: #{resource_uri}"
      if @am_manager.kind_of? OMF::SFA::AM::CentralAMManager
        # Central manager just need to pass the request to the respectives subauthorities
        central_result = @am_manager.pass_request(resource_uri, opts, self)
        return show_resource(central_result, opts)
      end

      authenticator = opts[:req].session[:authorizer]

      # Request of a single resource like path '/resources/type1/UUID-OR-URN'
      if opts[:source_resource_uri] && opts[:source_resource_uuid]
        debug "Requesting a single resource"
        resource_type = opts[:source_resource_uri].singularize.camelize

        # Test if resource type exists
        begin
          eval("OMF::SFA::Model::#{resource_type}").class
        rescue NameError => ex
          raise OMF::SFA::AM::Rest::UnknownResourceException.new "Unknown resource type '#{resource_type}'."
        end

        desc = {
            :or => {
                :uuid => opts[:source_resource_uuid],
                :urn => opts[:source_resource_uuid],
                :name => opts[:source_resource_uuid]
            }
        }

        resource = @am_manager.find_resource(desc, resource_type, authenticator)
        raise OMF::SFA::AM::Rest::UnknownResourceException, "No resources matching the request." if (resource.nil?)
        return show_resource(resource, opts)
      end

      unless resource_uri.empty?
        resource_type, resource_params = parse_uri(resource_uri, opts)
        if resource_uri == 'leases'
          status_types = ["pending", "accepted", "active"] # default value
          status_types = resource_params[:status].split(',') unless resource_params[:status].nil?

          acc_desc = {}
          acc_desc[:urn] = resource_params.delete(:account_urn) if resource_params[:account_urn]
          acc_desc[:uuid] = resource_params.delete(:account_uuid) if resource_params[:account_uuid]
          account = @am_manager.find_account(acc_desc, authenticator) unless acc_desc.empty?

          start = resource_params[:start] unless resource_params[:start].nil?

          resource =  @am_manager.find_all_leases(account, status_types, authenticator, start)
          return show_resource(resource, opts)
        end
        descr = {}
        descr.merge!(resource_params) unless resource_params.empty?
        opts[:path] = opts[:req].path.split('/')[0 .. -2].join('/')
        descr[:account_id] = @am_manager.get_scheduler.get_nil_account.id if eval("OMF::SFA::Model::#{resource_type}").can_be_managed?
        if descr[:name].nil? && descr[:uuid].nil? && descr[:urn].nil?
           if descr[:account_urn]
            acc = @am_manager.find_account({urn: descr.delete(:account_urn)}, authenticator)
            descr[:account_id] = acc.id if acc
          elsif descr[:account_uuid]
            acc = @am_manager.find_account({uuid: descr.delete(:account_uuid)}, authenticator)
            descr[:account_id] = acc.id if acc
          end
          resource =  @am_manager.find_all_resources(descr, resource_type, authenticator)
          resource = resource.delete_if {|res| res.leases.first.status != "active" && res.leases.first.status != "accepted"} if resource_params[:account_urn] || resource_params[:account_uuid]
        else
          resource = @am_manager.find_resource(descr, resource_type, authenticator)
        end
        return show_resource(resource, opts)
      else
        debug "list all resources."
        resource = @am_manager.find_all_resources_for_account(opts[:account], authenticator)
        find_all = true
      end
      raise UnknownResourceException, "No resources matching the request." if (resource.empty? && find_all.nil?)
      show_resource(resource, opts)
    end

    # Update an existing resource
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the updated resource.
    def on_put(resource_uri, opts)
      debug "on_put: #{resource_uri}"
      if @am_manager.kind_of? OMF::SFA::AM::CentralAMManager
        # Central manager just need to pass the request to the respectives subauthorities
        central_result = @am_manager.pass_request(resource_uri, opts, self)
        return show_resource(central_result, opts)
      end

      resource = update_resource(resource_uri, true, opts)
      show_resource(resource, opts)
    end

    # Create a new resource
    # 
    # @param resource_uri [String] request URI
    # @param opts [Hash] options of the request
    # @return [String] Description of the created resource.
    def on_post(resource_uri, opts)
      debug "on_post: #{resource_uri}"
      if @am_manager.kind_of? OMF::SFA::AM::CentralAMManager
        # Central manager just need to pass the request to the respectives subauthorities
        central_result = @am_manager.pass_request(resource_uri, opts, self)
        return show_resource(central_result, opts)
      end

      resource = update_resource(resource_uri, false, opts)
      show_resource(resource, opts)
    end

    # Deletes an existing resource
    # 
    # @param resource_uri [String] request URI
    # @param opts [Hash] options of the request
    # @return [String] Description of the created resource.
    def on_delete(resource_uri, opts)
      debug "on_delete: #{resource_uri}"
      if @am_manager.kind_of? OMF::SFA::AM::CentralAMManager
        # Central manager just need to pass the request to the respectives subauthorities
        central_result = @am_manager.pass_request(resource_uri, opts, self)
        return show_resource(central_result, opts)
      end

      delete_resource(resource_uri, opts)
      show_resource(nil, opts)
    end

    # Update resource(s) referred to by +resource_uri+. If +clean_state+ is
    # true, reset any other state to it's default.
    #
    def update_resource(resource_uri, clean_state, opts)
      body, format = parse_body(opts)
      resource_type, resource_params = parse_uri(resource_uri, opts)
      authenticator = opts[:req].session[:authorizer]
      case format
      # when :empty
        # # do nothing
      when :xml
        resource = @am_manager.update_resources_from_xml(body.root, clean_state, opts)
      when :json
        if clean_state
          # Handle PUT request
          resource = @am_manager.update_a_resource(body, resource_type, authenticator)
        else
          # Handle POST request
          resource = @am_manager.create_new_resource(body, resource_type, authenticator)
        end
      else
        raise UnsupportedBodyFormatException.new(format)
      end
      resource
    end


    # This methods deletes components, or more broadly defined, removes them
    # from a slice.
    #
    # Currently, we simply transfer components to the +default_sliver+
    #
    def delete_resource(resource_uri, opts)
      body, format = parse_body(opts)
      resource_type, resource_params = parse_uri(resource_uri, opts)
      authenticator = opts[:req].session[:authorizer]
      @am_manager.release_a_resource(body, resource_type, authenticator)
    end

    # Update the state of +component+ according to inforamtion
    # in the http +req+.
    #
    #
    def update_component_xml(component, modifier_el, opts)
    end

    # Return the state of +component+
    #
    # +component+ - Component to display information about. !!! Can be nil - show only envelope
    #
    def show_resource(resource, opts)
      unless about = opts[:req].path
        throw "Missing 'path' declaration in request"
      end
      path = opts[:path] || about

      case opts[:format]
      when 'xml'
        show_resources_xml(resource, path, opts)
      else
        show_resources_json(resource, path, opts)
      end
    end

    def show_resources_xml(resource, path, opts)
      #debug "show_resources_xml: #{resource}"
      opts[:href_prefix] = path
      announcement = OMF::SFA::Model::OComponent.sfa_advertisement_xml(resource, opts)
      ['text/xml', announcement.to_xml]
    end

    def show_resources_json(resources, path, opts)
      if @am_manager.kind_of? OMF::SFA::AM::CentralAMManager
        res = resources
      else
        res = resources ? resource_to_json(resources, path, opts) : {response: "OK"}
      end
      res[:about] = opts[:req].path

      ['application/json', JSON.pretty_generate({:resource_response => res}, :for_rest => true)]
    end

    def resource_to_json(resource, path, opts, already_described = {})
      # debug "resource_to_json: resource: #{resource.inspect}, path: #{path}"
      if resource.kind_of? Enumerable and !resource.kind_of? Hash
        res = []
        resource.each do |r|
          p = path
          res << resource_to_json(r, p, opts, already_described)[:resource]
        end
        res = {:resources => res}
      else
        #prefix = path.split('/')[0 .. -2].join('/') # + '/'
        prefix = path
        if resource.respond_to? :to_sfa_hashXXX
          debug "TO_SFA_HASH: #{resource}"
          res = {:resource => resource.to_sfa_hash(already_described, :href_prefix => prefix)}
        else
          rh = resource.kind_of?(Hash) ? resource : resource.to_hash

          # unless (account = resource.account) == @am_manager.get_default_account()
            # rh[:account] = {:uuid => account.uuid.to_s, :name => account.name}
          # end
          res = {:resource => rh}
        end
      end
      res
    end

    protected

    def parse_uri(resource_uri, opts)
      params = opts[:req].params.symbolize_keys!
      params.delete("account")

      return ['mapper', params] if opts[:req].env["REQUEST_PATH"] == '/mapper'

      case resource_uri
      when "cmc"
        type = "ChasisManagerCard"
      when "wimax"
        type = "WimaxBaseStation"
      when "lte"
        type = "ENodeB"
      when "openflow"
        type = "OpenflowSwitch"
      else
        type = if resource_uri.empty? then "unknown" else resource_uri.singularize.camelize end
        begin
          eval("OMF::SFA::Model::#{type}").class
        rescue
          raise OMF::SFA::AM::Rest::UnknownResourceException.new "Unknown resource type '#{resource_uri}'"
        end
      end
      [type, params]
    end

    # Before create a new resource, parse the resource description and alternate existing resources.
    #
    # @param [Hash] Resource Description
    # @return [Hash] New Resource Description
    # @raise [UnknownResourceException] if no resource can be created
    #
    def parse_resource_description(resource_descr, type_to_create)
      resource_descr.each do |key, value|
        debug "checking prop: '#{key}': '#{value}': '#{type_to_create}'"
        if value.kind_of? Array
          value.each_with_index do |v, i|
            if v.kind_of? Hash
              # debug "Array: #{v.inspect}"
              begin
                k = eval("OMF::SFA::Model::#{key.to_s.singularize.capitalize}").first(v)
                raise NameError if k.nil?
                resource_descr[key][i] = k
              rescue NameError => nex
                model = eval("OMF::SFA::Model::#{type_to_create}.get_oprops[key][:__type__]")
                resource_descr[key][i] = (k = eval("OMF::SFA::Model::#{model}").first(v)) ? k : v
              end
            end
          end
        elsif value.kind_of? Hash
          debug "Hash: #{key.inspect}: #{value.inspect}"
          begin
            k = eval("OMF::SFA::Model::#{key.to_s.singularize.capitalize}").first(value)
            raise NameError if k.nil?
            resource_descr[key] = k
          rescue NameError => nex
            model = eval("OMF::SFA::Model::#{type_to_create}.get_oprops[key][:__type__]")
            resource_descr[key] = (k = eval("OMF::SFA::Model::#{model}").first(value)) ? k : value
          end
        end
      end
      resource_descr
    end
  end # ResourceHandler
end # module


class Time
  def to_json(options = {})
    super
  end
end