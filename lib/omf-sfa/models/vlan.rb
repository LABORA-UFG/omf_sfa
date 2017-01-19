require 'omf-sfa/models/resource'

module OMF::SFA::Model
  class Vlan < Resource
    many_to_one :openflow_switch

    plugin :nested_attributes
    nested_attributes :openflow_switch

    extend OMF::SFA::Model::Base::ClassMethods
    include OMF::SFA::Model::Base::InstanceMethods

    sfa_class 'vlan', :can_be_referred => true, :expose_id => false

    def self.exclude_from_json
      sup = super
      [:node_id].concat(sup)
    end

    def self.include_nested_attributes_to_json
      sup = super
      [:openflow_switch].concat(sup)
    end

  end
end
