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
      #slices = OMF::SFA::Model::Slices.where({:account_id => resource_descr[:account_id]})
      self.where(resource_descr)
    end
  end
end
