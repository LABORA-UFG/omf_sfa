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
  puts "Delete links through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n"

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
  puts "List #{res_desc} through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n"

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
  puts "Update #{type} through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n"

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

  puts "OUTPUT:"
  puts "#{response.inspect}"
end

def create_resource_with_rest(url, type, res_desc, pem, key, ch_key)
  puts "Create #{type} through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n"

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

  puts "OUTPUT:"
  puts "#{response.inspect}"
end

def authorization?
  @authorization
end

OmfCommon.init(op_mode, opts) do |el|
  OmfCommon.comm.on_connected do |comm|
    if authorization?
      OmfCommon::Auth::CertificateStore.instance.register_default_certs(@trusted_roots)
      @entity.resource_id = OmfCommon.comm.local_topic.address
      OmfCommon::Auth::CertificateStore.instance.register(@entity)
    end
    comm.subscribe(@flowvisor_rc_topic) do |flowvisor|
      puts "PASSEI AQUI 1"
      flowvisor.request([:links]) do |msg|
        unless msg.itype == "ERROR"

          puts "PASSEI AQUI 2 = #{msg.itype}"
          links = if msg.properties[:links] then msg.properties[:links] else [] end
          info "Links requested: #{links}"

          broker_links = list_resources_with_rest("#{resource_url}/links", "links", @pem, @pkey, ch_key)
          interfaces = list_resources_with_rest("#{resource_url}/interfaces", "interfaces", @pem, @pkey, ch_key)
          of_switches = list_resources_with_rest("#{resource_url}/openflow_switch", "openflow_switches", @pem, @pkey, ch_key)

          puts "broker_links = #{broker_links}"

          broker_links_names = broker_links.collect {|link| link["name"]}
          broker_of_switches_dpids = interfaces.collect {|interface| interface["datapathid"]}

          links_properties = []
          link_names = []
          interfaces_urns = []

          links.each {|link|
            link_name1 = "$fv-#{link[:srcDPID]}-#{link[:srcPort]}-#{link[:dstDPID]}-#{link[:dstPort]}".parameterize.underscore
            link_name2 = "$fv-#{link[:dstDPID]}-#{link[:dstPort]}-#{link[:srcDPID]}-#{link[:srcPort]}".parameterize.underscore
            link_names.push(link_name1)
            link_names.push(link_name2)

            # Look for both links, because they are the same, just in opposite direction.
            # If one of the links is registered, we go to the next.
            next if broker_links_names.include?(link_name1) or broker_links_names.include?(link_name2)
            broker_links_names.push(link_name1)

            new_link = {
                :name => "#{link_name1}",
                :urn => "urn:publicid:IDN+#{domain}+link+#{link_name1}"
            }
            links_properties.push(new_link)
          }

          puts "RESOURCE PROPERTIES = #{links_properties}"

          deprecated_links = broker_links_names - link_names

          # Remove old links
          deprecated_links.each {|link_name|
            next unless link_name.starts_with? "$fv-"
            link_desc = {
                :urn => "urn:publicid:IDN+#{domain}+link+#{link_name}"
            }
            delete_resources_with_rest("#{base_url}/links", link_desc, @pem, @pkey, ch_key)
          }

          unless links_properties.empty?
            create_resource_with_rest("#{resource_url}/links", "links", links_properties, @pem, @pkey, ch_key)
          end

          # Create the switches if they don't exist
          links.each {|link|
            switch_name = "$fv-of_switch-#{link[:srcDPID]}".parameterize.underscore
            interface_name = "$fv-interface-#{link[:srcDPID]}".parameterize.underscore
            interface_urn = "urn:publicid:IDN+#{domain}+interface+#{interface_name}"
            interfaces_urns.push(interface_urn)
            unless broker_of_switches_dpids.include?(link[:srcDPID])
              of_switch_properties = {
                  :name => switch_name,
                  :urn => "urn:publicid:IDN+#{domain}+openflow_switch+#{switch_name}",
                  :resource_type => "openflow_switch",
                  :datapathid => link[:srcDPID],
                  :interfaces_attributes => [
                      {
                          :name => interface_name,
                          :role => "control"
                      }
                  ]
              }
              create_resource_with_rest("#{resource_url}/openflow_switch", "openflow_switch",of_switch_properties, @pem, @pkey, ch_key)
            else

            end

            switch_name = "$fv-of_switch-#{link[:dstDPID]}".parameterize.underscore
            interface_name = "$fv-interface-#{link[:dstDPID]}".parameterize.underscore
            interface_urn = "urn:publicid:IDN+#{domain}+interface+#{interface_name}"
            interfaces_urns.push(interface_urn)
            unless broker_of_switches_dpids.include?(link[:dstDPID])
              of_switch_properties = {
                  :name => switch_name,
                  :urn => "urn:publicid:IDN+#{domain}+openflow_switch+#{switch_name}",
                  :resource_type => "openflow_switch",
                  :datapathid => link[:dstDPID],
                  :interfaces_attributes => [
                      {
                          :name => interface_name,
                          :role => "control"
                      }
                  ]
              }
              create_resource_with_rest("#{resource_url}/openflow_switch", "openflow_switch",of_switch_properties, @pem, @pkey, ch_key)
            end
          }

          # Put the interfaces into links
          interfaces_urns.each {|urn|
            url = "#{resource_url}/interfaces/#{urn}/links"
            update_resource_with_rest(url, "interfaces", links_properties[0], @pem, @pkey, ch_key)
            #update_resource_with_rest(url, links_properties[1], @pem, @pkey, ch_key)
          }

          puts 'done.'
          comm.disconnect
        end
      end
    end
  end
end
