Sequel.migration do
  up do
    add_column :sliver_types, :cpu_cores, Integer
    add_column :sliver_types, :ram_in_mb, Integer
  end

  down do
    drop_column :sliver_types, :cpu_cores
    drop_column :sliver_types, :ram_in_mb
  end
end
