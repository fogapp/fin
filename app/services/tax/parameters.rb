# typed: strict

module Tax
  # Pure constants for the exercise-planner tax engines, keyed by
  # (jurisdiction, tax_year, filing_status). v1 supports `single` and `mfj`
  # only. Each (jurisdiction, year) carries a figures_status flag —
  # :final when the authority has published the year's tables, :projected
  # when we are carrying forward the prior year's figures (CA 2026 until the
  # FTB publishes).
  #
  # Brackets are [rate, top-of-bracket] pairs over TAXABLE income; the last
  # bracket's top is nil (unbounded).
  module Parameters
    extend T::Sig

    class Missing < StandardError; end

    # ---------------------------------------------------------------- federal

    FEDERAL = T.let({
      2026 => {
        figures_status: :final, # Rev. Proc. 2025-32
        ordinary_brackets: {
          FilingStatus::Single => [
            [ 0.10,  12_400 ], [ 0.12,  50_400 ], [ 0.22, 105_700 ],
            [ 0.24, 201_775 ], [ 0.32, 256_225 ], [ 0.35, 640_600 ],
            [ 0.37, nil ]
          ],
          FilingStatus::Mfj => [
            [ 0.10,  24_800 ], [ 0.12, 100_800 ], [ 0.22, 211_400 ],
            [ 0.24, 403_550 ], [ 0.32, 512_450 ], [ 0.35, 768_700 ],
            [ 0.37, nil ]
          ]
        },
        # LTCG/QD rate breakpoints over taxable income (standard stacking).
        ltcg_brackets: {
          FilingStatus::Single => [ [ 0.0, 49_450 ], [ 0.15, 545_500 ], [ 0.20, nil ] ],
          FilingStatus::Mfj    => [ [ 0.0, 98_900 ], [ 0.15, 613_700 ], [ 0.20, nil ] ]
        },
        standard_deduction: { FilingStatus::Single => 16_100, FilingStatus::Mfj => 32_200 },
        amt: {
          exemption:          { FilingStatus::Single => 90_100,  FilingStatus::Mfj => 140_200 },
          phaseout_threshold: { FilingStatus::Single => 500_000, FilingStatus::Mfj => 1_000_000 },
          phaseout_rate:      0.50, # 50¢ of exemption lost per $ of AMTI over threshold (OBBBA)
          rate_low:           0.26,
          rate_high:          0.28,
          rate_breakpoint:    244_500 # taxable excess above this is taxed at 28%
        },
        salt: {
          cap:                40_400, # both statuses
          phasedown_start:    505_000, # MAGI
          phasedown_rate:     0.30,
          floor:              10_000
        },
        safe_harbor: {
          prior_year_multiplier_high_agi: 1.10,
          high_agi_threshold:             150_000,
          underpayment_threshold:         1_000
        },
        # Per-bucket contribution limits (tax center), keyed by the bucket
        # keys in CONTRIBUTION_BUCKETS and then filing status. Catch-up
        # contributions are ignored in v1.
        contribution_limits: {
          "401k"      => { FilingStatus::Single => 24_500, FilingStatus::Mfj => 24_500 }, # employee deferral (402(g))
          "ira"       => { FilingStatus::Single =>  7_500, FilingStatus::Mfj =>  7_500 },
          "hsa"       => { FilingStatus::Single =>  4_400, FilingStatus::Mfj =>  8_750 }, # filing status proxies self-only vs family
          "education" => { FilingStatus::Single => 19_000, FilingStatus::Mfj => 19_000 }  # per-donee gift exclusion (informational)
        }
      }
    }.freeze, T::Hash[Integer, T::Hash[Symbol, T.untyped]])

    # ------------------------------------------------------------ contributions

    # Year-independent bucket structure for contribution tracking; the
    # per-year dollar limits live in the federal parameter hash above.
    # Traditional and Roth 401(k)s share one employee deferral limit, as do
    # the two IRA flavors. Catch-up contributions are not modeled (v1).
    CONTRIBUTION_BUCKETS = T.let({
      "401k" => {
        label:         "401(k) employee deferral",
        treatments:    [ Account::TaxTreatment::Traditional401k, Account::TaxTreatment::Roth401k ],
        informational: false,
        note:          "Traditional + Roth 401(k) share one employee deferral limit; catch-up contributions not modeled (v1)"
      },
      "ira" => {
        label:         "IRA",
        treatments:    [ Account::TaxTreatment::TraditionalIra, Account::TaxTreatment::RothIra ],
        informational: false,
        note:          "Traditional + Roth IRA share one limit; catch-up contributions not modeled (v1)"
      },
      "hsa" => {
        label:         "HSA",
        treatments:    [ Account::TaxTreatment::Hsa ],
        informational: false,
        note:          "Filing status is used as a proxy for self-only vs family coverage"
      },
      "education" => {
        label:         "529 / education gifts",
        treatments:    [ Account::TaxTreatment::Education ],
        informational: true,
        note:          "Per-donee annual gift-tax exclusion — informational, not a hard contribution cap"
      }
    }.freeze, T::Hash[String, T::Hash[Symbol, T.untyped]])

    CONTRIBUTION_BUCKET_KEYS = T.let(CONTRIBUTION_BUCKETS.keys.freeze, T::Array[String])

    sig { params(bucket: String, tax_year: Integer, filing_status: FilingStatus).returns(T.nilable(Integer)) }
    def self.contribution_limit(bucket, tax_year, filing_status)
      federal(tax_year).dig(:contribution_limits, bucket, filing_status)
    end

    # ------------------------------------------------------------- california

    CA_2025_FIGURES = T.let({
      ordinary_brackets: {
        FilingStatus::Single => [
          [ 0.010,  11_079 ], [ 0.020,  26_264 ], [ 0.040,  41_451 ],
          [ 0.060,  57_543 ], [ 0.080,  72_723 ], [ 0.093, 371_479 ],
          [ 0.103, 445_771 ], [ 0.113, 742_953 ], [ 0.123, nil ]
        ],
        # MFJ bracket tops are exactly double the single tops.
        FilingStatus::Mfj => [
          [ 0.010,  22_158 ], [ 0.020,  52_528 ], [ 0.040,  82_902 ],
          [ 0.060, 115_086 ], [ 0.080, 145_446 ], [ 0.093, 742_958 ],
          [ 0.103, 891_542 ], [ 0.113, 1_485_906 ], [ 0.123, nil ]
        ]
      },
      # Behavioral Health Services Tax: +1% on taxable income over $1M
      # (the threshold is NOT doubled for MFJ).
      bhst: { rate: 0.01, threshold: 1_000_000 },
      standard_deduction: { FilingStatus::Single => 5_540, FilingStatus::Mfj => 11_080 },
      amt: {
        rate:               0.070,
        exemption:          { FilingStatus::Single => 92_749,  FilingStatus::Mfj => 123_667 },
        phaseout_threshold: { FilingStatus::Single => 347_808, FilingStatus::Mfj => 463_745 },
        phaseout_rate:      0.25
      },
      estimated_tax: {
        installment_weights:            [ 0.30, 0.40, 0.0, 0.30 ],
        prior_year_multiplier_high_agi: 1.10,
        high_agi_threshold:             150_000,
        safe_harbor_agi_ceiling:        1_000_000 # unavailable at/over $1M current-year CA AGI
      },
      supplemental_withholding_rate: 0.1023 # stock comp (for the NSO gap calc)
    }.freeze, T::Hash[Symbol, T.untyped])

    CALIFORNIA = T.let({
      2025 => CA_2025_FIGURES.merge(figures_status: :final),
      # FTB has not published 2026 tables yet — carry 2025 forward, flagged.
      2026 => CA_2025_FIGURES.merge(figures_status: :projected)
    }.freeze, T::Hash[Integer, T::Hash[Symbol, T.untyped]])

    # ----------------------------------------------------------------- lookup

    sig { params(tax_year: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def self.federal(tax_year)
      FEDERAL[tax_year] or
        raise Missing, "No federal tax parameters for #{tax_year}"
    end

    sig { params(tax_year: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def self.california(tax_year)
      CALIFORNIA[tax_year] or
        raise Missing, "No California tax parameters for #{tax_year}"
    end

    # NOTE: `jurisdiction` here names a parameter TABLE (:federal or
    # :california — CA is the only state implemented), not the record-level
    # Tax::Jurisdiction enum (federal/state/both); the two are deliberately
    # separate concepts.
    sig { params(jurisdiction: Symbol, tax_year: Integer).returns(Symbol) }
    def self.figures_status(jurisdiction, tax_year)
      case jurisdiction
      when :federal    then federal(tax_year).fetch(:figures_status)
      when :california then california(tax_year).fetch(:figures_status)
      else raise ArgumentError, "Unknown jurisdiction #{jurisdiction}"
      end
    end
  end
end
