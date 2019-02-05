require 'omf_common'
require 'omf-sfa/am/am_manager'
require 'omf-sfa/am/nitos_am_liaison'
require "net/https"
require "uri"
require 'json'
require 'open3'

module OMF::SFA::AM

  extend OMF::SFA::AM

  # This class implements the Fibre AM Liaison (For Central Broker only)
  #
  class FibreCentralAMLiaison < DefaultAMLiaison

    def initialize(opts)
      super
      @am_manager = opts[:am][:manager]
      @am_scheduler = @am_manager.get_scheduler

      config_file_path = File.dirname(__FILE__) + '/../../../etc/omf-sfa'
      @config = OMF::Common::YAML.load('omf-sfa-am', :path => [config_file_path])[:omf_sfa_am]

      if @config[:central_broker].nil? or @config[:central_broker][:enabled] === false or
          not @am_manager.kind_of? OMF::SFA::AM::CentralAMManager
        raise "Could not use FibreCentralAMLiaison on Brokers that have not enabled the central broker configuration."
      end
    end

    def inform_lease_start_event(lease_event)
      debug "FibreCentralAMLiaison: inform_lease_start_event: #{lease_event.inspect}"
      send_lease_event_to_subauthorities(lease_event)
      {:message => 'Successfully received lease_start event'}
    end

    def inform_lease_end_event(lease_event)
      debug "FibreCentralAMLiaison: inform_lease_start_event: #{lease_event.inspect}"
      send_lease_event_to_subauthorities(lease_event)
      {:message => 'Successfully received lease_end event'}
    end

    def send_lease_event_to_subauthorities(event_data)
      event_type = event_data[:event_type]
      tds = []
      @am_manager.subauthorities.each do |subauth, subauth_opts|
        unless subauth_opts[:event_forwarding]
          next
        end

        tds << Thread.new {
          event_inform_path = "#{subauth_opts[:address]}/inform_event2"
          debug "Sending '#{event_type}' event to subauth: #{subauth} - #{event_inform_path}"
          begin
            http, request = prepare_request('POST', event_inform_path, subauth_opts, event_data)
            out = http.request(request)
            response = JSON.parse(out.body, symbolize_names: true)
            debug "SubAuth #{subauth} event '#{event_type}' broker result:"
            debug response
          rescue Exception => e
            error "Error in send '#{event_type}' event to subauth broker #{subauth}: #{e.to_s}"
          end
        }
      end
      tds.each {|td| td.join}
    end

    def prepare_request(type, url, subauthority=nil, options=nil, header=nil)
      header = {'Content-Type' => 'application/json', 'Accept' => 'application/json'} if header.nil?
      type = type.capitalize

      pem, pkey = nil
      begin
        pem = File.read(subauthority[:cert]) unless subauthority.nil?
      rescue
        pem = nil
      end
      begin
        pkey = File.read(subauthority[:key]) unless subauthority.nil?
      rescue
        pkey = nil
      end

      uri              = URI.parse(URI.encode(url))
      http             = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = true
      http.read_timeout = 30
      http.open_timeout = 2
      http.cert        = OpenSSL::X509::Certificate.new(pem) unless (type == "Get" || pem.nil? || pem.empty?)
      http.key         = OpenSSL::PKey::RSA.new(pkey) unless (type == "Get" || pkey.nil? || pkey.empty?)
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      request          = eval("Net::HTTP::#{type}").new(uri.request_uri, header)

      request['Token'] = CB_TOKEN
      request.body  = options.to_json unless options.nil?
      [http, request]
    end
  end # OMF::SFA::AM
end

