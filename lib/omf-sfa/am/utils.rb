
module OMF::SFA::AM
  class Utils
    def self.create_account_name_from_urn(urn)
      max_size = 32
      gurn = OMF::SFA::Model::GURN.create(urn, :type => "OMF::SFA::Resource::Account")
      domain = gurn.domain.gsub(":", '.')
      acc_name = "#{domain}.#{gurn.short_name}"
      return acc_name if acc_name.size <= max_size

      domain = gurn.domain
      authority = domain.split(":").first.split(".").first
      subauthority = domain.split(":").last
      acc_name = "#{authority}.#{subauthority}.#{gurn.short_name}"
      return acc_name if acc_name.size <= max_size

      acc_name = "#{subauthority}.#{gurn.short_name}"
      if acc_name.size <= max_size
        if Utils::check_account_name_conflict?(acc_name, urn)
          nof_chars_to_delete = "#{authority}.#{subauthority}.#{gurn.short_name}".size - max_size
          acc_name = ""
          acc_name += "#{authority[0..-(nof_chars_to_delete / 2 + 1).to_i]}." # +1 for the dot in the end
          acc_name +=  "#{subauthority[0..-(nof_chars_to_delete / 2 + 1).to_i]}.#{gurn.short_name}"
          acc_name = acc_name.sub('..','.')
          return acc_name unless Utils::check_account_name_conflict?(acc_name, urn)
        else
          return acc_name
        end
      end

      acc_name = gurn.short_name
      return acc_name if acc_name.size <= max_size && !Utils::check_account_name_conflict?(acc_name, urn)
      raise OMF::SFA::AM::FormatException.new "Slice urn is too long, account '#{acc_name}' cannot be generated."
    end

    def self.check_account_name_conflict?(name, urn)
      acc = OMF::SFA::Model::Account.first(name: name)
      return true if acc && acc.urn != urn
      false
    end
  end
end