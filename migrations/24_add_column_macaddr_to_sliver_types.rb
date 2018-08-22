Sequel.migration do
  up do
    add_column :sliver_types, :mac_address, String
  end

  down do
    drop_column :sliver_types, :mac_address
  end
end
