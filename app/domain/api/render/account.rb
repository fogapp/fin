# typed: strict

module Api
  module Render
    class Account < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        # One grouped scan per ledger: { account_id => [count, latest date] }.
        cash_stats = ledger_stats(::CashTransaction, :transaction_date)
        inv_stats  = ledger_stats(::InvestmentTransaction, :trade_date)
        portfolio_value = ::Positions::CurrentPositions.new.relation
                                            .group(:account_id)
                                            .sum(:market_value)
        loan_by_account = ::Loan.where.not(account_id: nil).pluck(:account_id, :id).to_h

        ::Account.includes(:broker, :plaid_accounts).order("brokers.name", "accounts.name").map do |a|
          cash_count, cash_latest = cash_stats[a.id]
          inv_count,  inv_latest  = inv_stats[a.id]
          latest = [ cash_latest, inv_latest ].compact.max

          serialize(a).merge(
            cash_transaction_count:       cash_count || 0,
            investment_transaction_count: inv_count || 0,
            portfolio_value:              portfolio_value[a.id].to_f,
            latest_transaction_date:      latest,
            linked_loan_id:               loan_by_account[a.id]
          )
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        serialize(::Account.includes(:broker, :plaid_accounts).find(params[:id]))
      end

      sig { params(account: ::Account).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(account)
        plaid_item_id = account.plaid_accounts.first&.plaid_item_id
        {
          id:               account.id,
          name:             account.name,
          account_number:   account.account_number,
          account_type:     account.account_type,
          balance:          account.balance&.to_f,
          balance_currency: account.balance_currency,
          balance_usd:      account.balance_usd&.to_f,
          broker_id:        account.broker_id,
          broker_name:      account.broker&.name,
          plaid_item_id:    plaid_item_id,
          hidden:           account.hidden,
          kind:             account.kind,
          tax_treatment:    account.tax_treatment
        }
      end

      private

      sig { params(model: T.untyped, date_column: Symbol).returns(T::Hash[T.untyped, [ Integer, T.nilable(Date) ]]) }
      def ledger_stats(model, date_column)
        model.group(:account_id)
             .pluck(:account_id, Arel.sql("COUNT(*)"), Arel.sql("MAX(#{model.table_name}.#{date_column})"))
             .to_h { |id, count, latest| [ id, [ count, latest ] ] }
      end
    end
  end
end
