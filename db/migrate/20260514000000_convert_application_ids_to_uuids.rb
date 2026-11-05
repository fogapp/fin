# Converts every application table's primary key from bigint to uuid (with
# gen_random_uuid() as the default), and updates all FK columns to match.
#
# This migration sits between the April bigint create_table migrations and the
# May UUID-aware migrations (rule_folders, transfers, security_overviews) that
# *require* their referenced PKs to already be uuid.
#
# Data loss: this migration TRUNCATEs every converted table. There is no safe
# way to map old bigint IDs onto new random UUIDs while preserving FK integrity
# in a single migration, and per project decision, dev data is reseeded after
# this runs. Production deploys had no data, so no live data is affected.
#
# Idempotent: re-running against an already-UUID schema is a no-op (used so the
# migration is safe under `db:schema:load` followed by `db:migrate`).
class ConvertApplicationIdsToUuids < ActiveRecord::Migration[8.0]
  # Tables that should use uuid PKs. Solid Queue tables stay bigint (gem-internal).
  APP_TABLES = %w[
    accounts api_tokens
    bank_transactions bank_transaction_tags
    brokers categories
    cash_transactions cash_transaction_tags
    credit_card_transactions credit_card_transaction_tags
    csv_imports investment_transactions market_prices
    merchant_rules merchants
    plaid_accounts plaid_items position_snapshots
    recurring_patterns
    rule_actions rule_conditions rule_executions rules
    saved_views securities tags transaction_types
    active_storage_attachments active_storage_blobs active_storage_variant_records
  ].freeze

  # Polymorphic id columns — they reference any model, so they can't be uuid;
  # they store the foreign key as a string regardless of source PK shape.
  POLYMORPHIC_ID_COLUMNS = {
    "active_storage_attachments" => "record_id",
    "rule_executions"            => "trigger_resource_id"
  }.freeze

  def up
    return unless connection.adapter_name == "PostgreSQL"
    return if id_already_uuid?("accounts") # already converted

    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    tables = APP_TABLES.select { |t| table_exists?(t) }

    # 1. Snapshot every FK on application tables so we can re-add them after
    #    column types change.
    fks = tables.flat_map { |t| foreign_keys(t).map { |fk| capture_fk(t, fk) } }

    # 2. Drop FK constraints (can't TRUNCATE or change column types otherwise).
    fks.each { |fk| execute %(ALTER TABLE "#{fk[:from_table]}" DROP CONSTRAINT IF EXISTS "#{fk[:name]}") }

    # 3. Wipe data — see header comment.
    execute "TRUNCATE TABLE #{tables.map { |t| %("#{t}") }.join(', ')} RESTART IDENTITY CASCADE"

    # 4. Convert each PK from bigint to uuid.
    tables.each do |table|
      next if id_already_uuid?(table)
      execute %(ALTER TABLE "#{table}" ALTER COLUMN "id" DROP DEFAULT)
      execute %(DROP SEQUENCE IF EXISTS "#{table}_id_seq" CASCADE)
      execute %(ALTER TABLE "#{table}" ALTER COLUMN "id" TYPE uuid USING gen_random_uuid())
      execute %(ALTER TABLE "#{table}" ALTER COLUMN "id" SET DEFAULT gen_random_uuid())
    end

    # 5. Convert every FK column from bigint to uuid.
    fks.each do |fk|
      next if column_type?(fk[:from_table], fk[:column], "uuid")
      execute %(ALTER TABLE "#{fk[:from_table]}" ALTER COLUMN "#{fk[:column]}" TYPE uuid USING NULL)
    end

    # 6. Convert polymorphic id columns to string (can hold any id format).
    POLYMORPHIC_ID_COLUMNS.each do |table, column|
      next unless table_exists?(table) && connection.column_exists?(table, column)
      next if column_type?(table, column, "character varying", "text", "uuid")
      execute %(ALTER TABLE "#{table}" ALTER COLUMN "#{column}" TYPE varchar USING "#{column}"::varchar)
    end

    # 7. Re-add FK constraints (now uuid -> uuid).
    fks.each { |fk| recreate_fk(fk) }
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "UUID conversion is one-way; restore from backup or recreate from schema.rb."
  end

  private

  def capture_fk(from_table, fk)
    {
      from_table: from_table,
      to_table:   fk.to_table,
      column:     fk.column,
      primary_key: fk.primary_key || "id",
      name:       fk.name,
      on_delete:  fk.on_delete,
      on_update:  fk.on_update
    }
  end

  def recreate_fk(fk)
    parts = [
      %(ALTER TABLE "#{fk[:from_table]}"),
      %(ADD CONSTRAINT "#{fk[:name]}"),
      %(FOREIGN KEY ("#{fk[:column]}")),
      %(REFERENCES "#{fk[:to_table]}" ("#{fk[:primary_key]}"))
    ]
    parts << "ON DELETE #{fk_action_sql(fk[:on_delete])}" if fk[:on_delete]
    parts << "ON UPDATE #{fk_action_sql(fk[:on_update])}" if fk[:on_update]
    execute parts.join(" ")
  end

  def fk_action_sql(action)
    { cascade: "CASCADE", nullify: "SET NULL", restrict: "RESTRICT", default: "SET DEFAULT" }[action]
  end

  def id_already_uuid?(table)
    column_type?(table, "id", "uuid")
  end

  def column_type?(table, column, *expected)
    col = connection.columns(table).find { |c| c.name == column }
    col && expected.include?(col.sql_type)
  rescue ActiveRecord::StatementInvalid
    false
  end
end
