require 'omf-sfa/am/am-rest/rest_handler'
require 'omf-sfa/am/am_manager'
require 'omf-sfa/am/fibre_am_liaison'
require 'uuid'

module OMF::SFA::AM::Rest

  # Handles an individual resource
  #
  class EventsHandler < RestHandler

    # Return the handler responsible for requests to +path+.
    # The default is 'self', but override if someone else
    # should take care of it
    #
    def find_handler(path, opts)
      opts[:resource_uri] = path.shift
      @liaison = @am_manager.liaison
      self
    end

    # Not supported by this handler
    # 
    # @param [String] resource_uri URI
    # @param [Hash] opts of the request
    # @return [String] Description of the resources.
    def on_get(resource_uri, opts)
      debug "on_get: #{resource_uri}"
      raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL."
    end

    # Not supported by this handler
    # 
    # @param [String] resource_uri URI
    # @param [Hash] opts of the request
    # @return [String] Description of the updated resource.
    def on_put(resource_uri, opts)
      debug  "on_put: #{resource_uri}"
      raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL."
    end

    # Executes event inform
    # 
    # @param [String] resource_uri URI
    # @param [Hash] opts of the request
    # @return [String] Description of the created resource.
    def on_post(resource_uri, opts)
      debug "on_post: #{resource_uri}"

      body, format = parse_body(opts)
      headers = get_request_headers(opts)
      unless headers["Token"] and headers["Token"] == CB_TOKEN
        raise OMF::SFA::AM::Rest::NotAuthorizedException.new "Invalid auth Token informed"
      end

      event_type = if not body[:event_type].nil? and body[:event_type].kind_of? String
                     body[:event_type].upcase else 'NONE' end

      case event_type
        when 'LEASE_START'
          response = @liaison.inform_lease_start_event(body)
        when 'LEASE_END'
          response = @liaison.inform_lease_end_event(body)
        else
          response = {:error => 'Invalid event type informed'}
      end

      ['application/json', "#{JSON.pretty_generate({result: response}, :for_rest => true)}\n"]
    end

    # Not supported by this handler
    # 
    # @param [String] resource_uri URI
    # @param [Hash] opts of the request
    # @return [String] Description of the deleted resource.
    def on_delete(resource_uri, opts)
      debug "on_delete: #{resource_uri}"
      raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL."
    end

    protected

    def parse_uri(resource_uri, opts)
      params = opts[:req].params.symbolize_keys!
      [params]
    end
  end # EventsHandler
end # module
