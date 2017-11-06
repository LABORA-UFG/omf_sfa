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
    error "Flowvisor RC details was found in the configuration file"
    exit
  end

  if x = @y[:amqp]
    resource_url = x[:topic]
    opts[:communication][:url] = "amqp://#{x[:username]}:#{x[:password]}@#{x[:server]}"
    op_mode = x[:op_mode]
    comm_type = "AMQP"
  else
    error "AMQP details was found in the configuration file"
    exit
  end

  if x = @y[:rest]
    require "net/https"
    require "uri"
    resource_url = "https://#{x[:server]}:#{x[:port]}/resources/#{resource_type.to_s.downcase.pluralize}"
    comm_type = "REST"
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

def create_resource_with_rest(url, res_desc, pem, key)
  puts "Create resource through REST.\nURL: #{url}\nRESOURCE DESCRIPTION: \n#{res_desc}\n"

  uri = URI.parse(url)
  pem = File.read(pem)
  pkey = File.read(key)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.cert = OpenSSL::X509::Certificate.new(pem)
  http.key = OpenSSL::PKey::RSA.new(pkey)
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Post.new(uri.request_uri, initheader = {'Content-Type' =>'application/json'})
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
      flowvisor.request([:links]) do |msg|
        links = msg.properties[:links]
        info "Links requested: #{links}"

        puts links

        resource_properties = {
            :name => "#{links[0][:dstDPID]}:#{links[1][:dstDPID]}",
            :urn => "urn:publicid:IDN+ufg.br+link+#{links[0][:dstDPID]}:#{links[1][:dstDPID]}"
        }

        puts resource_properties.to_json
        #create_resource_with_rest(resource_url, resource_properties, @pem, @pkey)

        puts 'done.'
        comm.disconnect
      end
    end
  end
end
