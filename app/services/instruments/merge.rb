# typed: strict

module Instruments
  # Merges a duplicate Security into a keeper: repoints every dependent
  # record, resolving unique-index conflicts in the keeper's favor, then
  # removes the duplicate. Used by the identity migration and available for
  # manual cleanup of resolver-flagged conflicts.
  module Merge
    extend T::Sig

    sig { params(keep: Security, remove: Security).void }
    def self.call(keep:, remove:)
      raise ArgumentError, "cannot merge a security into itself" if keep.id == remove.id

      Security.transaction do
        InvestmentTransaction.unscoped.where(security_id: remove.id).update_all(security_id: keep.id)
        InvestmentLot.unscoped.where(security_id: remove.id).update_all(security_id: keep.id)
        SecurityNewsArticle.unscoped.where(security_id: remove.id).update_all(security_id: keep.id)

        merge_market_prices(keep, remove)
        merge_candles(keep, remove)
        merge_corporate_actions(keep, remove)
        merge_quotes(keep, remove)
        merge_data_links(keep, remove)
        merge_positions(keep, remove)
        merge_position_snapshots(keep, remove)
        merge_watches(keep, remove)
        merge_labels(keep, remove)
        merge_identifiers(keep, remove)

        SecurityOverview.unscoped.where(security_id: remove.id).delete_all if keep.overview.present?
        SecurityOverview.unscoped.where(security_id: remove.id).update_all(security_id: keep.id)

        # Read the richer metadata now, write it after the duplicate is gone:
        # cusip is unique, so adopting it while the duplicate still holds it
        # fails validation against the very row being removed.
        adopted = adoptable_attributes(keep, remove)
        remove.reload.destroy!
        keep.update!(adopted)
      end

      # The mass update_all/delete_all above skip the per-record after_commit
      # bump, so cached endpoints would keep serving the merged-away security.
      # Securities are global rows, so every household's caches may reference
      # them — rotate them all (coalesced; this is a rare manual operation).
      Household.unscoped.ids.each { |id| Households::DataVersion.bump_coalesced!(id) }
    end

    # The keeper's own values always win; blanks are filled from the duplicate.
    # No third row can hold the cusip — it is uniquely indexed — so once the
    # duplicate is destroyed the value is free.
    sig { params(keep: Security, remove: Security).returns(T::Hash[Symbol, T.untyped]) }
    def self.adoptable_attributes(keep, remove)
      {
        cusip: keep.cusip.presence || remove.cusip,
        name:  keep.name.presence || remove.name,
        slug:  keep.slug.presence || remove.slug
      }
    end
    private_class_method :adoptable_attributes

    sig { params(keep: Security, remove: Security).void }
    def self.merge_market_prices(keep, remove)
      keeper_dates = MarketPrice.unscoped.where(security_id: keep.id).select(:date)
      MarketPrice.unscoped.where(security_id: remove.id).where(date: keeper_dates).delete_all
      MarketPrice.unscoped.where(security_id: remove.id).update_all(security_id: keep.id)
    end
    private_class_method :merge_market_prices

    # unique (security_id, granularity, date): move the duplicate's history
    # where the keeper has none, keeper wins conflicts.
    sig { params(keep: Security, remove: Security).void }
    def self.merge_candles(keep, remove)
      Candle.where(security_id: remove.id)
            .where(<<~SQL.squish, keep.id)
              EXISTS (SELECT 1 FROM candles k
                      WHERE k.security_id = ?
                        AND k.granularity = candles.granularity
                        AND k.date = candles.date)
            SQL
            .delete_all
      Candle.where(security_id: remove.id).update_all(security_id: keep.id)
    end
    private_class_method :merge_candles

    # unique (security_id, kind, ex_date): keeper wins conflicts.
    sig { params(keep: Security, remove: Security).void }
    def self.merge_corporate_actions(keep, remove)
      CorporateAction.where(security_id: remove.id)
                     .where(<<~SQL.squish, keep.id)
                       EXISTS (SELECT 1 FROM corporate_actions k
                               WHERE k.security_id = ?
                                 AND k.kind = corporate_actions.kind
                                 AND k.ex_date = corporate_actions.ex_date)
                     SQL
                     .delete_all
      CorporateAction.where(security_id: remove.id).update_all(security_id: keep.id)
    end
    private_class_method :merge_corporate_actions

    # unique (security_id): the keeper's live quote wins; adopt the
    # duplicate's only when the keeper has none.
    sig { params(keep: Security, remove: Security).void }
    def self.merge_quotes(keep, remove)
      if InstrumentQuote.exists?(security_id: keep.id)
        InstrumentQuote.where(security_id: remove.id).delete_all
      else
        InstrumentQuote.where(security_id: remove.id).update_all(security_id: keep.id)
      end
    end
    private_class_method :merge_quotes

    # unique (security_id, capability): keeper's provider wiring wins.
    sig { params(keep: Security, remove: Security).void }
    def self.merge_data_links(keep, remove)
      InstrumentDataLink.where(security_id: remove.id).find_each do |link|
        if InstrumentDataLink.exists?(security_id: keep.id, capability: link.capability)
          link.destroy!
        else
          link.update_columns(security_id: keep.id)
        end
      end
    end
    private_class_method :merge_data_links

    # unique (account_id, security_id): keeper wins conflicts. Positions are
    # ledger-derived; a conflicting row's quantity is stale either way and the
    # next Positions::Rebuild (the transactions were repointed above)
    # recomputes it.
    sig { params(keep: Security, remove: Security).void }
    def self.merge_positions(keep, remove)
      Position.unscoped.where(security_id: remove.id).find_each do |position|
        if Position.unscoped.exists?(account_id: position.account_id, security_id: keep.id)
          position.destroy!
        else
          position.update_columns(security_id: keep.id)
        end
      end
    end
    private_class_method :merge_positions

    sig { params(keep: Security, remove: Security).void }
    def self.merge_position_snapshots(keep, remove)
      # unique (account_id, security_id, as_of_date): keeper wins conflicts.
      PositionSnapshot.unscoped.where(security_id: remove.id).find_each do |snap|
        if PositionSnapshot.unscoped.exists?(account_id: snap.account_id, security_id: keep.id,
                                             as_of_date: snap.as_of_date)
          snap.destroy!
        else
          snap.update_columns(security_id: keep.id)
        end
      end
    end
    private_class_method :merge_position_snapshots

    sig { params(keep: Security, remove: Security).void }
    def self.merge_watches(keep, remove)
      SecurityWatch.unscoped.where(security_id: remove.id).find_each do |watch|
        if SecurityWatch.unscoped.exists?(household_id: watch.household_id, security_id: keep.id)
          watch.destroy!
        else
          watch.update_columns(security_id: keep.id)
        end
      end
    end
    private_class_method :merge_watches

    # unique (household_id, security_id): the household's label for the keeper
    # wins; a label that only exists on the duplicate is adopted, so merging
    # never silently discards a name the user typed.
    sig { params(keep: Security, remove: Security).void }
    def self.merge_labels(keep, remove)
      SecurityLabel.unscoped.where(security_id: remove.id).find_each do |label|
        if SecurityLabel.unscoped.exists?(household_id: label.household_id, security_id: keep.id)
          label.destroy!
        else
          label.update_columns(security_id: keep.id)
        end
      end
    end
    private_class_method :merge_labels

    sig { params(keep: Security, remove: Security).void }
    def self.merge_identifiers(keep, remove)
      InstrumentIdentifier.unscoped.where(security_id: remove.id).find_each do |ident|
        if InstrumentIdentifier.unscoped.where(scheme: ident.scheme, value: ident.value)
                               .where.not(security_id: remove.id).exists?
          ident.destroy!
        else
          ident.update_columns(security_id: keep.id)
        end
      end
    end
    private_class_method :merge_identifiers
  end
end
