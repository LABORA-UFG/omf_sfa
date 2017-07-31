
require 'omf-sfa/am/default_authorizer'
require 'omf-sfa/am/utils'

module OMF::SFA::AM::Rest::DummyAuth

  include OMF::Common

  # This class implements the decision logic for determining
  # access of a user in a specific context to specific functionality
  # in the AM
  #
  class AMAuthorizer < OMF::SFA::AM::DefaultAuthorizer
    def self.create_for_rest_request(am_manager)
      self.new(am_manager)
    end

    protected

    def initialize(am_manager)
      super()

      @am_manager = am_manager
      @permissions = {
          can_create_account?:   true,
          can_view_account?:     true,
          can_renew_account?:    true,
          can_close_account?:    true,
          # RESOURCE
          can_create_resource?:  true,
          can_modify_resource?:  true,
          can_view_resource?:    true,
          can_release_resource?: true,
          # LEASE
          can_view_lease?:       true,
          can_modify_lease?:     true,
          can_release_lease?:    true
      }
    end
  end # class
end # module
