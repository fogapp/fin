# typed: strict
# frozen_string_literal: true

module FogBackup
  # After a restore the operator made knowing the secrets the artifact was
  # written with are gone (fog:docs/backup-contract.md, "Restoring without the
  # original secrets"): every value Active Record encryption wrote under the
  # old keys is ciphertext nothing can read, and reading one raises. Clear
  # them all so Fin boots and says what needs entering again.
  #
  # A nullable attribute becomes nil. A required one needs a rule saying how
  # the row survives without it; an encrypted attribute that is required and
  # has no rule fails the restore (and the spec), so a new one cannot slip
  # through unhandled.
  module ForgetSecrets
    extend T::Sig

    class Error < StandardError; end

    # What a required credential holds once forgotten: readable under the new
    # keys, and useless to the service it was for.
    FORGOTTEN = "forgotten-on-restore"

    # Required encrypted attributes, by model: what clearing means for them.
    REQUIRED = T.let({
      # A linked institution. Its history (accounts, transactions) stays; the
      # access token that let Fin sync it does not. The item is marked in
      # error with the reason, so it shows as needing to be linked again.
      "PlaidItem" => lambda do |model|
        model.unscoped.update_all(
          # update_all casts through the attribute type, so this is
          # encrypted under the new keys on its way in.
          access_token: FORGOTTEN,
          status: "error",
          error_message: "Link this institution again: its access token was lost when Fin was restored without its original secrets"
        )
      end
    }.freeze, T::Hash[String, T.proc.params(model: T.class_of(ApplicationRecord)).void])

    # Clears every encrypted attribute and answers what was cleared, as
    # model name => attribute names.
    sig { returns(T::Hash[String, T::Array[String]]) }
    def self.run!
      Rails.application.eager_load!
      forgotten = T.let({}, T::Hash[String, T::Array[String]])
      ApplicationRecord.descendants.reject(&:abstract_class?).sort_by(&:name).each do |model|
        attrs = model.encrypted_attributes.to_a.map(&:to_s).sort
        next if attrs.empty? || !model.table_exists?

        model.reset_column_information
        nullable, required = attrs.partition { |a| model.columns_hash.fetch(a).null }
        model.unscoped.update_all(nullable.index_with(nil)) if nullable.any?
        if required.any?
          rule = REQUIRED[model.name]
          raise Error, "#{model.name}.#{required.join(", ")} is encrypted and required, with no rule for forgetting it" if rule.nil?

          rule.call(model)
        end
        forgotten[model.name] = attrs
      end
      forgotten
    end
  end
end
