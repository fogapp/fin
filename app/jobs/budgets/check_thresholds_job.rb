# typed: true

module Budgets
  class CheckThresholdsJob < ApplicationJob
    extend T::Sig

    queue_as :default

    sig { params(transaction_id: String).void }
    def perform(transaction_id)
      with_record(CashTransaction, transaction_id) do |transaction|
        Budgets::CheckThresholds.call(transaction)
      end
    end
  end
end
