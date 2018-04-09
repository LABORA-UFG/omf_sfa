require 'omf-sfa/models/resource'
require 'omf-sfa/models/component'

module OMF::SFA::Model
  class Lease < Resource
    many_to_many :components, :left_key=>:lease_id, :right_key=>:component_id,
    :join_table=>:components_leases


    extend OMF::SFA::Model::Base::ClassMethods
    include OMF::SFA::Model::Base::InstanceMethods

    sfa_add_namespace :ol, 'http://nitlab.inf.uth.gr/schema/sfa/rspec/1'

    sfa_class 'lease', :namespace => :ol, :can_be_referred => true
    sfa :valid_from, :attribute => true
    sfa :valid_until, :attribute => true
    sfa :client_id, :attribute => true
    sfa :sliver_id, :attribute => true

    def self.include_nested_attributes_to_json
      sup = super
      [:components].concat(sup)
    end

    def before_save
      self.status = 'pending' if self.status.nil?
      self.name = self.uuid if self.name.nil?
      self.valid_until = Time.parse(self.valid_until) if self.valid_until.kind_of? String
      self.valid_from = Time.parse(self.valid_from) if self.valid_from.kind_of? String
      # Get rid of the milliseconds
      self.valid_from = Time.at(self.valid_from.to_i) unless valid_from.nil?
      self.valid_until = Time.at(self.valid_until.to_i) unless valid_until.nil?
      super
      self.urn = GURN.create(self.name, :type => 'sliver').to_s if GURN.parse(self.urn).type == 'lease'
    end

    def sliver_id
      self.urn
    end

    def active?
      return false if self.status == 'cancelled' || self.status == 'past'
      t_now = Time.now
      t_now >= self.valid_from && t_now < self.valid_until
    end

    def to_hash
      values.reject! { |k, v| v.nil?}
      values[:components] = []
      self.components.each do |component|
        next if ((self.status == 'active' || self.status == 'accepted') && component.account.id == 2)
        if component.respond_to?(:sliver_type) && !component.sliver_type.nil?
          values[:components] << component.to_hash
        else
          values[:components] << component.to_hash_brief
        end
      end
      values[:account] = self.account ? self.account.to_hash_brief : nil
      excluded = self.class.exclude_from_json
      values.reject! { |k, v| excluded.include?(k)}
      values
    end

    def to_hash_brief
      values[:account] = self.account.to_hash_brief unless self.account.nil?
      super
    end

    def allocation_status
      return "geni_unallocated" if self.status == 'pending' || self.status == 'cancelled'
      return "geni_allocated" unless self.status == 'active'
      ret = 'geni_provisioned'
      self.components.each do |comp|
        next if comp.parent.nil?
        if comp.resource_type == 'node' && comp.status != 'geni_provisioned'
          ret = 'geni_allocated'
          break
        end
      end
      ret
    end

    def operational_status
      case self.status
      when 'pending'
        "geni_failed"
      when 'accepted'
        "geni_pending_allocation"
      when "active"
        "geni_ready"
      when 'cancelled'
        "geni_unallocated"
      when 'passed'
        "geni_unallocated"
      else
        self.status
      end
    end

    ##
    ## REST HANDLE METHODS
    ##
    def self.handle_rest_resource_creation(body_opts, authorizer, scheduler)
      # Validate mandatory parameters
      raise OMF::SFA::AM::Rest::BadRequestException.new "Attribute account is mandatory." if body_opts[:account].nil? && body_opts[:account_attributes].nil?
      raise OMF::SFA::AM::Rest::BadRequestException.new "Attributes valid_from and valid_until are mandatory." if body_opts[:valid_from].nil? || body_opts[:valid_until].nil?
      raise OMF::SFA::AM::Rest::BadRequestException.new "Attribute components is mandatory." if (body_opts[:components].nil? || body_opts[:components].empty?) &&
          (body_opts[:components_attributes].nil? || body_opts[:components_attributes].empty?) && (body_opts[:use_slice_components].nil? || body_opts[:use_slice_components] != true)

      # Get account...
      ac_desc = body_opts[:account] || body_opts[:account_attributes]
      account = OMF::SFA::Model::Account.first(ac_desc)
      raise OMF::SFA::AM::Rest::UnknownResourceException.new "Account with description '#{ac_desc}' does not exist." if account.nil?
      raise OMF::SFA::AM::Rest::NotAuthorizedException.new "Account with description '#{ac_desc}' is closed." unless account.active?

      # Get components...
      components = []
      nil_account_id = scheduler.get_nil_account().id
      if body_opts[:use_slice_components] === true
        slice = OMF::SFA::Model::Account.join(OMF::SFA::Model::Slice.select_all, account_id: :id)
                    .filter(Sequel.qualify("Class", "urn") => account.urn).first
        components = slice.components
        components.each do |comp|
          if comp.account.id == nil_account_id
            comp[:clone_resource] = true
          end
        end
        raise OMF::SFA::AM::Rest::BadRequestException.new "Your can't use slice components of account '#{account.urn}'" \
                          "because it have not a slice" unless slice
      else
        comps = body_opts[:components] || body_opts[:components_attributes]
        not_founded_components = []
        comps.each do |c|
          desc = {}
          desc[:account_id] = nil_account_id
          desc[:uuid] = c[:uuid] unless c[:uuid].nil?
          desc[:name] = c[:name] unless c[:name].nil?
          desc[:urn] = c[:urn] unless c[:urn].nil?

          resource_obj = OMF::SFA::Model::Resource.first(desc)
          if resource_obj.nil?
            desc.delete(:account_id)
            not_founded_components << desc
          else
            resource_obj[:clone_resource] = true
            resource_obj[:sliver_infos] = c[:sliver_infos] unless c[:sliver_infos].nil?
            components << resource_obj
          end
        end

        unless not_founded_components.empty?
          not_founded_components.compact! # removing nils
          raise OMF::SFA::AM::Rest::UnknownResourceException.new "You are trying to reserve unknown resources. " \
                            "Resources with the following identifiers were not found: #{not_founded_components.to_s.gsub('"', '')}"
        end
      end

      # Check if have components to make the lease
      raise OMF::SFA::AM::Rest::BadRequestException.new "Could not create a lease without components." if components.empty?

      begin
        # Create lease
        res_descr = {
            :name =>  body_opts[:name],
            :valid_from => body_opts[:valid_from],
            :valid_until => body_opts[:valid_until],
            :account_id => account.id
        }
        lease = find_or_create_lease(res_descr, authorizer, scheduler)

        comps = []
        components.each do |comp|
          c = comp
          if comp[:clone_resource] === true
            c = scheduler.create_child_resource({uuid: comp.uuid, account_id: account.id},
                                                comp[:type].to_s.split('::').last, comp[:sliver_infos])
          end
          comps << c
          unless scheduler.lease_component(lease, c)
            scheduler.delete_lease(lease)
            comps.each do |release_resource|
              scheduler.release_resource(release_resource)
            end
            raise OMF::SFA::AM::Rest::NotAuthorizedException.new "Reservation for the resource '#{c.urn}' failed." \
                                          " The resource is either unavailable or a policy quota has been exceeded."
          end
        end
        return lease
      rescue => ex
        raise OMF::SFA::AM::Rest::BadRequestException.new "Could not finalize the lease creation: #{ex.to_s}"
      end
    end

    # Return the lease described by +lease_descr+.
    #
    # @param [Hash] properties of lease
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Lease] The requested lease
    # @raise [UnknownResourceException] if requested lease cannot be found
    # @raise [InsufficientPrivilegesException] if permission is not granted
    #
    def self.find_lease(lease_descr, authorizer)
      lease = self.first(lease_descr)
      unless lease
        raise OMF::SFA::AM::UnavailableResourceException.new "Unknown lease '#{lease_descr.inspect}'"
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException unless authorizer.can_view_lease?(lease)
      lease
    end

    # Return the lease described by +lease_descr+. Create if it doesn't exist.
    #
    # @param [Hash] lease_descr properties of lease
    # @param [Authorizer] Defines context for authorization decisions
    # @return [Lease] The requested lease
    # @raise [UnknownResourceException] if requested lease cannot be created
    # @raise [InsufficientPrivilegesException] if permission is not granted
    #
    def self.find_or_create_lease(lease_descr, authorizer, scheduler)
      debug "find_or_create_lease: '#{lease_descr.inspect}'"
      begin
        return find_lease(lease_descr, authorizer)
      rescue OMF::SFA::AM::UnavailableResourceException
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException unless authorizer.can_create_resource?(lease_descr, 'lease')

      lease = self.create(lease_descr)
      raise OMF::SFA::AM::UnavailableResourceException.new "Cannot create '#{lease_descr.inspect}'" unless lease
      scheduler.add_lease_events_on_event_scheduler(lease)
      scheduler.list_all_event_scheduler_jobs
      lease
    end
  end
end
