# typed: true

# One expected (or received) tax document for a (household, tax_year).
# Auto-seeded rows come from Tax::ChecklistSeeder (brokers with activity →
# 1099s, active loans → 1098s, ISO exercises → 3921s, …) and are keyed by
# the [household, year, kind, source_label] unique index so re-seeding is
# idempotent; users add their own rows for anything Fin can't infer.
# Auto-seeded rows can't be deleted — mark them n_a instead, so the seeder
# doesn't resurrect them on the next report load.
class TaxChecklistItem < ApplicationRecord
  include HouseholdScoped
  # Feeds the cached tax report (render_cached), so writes must rotate the key.
  include BumpsHouseholdDataVersion

  # The document type expected/received for the year.
  class Kind < T::Enum
    include ApplicationEnum

    enums do
      W2                   = new("w2")
      Form1099Consolidated = new("1099_consolidated")
      Form1099Int          = new("1099_int")
      Form1099R            = new("1099_r")
      K1                   = new("k1")
      Form1098             = new("1098")
      Form3921             = new("3921")
      Form3922             = new("3922")
      Form5498             = new("5498")
      PropertyTax          = new("property_tax")
      CharitableReceipt    = new("charitable_receipt")
      Other                = new("other")
    end
  end

  # n_a is the durable dismissal for auto-seeded rows (deletes would just
  # be resurrected by the next re-seed).
  class Status < T::Enum
    include ApplicationEnum

    enums do
      Expected      = new("expected")
      Received      = new("received")
      Corrected     = new("corrected")
      NotApplicable = new("n_a")
    end
  end

  typed_enum :kind, Kind
  typed_enum :status, Status

  validates :tax_year, presence: true,
                       numericality: { only_integer: true, greater_than: 2000, less_than: 2100 }
  validates :source_label, presence: true,
                           uniqueness: { scope: %i[household_id tax_year kind] }
end
