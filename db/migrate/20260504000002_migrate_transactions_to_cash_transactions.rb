# frozen_string_literal: true

class MigrateTransactionsToCashTransactions < ActiveRecord::Migration[8.1]
  def up
    # Migrate bank transactions
    execute <<~SQL
      INSERT INTO cash_transactions (
        source, account_id, amount, category_id, description, merchant_id,
        post_date, source_row_hash, transaction_date, transaction_type,
        balance, tran_code, tran_code_description,
        memo, raw_category,
        created_at, updated_at
      )
      SELECT
        'bank', account_id, amount, category_id, description, merchant_id,
        post_date, source_row_hash, transaction_date, transaction_type,
        balance, tran_code, tran_code_description,
        NULL, NULL,
        created_at, updated_at
      FROM bank_transactions
    SQL

    # Migrate credit card transactions
    execute <<~SQL
      INSERT INTO cash_transactions (
        source, account_id, amount, category_id, description, merchant_id,
        post_date, source_row_hash, transaction_date, transaction_type,
        balance, tran_code, tran_code_description,
        memo, raw_category,
        created_at, updated_at
      )
      SELECT
        'credit_card', account_id, amount, category_id, description, merchant_id,
        post_date, source_row_hash, transaction_date, transaction_type,
        NULL, NULL, NULL,
        memo, raw_category,
        created_at, updated_at
      FROM credit_card_transactions
    SQL

    # Migrate bank transaction tags
    execute <<~SQL
      INSERT INTO cash_transaction_tags (cash_transaction_id, tag_id, created_at, updated_at)
      SELECT ct.id, btt.tag_id, btt.created_at, btt.updated_at
      FROM bank_transaction_tags btt
      JOIN bank_transactions bt ON bt.id = btt.bank_transaction_id
      JOIN cash_transactions ct ON ct.source_row_hash = bt.source_row_hash AND ct.source = 'bank'
    SQL

    # Migrate credit card transaction tags
    execute <<~SQL
      INSERT INTO cash_transaction_tags (cash_transaction_id, tag_id, created_at, updated_at)
      SELECT ct.id, ctt.tag_id, ctt.created_at, ctt.updated_at
      FROM credit_card_transaction_tags ctt
      JOIN credit_card_transactions cct ON cct.id = ctt.credit_card_transaction_id
      JOIN cash_transactions ct ON ct.source_row_hash = cct.source_row_hash AND ct.source = 'credit_card'
    SQL
  end

  def down
    execute "DELETE FROM cash_transaction_tags"
    execute "DELETE FROM cash_transactions"
  end
end
