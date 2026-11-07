# typed: strict

module CashTransactions
  # The single param→scope translation for filtering cash transactions,
  # shared by the transaction list renderer and the cashflow renderer's
  # scoping. Each param has exactly one semantic here:
  #
  #   source, merchant_id, account_id, loan_id, transaction_type —
  #     exact-match column filters.
  #   category_ids — comma-separated list of exact category ids; takes
  #     precedence over category_id when both are sent.
  #   category_id — the category's rollup: the id itself plus its direct
  #     children, because detail pages show a parent together with its
  #     subcategories while the URL carries one id.
  #   tag_id — rows carrying the tag (via cash_transaction_tags).
  #   exclude_tag_ids — comma-separated tag ids; drops rows carrying any of
  #     them (e.g. analyze spending without the vacation). A view-time
  #     filter only — nothing about the rows themselves changes.
  #   description — case-insensitive substring match, LIKE-escaped so
  #     searching "50% off" matches that literal text.
  #   start_date / end_date (aliases: from / to) — inclusive date window.
  #     The explicit names win over the aliases when both are sent.
  #
  # Callers that only honor a subset (cashflow scoping is account/tag/
  # category only — its date windows are computed per-metric, not from a
  # blanket row filter) pass `only:` to whitelist keys.
  class Filter
    extend T::Sig

    # The scoping subset the cashflow renderer honors. merchant_id is here
    # for the merchant detail pages' spend chart, which scopes the
    # spend_breakdown endpoint by merchant.
    SCOPE_KEYS = T.let([ :account_id, :tag_id, :exclude_tag_ids, :category_id, :merchant_id ].freeze, T::Array[Symbol])

    sig { params(params: T.untyped).void }
    def initialize(params)
      @params = params
    end

    sig { params(scope: T.untyped, only: T.nilable(T::Array[Symbol])).returns(T.untyped) }
    def relation(scope, only: nil)
      active = ->(key) { (only.nil? || only.include?(key)) && @params[key].present? }

      scope = scope.where(source: @params[:source])                     if active.call(:source)
      scope = scope.where(merchant_id: @params[:merchant_id])           if active.call(:merchant_id)
      scope = scope.where(account_id: @params[:account_id])             if active.call(:account_id)
      scope = scope.where(loan_id: @params[:loan_id])                   if active.call(:loan_id)
      scope = scope.where(transaction_type: @params[:transaction_type]) if active.call(:transaction_type)

      if active.call(:category_ids)
        scope = scope.where(category_id: @params[:category_ids].split(","))
      elsif active.call(:category_id)
        scope = scope.where(category_id: category_rollup_ids)
      end

      if active.call(:tag_id)
        scope = scope.joins(:cash_transaction_tags)
                     .where(cash_transaction_tags: { tag_id: @params[:tag_id] })
      end

      if active.call(:exclude_tag_ids)
        # Anti-join via subquery rather than a join: a row carrying two
        # excluded tags must drop once, not fan out.
        scope = scope.where.not(
          id: CashTransactionTag.where(tag_id: @params[:exclude_tag_ids].to_s.split(",")).select(:cash_transaction_id)
        )
      end

      if active.call(:description)
        # sanitize_sql_like escapes % and _ in the user's text, so searching
        # for "50% off" matches that literal string instead of turning the
        # wildcard loose and matching everything after "50".
        term = ActiveRecord::Base.sanitize_sql_like(@params[:description].to_s)
        scope = scope.where("description ILIKE ?", "%#{term}%")
      end

      from = date_bound(:start_date, :from, only)
      to   = date_bound(:end_date, :to, only)
      scope = scope.where("transaction_date >= ?", from) if from
      scope = scope.where("transaction_date <= ?", to)   if to

      scope
    end

    private

    # First parseable of the canonical param and its alias. Malformed input
    # raises Date::Error, which the base controller maps to a 400.
    sig { params(key: Symbol, alias_key: Symbol, only: T.nilable(T::Array[Symbol])).returns(T.nilable(Date)) }
    def date_bound(key, alias_key, only)
      [ key, alias_key ].each do |k|
        next if only && !only.include?(k)
        return Date.parse(@params[k].to_s) if @params[k].present?
      end
      nil
    end

    # A category filter means the category's rollup — itself plus its direct
    # children — so a parent's page covers its subcategories' rows too.
    sig { returns(T::Array[String]) }
    def category_rollup_ids
      @category_rollup_ids ||= T.let(
        [ @params[:category_id].to_s, *Category.where(parent_id: @params[:category_id]).pluck(:id) ],
        T.nilable(T::Array[String])
      )
    end
  end
end
