class DependencyBranch < ApplicationRecord
  belongs_to :preview

  normalizes :branch, with: ->(branch) { branch.strip }
end
