
require 'omf-sfa/am/default_authorizer'
require 'omf-sfa/am/utils'

module OMF::SFA::AM::Rest::FibreAuth

  include OMF::Common

  # This class implements the decision logic for determining
  # access of a user in a specific context to specific functionality
  # in the AM
  #
  class AMAuthorizer < OMF::SFA::AM::DefaultAuthorizer

    # @!attribute [r] account
    #        @return [Account] The account associated with this instance
    attr_reader :account

    # @!attribute [r] user
    #        @return [User] The user associated with this membership
    attr_reader :user

    # @!attribute [r] ch_key
    #        @return [String] The Clearing House key associated with this membership
    attr_reader :ch_key


    def self.create_for_rest_request(credential, am_manager, ch_key)
      debug "Requester #{credential.signer_urn} :: #{credential.user_urn}"

      user_descr = {}
      user_descr.merge!({urn: credential.user_urn}) unless credential.user_urn.nil?
      raise OMF::SFA::AM::InsufficientPrivilegesException.new "Credential owner URN is missing." if user_descr.empty?

      begin
        user = am_manager.find_or_create_user(user_descr)
      rescue OMF::SFA::AM::UnavailableResourceException
        raise OMF::SFA::AM::InsufficientPrivilegesException.new "User: '#{user_descr}' does not exist and its not " +
                  "possible to create it"
      end

      account_urn = if credential.type == 'slice' then credential.target_urn else nil end
      self.new(account_urn, user, credential, am_manager, ch_key)
    end


    ##### RESOURCE

    def can_create_resource?(resource, type)
      type = type.downcase
      debug "Check permission 'can_create_resource?' (#{@permissions[:can_create_resource?]})"

      especial_types = ['lease', 'account']
      if (type == 'lease' && @permissions[:can_create_lease?]) ||
          (type == 'account' && @permissions[:can_create_account?]) ||
          (especial_types.include?(type) == false && @permissions[:can_create_resource?])
        return true
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException.new("You have no permission to create '#{type}' resource")
    end

    def can_modify_resource?(resource, type)
      type = type.downcase
      debug "Check permission 'can_modify_resource?' (#{@permissions[:can_modify_resource?]})"

      if (type == 'account' && @permissions[:can_renew_account?]) ||
          (type != 'account' && @permissions[:can_modify_resource?])
        return true
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException.new("You have no permission to modify '#{type}' resource")
    end

    def can_view_resource?(resource)
      type = resource.resource_type.downcase
      debug "Check permission 'can_view_resource?' (#{@permissions[:can_view_resource?]})"

      especial_types = ['lease', 'account']
      if (type == 'lease' && can_view_lease?(resource)) || (type == 'account' && can_view_account?(resource)) ||
          (especial_types.include?(type) == false && @permissions[:can_view_resource?])
        return true
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException.new('You have no permission to view this resource')
    end

    def can_release_resource?(resource)
      is_slice_cred = @credential.type.eql?('slice')
      is_user_cred = @credential.type.eql?('user')
      can_release_resource = (@permissions[:can_release_resource?] &&
          (is_user_cred || (is_slice_cred  && resource.account == @account)))

      debug "Check permission 'can_release_resource?' (#{can_release_resource}, #{resource})"
      return true if can_release_resource
      raise OMF::SFA::AM::InsufficientPrivilegesException.new('You have no permission to release this resource')
    end

    ##### ACCOUNT

    def can_view_account?(account)
      debug "Check permission 'can_view_account?' (#{account.urn == @account_urn}, #{@permissions[:can_view_account?]})"

      return true if (((account.urn == @account_urn) || account.nil?) && @permissions[:can_view_account?]) || (account.nil? || account == @am_manager._get_nil_account)
      raise OMF::SFA::AM::InsufficientPrivilegesException.new('You have no permission to view this account')
    end

    def can_renew_account?(account, expiration_time)
      debug "Check permission 'can_renew_account?' (#{account == @account}, #{@permissions[:can_renew_account?]})"
      if account == @account && @permissions[:can_renew_account?] && @credential.valid_at?(expiration_time)
        return true
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException.new('You have no permission to renew this account')
    end

    def can_close_account?(account)
      debug "Check permission 'can_close_account?' (#{account == @account}, #{@permissions[:can_close_account?]})"
      if account == @account && @permissions[:can_close_account?]
        return true
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException.new('You have no permission to close this account')
    end

    ##### LEASE

    def can_view_lease?(lease)
      is_slice_cred = @credential.type.eql?('slice')
      is_user_cred = @credential.type.eql?('user')
      can_view_lease = (@permissions[:can_view_lease?] &&
          (is_user_cred || (is_slice_cred  && lease.account == @account)))

      debug "Check permission 'can_view_lease?' (#{can_view_lease}, #{lease.urn})"
      return true if can_view_lease
      raise OMF::SFA::AM::InsufficientPrivilegesException.new('You have no permission to view this lease')
    end

    def can_modify_lease?(lease)
      debug "Check permission 'can_modify_lease?' (#{@account == lease.account}, #{@permissions[:can_modify_lease?]})"
      if @account == lease.account && @permissions[:can_modify_lease?]
        return true
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException.new('You have no permission to modify this lease')
    end

    def can_release_lease?(lease)
      debug "Check permission 'can_release_lease?' (#{@account == lease.account}, #{@permissions[:can_release_lease?]})"
      if @account == lease.account && @permissions[:can_release_lease?]
        return true
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException.new('You have no permission to release this lease')
    end

    protected

    def initialize(account_urn, user, credential, am_manager, ch_key)
      super()

      debug "Initialize for account: #{account_urn} and user: #{user.inspect})"
      @user = user
      @credential = credential
      @ch_key = ch_key
      @account_urn = account_urn
      @am_manager = am_manager
      @permissions = create_credential_permissions(credential)
      @account = nil

      debug "Credential permissions: #{@permissions}"

      unless account_urn.nil?
        acc_name = OMF::SFA::AM::Utils::create_account_name_from_urn(account_urn)
        @account = am_manager.find_or_create_account({:urn => account_urn, :name => acc_name}, self)

        if credential.type == 'slice' and @account.valid_until < credential.valid_until
          debug "Renewing account '#{@account.name}' until '#{credential.valid_until}'"
          am_manager.renew_account_until(@account, credential.valid_until, self)
        end

        unless am_manager.kind_of? OMF::SFA::AM::CentralAMManager
          if @account.closed?
            if @permissions[:can_create_account?]
              @account.closed_at = nil
            else
              raise OMF::SFA::AM::InsufficientPrivilegesException.new("The account is closed and you don't have " +
                                                                          "the privilege to enable a closed account")
            end
          end
          @account.add_user(@user) unless @account.users.include?(@user)
          @account.save
        end
      end
    end

    ##
    # Create permissions by credential privileges
    #
    def create_credential_permissions(credential)
      all_privileges = credential.privilege?('*')
      is_slice_cred = credential.type.eql?('slice')
      is_user_cred = credential.type.eql?('user')

      debug "is_slice_cred?(#{is_slice_cred}), is_user_cred?(#{is_user_cred})"

      privileges = {
          # RESOURCE
          can_create_resource?:  (is_user_cred && (all_privileges || credential.privilege?('refresh'))),
          can_modify_resource?:  (is_user_cred && (all_privileges || credential.privilege?('refresh'))),
          can_view_resource?:    (is_user_cred && (all_privileges || credential.privilege?('info'))),
          can_release_resource?: (all_privileges || credential.privilege?('refresh')),
          # SLICE
          can_create_account?:   (is_slice_cred && (all_privileges || credential.privilege?('control'))),
          can_view_account?:     (is_slice_cred && (all_privileges || credential.privilege?('info'))),
          can_renew_account?:    (is_slice_cred && (all_privileges || credential.privilege?('refresh'))),
          can_close_account?:    (is_slice_cred && (all_privileges || credential.privilege?('control'))),
          # LEASE
          can_create_lease?:     (is_slice_cred && (all_privileges || credential.privilege?('control'))),
          can_view_lease?:       (all_privileges || credential.privilege?('info')),
          can_modify_lease?:     (is_slice_cred && (all_privileges || credential.privilege?('refresh'))),
          can_release_lease?:    (is_slice_cred && (all_privileges || credential.privilege?('refresh'))),
      }
    end

  end # class
end # module
