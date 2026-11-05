# typed: strict

module Workflows
  module Actions
    class AssignCategory < T::Struct
      include SetsColumn

      const :category_id, T.nilable(String)
      sets_column :category_id
    end
  end
end
