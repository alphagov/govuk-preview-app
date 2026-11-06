# dependency_branches: which branch each app in a top-level preview's stack
# runs, by app name, for any that isn't `main` - see
# Preview#dependency_branch.
class AddDependencyBranchesToPreviews < ActiveRecord::Migration[8.1]
  def change
    add_column :previews, :dependency_branches, :jsonb, default: {}, null: false
  end
end
