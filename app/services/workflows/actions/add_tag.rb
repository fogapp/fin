# typed: strict

module Workflows
  module Actions
    class AddTag < T::Struct
      # Scalar or array — the bulk path and migrated rule data store arrays.
      const :tag_id, T.untyped

      sig { params(resource: T.untyped, dry_run: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def execute(resource, dry_run: false)
        tag_ids = Array(tag_id).compact
        # The subject's own household, not whatever Current says: tag ids come
        # from stored step config, and a join row is never validated.
        tags = Tag.unscoped.where(household_id: resource.household_id, id: tag_ids).to_a
        missing = tag_ids - tags.map(&:id)
        return { status: :error, error: "Tag #{missing.join(', ')} not found" } if missing.any?
        return { status: :error, error: "No tag given" } if tags.empty?

        join_class = tagging_class_for(resource)
        return { status: :error, error: "No tagging join for #{resource.class.name}" } unless join_class

        fk = fk_for(resource)
        applied = tags.reject { |tag| join_class.exists?(tag_id: tag.id, fk => resource.id) }
        return { status: :skipped, reason: "tags already applied" } if applied.empty?

        applied.each { |tag| join_class.create!(tag_id: tag.id, fk => resource.id) } unless dry_run
        { status: :applied, changes: { tag_id: applied.map(&:id), tag_name: applied.map(&:name).join(", ") } }
      end

      private

      TAGGING_MAP = T.let({
        "CashTransaction"        => { join: CashTransactionTag,       fk: :cash_transaction_id },
        "InvestmentTransaction"  => nil
      }.freeze, T::Hash[String, T.untyped])

      sig { params(resource: T.untyped).returns(T.untyped) }
      def tagging_class_for(resource)
        TAGGING_MAP.dig(resource.class.name, :join)
      end

      sig { params(resource: T.untyped).returns(T.untyped) }
      def fk_for(resource)
        TAGGING_MAP.dig(resource.class.name, :fk)
      end
    end
  end
end
