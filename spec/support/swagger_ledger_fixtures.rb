# Fully-populated ledger records for the swagger specs. Strict response
# validation only checks the fields a response actually carries, so an
# example built from bare factories (nil category, no tags, no transfer)
# would let a wrong nested schema pass unnoticed.
module SwaggerLedgerFixtures
  # A bank debit with every association the serializer reads filled in:
  # subcategory (so category_parent_name is set), merchant, account, loan,
  # a tag, and a confirmed transfer to a second account.
  def rich_cash_transaction(**overrides)
    parent   = create(:category, name: "Home #{SecureRandom.hex(2)}")
    category = create(:category, name: "Utilities", parent: parent)
    account  = create(:account)
    txn = create(:cash_transaction, :bank, :debit,
                 account: account, category: category, merchant: create(:merchant, category: category),
                 loan: create(:loan), memo: "Quarterly", post_date: Date.current, **overrides)
    txn.tags << create(:tag)

    counterpart = create(:cash_transaction, :bank, :credit, account: create(:account), amount: -txn.amount)
    create(:transfer, from_transaction_id: txn.id, from_transaction_type: "CashTransaction",
                      to_transaction_id: counterpart.id, to_transaction_type: "CashTransaction",
                      amount: txn.amount.abs, note: "Moved to savings").confirm!
    txn.reload
  end

  # A purchase with account, security and transaction type populated.
  def rich_investment_transaction(**overrides)
    create(:investment_transaction,
           transaction_type: create(:transaction_type, :purchase, code: "P#{SecureRandom.hex(3)}"),
           description: "BOUGHT 10 SHARES", cost_usd: 100.0, **overrides)
  end
end

RSpec.configure { |config| config.include SwaggerLedgerFixtures, type: :request }
