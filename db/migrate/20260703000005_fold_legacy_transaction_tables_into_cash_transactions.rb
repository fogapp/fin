# cash_transactions (with its source enum) superseded the separate
# bank_transactions and credit_card_transactions tables, but the legacy
# tables stayed wired into backup and merchant matching — tripling
# validations/scopes/associations and, because they have no household_id,
# forming a permanent hole in the tenancy story.
#
# This migration folds any legacy rows that never made it into
# cash_transactions (matched by source_row_hash), ports their tag joins,
# and drops all four legacy tables.
class FoldLegacyTransactionTablesIntoCashTransactions < ActiveRecord::Migration[8.1]
  def up
    fallback_household = "(SELECT id FROM households ORDER BY created_at ASC LIMIT 1)"

    execute <<~SQL
      INSERT INTO cash_transactions (
        id, account_id, amount, balance, category_id, created_at, description,
        household_id, merchant_id, post_date, source, source_row_hash,
        tran_code, tran_code_description, transaction_date, transaction_type, updated_at
      )
      SELECT gen_random_uuid(), b.account_id, b.amount, b.balance, b.category_id, b.created_at,
             b.description, COALESCE(a.household_id, #{fallback_household}), b.merchant_id,
             b.post_date, 'bank', b.source_row_hash, b.tran_code, b.tran_code_description,
             b.transaction_date, b.transaction_type, b.updated_at
      FROM bank_transactions b
      LEFT JOIN accounts a ON a.id = b.account_id
      WHERE NOT EXISTS (
        SELECT 1 FROM cash_transactions c WHERE c.source_row_hash = b.source_row_hash
      )
    SQL

    execute <<~SQL
      INSERT INTO cash_transactions (
        id, account_id, amount, category_id, created_at, description,
        household_id, memo, merchant_id, post_date, raw_category, source,
        source_row_hash, transaction_date, transaction_type, updated_at
      )
      SELECT gen_random_uuid(), cc.account_id, cc.amount, cc.category_id, cc.created_at,
             cc.description, COALESCE(a.household_id, #{fallback_household}), cc.memo,
             cc.merchant_id, cc.post_date, cc.raw_category, 'credit_card',
             cc.source_row_hash, cc.transaction_date, cc.transaction_type, cc.updated_at
      FROM credit_card_transactions cc
      LEFT JOIN accounts a ON a.id = cc.account_id
      WHERE NOT EXISTS (
        SELECT 1 FROM cash_transactions c WHERE c.source_row_hash = cc.source_row_hash
      )
    SQL

    # Port tag joins across (matched through source_row_hash).
    execute <<~SQL
      INSERT INTO cash_transaction_tags (id, cash_transaction_id, tag_id, created_at, updated_at)
      SELECT gen_random_uuid(), c.id, jt.tag_id, NOW(), NOW()
      FROM bank_transaction_tags jt
      JOIN bank_transactions b ON b.id = jt.bank_transaction_id
      JOIN cash_transactions c ON c.source_row_hash = b.source_row_hash
      ON CONFLICT (cash_transaction_id, tag_id) DO NOTHING
    SQL

    execute <<~SQL
      INSERT INTO cash_transaction_tags (id, cash_transaction_id, tag_id, created_at, updated_at)
      SELECT gen_random_uuid(), c.id, jt.tag_id, NOW(), NOW()
      FROM credit_card_transaction_tags jt
      JOIN credit_card_transactions cc ON cc.id = jt.credit_card_transaction_id
      JOIN cash_transactions c ON c.source_row_hash = cc.source_row_hash
      ON CONFLICT (cash_transaction_id, tag_id) DO NOTHING
    SQL

    drop_table :bank_transaction_tags
    drop_table :credit_card_transaction_tags
    drop_table :bank_transactions
    drop_table :credit_card_transactions
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "legacy transaction tables were folded into cash_transactions"
  end
end
