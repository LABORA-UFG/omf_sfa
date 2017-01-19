require 'omf-sfa/models/component'
require 'omf-sfa/models/interface'
require 'omf-sfa/models/ip'
require 'omf-sfa/models/vlan'

module OMF::SFA::Model
  class OpenflowSwitch < Component
    many_to_one :of_controller_ip, class: Ip
    one_to_many :interfaces
    one_to_many :vlans, class: Vlan

    plugin :nested_attributes
    nested_attributes :of_controller_ip, :interfaces, :vlans

    sfa_class 'openflow_switch', :can_be_referred => true, :expose_id => false

    def self.exclude_from_json
      sup = super
      [:of_controller_ip_id].concat(sup)
    end

    def self.include_nested_attributes_to_json
      sup = super
      [:leases, :of_controller_ip, :interfaces, :vlans].concat(sup)
    end

    def self.can_be_managed?
      true
    end
  end
end
