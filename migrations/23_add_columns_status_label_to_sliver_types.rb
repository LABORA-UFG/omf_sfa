Sequel.migration do
  up do
    # Add sliver type new params
    add_column :sliver_types, :label, String
    add_column :sliver_types, :ip_address, String

    # Add keys new param
    add_column :keys, :is_base64, TrueClass, :default => false
  end

  down do
    drop_column :sliver_types, :label
    drop_column :sliver_types, :ip_address
    drop_column :keys, :is_base64
  end
end
