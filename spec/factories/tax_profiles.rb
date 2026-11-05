FactoryBot.define do
  factory :tax_profile do
    tax_year { 2026 }
    filing_status { "single" }
    state { "CA" }
    projected_wages { 400_000 }
    other_ordinary_income { 0 }
    ltcg_qd_income { 0 }
    itemizing { false }
    salt_paid { 0 }
    itemized_other { 0 }
    ytd_withholding_federal { 0 }
    ytd_withholding_state { 0 }
  end
end
