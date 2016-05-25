require 'omf_common'
require 'omf-sfa/am/am_manager'
require 'omf-sfa/am/default_am_liaison'
require "net/https"
require "uri"
require 'json'

DEFAULT_REST_END_POINT = {url: "https://localhost:4567", user: "root", token: "1234556789abcdefghij"}

module OMF::SFA::AM

  extend OMF::SFA::AM

  # This class implements the AM Liaison
  #
  class NitosAMLiaison < DefaultAMLiaison

    def initialize(opts)
      super
      @default_sliver_type = OMF::SFA::Model::SliverType.find(urn: @config[:provision][:default_sliver_type_urn])
      @rest_end_points = @config[:REST_end_points]
    end

    def create_account(account)
      warn "Am liaison: create_account: Not implemented."
    end

    def close_account(account)
      warn "Am liaison: close_account: Not implemented."
    end

    def configure_keys(keys, account)
      warn "Am liaison: configure_keys: Not implemented."
    end

    def create_resource(resource, lease, component)
      warn "Am liaison: create_resource: Not implemented."
    end

    def release_resource(resource, new_res, lease, component)
      warn "Am liaison: release_resource: Not implemented."
    end

    def start_resource_monitoring(resource, lease, oml_uri=nil)
      warn "Am liaison: start_resource_monitoring: Not implemented."
    end

    def on_lease_start(lease)
      warn "Am liaison: on_lease_start: Not implemented."
    end

    def on_lease_end(lease)
      warn "Am liaison: on_lease_end: Not implemented."
    end

    def provision(leases)
      warn "Am liaison: on_provision: Not implemented."
    end
end # OMF::SFA::AM
