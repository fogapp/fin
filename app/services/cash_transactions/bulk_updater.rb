# typed: strict

module CashTransactions
  class BulkUpdater
    extend T::Sig

    Result = Struct.new(:updated, :account_id, :merchant_id, :category_id, :tag_ids, keyword_init: true)

    sig do
      params(
        ids: T::Array[String], account_id: T.nilable(String), merchant_id: T.nilable(String),
        category_id: T.nilable(String), tag_ids: T.nilable(T::Array[String])
      ).void
    end
    def initialize(ids:, account_id: nil, merchant_id: nil, category_id: nil, tag_ids: [])
      @ids         = ids
      @account_id  = account_id
      @merchant_id = merchant_id
      @category_id = category_id
      @tag_ids     = T.let(Array(tag_ids).map(&:to_s).select(&:present?), T::Array[String])
    end

    sig { returns(CashTransactions::BulkUpdater::Result) }
    def call
      raise ArgumentError, "ids is required" if @ids.empty?

      # Count what actually exists (household-scoped) — the caller may pass
      # ids that were deleted or belong elsewhere, and "updated" must not
      # report rows that were never touched.
      found_ids = CashTransaction.where(id: @ids).pluck(:id).map(&:to_s)
      # Tags resolve through the household-scoped model before anything is
      # written, like the account/merchant/category below: the join rows go
      # in via insert_all (no validations), so another household's tag must
      # 404 rather than be linked.
      tag_ids = @tag_ids.any? ? Tag.find(@tag_ids.uniq).map(&:id) : []
      result = Result.new(updated: found_ids.size, account_id: nil, merchant_id: nil, category_id: nil, tag_ids: [])

      if @account_id.present?
        account = Account.find(@account_id)
        CashTransaction.where(id: found_ids).update_all(account_id: account.id)
        result.account_id = account.id
      end

      if @merchant_id.present?
        merchant = Merchant.find(@merchant_id)
        CashTransaction.where(id: found_ids).update_all(merchant_id: merchant.id)
        result.merchant_id = merchant.id
      end

      if @category_id.present?
        category = Category.find(@category_id)
        CashTransaction.where(id: found_ids).update_all(category_id: category.id)
        result.category_id = category.id
      end

      if tag_ids.any?
        existing = CashTransactionTag
          .where(cash_transaction_id: found_ids, tag_id: tag_ids)
          .pluck(:cash_transaction_id, :tag_id)
          .to_set

        rows = found_ids.flat_map do |txn_id|
          tag_ids.map do |tag_id|
            next if existing.include?([ txn_id, tag_id ])
            { cash_transaction_id: txn_id, tag_id: tag_id,
              created_at: Time.current, updated_at: Time.current }
          end.compact
        end

        CashTransactionTag.insert_all(rows) if rows.any?
        result.tag_ids = tag_ids
      end

      # update_all/insert_all skip callbacks, so cached endpoints must be
      # invalidated by hand.
      Households::DataVersion.bump!(Current.household&.id)

      result
    end
  end
end
