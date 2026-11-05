# typed: strict

module Workflows
  module Actions
    class SetLoan < T::Struct
      include SetsColumn

      const :loan_id, T.nilable(String)
      sets_column :loan_id
    end
  end
end
