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

  if x = @y[:images_cleaner]
    @image_cleaner_days = x[:days]
  else
    error "Image cleaner days configuration was not found in the configuration file"
    exit
  end

  if x = @y[:rest]
    require "net/https"
    require "uri"
    resource_url = "https://#{x[:server]}:#{x[:port]}/resources/leases?status=past&start=2017-03-01&end=2017-04-01"
    domain = x[:domain]
    comm_type = "REST"
    ch_key = File.read(x[:ch_key])
  else
    error "REST details was found in the configuration file"
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

def list_resources_with_rest(url, res_desc, pem, key, ch_key)
  puts "List Leases through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n"

  uri = URI.parse(url)
  pem = File.read(pem)
  pkey = File.read(key)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  #http.cert = OpenSSL::X509::Certificate.new(pem)
  #http.key = OpenSSL::PKey::RSA.new(pkey)
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  puts "uri = #{url}"

  request = Net::HTTP::Get.new(uri.request_uri, initheader = {'Content-Type' =>'application/json'})
  request['CH-Credential'] = ch_key
  request.body = res_desc.to_json

  response = http.request(request)

  body = JSON.parse(response.body)["resource_response"]
  body = if body then body["resources"] else {} end
  body
end

def authorization?
  @authorization
end

def main(resource_url, pem, pkey, ch_key)
  puts "resource_url = #{resource_url}"
  leases = list_resources_with_rest(resource_url, {}, @pem, @pkey, ch_key)

  puts "broker_links = #{leases}"

  @image_cleaner_days

  # broker_links_names = leases.collect {|link| link["name"]}
  #
  # resource_properties = []
  # link_names = []
  #
  # links.each {|link|
  #   link_name1 = "$fv-#{link[:srcDPID]}-#{link[:srcPort]}:#{link[:dstDPID]}-#{link[:dstPort]}"
  #   link_name2 = "$fv-#{link[:dstDPID]}-#{link[:dstPort]}:#{link[:srcDPID]}-#{link[:srcPort]}"
  #   link_names.push(link_name1)
  #   link_names.push(link_name2)
  #
  #   # Look for both links, because they are the same, just in opposite direction.
  #   # If one of the links is registered, we go to the next.
  #   next if broker_links_names.include?(link_name1) or broker_links_names.include?(link_name2)
  #
  #   new_link = {
  #       :name => "#{link_name1}",
  #       :urn => "urn:publicid:IDN+#{domain}+link+#{link_name1}"
  #   }
  #   resource_properties.push(new_link)
  # }
  #
  # puts "RESOURCE PROPERTIES = #{resource_properties}"
  #
  # deprecated_links = broker_links_names - link_names
  #
  # # Remove old links
  # deprecated_links.each {|link_name|
  #   next unless link_name.starts_with? "$fv-"
  #   link_desc = {
  #       :urn => "urn:publicid:IDN+#{domain}+link+#{link_name}"
  #   }
  #   delete_resources_with_rest("#{base_url}/links", link_desc, @pem, @pkey, ch_key)
  # }
  #
  # unless resource_properties.empty?
  #   create_resource_with_rest(resource_url, resource_properties, @pem, @pkey, ch_key)
  # end

  puts 'done.'
end

main(resource_url, @pem, @pkey, ch_key)