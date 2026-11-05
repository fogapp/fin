# typed: strict

module Workflows
  module Actions
    class AssignAccount < T::Struct
      include SetsColumn

      const :account_id, T.nilable(String)
      sets_column :account_id
    end
  end
end
