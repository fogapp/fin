# typed: strict

module Api
  module Render
    class Loan < Api::Render::Base
      extend T::Sig

      include Api::Render::Concerns::SerializesTransactionRow

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        ::Loan.includes(:account, :merchant, :cash_transactions).order(created_at: :desc).map { |l| serialize(l) }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        loan = ::Loan.includes(:account, :merchant, cash_transactions: [ :account ]).find(params[:id])
        stats = loan.payment_stats

        serialize_base(loan, stats).merge(
          amortization_schedule: loan.amortization_schedule,
          linked_transactions: loan.cash_transactions.sort_by(&:transaction_date).reverse.map { |t| transaction_row(t) }
        )
      end

      # Cash transactions from the loan's account that could be payments —
      # already-linked rows are excluded so the picker only offers new links.
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def candidate_transactions
        loan = ::Loan.find(params[:id])
        linked_ids = loan.cash_transactions.pluck(:id)

        scope = ::CashTransaction
          .includes(:account)
          .where.not(id: linked_ids)
          .order(transaction_date: :desc)
          .limit(100)

        scope = scope.where(account_id: loan.account_id) if loan.account_id.present?

        scope.map { |t| transaction_row(t) }
      end

      sig { params(loan: ::Loan).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(loan)
        stats = loan.payment_stats
        serialize_base(loan, stats)
      end

      private

      sig { params(loan: ::Loan, stats: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_base(loan, stats)
        {
          id:                       loan.id,
          name:                     loan.name,
          lender:                   loan.lender,
          loan_type:                loan.loan_type,
          original_principal:       loan.original_principal.to_f,
          interest_rate:            loan.interest_rate.to_f,
          term_months:              loan.term_months,
          start_date:               loan.start_date,
          monthly_payment:          loan.computed_monthly_payment.to_f,
          entered_monthly_payment:  loan.monthly_payment&.to_f,
          principal_and_interest_payment: loan.principal_and_interest_payment.to_f,
          escrow_property_tax:      loan.escrow_property_tax&.to_f,
          escrow_insurance:         loan.escrow_insurance&.to_f,
          escrow_other:             loan.escrow_other&.to_f,
          escrow_payment:           loan.escrow_payment.to_f,
          status:                   loan.status,
          notes:                    loan.notes,
          interest_only:            loan.interest_only?,
          merchant_id:              loan.merchant_id,
          merchant_name:            loan.merchant&.name,
          account_id:               loan.account_id,
          account_name:             loan.account&.name,
          balance_anchor_amount:    loan.balance_anchor_amount&.to_f,
          balance_anchor_date:      loan.balance_anchor_date,
          total_scheduled_interest: loan.total_scheduled_interest.to_f,
          total_paid:               stats[:total_paid].to_f,
          principal_paid:           stats[:principal_paid].to_f,
          interest_paid:            stats[:interest_paid].to_f,
          escrow_paid:              stats[:escrow_paid].to_f,
          property_tax_paid:        stats[:property_tax_paid].to_f,
          insurance_paid:           stats[:insurance_paid].to_f,
          other_escrow_paid:        stats[:other_escrow_paid].to_f,
          current_balance:          stats[:current_balance].to_f,
          payments_count:           stats[:payments_count],
          created_at:               loan.created_at,
          updated_at:               loan.updated_at
        }
      end
    end
  end
end
