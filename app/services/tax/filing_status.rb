# typed: strict

module Tax
  # Filing statuses supported by the v1 tax engines (single and mfj only).
  # Tax::Parameters keys its per-status tables by these values, and
  # TaxProfile#filing_status reads as one, so an unsupported status can
  # never reach a bracket lookup.
  class FilingStatus < T::Enum
    include ApplicationEnum

    enums do
      Single = new("single")
      Mfj    = new("mfj")
    end
  end
end
