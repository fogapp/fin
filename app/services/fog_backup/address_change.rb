# typed: strict
# frozen_string_literal: true

module FogBackup
  # What a restore at a different address leaves behind. The data arrives
  # whole, but some of it was bound to where the instance used to live:
  # passkeys to their RP ID, Alchemy's webhooks to the old public URL. None
  # of that can be repaired from inside a boot — a passkey needs its owner's
  # device, and re-pointing webhooks would pull them away from a source
  # instance that may still be running — so each becomes an Issue that says
  # exactly what to do, in every restored household.
  #
  # Runs after db:prepare (the fog rake tasks), not inside the Restorer: an
  # artifact from older code is only migrated to this code's schema then.
  module AddressChange
    extend T::Sig

    MOVED_KEY = T.let("instance.address_changed", String)
    ALCHEMY_KEY = T.let("instance.address_changed.alchemy_webhooks", String)

    class Move < T::Struct
      const :from, String
      const :to, String
    end

    # A move is only declared when both ends are known. An instance that
    # derives its RP ID from requests and was staged by fog has no address to
    # compare at boot; guessing "moved" there would raise issues on a plain
    # same-address restore.
    sig { params(manifest: Manifest::Parsed, current_rp: T.nilable(String)).returns(T.nilable(Move)) }
    def self.detect(manifest, current_rp:)
      from = manifest.identity_rp_id
      return nil if from.nil? || current_rp.nil? || from.casecmp?(current_rp)

      Move.new(from: from, to: current_rp)
    end

    # The receipt carries the move across the migration; reconciled_at makes
    # a later plain restart a no-op.
    sig { void }
    def self.reconcile_pending!
      receipt = Staging.receipt
      return if receipt.nil? || receipt["moved_from"].blank? || receipt["moved_to"].blank?
      return if receipt["move_reconciled_at"].present?

      reconcile!(Move.new(from: receipt["moved_from"].to_s, to: receipt["moved_to"].to_s))
      Staging.receipt_path.write(JSON.pretty_generate(receipt.merge("move_reconciled_at" => Time.current.utc.iso8601)))
    rescue StandardError => e
      # The restore itself succeeded; failing the boot over a missing
      # reminder would turn a recovered instance into an unreachable one.
      Rails.logger.error("[fog] address-change reconciliation failed: #{e.class}: #{e.message}")
    end

    sig { params(move: Move).void }
    def self.reconcile!(move)
      # The same process loaded these models against the pre-migration schema.
      [ Household, Issue, AlchemyConfiguration ].each(&:reset_column_information)

      Household.find_each do |household|
        Current.set(household: household) do
          flag_passkeys(move)
          flag_alchemy_webhooks(move)
        end
      end
    end

    sig { params(move: Move).void }
    def self.flag_passkeys(move)
      Issue.raise_once!(
        key: MOVED_KEY,
        source: "backup",
        severity: Severity::Warning,
        title: "Fin moved from #{move.from} to #{move.to}",
        body: "This instance was restored from a backup taken at #{move.from}. Passkeys are bound to the address " \
          "they were registered on, so the ones from #{move.from} cannot sign in here. Give each household member " \
          "a sign-in link for #{move.to} (Settings → Backup → Moving to a new address) to register a new passkey; " \
          "the old ones can then be removed under Settings → Devices. API tokens and MCP clients keep working once " \
          "they are pointed at the new URL. Retire the old instance so the two don't both sync your accounts."
      )
    end
    private_class_method :flag_passkeys

    sig { params(move: Move).void }
    def self.flag_alchemy_webhooks(move)
      base = AlchemyConfiguration.first&.webhook_base_url.to_s
      return unless url_host(base)&.casecmp?(move.from)

      Issue.raise_once!(
        key: ALCHEMY_KEY,
        source: "backup",
        severity: Severity::Warning,
        title: "Alchemy webhooks still deliver to #{move.from}",
        body: "Real-time wallet activity is sent to #{base}, the address this instance was restored from. " \
          "Set the webhook base URL to this instance's address under Settings → Integrations → Alchemy; " \
          "saving re-registers the webhooks there."
      )
    end
    private_class_method :flag_alchemy_webhooks

    sig { params(url: String).returns(T.nilable(String)) }
    def self.url_host(url)
      URI.parse(url).host
    rescue URI::Error
      nil
    end
    private_class_method :url_host
  end
end
