# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_04_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"

  create_table "account_balance_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "balance", precision: 15, scale: 2, null: false
    t.string "balance_currency", default: "USD"
    t.decimal "balance_usd", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.datetime "recorded_at", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "recorded_at"], name: "index_account_balance_snapshots_on_account_id_and_recorded_at"
    t.index ["account_id", "source", "recorded_at"], name: "index_balance_snapshots_on_account_source_recorded_at"
  end

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account_number", null: false
    t.string "account_type"
    t.decimal "balance", precision: 15, scale: 2
    t.string "balance_currency", default: "USD"
    t.decimal "balance_usd", precision: 15, scale: 2
    t.uuid "broker_id"
    t.datetime "created_at", null: false
    t.boolean "hidden", default: false, null: false
    t.uuid "household_id", null: false
    t.string "kind", default: "standard", null: false
    t.string "name", null: false
    t.string "tax_treatment", default: "taxable", null: false
    t.datetime "updated_at", null: false
    t.index ["broker_id", "account_number"], name: "index_accounts_on_broker_id_and_account_number", unique: true
    t.index ["broker_id"], name: "index_accounts_on_broker_id"
    t.index ["household_id"], name: "index_accounts_on_household_id"
    t.index ["name"], name: "index_accounts_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activity_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "caused_by_id"
    t.string "caused_by_type"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "event", null: false
    t.uuid "household_id", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "severity", default: "info", null: false
    t.string "source", null: false
    t.uuid "subject_id"
    t.string "subject_type"
    t.string "summary", null: false
    t.uuid "trace_id"
    t.datetime "updated_at", null: false
    t.index ["household_id", "occurred_at"], name: "index_activity_entries_on_household_id_and_occurred_at"
    t.index ["household_id", "severity", "occurred_at"], name: "idx_on_household_id_severity_occurred_at_48edbd1490"
    t.index ["household_id", "source", "occurred_at"], name: "idx_on_household_id_source_occurred_at_9f54b92554"
    t.index ["occurred_at"], name: "index_activity_entries_on_occurred_at"
    t.index ["subject_type", "subject_id"], name: "index_activity_entries_on_subject_type_and_subject_id"
    t.index ["trace_id"], name: "index_activity_entries_on_trace_id"
  end

  create_table "alchemy_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "api_key"
    t.text "auth_token"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "sync_frequency", default: "daily", null: false
    t.boolean "transactions_enabled", default: false, null: false
    t.datetime "transactions_last_synced_at"
    t.datetime "updated_at", null: false
    t.string "webhook_base_url"
    t.index ["household_id"], name: "index_alchemy_configurations_on_household_id"
  end

  create_table "alchemy_wallet_syncs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "alchemy_wallet_id", null: false
    t.jsonb "backfill_cursor", default: {}, null: false
    t.string "backfill_status", default: "pending", null: false
    t.bigint "backfill_target_block"
    t.integer "backfill_transfer_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.bigint "last_synced_block"
    t.string "network", null: false
    t.datetime "updated_at", null: false
    t.index ["alchemy_wallet_id", "network"], name: "index_alchemy_wallet_syncs_on_alchemy_wallet_id_and_network", unique: true
    t.index ["household_id"], name: "index_alchemy_wallet_syncs_on_household_id"
  end

  create_table "alchemy_wallets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.boolean "active", default: true, null: false
    t.string "address", null: false
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.jsonb "known_token_contracts", default: {}, null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.string "name"
    t.jsonb "networks", default: ["eth-mainnet", "base-mainnet"], null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_alchemy_wallets_on_account_id"
    t.index ["household_id", "address"], name: "index_alchemy_wallets_on_household_id_and_address", unique: true
  end

  create_table "alchemy_webhooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.uuid "household_id", null: false
    t.text "last_error"
    t.datetime "last_received_at"
    t.string "network", null: false
    t.text "signing_key"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["external_id"], name: "index_alchemy_webhooks_on_external_id", unique: true
    t.index ["household_id", "network"], name: "index_alchemy_webhooks_on_household_id_and_network", unique: true
  end

  create_table "alpha_vantage_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "api_key"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_alpha_vantage_configurations_on_household_id", unique: true
  end

  create_table "api_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "handoff_digest"
    t.datetime "handoff_expires_at"
    t.uuid "household_id", null: false
    t.datetime "last_used_at"
    t.string "name"
    t.string "oidc_sid"
    t.string "scope", default: "full", null: false
    t.boolean "session", default: false, null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["handoff_digest"], name: "index_api_tokens_on_handoff_digest", unique: true
    t.index ["household_id"], name: "index_api_tokens_on_household_id"
    t.index ["oidc_sid"], name: "index_api_tokens_on_oidc_sid"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "brokers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_brokers_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_brokers_on_household_id"
  end

  create_table "budget_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "approaching_alerted_at"
    t.uuid "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "exceeded_alerted_at"
    t.uuid "household_id", null: false
    t.string "mode", default: "ongoing", null: false
    t.date "month", null: false
    t.string "period", default: "monthly", null: false
    t.decimal "planned", precision: 14, scale: 2, default: "0.0", null: false
    t.boolean "rollover", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "category_id", "month"], name: "index_budget_lines_on_household_id_and_category_id_and_month", unique: true
    t.index ["household_id", "month"], name: "index_budget_lines_on_household_id_and_month"
  end

  create_table "budget_periods", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.decimal "income_planned", precision: 14, scale: 2
    t.date "month", null: false
    t.decimal "other_planned", precision: 14, scale: 2
    t.datetime "updated_at", null: false
    t.index ["household_id", "month"], name: "index_budget_periods_on_household_id_and_month", unique: true
  end

  create_table "candles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "adjusted_close", precision: 24, scale: 10
    t.decimal "close", precision: 24, scale: 10, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.date "date", null: false
    t.string "granularity", default: "1d", null: false
    t.decimal "high", precision: 24, scale: 10
    t.decimal "low", precision: 24, scale: 10
    t.decimal "open", precision: 24, scale: 10
    t.uuid "security_id", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.bigint "volume"
    t.index ["security_id", "date"], name: "index_candles_on_security_id_and_date"
    t.index ["security_id", "granularity", "date"], name: "index_candles_on_security_id_and_granularity_and_date", unique: true
  end

  create_table "cash_transaction_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "cash_transaction_id", null: false
    t.datetime "created_at", null: false
    t.uuid "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["cash_transaction_id", "tag_id"], name: "index_cash_transaction_tags_on_cash_transaction_id_and_tag_id", unique: true
    t.index ["tag_id"], name: "index_cash_transaction_tags_on_tag_id"
  end

  create_table "cash_transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.decimal "amount", precision: 18, scale: 2, null: false
    t.decimal "balance", precision: 18, scale: 2
    t.boolean "budget_excluded", default: false, null: false
    t.uuid "category_id"
    t.datetime "created_at", null: false
    t.string "description"
    t.uuid "household_id", null: false
    t.uuid "loan_id"
    t.string "memo"
    t.uuid "merchant_id"
    t.date "post_date"
    t.string "raw_category"
    t.string "source", null: false
    t.string "source_row_hash", null: false
    t.string "tran_code"
    t.string "tran_code_description"
    t.date "transaction_date", null: false
    t.string "transaction_type"
    t.uuid "transfer_id"
    t.datetime "updated_at", null: false
    t.index ["account_id", "transaction_date"], name: "index_cash_transactions_on_account_and_date"
    t.index ["category_id", "transaction_date"], name: "index_cash_transactions_on_category_and_date"
    t.index ["description"], name: "index_cash_transactions_on_description_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["household_id", "transaction_date"], name: "index_cash_transactions_on_household_and_date"
    t.index ["loan_id"], name: "index_cash_transactions_on_loan_id"
    t.index ["memo"], name: "index_cash_transactions_on_memo_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["merchant_id", "transaction_date"], name: "index_cash_transactions_on_merchant_and_date"
    t.index ["source", "transaction_type"], name: "index_cash_transactions_on_source_and_type"
    t.index ["source_row_hash"], name: "index_cash_transactions_on_source_row_hash", unique: true
    t.index ["transaction_date"], name: "index_cash_transactions_on_transaction_date"
    t.index ["transaction_type"], name: "index_cash_transactions_on_transaction_type"
    t.index ["transfer_id"], name: "index_cash_transactions_on_transfer_id"
  end

  create_table "categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "budget_kind", default: "flex", null: false
    t.boolean "charitable", default: false, null: false
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "name", null: false
    t.uuid "parent_id"
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_categories_on_household_name_roots", unique: true, where: "(parent_id IS NULL)"
    t.index ["household_id", "parent_id", "name"], name: "index_categories_on_household_parent_name", unique: true, where: "(parent_id IS NOT NULL)"
    t.index ["household_id"], name: "index_categories_on_household_id"
    t.index ["name"], name: "index_categories_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["parent_id"], name: "index_categories_on_parent_id"
  end

  create_table "coin_market_cap_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "api_key"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_coin_market_cap_configurations_on_household_id", unique: true
  end

  create_table "coinbase_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "api_key_id"
    t.text "api_key_secret"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_coinbase_configurations_on_household_id", unique: true
  end

  create_table "corporate_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 18, scale: 8
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.date "ex_date", null: false
    t.string "kind", null: false
    t.decimal "ratio", precision: 16, scale: 8
    t.uuid "security_id", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["security_id", "kind", "ex_date"], name: "index_corporate_actions_on_security_id_and_kind_and_ex_date", unique: true
  end

  create_table "csv_imports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "broker_name"
    t.datetime "created_at", null: false
    t.integer "error_count", default: 0, null: false
    t.text "error_log"
    t.datetime "finished_at"
    t.uuid "household_id", null: false
    t.integer "imported_count", default: 0, null: false
    t.integer "kind", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.string "source_filename", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.uuid "target_account_id"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_csv_imports_on_created_at"
    t.index ["household_id"], name: "index_csv_imports_on_household_id"
    t.index ["kind"], name: "index_csv_imports_on_kind"
    t.index ["target_account_id"], name: "index_csv_imports_on_target_account_id"
  end

  create_table "equity_companies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "c_corp", default: true, null: false
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "name", null: false
    t.string "notes"
    t.decimal "preferred_price", precision: 18, scale: 6
    t.boolean "public_company", default: false, null: false
    t.boolean "qsbs_candidate", default: false, null: false
    t.uuid "security_id"
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_equity_companies_on_household_id"
  end

  create_table "equity_fmv_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "effective_date", null: false
    t.uuid "equity_company_id", null: false
    t.uuid "household_id", null: false
    t.decimal "price_per_share", precision: 18, scale: 6, null: false
    t.string "source", default: "409a", null: false
    t.datetime "updated_at", null: false
    t.index ["equity_company_id", "effective_date"], name: "idx_on_equity_company_id_effective_date_3c6ac41b9d", unique: true
    t.index ["household_id"], name: "index_equity_fmv_entries_on_household_id"
  end

  create_table "equity_grant_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "buyer_type"
    t.datetime "created_at", null: false
    t.boolean "election_83b", default: false, null: false
    t.date "election_83b_date"
    t.uuid "equity_grant_id", null: false
    t.uuid "household_id", null: false
    t.string "kind", null: false
    t.string "method"
    t.string "notes"
    t.date "occurred_on", null: false
    t.decimal "quantity", precision: 18, scale: 4, null: false
    t.decimal "share_price", precision: 18, scale: 6
    t.decimal "shares_withheld", precision: 18, scale: 4
    t.datetime "updated_at", null: false
    t.index ["equity_grant_id"], name: "index_equity_grant_events_on_equity_grant_id"
    t.index ["household_id"], name: "index_equity_grant_events_on_household_id"
  end

  create_table "equity_grants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "cliff_installments", default: 0, null: false
    t.datetime "created_at", null: false
    t.jsonb "custom_tranches"
    t.boolean "double_trigger", default: false, null: false
    t.boolean "early_exercisable", default: false, null: false
    t.uuid "equity_company_id", null: false
    t.date "expiration_date"
    t.date "grant_date", null: false
    t.string "grant_type", null: false
    t.uuid "household_id", null: false
    t.string "label"
    t.string "notes"
    t.integer "pte_window_days"
    t.decimal "quantity", precision: 18, scale: 4, null: false
    t.decimal "strike_price", precision: 18, scale: 6
    t.datetime "updated_at", null: false
    t.date "vesting_commencement_date"
    t.string "vesting_interval"
    t.integer "vesting_occurrences"
    t.index ["equity_company_id"], name: "index_equity_grants_on_equity_company_id"
    t.index ["household_id"], name: "index_equity_grants_on_household_id"
  end

  create_table "estimated_tax_payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "jurisdiction", null: false
    t.string "notes"
    t.date "paid_on", null: false
    t.integer "tax_year", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "tax_year"], name: "index_estimated_tax_payments_on_household_id_and_tax_year"
  end

  create_table "fog_integrations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_token_id"
    t.uuid "approved_by_id"
    t.datetime "claimed_at"
    t.string "consumer", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.uuid "household_id", null: false
    t.string "offer", null: false
    t.string "return_to", null: false
    t.text "secret"
    t.string "state", default: "pending", null: false
    t.string "ticket_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token_id"], name: "index_fog_integrations_on_api_token_id"
    t.index ["approved_by_id"], name: "index_fog_integrations_on_approved_by_id"
    t.index ["household_id"], name: "index_fog_integrations_on_household_id"
    t.index ["ticket_digest"], name: "index_fog_integrations_on_ticket_digest", unique: true
  end

  create_table "fx_rates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "base", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "quote", null: false
    t.decimal "rate", precision: 24, scale: 10, null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["base", "quote", "date"], name: "index_fx_rates_on_base_and_quote_and_date", unique: true
  end

  create_table "household_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["household_id"], name: "index_household_memberships_on_household_id"
    t.index ["user_id", "household_id"], name: "index_household_memberships_on_user_id_and_household_id", unique: true
  end

  create_table "households", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "include_unvested_equity", default: false, null: false
    t.string "name", null: false
    t.string "notification_webhook_url"
    t.datetime "updated_at", null: false
    t.string "workflow_log_level", default: "info", null: false
  end

  create_table "identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "issuer", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["issuer", "subject"], name: "index_identities_on_issuer_and_subject", unique: true
    t.index ["subject"], name: "index_identities_on_subject"
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "instance_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fog_attested_at"
    t.boolean "singleton", default: true, null: false
    t.string "time_zone", default: "America/Los_Angeles", null: false
    t.datetime "updated_at", null: false
    t.index ["singleton"], name: "index_instance_settings_on_singleton", unique: true
    t.check_constraint "singleton", name: "instance_settings_one_row"
  end

  create_table "instrument_data_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "capability", null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.boolean "disabled", default: false, null: false
    t.datetime "last_attempt_at"
    t.string "last_error"
    t.datetime "last_success_at"
    t.integer "priority", default: 0, null: false
    t.string "provider", null: false
    t.string "provider_ref"
    t.uuid "security_id", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_instrument_data_links_on_provider"
    t.index ["security_id", "capability"], name: "index_instrument_data_links_on_security_id_and_capability", unique: true
  end

  create_table "instrument_identifiers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "scheme", null: false
    t.uuid "security_id", null: false
    t.datetime "updated_at", null: false
    t.string "value", null: false
    t.index ["scheme", "value"], name: "index_instrument_identifiers_on_scheme_and_value", unique: true
    t.index ["security_id"], name: "index_instrument_identifiers_on_security_id"
  end

  create_table "instrument_quotes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "as_of", null: false
    t.decimal "change_pct_24h", precision: 10, scale: 4
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.decimal "price", precision: 24, scale: 10, null: false
    t.uuid "security_id", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["security_id"], name: "index_instrument_quotes_on_security_id", unique: true
  end

  create_table "investment_lots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.date "acquired_date"
    t.decimal "cost_basis", precision: 18, scale: 4, null: false
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "notes"
    t.decimal "quantity", precision: 18, scale: 6, null: false
    t.uuid "security_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_investment_lots_on_account_id"
    t.index ["household_id"], name: "index_investment_lots_on_household_id"
    t.index ["security_id"], name: "index_investment_lots_on_security_id"
  end

  create_table "investment_transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "amount_local", precision: 18, scale: 4
    t.decimal "amount_usd", precision: 18, scale: 4
    t.decimal "balance", precision: 18, scale: 4
    t.string "check_number"
    t.decimal "commissions_local", precision: 18, scale: 4
    t.decimal "commissions_usd", precision: 18, scale: 4
    t.decimal "cost_local", precision: 18, scale: 4
    t.decimal "cost_usd", precision: 18, scale: 4
    t.datetime "created_at", null: false
    t.string "description"
    t.string "executing_dealer"
    t.decimal "gl_long_local", precision: 18, scale: 4
    t.decimal "gl_long_usd", precision: 18, scale: 4
    t.decimal "gl_short_local", precision: 18, scale: 4
    t.decimal "gl_short_usd", precision: 18, scale: 4
    t.uuid "household_id", null: false
    t.decimal "income_local", precision: 18, scale: 4
    t.decimal "income_usd", precision: 18, scale: 4
    t.string "local_currency"
    t.date "post_date"
    t.decimal "price_local", precision: 18, scale: 6
    t.decimal "price_usd", precision: 18, scale: 6
    t.decimal "quantity", precision: 38, scale: 18
    t.uuid "security_id"
    t.date "settlement_date"
    t.string "source_row_hash", null: false
    t.decimal "tax_withheld", precision: 18, scale: 4
    t.date "trade_date", null: false
    t.uuid "transaction_type_id", null: false
    t.uuid "transfer_id"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_investment_transactions_on_account_id"
    t.index ["description"], name: "index_investment_transactions_on_description_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["household_id", "trade_date"], name: "index_investment_transactions_on_household_and_date"
    t.index ["household_id"], name: "index_investment_transactions_on_household_id"
    t.index ["security_id"], name: "index_investment_transactions_on_security_id"
    t.index ["source_row_hash"], name: "index_investment_transactions_on_source_row_hash", unique: true
    t.index ["trade_date"], name: "index_investment_transactions_on_trade_date"
    t.index ["transaction_type_id"], name: "index_investment_transactions_on_transaction_type_id"
    t.index ["transfer_id"], name: "index_investment_transactions_on_transfer_id"
  end

  create_table "invite_codes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.datetime "expires_at"
    t.uuid "household_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.uuid "used_by_id"
    t.index ["code"], name: "index_invite_codes_on_code", unique: true
    t.index ["created_by_id"], name: "index_invite_codes_on_created_by_id"
    t.index ["household_id"], name: "index_invite_codes_on_household_id"
    t.index ["used_by_id"], name: "index_invite_codes_on_used_by_id"
  end

  create_table "issues", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.uuid "household_id", null: false
    t.string "key"
    t.string "severity", default: "warning", null: false
    t.string "source"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_issues_on_created_at"
    t.index ["household_id", "key"], name: "index_issues_on_household_id_and_key", unique: true, where: "(key IS NOT NULL)"
    t.index ["household_id"], name: "index_issues_on_household_id"
  end

  create_table "loans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.decimal "balance_anchor_amount", precision: 15, scale: 2
    t.date "balance_anchor_date"
    t.datetime "created_at", null: false
    t.decimal "escrow_insurance", precision: 15, scale: 2
    t.decimal "escrow_other", precision: 15, scale: 2
    t.decimal "escrow_property_tax", precision: 15, scale: 2
    t.uuid "household_id", null: false
    t.boolean "interest_only", default: false, null: false
    t.decimal "interest_rate", precision: 8, scale: 4, null: false
    t.string "lender"
    t.string "loan_type", null: false
    t.uuid "merchant_id"
    t.decimal "monthly_payment", precision: 15, scale: 2
    t.string "name", null: false
    t.text "notes"
    t.decimal "original_principal", precision: 15, scale: 2, null: false
    t.uuid "real_estate_property_id"
    t.date "start_date", null: false
    t.string "status", default: "active", null: false
    t.integer "term_months", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_loans_on_account_id"
    t.index ["household_id"], name: "index_loans_on_household_id"
    t.index ["lender"], name: "index_loans_on_lender_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["merchant_id"], name: "index_loans_on_merchant_id"
    t.index ["name"], name: "index_loans_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["real_estate_property_id"], name: "index_loans_on_real_estate_property_id"
  end

  create_table "market_prices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "adjusted_close", precision: 18, scale: 6
    t.decimal "close", precision: 18, scale: 6
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.decimal "high", precision: 18, scale: 6
    t.decimal "low", precision: 18, scale: 6
    t.decimal "open", precision: 18, scale: 6
    t.uuid "security_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "volume"
    t.index ["security_id", "date"], name: "index_market_prices_on_security_id_and_date", unique: true
  end

  create_table "merchant_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "category_id"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.uuid "merchant_id", null: false
    t.string "pattern", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_merchant_rules_on_category_id"
    t.index ["household_id"], name: "index_merchant_rules_on_household_id"
    t.index ["merchant_id", "priority"], name: "index_merchant_rules_on_merchant_id_and_priority"
  end

  create_table "merchants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "category_id"
    t.datetime "created_at", null: false
    t.boolean "excluded", default: false, null: false
    t.uuid "household_id", null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_merchants_on_category_id"
    t.index ["excluded"], name: "index_merchants_on_excluded"
    t.index ["household_id", "name"], name: "index_merchants_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_merchants_on_household_id"
    t.index ["name"], name: "index_merchants_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "metric_points", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "computed_at", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.uuid "household_id", null: false
    t.string "metric_key", null: false
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 18, scale: 4
    t.index ["household_id", "metric_key", "date"], name: "index_metric_points_on_household_id_and_metric_key_and_date", unique: true
  end

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "href"
    t.datetime "read_at"
    t.string "severity", default: "info", null: false
    t.uuid "subject_id"
    t.string "subject_type"
    t.string "title", null: false
    t.uuid "trace_id"
    t.datetime "updated_at", null: false
    t.uuid "workflow_run_id"
    t.index ["household_id", "created_at"], name: "index_notifications_on_household_id_and_created_at"
    t.index ["household_id", "read_at"], name: "index_notifications_on_household_id_and_read_at"
    t.index ["trace_id"], name: "index_notifications_on_trace_id"
  end

  create_table "office_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "api_key"
    t.string "base_url"
    t.datetime "created_at", null: false
    t.integer "default_folder_id"
    t.uuid "household_id", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_office_configurations_on_household_id", unique: true
  end

  create_table "office_sheet_exports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "column_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "dataset", null: false
    t.bigint "document_id", null: false
    t.jsonb "filters", default: {}, null: false
    t.uuid "household_id", null: false
    t.text "last_error"
    t.datetime "last_exported_at"
    t.integer "row_count", default: 0, null: false
    t.string "sheet_name"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.uuid "user_id"
    t.index ["household_id", "dataset"], name: "index_office_sheet_exports_on_household_id_and_dataset"
    t.index ["household_id", "document_id"], name: "index_office_sheet_exports_on_household_id_and_document_id", unique: true
  end

  create_table "plaid_accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.string "account_subtype"
    t.string "account_type"
    t.decimal "balance_available", precision: 18, scale: 4
    t.string "balance_currency"
    t.decimal "balance_current", precision: 18, scale: 4
    t.decimal "balance_limit", precision: 18, scale: 4
    t.datetime "balance_updated_at"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "mask"
    t.string "name", null: false
    t.string "plaid_account_id", null: false
    t.uuid "plaid_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_plaid_accounts_on_account_id"
    t.index ["household_id"], name: "index_plaid_accounts_on_household_id"
    t.index ["plaid_account_id"], name: "index_plaid_accounts_on_plaid_account_id", unique: true
    t.index ["plaid_item_id"], name: "index_plaid_accounts_on_plaid_item_id"
  end

  create_table "plaid_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "client_id"
    t.datetime "created_at", null: false
    t.string "environment", default: "production", null: false
    t.uuid "household_id", null: false
    t.text "secret"
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_plaid_configurations_on_household_id", unique: true
  end

  create_table "plaid_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "created_at", null: false
    t.text "cursor"
    t.text "error_message"
    t.uuid "household_id", null: false
    t.string "institution_id"
    t.string "institution_name"
    t.string "item_id", null: false
    t.datetime "last_synced_at"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_plaid_items_on_household_id"
    t.index ["item_id"], name: "index_plaid_items_on_item_id", unique: true
  end

  create_table "position_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "accrued_income", precision: 18, scale: 4
    t.date "acquisition_date"
    t.date "as_of_date", null: false
    t.string "asset_class"
    t.string "asset_strategy"
    t.string "asset_strategy_detail"
    t.decimal "cost_basis", precision: 18, scale: 4
    t.decimal "cost_basis_override", precision: 18, scale: 4
    t.datetime "created_at", null: false
    t.decimal "dividend_yield", precision: 10, scale: 4
    t.decimal "est_annual_income", precision: 18, scale: 4
    t.uuid "household_id", null: false
    t.decimal "market_value", precision: 18, scale: 4
    t.decimal "price", precision: 18, scale: 6
    t.decimal "quantity", precision: 38, scale: 18
    t.uuid "security_id", null: false
    t.string "source_row_hash", null: false
    t.decimal "unit_cost", precision: 18, scale: 6
    t.decimal "unrealized_gain_loss", precision: 18, scale: 4
    t.decimal "unrealized_gain_loss_pct", precision: 10, scale: 4
    t.datetime "updated_at", null: false
    t.index ["account_id", "security_id", "as_of_date"], name: "idx_pos_snap_unique", unique: true
    t.index ["as_of_date", "security_id"], name: "index_position_snapshots_on_date_and_security"
    t.index ["household_id", "as_of_date"], name: "index_position_snapshots_on_household_and_date"
    t.index ["security_id"], name: "index_position_snapshots_on_security_id"
    t.index ["source_row_hash"], name: "index_position_snapshots_on_source_row_hash", unique: true
    t.index ["source_row_hash"], name: "index_position_snapshots_on_source_row_hash_pattern", opclass: :text_pattern_ops
  end

  create_table "positions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "cost_basis", precision: 20, scale: 4
    t.datetime "created_at", null: false
    t.date "first_acquired_on"
    t.uuid "household_id", null: false
    t.datetime "ledger_updated_at"
    t.decimal "quantity", precision: 24, scale: 8, default: "0.0", null: false
    t.uuid "security_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "security_id"], name: "index_positions_on_account_id_and_security_id", unique: true
    t.index ["household_id", "security_id"], name: "index_positions_on_household_id_and_security_id"
  end

  create_table "real_estate_properties", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "address_line1", null: false
    t.string "address_line2"
    t.decimal "bathrooms", precision: 4, scale: 1
    t.integer "bedrooms"
    t.string "city"
    t.datetime "created_at", null: false
    t.datetime "facts_synced_at"
    t.string "formatted_address"
    t.decimal "hoa_fee", precision: 15, scale: 2
    t.uuid "household_id", null: false
    t.string "last_sync_error"
    t.datetime "last_synced_at"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.integer "lot_size"
    t.string "name", null: false
    t.text "notes"
    t.string "property_type"
    t.date "purchase_date"
    t.decimal "purchase_price", precision: 15, scale: 2
    t.string "rentcast_id"
    t.date "sold_date"
    t.decimal "sold_price", precision: 15, scale: 2
    t.integer "square_footage"
    t.string "state"
    t.string "status", default: "owned", null: false
    t.boolean "sync_enabled", default: true, null: false
    t.datetime "updated_at", null: false
    t.integer "year_built"
    t.string "zip_code"
    t.index ["household_id", "status"], name: "index_real_estate_properties_on_household_id_and_status"
  end

  create_table "real_estate_valuations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.date "as_of", null: false
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.jsonb "payload"
    t.uuid "real_estate_property_id", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.decimal "value_high", precision: 15, scale: 2
    t.decimal "value_low", precision: 15, scale: 2
    t.index ["household_id"], name: "index_real_estate_valuations_on_household_id"
    t.index ["real_estate_property_id", "as_of"], name: "idx_on_real_estate_property_id_as_of_a24a78f3ef"
    t.index ["real_estate_property_id", "source", "as_of"], name: "index_real_estate_valuations_unique_point", unique: true
  end

  create_table "recurring_occurrences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2
    t.uuid "cash_transaction_id"
    t.date "charged_date"
    t.datetime "created_at", null: false
    t.decimal "expected_amount", precision: 10, scale: 2
    t.date "expected_date", null: false
    t.uuid "household_id", null: false
    t.uuid "recurring_series_id", null: false
    t.string "status", default: "upcoming", null: false
    t.datetime "updated_at", null: false
    t.index ["cash_transaction_id"], name: "index_recurring_occurrences_on_cash_transaction_id", unique: true, where: "(cash_transaction_id IS NOT NULL)"
    t.index ["household_id", "status", "expected_date"], name: "idx_on_household_id_status_expected_date_16a59c622c"
    t.index ["recurring_series_id", "expected_date"], name: "idx_on_recurring_series_id_expected_date_2c58854160", unique: true
  end

  create_table "recurring_series", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "accepted_at"
    t.uuid "account_id"
    t.decimal "amount_tolerance", precision: 4, scale: 3, default: "0.075", null: false
    t.jsonb "anchor", default: {}, null: false
    t.decimal "average_amount", precision: 10, scale: 2, null: false
    t.float "confidence", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.string "description_pattern"
    t.datetime "dismissed_at"
    t.datetime "ended_at"
    t.date "first_charge_date"
    t.string "granularity", null: false
    t.uuid "household_id", null: false
    t.string "kind", default: "subscription", null: false
    t.decimal "last_amount", precision: 10, scale: 2
    t.date "last_charge_date"
    t.datetime "last_price_change_at"
    t.decimal "max_amount", precision: 10, scale: 2
    t.uuid "merchant_id"
    t.decimal "min_amount", precision: 10, scale: 2
    t.integer "misses_streak", default: 0, null: false
    t.string "name", null: false
    t.date "next_expected_date"
    t.text "notes"
    t.integer "occurrences_count", default: 0, null: false
    t.integer "quantity", default: 1, null: false
    t.string "series_key", null: false
    t.string "source", default: "detected", null: false
    t.string "status", default: "suggested", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "series_key"], name: "index_recurring_series_on_household_id_and_series_key", unique: true
    t.index ["household_id", "status"], name: "index_recurring_series_on_household_id_and_status"
    t.index ["merchant_id"], name: "index_recurring_series_on_merchant_id"
    t.index ["next_expected_date"], name: "index_recurring_series_on_next_expected_date"
  end

  create_table "releases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "git_sha", null: false
    t.datetime "updated_at", null: false
    t.index ["git_sha"], name: "index_releases_on_git_sha", unique: true
  end

  create_table "rentcast_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "api_key"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.datetime "last_synced_at"
    t.integer "monthly_request_limit", default: 50, null: false
    t.date "quota_period_start"
    t.integer "requests_used", default: 0, null: false
    t.string "sync_frequency", default: "weekly", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_rentcast_configurations_on_household_id", unique: true
  end

  create_table "saved_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "config", null: false
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_saved_reports_on_household_id"
  end

  create_table "saved_views", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "filter_params", null: false
    t.uuid "household_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_saved_views_on_household_id"
  end

  create_table "securities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "cusip"
    t.jsonb "instrument_attributes", default: {}, null: false
    t.string "instrument_class", default: "other", null: false
    t.datetime "last_synced_at"
    t.string "name"
    t.string "security_type"
    t.string "slug"
    t.string "ticker"
    t.datetime "updated_at", null: false
    t.index ["cusip"], name: "index_securities_on_cusip", unique: true, where: "(cusip IS NOT NULL)"
    t.index ["instrument_class"], name: "index_securities_on_instrument_class"
    t.index ["name"], name: "index_securities_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["ticker"], name: "index_securities_on_ticker"
    t.index ["ticker"], name: "index_securities_on_ticker_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "security_conversions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.date "effective_date", null: false
    t.jsonb "evidence", default: {}, null: false
    t.uuid "from_security_id", null: false
    t.uuid "household_id", null: false
    t.decimal "ratio", precision: 20, scale: 10, null: false
    t.string "source", default: "detected", null: false
    t.string "status", default: "suggested", null: false
    t.uuid "to_security_id", null: false
    t.datetime "updated_at", null: false
    t.index ["from_security_id"], name: "index_security_conversions_on_from_security_id"
    t.index ["household_id", "from_security_id", "to_security_id"], name: "index_security_conversions_on_pair", unique: true
    t.index ["to_security_id"], name: "index_security_conversions_on_to_security_id"
  end

  create_table "security_labels", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "label", null: false
    t.uuid "security_id", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "security_id"], name: "index_security_labels_on_household_id_and_security_id", unique: true
    t.index ["security_id"], name: "index_security_labels_on_security_id"
  end

  create_table "security_news_articles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "published_at"
    t.uuid "security_id", null: false
    t.string "sentiment"
    t.decimal "sentiment_score", precision: 6, scale: 4
    t.string "source"
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["security_id", "published_at"], name: "index_security_news_articles_on_security_id_and_published_at"
    t.index ["security_id"], name: "index_security_news_articles_on_security_id"
    t.index ["url"], name: "index_security_news_articles_on_url", unique: true
  end

  create_table "security_overviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "analyst_target_price", precision: 18, scale: 6
    t.decimal "beta", precision: 18, scale: 6
    t.string "country"
    t.datetime "created_at", null: false
    t.string "currency"
    t.text "description"
    t.decimal "dividend_per_share", precision: 18, scale: 6
    t.decimal "dividend_yield", precision: 18, scale: 6
    t.decimal "eps", precision: 18, scale: 6
    t.date "ex_dividend_date"
    t.string "exchange"
    t.datetime "fetched_at"
    t.decimal "forward_pe", precision: 18, scale: 6
    t.string "industry"
    t.bigint "market_cap"
    t.decimal "pe_ratio", precision: 18, scale: 6
    t.decimal "profit_margin", precision: 18, scale: 6
    t.decimal "return_on_equity", precision: 18, scale: 6
    t.bigint "revenue_ttm"
    t.string "sector"
    t.uuid "security_id", null: false
    t.bigint "shares_outstanding"
    t.datetime "updated_at", null: false
    t.decimal "week_52_high", precision: 18, scale: 6
    t.decimal "week_52_low", precision: 18, scale: 6
    t.index ["security_id"], name: "index_security_overviews_on_security_id", unique: true
  end

  create_table "security_watches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.uuid "security_id", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "security_id"], name: "index_security_watches_on_household_id_and_security_id", unique: true
    t.index ["security_id"], name: "index_security_watches_on_security_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "household_id, lower((name)::text)", name: "index_tags_on_household_id_and_lower_name", unique: true
    t.index ["household_id"], name: "index_tags_on_household_id"
    t.index ["name"], name: "index_tags_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "tax_adjustments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.string "bucket"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "jurisdiction", default: "federal", null: false
    t.string "kind", null: false
    t.string "label", null: false
    t.string "notes"
    t.integer "tax_year", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "tax_year"], name: "index_tax_adjustments_on_household_id_and_tax_year"
  end

  create_table "tax_checklist_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "auto_seeded", default: false, null: false
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.string "kind", null: false
    t.string "notes"
    t.uuid "reference_id"
    t.string "source_label", null: false
    t.string "status", default: "expected", null: false
    t.integer "tax_year", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "tax_year", "kind", "source_label"], name: "index_tax_checklist_items_uniqueness", unique: true
  end

  create_table "tax_profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amt_credit_carryforward_ca", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "amt_credit_carryforward_federal", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "filing_status", default: "single", null: false
    t.uuid "household_id", null: false
    t.decimal "itemized_other", precision: 14, scale: 2, default: "0.0", null: false
    t.boolean "itemizing", default: false, null: false
    t.decimal "ltcg_qd_income", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "other_ordinary_income", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "prior_year_agi", precision: 14, scale: 2
    t.decimal "prior_year_total_tax", precision: 14, scale: 2
    t.decimal "projected_state_tax", precision: 14, scale: 2
    t.decimal "projected_wages", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "salt_paid", precision: 14, scale: 2, default: "0.0", null: false
    t.string "state", default: "CA", null: false
    t.integer "tax_year", null: false
    t.datetime "updated_at", null: false
    t.decimal "ytd_withholding_federal", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "ytd_withholding_state", precision: 14, scale: 2, default: "0.0", null: false
    t.index ["household_id", "tax_year"], name: "index_tax_profiles_on_household_id_and_tax_year", unique: true
  end

  create_table "tiingo_configurations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "api_key"
    t.datetime "created_at", null: false
    t.uuid "household_id", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_tiingo_configurations_on_household_id", unique: true
  end

  create_table "transaction_types", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "category"
    t.string "code"
    t.string "code_description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_transaction_types_on_code", unique: true
  end

  create_table "transfer_dismissals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "from_transaction_id", null: false
    t.string "from_transaction_type", null: false
    t.uuid "household_id", null: false
    t.uuid "to_transaction_id", null: false
    t.string "to_transaction_type", null: false
    t.datetime "updated_at", null: false
    t.index ["from_transaction_id", "to_transaction_id"], name: "index_transfer_dismissals_on_pair", unique: true
    t.index ["household_id"], name: "index_transfer_dismissals_on_household_id"
  end

  create_table "transfers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 18, scale: 2
    t.string "confirmation_source"
    t.datetime "confirmed_at"
    t.uuid "counterparty_account_id"
    t.datetime "created_at", null: false
    t.uuid "from_transaction_id"
    t.string "from_transaction_type"
    t.uuid "household_id", null: false
    t.boolean "include_in_spend", default: false, null: false
    t.string "kind", default: "transfer", null: false
    t.string "note"
    t.uuid "to_transaction_id"
    t.string "to_transaction_type"
    t.datetime "updated_at", null: false
    t.index ["counterparty_account_id"], name: "index_transfers_on_counterparty_account_id"
    t.index ["from_transaction_type", "from_transaction_id"], name: "index_transfers_on_from_transaction", unique: true, where: "(from_transaction_id IS NOT NULL)"
    t.index ["household_id"], name: "index_transfers_on_household_id"
    t.index ["kind"], name: "index_transfers_on_kind"
    t.index ["to_transaction_type", "to_transaction_id"], name: "index_transfers_on_to_transaction", unique: true, where: "(to_transaction_id IS NOT NULL)"
  end

  create_table "user_preferences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_user_preferences_on_user_id", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "webauthn_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname"
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["external_id"], name: "index_webauthn_credentials_on_external_id", unique: true
    t.index ["user_id"], name: "index_webauthn_credentials_on_user_id"
  end

  create_table "workflow_monitor_states", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_evaluated_at"
    t.boolean "result", default: false, null: false
    t.uuid "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "workflow_id", null: false
    t.index ["workflow_id", "subject_type", "subject_id"], name: "index_monitor_states_on_workflow_and_subject", unique: true
  end

  create_table "workflow_run_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "output", default: {}, null: false
    t.datetime "resume_at"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.uuid "workflow_run_id", null: false
    t.uuid "workflow_step_id"
    t.index ["workflow_run_id", "created_at"], name: "index_workflow_run_steps_on_workflow_run_id_and_created_at"
    t.index ["workflow_step_id"], name: "index_workflow_run_steps_on_workflow_step_id"
  end

  create_table "workflow_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "cursor_step_id"
    t.text "error"
    t.jsonb "event_payload", default: {}, null: false
    t.string "event_type", null: false
    t.datetime "finished_at"
    t.uuid "household_id", null: false
    t.datetime "reverted_at"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.uuid "subject_id"
    t.string "subject_type"
    t.uuid "trace_id"
    t.uuid "triggered_by_run_id"
    t.datetime "updated_at", null: false
    t.uuid "workflow_id", null: false
    t.index ["household_id", "created_at"], name: "index_workflow_runs_on_household_id_and_created_at"
    t.index ["status"], name: "index_workflow_runs_on_status"
    t.index ["subject_type", "subject_id"], name: "index_workflow_runs_on_subject_type_and_subject_id"
    t.index ["trace_id"], name: "index_workflow_runs_on_trace_id"
    t.index ["triggered_by_run_id"], name: "index_workflow_runs_on_triggered_by_run_id"
    t.index ["workflow_id", "created_at"], name: "index_workflow_runs_on_workflow_id_and_created_at"
  end

  create_table "workflow_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.uuid "parent_id"
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "workflow_id", null: false
    t.index ["workflow_id", "parent_id", "position"], name: "index_workflow_steps_on_workflow_id_and_parent_id_and_position"
  end

  create_table "workflows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.uuid "household_id", null: false
    t.string "name", null: false
    t.datetime "next_scheduled_at"
    t.integer "position", default: 0, null: false
    t.string "seed_key"
    t.jsonb "trigger_config", default: {}, null: false
    t.string "trigger_type", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_workflows_on_household_id_and_name", unique: true
    t.index ["household_id", "seed_key"], name: "index_workflows_on_household_id_and_seed_key", unique: true, where: "(seed_key IS NOT NULL)"
    t.index ["household_id", "trigger_type", "active"], name: "index_workflows_on_household_id_and_trigger_type_and_active"
    t.index ["next_scheduled_at"], name: "index_workflows_on_next_scheduled_at", where: "(next_scheduled_at IS NOT NULL)"
  end

  add_foreign_key "account_balance_snapshots", "accounts", on_delete: :cascade
  add_foreign_key "accounts", "brokers"
  add_foreign_key "accounts", "households", on_delete: :cascade
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activity_entries", "households", on_delete: :cascade
  add_foreign_key "alchemy_configurations", "households", on_delete: :cascade
  add_foreign_key "alchemy_wallet_syncs", "alchemy_wallets", on_delete: :cascade
  add_foreign_key "alchemy_wallet_syncs", "households", on_delete: :cascade
  add_foreign_key "alchemy_wallets", "accounts", on_delete: :nullify
  add_foreign_key "alchemy_wallets", "households", on_delete: :cascade
  add_foreign_key "alchemy_webhooks", "households", on_delete: :cascade
  add_foreign_key "alpha_vantage_configurations", "households", on_delete: :cascade
  add_foreign_key "api_tokens", "households", on_delete: :cascade
  add_foreign_key "api_tokens", "users", on_delete: :cascade
  add_foreign_key "brokers", "households", on_delete: :cascade
  add_foreign_key "budget_lines", "categories", on_delete: :cascade
  add_foreign_key "budget_lines", "households", on_delete: :cascade
  add_foreign_key "budget_periods", "households", on_delete: :cascade
  add_foreign_key "candles", "securities", on_delete: :cascade
  add_foreign_key "cash_transaction_tags", "cash_transactions", on_delete: :cascade
  add_foreign_key "cash_transaction_tags", "tags", on_delete: :cascade
  add_foreign_key "cash_transactions", "accounts"
  add_foreign_key "cash_transactions", "categories"
  add_foreign_key "cash_transactions", "households", on_delete: :cascade
  add_foreign_key "cash_transactions", "loans"
  add_foreign_key "cash_transactions", "merchants"
  add_foreign_key "cash_transactions", "transfers", on_delete: :nullify
  add_foreign_key "categories", "categories", column: "parent_id"
  add_foreign_key "categories", "households", on_delete: :cascade
  add_foreign_key "coin_market_cap_configurations", "households", on_delete: :cascade
  add_foreign_key "coinbase_configurations", "households", on_delete: :cascade
  add_foreign_key "corporate_actions", "securities", on_delete: :cascade
  add_foreign_key "csv_imports", "accounts", column: "target_account_id", on_delete: :nullify
  add_foreign_key "csv_imports", "households", on_delete: :cascade
  add_foreign_key "equity_companies", "households", on_delete: :cascade
  add_foreign_key "equity_companies", "securities", on_delete: :nullify
  add_foreign_key "equity_fmv_entries", "equity_companies", on_delete: :cascade
  add_foreign_key "equity_fmv_entries", "households", on_delete: :cascade
  add_foreign_key "equity_grant_events", "equity_grants", on_delete: :cascade
  add_foreign_key "equity_grant_events", "households", on_delete: :cascade
  add_foreign_key "equity_grants", "equity_companies", on_delete: :cascade
  add_foreign_key "equity_grants", "households", on_delete: :cascade
  add_foreign_key "estimated_tax_payments", "households", on_delete: :cascade
  add_foreign_key "fog_integrations", "api_tokens", on_delete: :nullify
  add_foreign_key "fog_integrations", "households", on_delete: :cascade
  add_foreign_key "fog_integrations", "users", column: "approved_by_id", on_delete: :nullify
  add_foreign_key "household_memberships", "households", on_delete: :cascade
  add_foreign_key "household_memberships", "users", on_delete: :cascade
  add_foreign_key "identities", "users", on_delete: :cascade
  add_foreign_key "instrument_data_links", "securities", on_delete: :cascade
  add_foreign_key "instrument_identifiers", "securities", on_delete: :cascade
  add_foreign_key "instrument_quotes", "securities", on_delete: :cascade
  add_foreign_key "investment_lots", "accounts"
  add_foreign_key "investment_lots", "households", on_delete: :cascade
  add_foreign_key "investment_lots", "securities"
  add_foreign_key "investment_transactions", "accounts"
  add_foreign_key "investment_transactions", "households", on_delete: :cascade
  add_foreign_key "investment_transactions", "securities"
  add_foreign_key "investment_transactions", "transaction_types"
  add_foreign_key "investment_transactions", "transfers", on_delete: :nullify
  add_foreign_key "invite_codes", "households", on_delete: :cascade
  add_foreign_key "invite_codes", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "invite_codes", "users", column: "used_by_id", on_delete: :nullify
  add_foreign_key "issues", "households", on_delete: :cascade
  add_foreign_key "loans", "accounts", on_delete: :nullify
  add_foreign_key "loans", "households", on_delete: :cascade
  add_foreign_key "loans", "merchants", on_delete: :nullify
  add_foreign_key "loans", "real_estate_properties", on_delete: :nullify
  add_foreign_key "market_prices", "securities"
  add_foreign_key "merchant_rules", "categories"
  add_foreign_key "merchant_rules", "households", on_delete: :cascade
  add_foreign_key "merchant_rules", "merchants"
  add_foreign_key "merchants", "categories"
  add_foreign_key "merchants", "households", on_delete: :cascade
  add_foreign_key "metric_points", "households", on_delete: :cascade
  add_foreign_key "notifications", "households", on_delete: :cascade
  add_foreign_key "notifications", "workflow_runs", on_delete: :nullify
  add_foreign_key "office_configurations", "households", on_delete: :cascade
  add_foreign_key "office_sheet_exports", "households", on_delete: :cascade
  add_foreign_key "office_sheet_exports", "users", on_delete: :nullify
  add_foreign_key "plaid_accounts", "accounts"
  add_foreign_key "plaid_accounts", "households", on_delete: :cascade
  add_foreign_key "plaid_accounts", "plaid_items"
  add_foreign_key "plaid_configurations", "households", on_delete: :cascade
  add_foreign_key "plaid_items", "households", on_delete: :cascade
  add_foreign_key "position_snapshots", "accounts"
  add_foreign_key "position_snapshots", "households", on_delete: :cascade
  add_foreign_key "position_snapshots", "securities"
  add_foreign_key "positions", "accounts", on_delete: :cascade
  add_foreign_key "positions", "households", on_delete: :cascade
  add_foreign_key "positions", "securities", on_delete: :cascade
  add_foreign_key "real_estate_properties", "households", on_delete: :cascade
  add_foreign_key "real_estate_valuations", "households", on_delete: :cascade
  add_foreign_key "real_estate_valuations", "real_estate_properties", on_delete: :cascade
  add_foreign_key "recurring_occurrences", "cash_transactions", on_delete: :nullify
  add_foreign_key "recurring_occurrences", "households", on_delete: :cascade
  add_foreign_key "recurring_occurrences", "recurring_series", on_delete: :cascade
  add_foreign_key "recurring_series", "accounts", on_delete: :nullify
  add_foreign_key "recurring_series", "households", on_delete: :cascade
  add_foreign_key "recurring_series", "merchants", on_delete: :nullify
  add_foreign_key "rentcast_configurations", "households", on_delete: :cascade
  add_foreign_key "saved_views", "households", on_delete: :cascade
  add_foreign_key "security_conversions", "households"
  add_foreign_key "security_conversions", "securities", column: "from_security_id"
  add_foreign_key "security_conversions", "securities", column: "to_security_id"
  add_foreign_key "security_labels", "households", on_delete: :cascade
  add_foreign_key "security_labels", "securities", on_delete: :cascade
  add_foreign_key "security_news_articles", "securities"
  add_foreign_key "security_overviews", "securities"
  add_foreign_key "security_watches", "households", on_delete: :cascade
  add_foreign_key "security_watches", "securities", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "tags", "households", on_delete: :cascade
  add_foreign_key "tax_adjustments", "households", on_delete: :cascade
  add_foreign_key "tax_checklist_items", "households", on_delete: :cascade
  add_foreign_key "tax_profiles", "households", on_delete: :cascade
  add_foreign_key "tiingo_configurations", "households", on_delete: :cascade
  add_foreign_key "transfers", "accounts", column: "counterparty_account_id", on_delete: :nullify
  add_foreign_key "transfers", "households", on_delete: :cascade
  add_foreign_key "user_preferences", "users"
  add_foreign_key "webauthn_credentials", "users", on_delete: :cascade
  add_foreign_key "workflow_monitor_states", "workflows", on_delete: :cascade
  add_foreign_key "workflow_run_steps", "workflow_runs", on_delete: :cascade
  add_foreign_key "workflow_run_steps", "workflow_steps", on_delete: :nullify
  add_foreign_key "workflow_runs", "households", on_delete: :cascade
  add_foreign_key "workflow_runs", "workflows", on_delete: :cascade
  add_foreign_key "workflow_steps", "workflow_steps", column: "parent_id", on_delete: :cascade
  add_foreign_key "workflow_steps", "workflows", on_delete: :cascade
  add_foreign_key "workflows", "households", on_delete: :cascade
end
