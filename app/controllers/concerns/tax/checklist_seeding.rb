# typed: true

module Tax
  # Shared by the tax report + export endpoints (both GETs for a tax year).
  # A GET should not write on every load — the seeder is idempotent but
  # still issues one query (or insert) per candidate document. One cheap
  # existence check keeps the first-visit behavior (documents section
  # populated immediately) and makes every later GET write-free.
  module ChecklistSeeding
    extend ActiveSupport::Concern
    extend T::Sig

    private

    sig { params(household: Household).void }
    def seed_checklist_once(household)
      return if TaxChecklistItem.exists?(household_id: household.id, tax_year: year_param)

      ::Tax::ChecklistSeeder.ensure!(household: household, year: year_param)
    end
  end
end
