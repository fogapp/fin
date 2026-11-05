# typed: strict

module Reconciliation
  # How a ledger/custodian pair disagrees: the side that's empty names the
  # finding; both non-zero is plain quantity drift.
  class FindingKind < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      MissingFromLedger = new("missing_from_ledger")
      MissingFromCustodian = new("missing_from_custodian")
      QuantityDrift = new("quantity_drift")
    end
  end
end
