require 'omf-sfa/am/am-rest/rest_handler'
require 'omf-sfa/am/am_manager'
require 'uuid'

DEFAULT_SAVE_IMAGE_NAME = '/tmp/image.nbz'

module OMF::SFA::AM::Rest

  # Handles an individual resource
  #
  class CentralBrokerEventsHandler < RestHandler

    # Return the handler responsible for requests to +path+.
    # The default is 'self', but override if someone else
    # should take care of it
    #
    def find_handler(path, opts)
      opts[:resource_uri] = path.shift
      @liaison = @am_manager.liaison
      self
    end

    # Actions that don't change the status of resources
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the requested resource.
    def on_get(resource_uri, opts)
      debug "on_get: #{resource_uri}"
      raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL."
    end

    # Actions that change the status of resources
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the updated resource.
    def on_put(resource_uri, opts)
      debug  "on_put: #{resource_uri}"
      raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL."
    end

    # Not supported by this handler
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the created resource.
    def on_post(resource_uri, opts)
      debug "on_post: #{resource_uri}"

      # unless @am_manager.kind_of? OMF::SFA::AM::CentralAMManager
      #   raise OMF::SFA::AM::Rest::BadRequestException.new "This method is only available on Central Broker."
      # end

      body, format = parse_body(opts)
      event_type = if not body[:event_type].nil? and body[:event_type].kind_of? String
                     body[:event_type].upcase else 'NONE' end
      case event_type
        when 'LEASE_START'
          response = {:message => 'Successfully received lease_start event'}
        when 'LEASE_END'
          response = {:message => 'Successfully received lease_end event'}
        else
          response = {:error => 'Invalid event type informed'}
      end

      ['application/json', "#{JSON.pretty_generate({result: response}, :for_rest => true)}\n"]
    end

    # Not supported by this handler
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the created resource.
    def on_delete(resource_uri, opts)
      debug "on_delete: #{resource_uri}"
      raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL."
    end

    protected

    def parse_uri(resource_uri, opts)
      params = opts[:req].params.symbolize_keys!
      [params]
    end
  end # CentralBrokerEventsHandler
end # module
