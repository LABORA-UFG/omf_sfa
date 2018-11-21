Sequel.migration do

  up do
    create_table :resources do
      primary_key :id
      String :name
      String :urn
      String :uuid
      String :type
    end

  	create_table(:accounts) do
  		foreign_key :id, :resources, :primary_key => true, :on_delete => :cascade

  		DateTime :created_at
  		DateTime :valid_until
  		DateTime :closed_at
  	end

  	alter_table(:resources) do
  	  add_foreign_key :account_id, :accounts, :on_delete => :set_null
  	end

    create_table(:leases) do
      foreign_key :id, :resources, :primary_key => true, :on_delete => :cascade
      DateTime :valid_from
      DateTime :valid_until
      String :status # pending, accepted, active, past, cancelled
    end

    create_table(:users) do
      foreign_key :id, :resources, :primary_key => true, :on_delete => :cascade
    end

    create_table(:keys) do
      foreign_key :id, :resources, :primary_key => true, :on_delete => :cascade
      foreign_key :user_id, :users, :on_delete => :cascade

      String :ssh_key
    end

    create_table(:accounts_users) do
      foreign_key :account_id, :accounts, :on_delete => :cascade
      foreign_key :user_id, :users, :on_delete => :cascade
      primary_key [:account_id, :user_id]
    end
  end

  down do
    drop_table(:accounts_users)
    drop_table(:keys)
    drop_table(:users)
    drop_table(:leases)
    drop_column(:resources, :account_id)
    drop_table(:accounts)
    drop_table(:resources)
  end
end
