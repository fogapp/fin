# typed: strict

module Merchants
  class RuleMatcher
    extend T::Sig

    MatchResult = Struct.new(:merchant, :category, keyword_init: true)

    # Process-level cache, declared once here rather than re-asserted at every
    # assignment — a T.let per write both widened the assigned type and made
    # reset_cache's last expression nilable instead of nil.
    @compiled_rules = T.let(nil, T.untyped)
    @cache_stamp = T.let(nil, T.untyped)
    @cache_checked_at = T.let(nil, T.nilable(Float))

    # Returns the matching Merchant for a single description.
    sig { params(description: T.nilable(String)).returns(T.nilable(Merchant)) }
    def self.match(description)
      match_result(description)&.merchant
    end

    # Returns a MatchResult with both merchant and effective category
    # (rule-level category overrides merchant category).
    sig { params(description: T.nilable(String)).returns(T.nilable(Merchants::RuleMatcher::MatchResult)) }
    def self.match_result(description)
      return nil if description.blank?

      compiled_rules.each do |regex, merchant, category|
        if regex.match?(description)
          return MatchResult.new(merchant: merchant, category: category)
        end
      end

      nil
    end

    # Re-runs all rules against every transaction using a single pass:
    #   1. Load rules + merchants + categories into memory once.
    #   2. Pluck all transaction rows (no AR object overhead).
    #   3. Match each description against pre-compiled regexes.
    #   4. Group transaction IDs by (merchant_id, category_id) result.
    #   5. One UPDATE per distinct group — typically just a handful of queries.
    #
    # Rows no rule matches are left untouched (manual merchant/category
    # assignments survive a rematch); their raw statement category is only
    # used to fill a missing category, never to overwrite one.
    sig { returns(T::Hash[Symbol, Integer]) }
    def self.rematch_all
      reset_cache                          # ensure fresh rules on every bulk run
      rules      = compiled_rules          # [[Regexp, Merchant, Category], ...]
      cat_lookup = Category.pluck(:name, :id).to_h   # { name => id }

      matched = 0
      unmatched = 0

      groups = Hash.new { |h, k| h[k] = [] }
      fallback_groups = Hash.new { |h, k| h[k] = [] }

      CashTransaction.pluck(:id, :description, :raw_category).each do |id, description, raw_category|
        merchant = T.let(nil, T.nilable(Merchant))
        category = T.let(nil, T.nilable(Category))
        unless description.blank?
          rules.each do |regex, m, c|
            if regex.match?(description)
              merchant = m
              category = c
              break
            end
          end
        end

        if merchant
          groups[[ merchant.id, category&.id ]] << id
          matched += 1
        else
          unmatched += 1
          fallback_category_id = raw_category && cat_lookup[raw_category]
          fallback_groups[fallback_category_id] << id if fallback_category_id
        end
      end

      groups.each do |(merchant_id, category_id), ids|
        if category_id
          CashTransaction.where(id: ids).update_all(merchant_id: merchant_id, category_id: category_id)
        else
          CashTransaction.where(id: ids).update_all(merchant_id: merchant_id)
        end
      end

      fallback_groups.each do |category_id, ids|
        CashTransaction.where(id: ids, category_id: nil).update_all(category_id: category_id)
      end

      # update_all skips callbacks, so cached endpoints must be invalidated
      # by hand (same as CashTransactions::BulkUpdater).
      Households::DataVersion.bump!(Current.household&.id)

      { matched: matched, unmatched: unmatched }
    end

    private

    # How long the compiled-rules memo may be used before re-checking the DB
    # stamp. Keeps per-row matching cheap without letting long-lived worker
    # processes match against rules loaded at boot forever.
    CACHE_TTL_SECONDS = 10

    # Loads all valid rules ordered by priority desc, compiles each pattern
    # into a Regexp. Invalid patterns are silently skipped. Result is memoised
    # per process but invalidated when merchant rules change: at most every
    # CACHE_TTL_SECONDS we compare a (count, max updated_at) stamp and reload
    # if it moved. Call .reset_cache to force an immediate reload.
    sig { returns(T.untyped) }
    def self.compiled_rules
      # to_f: clock_gettime's return type widens to Integer for some unit
      # arguments, and the cache stamp is declared as a Float.
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f
      checked_at = @cache_checked_at
      if @compiled_rules.nil? || checked_at.nil? || (now - checked_at) > CACHE_TTL_SECONDS
        @cache_checked_at = now
        stamp = [ MerchantRule.count, MerchantRule.maximum(:updated_at) ]
        if @compiled_rules.nil? || stamp != @cache_stamp
          @cache_stamp = stamp
          @compiled_rules = load_rules
        end
      end
      @compiled_rules
    end

    sig { void }
    def self.reset_cache
      @compiled_rules = nil
      @cache_stamp = nil
      @cache_checked_at = nil
    end

    sig { returns(T.untyped) }
    def self.load_rules
      MerchantRule
        .includes(:category, merchant: :category)
        .order(priority: :desc, id: :asc)
        .filter_map do |rule|
          regex    = Regexp.new(rule.pattern, Regexp::IGNORECASE)
          category = rule.category || T.must(rule.merchant).category
          [ regex, rule.merchant, category ]
        rescue RegexpError
          nil
        end
    end
    private_class_method :load_rules
  end
end
