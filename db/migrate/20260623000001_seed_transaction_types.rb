class SeedTransactionTypes < ActiveRecord::Migration[8.1]
  TYPES = [
    { code: "BUY",  code_description: "Bought",           category: "Purchase" },
    { code: "SELL", code_description: "Sold",             category: "Sale" },
    { code: "DIV",  code_description: "Dividend",         category: "Dividend" },
    { code: "FDIV", code_description: "Foreign Dividend", category: "Foreign Dividend" },
    { code: "INT",  code_description: "Interest",         category: "Interest" },
    { code: "FEE",  code_description: "Advisory Fee",     category: "Fees" }
  ].freeze

  def up
    TYPES.each do |attrs|
      next if TransactionType.exists?(code: attrs[:code])
      TransactionType.create!(attrs)
    end
  end

  def down
    TransactionType.where(code: TYPES.map { |t| t[:code] }).destroy_all
  end
end
