#!/usr/bin/env ruby
# this executable populates the db with new resources.
# create_resource -t node -
BIN_DIR = File.dirname(File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__)
TOP_DIR = File.join(BIN_DIR, '..')
$: << File.join(TOP_DIR, 'lib')

DESCR = %{
Get the topology of OpenFlow Switches from Flowvisor and create or update that topology on Brokers database.

The Flowvisor address and the Broker URL are required as input.
}

MAC_SIZE = 17 # number of characters in a MAC address

begin; require 'json/jwt'; rescue Exception; end

require 'omf_common'

$debug = false

opts = {
    communication: {
        #url: 'xmpp://srv.mytestbed.net'
    },
    eventloop: { type: :em},
    logging: {
        level: 'info'
    }
}

comm_type = nil
resource_url = nil
base_url = nil
domain = nil
ch_key = nil
resource_type = :links
op_mode = :development
@flowvisor_rc_topic = nil
@authorization = false
@entity = nil
@trusted_roots = nil
@cert = nil
@pkey = nil

op = OptionParser.new
op.banner = "Usage: #{op.program_name} --conf CONF_FILE --in INPUT_FILE...\n#{DESCR}\n"

op.on '-c', '--conf FILE', "Configuration file with communication info" do |file|
  require 'yaml'
  if File.exists?(file)
    @y = YAML.load_file(file)
  else
    error "No such file: #{file}"
    exit
  end

  if x = @y[:flowvisor_rc_args]
    @flowvisor_rc_topic = x[:topic]
  else
    error "Flowvisor RC details was not found in the configuration file"
    exit
  end

  if x = @y[:amqp]
    resource_url = x[:topic]
    opts[:communication][:url] = "amqp://#{x[:username]}:#{x[:password]}@#{x[:server]}"
    op_mode = x[:op_mode]
    comm_type = "AMQP"
  else
    error "AMQP details was not found in the configuration file"
    exit
  end

  if x = @y[:rest]
    require "net/https"
    require "uri"
    base_url = "https://#{x[:server]}:#{x[:port]}/resources"
    domain = x[:domain]
    resource_url = "#{base_url}"
    comm_type = "REST"
    ch_key = File.read(x[:ch_key])
  else
    error "REST details was not found in the configuration file"
    exit
  end

  if a = @y[:auth]
    @pem = a[:entity_cert]
    @pkey = a[:entity_key]
  else
    warn "authorization is disabled."
    exit if comm_type == "REST"
  end
end

rest = op.parse(ARGV) || []

def delete_resources_with_rest(url, res_desc, pem, key, ch_key)
  puts "\n\nDelete links through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n\n"

  uri = URI.parse(url)
  pem = File.read(pem)
  pkey = File.read(key)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.cert = OpenSSL::X509::Certificate.new(pem)
  http.key = OpenSSL::PKey::RSA.new(pkey)
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Delete.new(uri.request_uri, initheader = {'Content-Type' =>'application/json'})
  request['CH-Credential'] = ch_key
  request.body = res_desc.to_json

  response = http.request(request)

  JSON.parse(response.body)
end

def list_resources_with_rest(url, res_desc, pem, key, ch_key)
  puts "\n\nList #{res_desc} through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n\n"

  uri = URI.parse(url)
  pem = File.read(pem)
  pkey = File.read(key)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.cert = OpenSSL::X509::Certificate.new(pem)
  http.key = OpenSSL::PKey::RSA.new(pkey)
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Get.new(uri.request_uri, initheader = {'Content-Type' =>'application/json'})
  request['CH-Credential'] = ch_key
  #request.body = res_desc.to_json

  response = http.request(request)

  body = JSON.parse(response.body)["resource_response"]
  body = if body then body["resources"] else {} end
  body
end

def update_resource_with_rest(url, type, res_desc, pem, key, ch_key)
  puts "\n\nUpdate #{type} through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n\n"

  uri = URI.parse(url)
  pem = File.read(pem)
  pkey = File.read(key)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.cert = OpenSSL::X509::Certificate.new(pem)
  http.key = OpenSSL::PKey::RSA.new(pkey)
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Put.new(uri.request_uri, initheader = {'Content-Type' =>'application/json'})
  request['CH-Credential'] = ch_key
  request.body = res_desc.to_json

  response = http.request(request)

  puts "#{response.inspect}"
end

def create_resource_with_rest(url, type, res_desc, pem, key, ch_key)
  puts "\n\nCreate #{type} through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n\n"

  uri = URI.parse(url)
  pem = File.read(pem)
  pkey = File.read(key)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.cert = OpenSSL::X509::Certificate.new(pem)
  http.key = OpenSSL::PKey::RSA.new(pkey)
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Post.new(uri.request_uri, initheader = {'Content-Type' =>'application/json'})
  request['CH-Credential'] = ch_key
  request.body = res_desc.to_json

  response = http.request(request)

  puts "#{response.inspect}"
end

def authorization?
  @authorization
end

def create_of_switch_and_interfaces(broker_of_switches_dpids, ch_key, domain, interfaces_urns, linkDPID, linkPort, resource_url)
  switch_name = "$fv_of_switch_#{linkDPID}".parameterize.underscore
  switch_urn = "urn:publicid:IDN+#{domain}+openflow_switch+#{switch_name}"
  interface_name = "$fv_interface_#{linkDPID}_#{linkPort}".parameterize.underscore
  interface_urn = "urn:publicid:IDN+#{domain}+interface+#{interface_name}"
  unless broker_of_switches_dpids.include?(linkDPID)
    of_switch_properties = {
        :name => switch_name,
        :urn => switch_urn,
        :resource_type => "openflow_switch",
        :datapathid => linkDPID,
        :interfaces_attributes => [
            {
                :name => interface_name,
                :urn => interface_urn,
                :role => "control"
            }
        ]
    }
    create_resource_with_rest("#{resource_url}/openflow_switch", "openflow_switch", of_switch_properties, @pem, @pkey, ch_key)
    broker_of_switches_dpids << linkDPID
  else
    url = "#{resource_url}/openflow_switch/#{switch_urn}/interfaces"
    interface_properties = {
        :name => interface_name,
        :urn => interface_urn,
        :role => "control"
    }
    create_resource_with_rest("#{resource_url}/interfaces", "interfaces", interface_properties, @pem, @pkey, ch_key) unless interfaces_urns.include?(interface_urn)
    update_resource_with_rest(url, "openflow_switch", interface_properties, @pem, @pkey, ch_key)
  end
  interfaces_urns.push(interface_urn)
end

OmfCommon.init(op_mode, opts) do |el|
  OmfCommon.comm.on_connected do |comm|
    if authorization?
      OmfCommon::Auth::CertificateStore.instance.register_default_certs(@trusted_roots)
      @entity.resource_id = OmfCommon.comm.local_topic.address
      OmfCommon::Auth::CertificateStore.instance.register(@entity)
    end
    comm.subscribe(@flowvisor_rc_topic) do |flowvisor|
      flowvisor.request([:links]) do |msg|
        unless msg.itype == "ERROR"
          flowvisor_links = if msg.properties[:links] then msg.properties[:links] else [] end
          puts "Flowvisor Links: #{flowvisor_links}"

          broker_links = list_resources_with_rest("#{resource_url}/links", "links", @pem, @pkey, ch_key)
          interfaces = list_resources_with_rest("#{resource_url}/interfaces", "interfaces", @pem, @pkey, ch_key)
          of_switches = list_resources_with_rest("#{resource_url}/openflow_switch", "openflow_switches", @pem, @pkey, ch_key)

          puts "Broker Current Links = #{broker_links}"

          broker_links_names = broker_links.collect {|link| link["name"]}
          broker_of_switches_dpids = of_switches.collect {|of_switches| of_switches["datapathid"]}

          links_properties = []
          link_names = []
          interfaces_urns = []

          flowvisor_links.each {|link|
            link_name = "$fv_#{link[:srcDPID]}_#{link[:srcPort]}_#{link[:dstDPID]}_#{link[:dstPort]}".parameterize.underscore

            # Look for both links, because they are the same, just in opposite direction.
            # If one of the links is registered, we go to the next.
            next if broker_links_names.include?(link_name) or link_names.include?(link_name)
            link_names.push(link_name)

            new_link = {
                :name => "#{link_name}",
                :urn => "urn:publicid:IDN+#{domain}+link+#{link_name}"
            }
            links_properties.push(new_link)
          }

          deprecated_links = broker_links_names - link_names

          # Remove old links
          deprecated_links.each {|link_name|
            next unless link_name.starts_with? "$fv_"
            link_desc = {
                :urn => "urn:publicid:IDN+#{domain}+link+#{link_name}"
            }
            delete_resources_with_rest("#{base_url}/links", link_desc, @pem, @pkey, ch_key)
          }

          # Create the switches if they don't exist
          flowvisor_links.each {|link|
            create_of_switch_and_interfaces(broker_of_switches_dpids, ch_key, domain, interfaces_urns, link[:srcDPID], link[:srcPort], resource_url)

            create_of_switch_and_interfaces(broker_of_switches_dpids, ch_key, domain, interfaces_urns, link[:dstDPID], link[:dstPort], resource_url)
          }

          new_links = link_names - broker_links_names

          unless new_links.empty?
            create_resource_with_rest("#{resource_url}/links", "links", links_properties, @pem, @pkey, ch_key)
          end

          # Put the interfaces into links
          interfaces_urns.each {|urn|
            url = "#{resource_url}/interfaces/#{urn}/links"
            interface_name = urn.split("interface_")[1]
            ralated_links = links_properties.select {|link|
              not /(?:#{interface_name}$|#{interface_name}_)/.match(link[:name]).nil?
            }

            for ralated_link in ralated_links
              puts "Adding link #{ralated_link} to interface = #{interface_name}"

              update_resource_with_rest(url, "interfaces", ralated_link, @pem, @pkey, ch_key)
            end
          }

          puts 'done.'
          comm.disconnect
        end
      end
    end
  end
end
