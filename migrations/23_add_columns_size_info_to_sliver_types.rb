Sequel.migration do
  up do
    add_column :sliver_types, :cpu_cores, Integer
    add_column :sliver_types, :ram_in_mb, Integer
    add_column :sliver_types, :lable, String
  end

  down do
    drop_column :sliver_types, :cpu_cores
    drop_column :sliver_types, :ram_in_mb
    drop_column :sliver_types, :lable
  end
end
