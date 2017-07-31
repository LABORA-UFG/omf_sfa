Sequel.migration do
  up do
    add_column :sliver_types, :label, String
    add_column :sliver_types, :status, String
    add_column :sliver_types, :ip_address, String
  end

  down do
    drop_column :sliver_types, :label
    drop_column :sliver_types, :status
    drop_column :sliver_types, :ip_address
  end
end
