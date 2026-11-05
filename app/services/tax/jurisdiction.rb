# typed: strict

module Tax
  # Which taxing authority a RECORD-level row counts toward: TaxAdjustment
  # accepts all three ("both" folds into each side of the year report);
  # EstimatedTaxPayment allows only Federal and State (a single payment
  # always goes to exactly one authority).
  #
  # Distinct from Tax::Parameters' internal :federal/:california symbols,
  # which name a parameter TABLE (California being the only state
  # implemented) — do not conflate the two.
  class Jurisdiction < T::Enum
    include ApplicationEnum

    enums do
      Federal = new("federal")
      State   = new("state")
      Both    = new("both")
    end
  end
end
