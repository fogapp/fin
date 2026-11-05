# typed: strict

module Api
  module Render
    # The CPA bundle for GET /tax/export: the full year report plus flat
    # transaction lists (charitable gifts, realized sales, estimated
    # payments) in one JSON payload. v1 is JSON only; a CSV bundle is planned.
    class TaxExport < Api::Render::Base
      extend T::Sig

      sig { params(report: T::Hash[Symbol, T.untyped], year: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def export(report:, year:)
        {
          generated_at: Time.current.iso8601,
          format:       "json",
          note:         "JSON export (v1) — CSV bundle planned",
          report:       report,
          transactions: {
            charitable:         report.dig(:deductions, :charitable, :gifts),
            realized_sales:     realized_sales(year),
            estimated_payments: report.dig(:payments, :federal, :estimated) +
                                report.dig(:payments, :state, :estimated)
          }
        }
      end

      private

      sig { params(year: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def realized_sales(year)
        ::InvestmentTransaction.sales
          .where(trade_date: Date.new(year, 1, 1)..Date.new(year, 12, 31))
          .includes(:security, :account)
          .order(:trade_date)
          .map do |txn|
            {
              date:     txn.trade_date,
              security: txn.security&.display_name,
              account:  T.must(txn.account).name,
              proceeds: txn.amount_usd&.to_f,
              st:       txn.gl_short_usd.to_f,
              lt:       txn.gl_long_usd.to_f
            }
          end
      end
    end
  end
end
