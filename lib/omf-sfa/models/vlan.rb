require 'omf-sfa/models/component'

module OMF::SFA::Model
  class Vlan < Component

    plugin :nested_attributes

    sfa_class 'vlan', :can_be_referred => true, :expose_id => false

    # def self.exclude_from_json
    #   sup = super
    #   [:node_id].concat(sup)
    # end

    def before_save
      self.available = true if self.available.nil?
      super
    end

    def availability
      self.available_now?
    end

    def self.can_be_managed?
      true
    end

    # def self.include_nested_attributes_to_json
    #   sup = super
    #   [:openflow_switch].concat(sup)
    # end

    def self.handle_rest_get_resource(resource_descr)
      # TODO get vlans associated with slices
      now = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      debug "NOW IS : #{now}"
      valid_accounts = OMF::SFA::Model::Account.where{valid_until >= now}.map {|s| s.id}
      slices = OMF::SFA::Model::Slice.where(account_id: valid_accounts)

      vlans = OMF::SFA::Model::Vlan.where(account_id: 2).map {|vlan| vlan}
      for slice in slices
        components = slice.components
        for component in components
          if component.is_a? OMF::SFA::Model::Vlan
            vlans.delete_if {|vlan| vlan.number == component.number}
          end
        end
      end

      vlans
    end
  end
end
