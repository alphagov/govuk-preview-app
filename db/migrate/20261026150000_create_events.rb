# A record of who did what to which preview, and when - see Event.
#
# preview_id has no foreign key: a deleted preview's events must outlive
# it, which is also why its app_name and branch are copied in.
class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string :action, null: false
      t.bigint :preview_id, index: true
      t.string :app_name, null: false
      t.string :branch, null: false
      t.string :user_email
      t.boolean :automatic, default: false, null: false
      t.datetime :created_at, null: false, index: true
    end
  end
end
