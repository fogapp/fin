# typed: strict

module Workflows
  module Actions
    class AssignMerchant < T::Struct
      include SetsColumn

      const :merchant_id, T.nilable(String)
      sets_column :merchant_id
    end
  end
end
