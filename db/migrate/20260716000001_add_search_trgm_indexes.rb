# typed: true

# Trigram GIN indexes backing the sitewide Cmd+K search (GET /api/v1/search),
# which filters every group with ILIKE '%term%' — a btree can't serve that,
# only a trigram index can. Same precedent as
# 20260714000006_add_reliability_and_query_indexes.rb's index on
# cash_transactions.description.
class AddSearchTrgmIndexes < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    add_index :merchants, :name,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_merchants_on_name_trgm"

    add_index :categories, :name,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_categories_on_name_trgm"

    add_index :tags, :name,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_tags_on_name_trgm"

    add_index :accounts, :name,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_accounts_on_name_trgm"

    add_index :loans, :name,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_loans_on_name_trgm"

    add_index :loans, :lender,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_loans_on_lender_trgm"

    add_index :cash_transactions, :memo,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_cash_transactions_on_memo_trgm"

    add_index :investment_transactions, :description,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_investment_transactions_on_description_trgm"

    add_index :securities, :name,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_securities_on_name_trgm"

    add_index :securities, :ticker,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_securities_on_ticker_trgm"
  end
end
