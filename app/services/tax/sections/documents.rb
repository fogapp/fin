# typed: strict

module Tax
  module Sections
    # Document bookkeeping: the year's checklist items (1099s, receipts, …)
    # in a stable kind/source order.
    class Documents < Base
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build
        items = TaxChecklistItem.where(household_id: @context.household.id, tax_year: @context.year)
                                .order(:kind, :source_label)
                                .map { |item| @context.renderer.checklist_item(item) }

        { kind: "record", items: items }
      end
    end
  end
end
