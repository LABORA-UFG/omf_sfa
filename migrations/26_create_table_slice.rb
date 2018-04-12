Sequel.migration do
  up do
    create_table(:slices) do
      foreign_key :id, :resources, :primary_key => true, :on_delete => :cascade
    end

    create_table(:components_slices) do
      foreign_key :component_id, :components, :on_delete => :cascade
      foreign_key :slice_id, :slices, :on_delete => :cascade
      primary_key [:component_id, :slice_id]
    end
  end

  down do
    drop_table(:components_slices)
    drop_table(:slices)
  end
end