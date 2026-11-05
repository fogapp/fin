# typed: strict

module Tax
  module Sections
    # Deduction facts: mortgage interest from each loan's amortization walk,
    # charitable gifts from charitable-tagged categories (with receipt
    # status), SALT bookkeeping, and deduction adjustments.
    class Deductions < Base
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build
        state_estimated = @context.estimated_payments.select { |p| p.jurisdiction == Jurisdiction::State }
                                  .sum(0.0) { |p| p.amount.to_f }.round(2)
        state_withholding = @context.profile&.ytd_withholding_state.to_f

        {
          kind:              "fact",
          mortgage_interest: mortgage_interest,
          charitable:        charitable,
          salt: {
            kind:                     "record",
            state_withholding:        state_withholding,
            state_estimated_payments: state_estimated,
            amount:                   (state_withholding + state_estimated).round(2),
            note: "State withholding (profile) + state estimated payments; add property tax as a deduction adjustment"
          },
          adjustments: @context.adjustments_group(TaxAdjustment::Kind::Deduction)
        }
      end

      private

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def mortgage_interest
        loans = Loan.where(household_id: @context.household.id, status: Loan::Status::Active).order(:name).map do |loan|
          { loan_id: loan.id, name: loan.name, interest_paid: loan.interest_paid_between(@context.range).to_f }
        end

        {
          total: loans.sum(0.0) { |l| l[:interest_paid] }.round(2),
          loans: loans,
          note:  "Interest portion of linked payment transactions via each loan's amortization walk, sliced to #{@context.year} — reconcile against Form 1098"
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def charitable
        category_ids = Category.where(household_id: @context.household.id, charitable: true).pluck(:id)
        gifts = []

        if category_ids.any?
          received = TaxChecklistItem
            .where(household_id: @context.household.id, tax_year: @context.year,
                   kind: TaxChecklistItem::Kind::CharitableReceipt, status: TaxChecklistItem::Status::Received)
            .pluck(:reference_id).compact.to_set

          gifts = CashTransaction.spend_like
            .where(household_id: @context.household.id, transaction_date: @context.range, category_id: category_ids)
            .includes(:merchant)
            .order(:transaction_date)
            .map do |txn|
              {
                transaction_id: txn.id,
                date:           txn.transaction_date,
                description:    txn.merchant&.name || txn.description,
                amount:         txn.amount.abs.to_f,
                receipt:        received.include?(txn.id)
              }
            end
        end

        { total: gifts.sum(0.0) { |g| g[:amount] }.round(2), gifts: gifts }
      end
    end
  end
end
