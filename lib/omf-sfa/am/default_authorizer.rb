

require 'omf_common/lobject'

module OMF::SFA::AM

  include OMF::Common

  class InsufficientPrivilegesException < AMManagerException; end

  # This class implements an authorizer which
  # only allows actions which have been enabled in a permission
  # hash.
  #
  class DefaultAuthorizer < LObject
    
    attr_accessor :account#TODO remove this when we enable authentication on both rest and xmpp
    [
      # ACCOUNT
      :can_create_account?, # ()
      :can_view_account?, # (account)
      :can_renew_account?, # (account, until)
      :can_close_account?, # (account)
      # RESOURCE
      :can_create_resource?, # (resource_descr, type)
      :can_modify_resource?, # (resource_descr, type)
      :can_view_resource?, # (resource)
      :can_release_resource?, # (resource)
      # LEASE
      :can_view_lease?, # (lease)
      :can_modify_lease?, # (lease)
      :can_release_lease?, # (lease)
      # SLICES
      :can_operate_slice?,
    ].each do |m|
      define_method(m) do |*args|
        debug "Check permission '#{m}'"
        unless @permissions[m]
          raise InsufficientPrivilegesException.new
        end
        true
      end
    end

    def initialize(permissions = {})
      @permissions = permissions
      @account = nil#TODO remove this when we enable authentication on both rest and xmpp
    end
  end
end
