
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


    def self.create_for_test_request(credential, am_manager)
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
      self.new(account_urn, user, credential, am_manager)
    end

    ##### ACCOUNT

    def can_view_account?(account)
      debug "Check permission 'can_view_account?' (#{account == @account}, #{@permissions[:can_view_account?]})"

      return true if @permissions[:can_view_account?]
      @user.accounts.each do |acc|
        return true if acc == account
      end
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

    ##### RESOURCE

    def can_create_resource?(resource, type)
      type = type.downcase
      debug "Check permission 'can_create_resource?' (#{type == 'lease'}, #{@permissions[:can_create_resource?]})"
      if (type == 'lease' && @permissions[:can_modify_lease?]) || @permissions[:can_create_resource?]
        return true
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException.new("You have no permission to create '#{type}' resource")
    end

    ##### LEASE

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

    def initialize(account_urn, user, credential, am_manager)
      super()

      debug "Initialize for account: #{account_urn} and user: #{user.inspect})"
      @user = user
      @credential = credential
      @am_manager = am_manager
      @permissions = create_credential_permissions(credential)
      @account = nil

      unless account_urn.nil?
        acc_name = OMF::SFA::AM::Utils::create_account_name_from_urn(account_urn)
        if am_manager.kind_of? OMF::SFA::AM::CentralAMManager
          @account = {urn: account_urn, name: acc_name}
        else
          @account = am_manager.find_or_create_account({:urn => account_urn, :name => acc_name}, self)

          if credential.type == 'slice' and @account.valid_until < credential.valid_until
            debug "Renewing account '#{@account.name}' until '#{credential.valid_until}'"
            am_manager.renew_account_until(@account, credential.valid_until, self)
          end

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
      privileges = {
          # RESOURCE
          can_create_resource?:  (all_privileges or credential.privilege?('control')),
          can_modify_resource?:  (all_privileges or credential.privilege?('control')),
          can_view_resource?:    (all_privileges or credential.privilege?('info')),
          can_release_resource?: (all_privileges or credential.privilege?('control')),
          # LEASE
          can_view_lease?:       (all_privileges or credential.privilege?('info')),
          can_modify_lease?:     (all_privileges or credential.privilege?('refresh')),
          can_release_lease?:    (all_privileges or credential.privilege?('refresh'))
      }

      if credential.type == 'slice'
        privileges.merge!(
            {
                can_create_account?:   (all_privileges or credential.privilege?('control')),
                can_view_account?:     (all_privileges or credential.privilege?('info')),
                can_renew_account?:    (all_privileges or credential.privilege?('refresh')),
                can_close_account?:    (all_privileges or credential.privilege?('control'))
            })
      end
    end

  end # class
end # module
