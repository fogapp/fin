# typed: strict

module Workflows
  module Actions
    class SetMemo < T::Struct
      include SetsColumn

      const :value, String
      sets_column :memo, from: :value, skip_reason: "memo already set to that value"
    end
  end
end
