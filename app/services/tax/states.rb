# typed: strict

module Tax
  # The US states (plus DC) a tax profile can name, and where each one's
  # projected state tax comes from in the year report: California runs the
  # CA engine, states without a tax on wage income come out to zero, and
  # every other state needs the profile's entered projected state tax —
  # which, when given, also overrides the first two.
  module States
    extend T::Sig

    class Source < T::Enum
      enums do
        Modeled     = new("modeled")
        Entered     = new("entered")
        NoIncomeTax = new("no_income_tax")
      end
    end

    CALIFORNIA = "CA"

    NAMES = T.let({
      "AL" => "Alabama", "AK" => "Alaska", "AZ" => "Arizona", "AR" => "Arkansas",
      "CA" => "California", "CO" => "Colorado", "CT" => "Connecticut", "DE" => "Delaware",
      "DC" => "District of Columbia", "FL" => "Florida", "GA" => "Georgia", "HI" => "Hawaii",
      "ID" => "Idaho", "IL" => "Illinois", "IN" => "Indiana", "IA" => "Iowa",
      "KS" => "Kansas", "KY" => "Kentucky", "LA" => "Louisiana", "ME" => "Maine",
      "MD" => "Maryland", "MA" => "Massachusetts", "MI" => "Michigan", "MN" => "Minnesota",
      "MS" => "Mississippi", "MO" => "Missouri", "MT" => "Montana", "NE" => "Nebraska",
      "NV" => "Nevada", "NH" => "New Hampshire", "NJ" => "New Jersey", "NM" => "New Mexico",
      "NY" => "New York", "NC" => "North Carolina", "ND" => "North Dakota", "OH" => "Ohio",
      "OK" => "Oklahoma", "OR" => "Oregon", "PA" => "Pennsylvania", "RI" => "Rhode Island",
      "SC" => "South Carolina", "SD" => "South Dakota", "TN" => "Tennessee", "TX" => "Texas",
      "UT" => "Utah", "VT" => "Vermont", "VA" => "Virginia", "WA" => "Washington",
      "WV" => "West Virginia", "WI" => "Wisconsin", "WY" => "Wyoming"
    }.freeze, T::Hash[String, String])

    CODES = T.let(NAMES.keys.freeze, T::Array[String])

    # No tax on wage income. Washington's capital-gains excise is not
    # modeled — enter it as the projected state tax when it applies.
    NO_INCOME_TAX = T.let(%w[AK FL NH NV SD TN TX WA WY].freeze, T::Array[String])

    sig { params(code: String).returns(String) }
    def self.name_for(code)
      NAMES.fetch(code, code)
    end

    # Nil when the state needs an entered amount and has none.
    sig { params(code: String, projected_state_tax: T.untyped).returns(T.nilable(Source)) }
    def self.source(code, projected_state_tax)
      return Source::Entered unless projected_state_tax.nil?
      return Source::Modeled if code == CALIFORNIA
      return Source::NoIncomeTax if NO_INCOME_TAX.include?(code)

      nil
    end
  end
end
