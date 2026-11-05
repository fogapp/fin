# typed: strict

module Metrics
  # The explicit list of live metric definitions. Registering a new metric is
  # one line here plus the definition class; the nightly Metrics::RefreshJob
  # auto-backfills any registered metric that has no stored points yet.
  module Registry
    extend T::Sig

    DEFINITIONS = [
      Definitions::CcTransactionCount,
      Definitions::CcAvgTransaction,
      Definitions::MonthlySpend,
      Definitions::MonthlyIncome,
      Definitions::NetCashflow,
      Definitions::SavingsRate,
      Definitions::DividendIncome,
      Definitions::InvestmentBuyVolume,
      Definitions::PortfolioValue,
      Definitions::NetWorth,
      Definitions::CryptoValue
    ].freeze

    GROUPS = T.let([
      { key: "cashflow",    label: "Cashflow" },
      { key: "investments", label: "Investments" },
      { key: "net_worth",   label: "Net Worth" }
    ].freeze, T::Array[T::Hash[Symbol, String]])

    sig { returns(T::Array[T.class_of(Definition)]) }
    def self.all
      DEFINITIONS
    end

    sig { params(key: T.any(String, Symbol)).returns(T.nilable(T.class_of(Definition))) }
    def self.find(key)
      DEFINITIONS.find { |d| d.key.to_s == key.to_s }
    end
  end
end
