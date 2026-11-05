# typed: strict

module Office
  # What Fin can hand Office as a spreadsheet. Each dataset turns request
  # params into a grid — a header row plus data rows of native values
  # (String, Numeric, Date, nil) — which Office types on arrival the way it
  # would type the same thing typed into a cell.
  #
  # Rows are built server-side from the same renderers and filters the API
  # endpoints use, so an export is the whole filtered result rather than
  # whatever pages the table happened to have loaded.
  module Datasets
    extend T::Sig

    # A dataset's grid plus what the sheet should be called. `filters` is
    # the subset of params that produced it, stored on the export so a
    # refresh replays the same query.
    class Grid < T::Struct
      const :title, String
      const :rows, T::Array[T::Array[T.untyped]]
      const :filters, T::Hash[Symbol, T.untyped]
    end

    class Dataset < T::Struct
      const :key, String
      const :label, String
      # Params this dataset reads; anything else is dropped before the
      # filters are stored, so a stray query param can't ride along.
      const :filter_keys, T::Array[Symbol]
      const :builder, T.proc.params(params: T::Hash[Symbol, T.untyped]).returns(Grid)
    end

    # Guards a single export: a sheet big enough to matter is one thing, a
    # sheet that times out the Office write is another.
    MAX_ROWS = 20_000

    sig { returns(T::Hash[String, Dataset]) }
    def self.all
      @all ||= T.let(build_registry, T.nilable(T::Hash[String, Dataset]))
    end

    sig { returns(T::Array[String]) }
    def self.keys
      all.keys
    end

    sig { params(key: T.untyped).returns(Dataset) }
    def self.fetch(key)
      all.fetch(key.to_s) do
        raise ArgumentError, "Unknown dataset #{key.inspect} (expected one of: #{keys.join(', ')})"
      end
    end

    # Builds the grid for `key`, keeping only the params the dataset reads.
    sig { params(key: T.untyped, params: T.untyped).returns(Grid) }
    def self.build(key, params)
      dataset = fetch(key)
      scoped  = dataset.filter_keys.each_with_object({}) do |filter_key, acc|
        value = params[filter_key]
        next if value.blank? && value != false

        # Scalars are normalized to strings so a filter set survives the
        # round trip through jsonb unchanged; the table's condition list is
        # structured and is kept as it came.
        acc[filter_key] = case value
        when Array, Hash then value.as_json
        when true, false then value
        else value.to_s
        end
      end

      grid = dataset.builder.call(scoped)
      raise ArgumentError, "That export is #{grid.rows.size} rows; Office sheets are capped at #{MAX_ROWS}" if grid.rows.size > MAX_ROWS

      grid
    end

    sig { returns(T::Hash[String, Dataset]) }
    def self.build_registry
      {
        "transactions" => Dataset.new(
          key: "transactions", label: "Transactions",
          # The transaction table's own filter vocabulary — CashTransactions::Filter
          # reads exactly these, so the sheet matches what the table shows.
          # `conditions` + `match_all` are the transaction table's own filter
          # vocabulary (the same shape saved views store and
          # CashTransactionsController#filter evaluates); the rest is the
          # column-filter vocabulary the account and category pages scope with.
          filter_keys: %i[conditions match_all search show_transfers source merchant_id account_id loan_id
                          transaction_type category_id category_ids tag_id exclude_tag_ids description
                          start_date end_date from to],
          builder: ->(params) { Office::Datasets::Transactions.new(params).grid }
        ),
        "holdings" => Dataset.new(
          key: "holdings", label: "Holdings",
          filter_keys: %i[account_id],
          builder: ->(params) { Office::Datasets::Holdings.new(params).grid }
        ),
        "portfolio" => Dataset.new(
          key: "portfolio", label: "Portfolio",
          filter_keys: %i[from to],
          builder: ->(params) { Office::Datasets::Portfolio.new(params).grid }
        )
      }.freeze
    end
    private_class_method :build_registry
  end
end
