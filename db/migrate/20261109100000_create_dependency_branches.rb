class CreateDependencyBranches < ActiveRecord::Migration[8.1]
  def change
    create_table :dependency_branches do |t|
      t.references :preview, null: false, foreign_key: true, index: false
      t.string :app_name, null: false
      t.string :branch, null: false
      t.timestamps
    end
    add_index :dependency_branches, %i[preview_id app_name], unique: true
  end
end
