# typed: strict

module Workflows
  module Actions
    # Shared execute body for the single-column actions (assign_account,
    # assign_category, assign_merchant, set_memo, set_loan). Each includer
    # is a T::Struct that declares its value via `const` and wires it to a
    # column with the `sets_column` macro.
    module SetsColumn
      extend T::Sig

      extend T::Helpers

      module ClassMethods
        extend T::Sig

        # Declares which column this action writes. `from:` names the struct
        # const holding the new value (defaults to the column name);
        # `skip_reason:` overrides the default skip message when the column
        # already holds the value.
        sig { params(column: Symbol, from: Symbol, skip_reason: T.nilable(String)).void }
        def sets_column(column, from: column, skip_reason: nil)
          @sets_column_config = T.let(
            { column: column, from: from, skip_reason: skip_reason },
            T.nilable(T::Hash[Symbol, T.untyped])
          )
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def sets_column_config
          @sets_column_config || raise("#{name} must declare sets_column")
        end
      end

      mixes_in_class_methods(ClassMethods)

      sig { params(resource: T.untyped, dry_run: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def execute(resource, dry_run: false)
        config = self.class.sets_column_config
        column = T.let(config.fetch(:column), Symbol)
        new_value = public_send(config.fetch(:from))
        old_value = resource.public_send(column)
        if old_value == new_value
          reason = config[:skip_reason] || "#{column} already set to #{new_value}"
          return { status: :skipped, reason: reason }
        end

        unless references_own_household?(resource, column, new_value)
          return { status: :error, error: "#{column.to_s.delete_suffix('_id')} #{new_value} not found" }
        end

        unless dry_run
          resource.update_columns(column => new_value)
          # update_columns skips the after_commit bump — rotate the cached
          # endpoints' version (coalesced per run/job) or they serve stale data.
          Households::DataVersion.bump_coalesced!(resource.household_id)
        end
        { status: :applied, changes: { column => [ old_value, new_value ] } }
      end

      private

      # update_columns skips validations, so HouseholdScoped's reference
      # check never sees this write: an id from the step config (stored JSON,
      # editable through the API) must name a row of the subject's own
      # household — otherwise a workflow could link a transaction to another
      # household's account, merchant, category or loan.
      sig { params(resource: T.untyped, column: Symbol, value: T.untyped).returns(T::Boolean) }
      def references_own_household?(resource, column, value)
        return true if value.nil?

        reflection = resource.class.reflect_on_all_associations(:belongs_to)
                             .find { |r| !r.polymorphic? && r.foreign_key.to_s == column.to_s }
        return true unless reflection && reflection.klass.include?(HouseholdScoped)

        reflection.klass.unscoped.where(id: value, household_id: resource.household_id).exists?
      end
    end
  end
end
