require "rails_helper"

RSpec.describe EquityVestScanJob, type: :job do
  let(:household) { Current.household }
  let(:company)   { create(:equity_company) }

  before do
    create(:equity_fmv_entry, equity_company: company, price_per_share: 10,
           effective_date: Date.current - 1.month)
    create(:workflow, name: "Vest upcoming", trigger_type: "equity.vest_upcoming")
    create(:workflow, name: "Vest occurred", trigger_type: "equity.vest_occurred")
    create(:workflow, name: "Grant expiring", trigger_type: "equity.grant_expiring")
    Workflows::Events.reset_cache
  end

  def rsu_with_tranches(*dates)
    create(:equity_grant, :rsu, equity_company: company, quantity: dates.size * 10,
           vesting_interval: nil, vesting_occurrences: nil, cliff_installments: 0,
           grant_date: Date.current - 1.year,
           custom_tranches: dates.map { |d| { "date" => d.iso8601, "quantity" => 10 } })
  end

  it "publishes vest_upcoming for tranches exactly 14 and 1 days out" do
    grant = rsu_with_tranches(Date.current + 14, Date.current + 1,
                              Date.current + 7, Date.current + 100)

    expect { described_class.perform_now }
      .to have_enqueued_job(Workflows::DispatchJob)
      .with("equity.vest_upcoming", household.id.to_s, "EquityGrant", grant.id.to_s,
            hash_including("tranche_date" => (Date.current + 14).iso8601,
                           "quantity" => 10.0, "value" => 100.0))
      .and have_enqueued_job(Workflows::DispatchJob)
      .with("equity.vest_upcoming", household.id.to_s, "EquityGrant", grant.id.to_s,
            hash_including("tranche_date" => (Date.current + 1).iso8601))
  end

  it "publishes vest_occurred for tranches vesting today" do
    grant = rsu_with_tranches(Date.current, Date.current + 30)

    expect { described_class.perform_now }
      .to have_enqueued_job(Workflows::DispatchJob)
      .with("equity.vest_occurred", household.id.to_s, "EquityGrant", grant.id.to_s,
            hash_including("tranche_date" => Date.current.iso8601, "value" => 100.0))
  end

  it "publishes grant_expiring at exactly 90 and 30 days before expiration" do
    expiring_90 = create(:equity_grant, equity_company: company, grant_date: Date.current - 5.years,
                         expiration_date: Date.current + 90)
    expiring_30 = create(:equity_grant, equity_company: company, grant_date: Date.current - 5.years,
                         expiration_date: Date.current + 30)
    create(:equity_grant, equity_company: company, grant_date: Date.current - 5.years,
           expiration_date: Date.current + 45)

    expect { described_class.perform_now }
      .to have_enqueued_job(Workflows::DispatchJob)
      .with("equity.grant_expiring", household.id.to_s, "EquityGrant", expiring_90.id.to_s,
            hash_including("days_until" => 90))
      .and have_enqueued_job(Workflows::DispatchJob)
      .with("equity.grant_expiring", household.id.to_s, "EquityGrant", expiring_30.id.to_s,
            hash_including("days_until" => 30))
  end

  it "publishes nothing when no tranche or expiration hits an exact offset" do
    rsu_with_tranches(Date.current + 2, Date.current + 15, Date.current - 1)

    expect { described_class.perform_now }.not_to have_enqueued_job(Workflows::DispatchJob)
  end

  describe "exercise window closing (the Dec 31 same-year-sale escape hatch)" do
    before do
      create(:workflow, name: "Window closing", trigger_type: "equity.exercise_window_closing")
      Workflows::Events.reset_cache
    end

    def exercised_grant
      create(:equity_grant, :fully_vested, equity_company: company, quantity: 100,
             grant_date: Date.current - 2.years)
    end

    it "publishes on Dec 1 for grants exercised this year with unsold shares" do
      dec_1 = Date.new(Date.current.year, 12, 1)
      grant = exercised_grant
      create(:equity_grant_event, equity_grant: grant, kind: "exercise", quantity: 30,
             occurred_on: dec_1 - 2.months)

      travel_to(dec_1) do
        expect { described_class.perform_now }
          .to have_enqueued_job(Workflows::DispatchJob)
          .with("equity.exercise_window_closing", household.id.to_s, "EquityGrant", grant.id.to_s,
                { "year_end" => "#{dec_1.year}-12-31", "exercised_this_year" => 30.0 })
      end
    end

    it "skips grants whose exercised shares were all sold" do
      dec_1 = Date.new(Date.current.year, 12, 1)
      grant = exercised_grant
      create(:equity_grant_event, equity_grant: grant, kind: "exercise", quantity: 20,
             occurred_on: dec_1 - 2.months)
      create(:equity_grant_event, equity_grant: grant, kind: "sale", quantity: 20,
             occurred_on: dec_1 - 1.month)

      travel_to(dec_1) do
        expect { described_class.perform_now }.not_to have_enqueued_job(Workflows::DispatchJob)
          .with("equity.exercise_window_closing", any_args)
      end
    end

    it "skips grants exercised only in prior years" do
      dec_1 = Date.new(Date.current.year, 12, 1)
      grant = exercised_grant
      create(:equity_grant_event, equity_grant: grant, kind: "exercise", quantity: 30,
             occurred_on: dec_1 - 14.months)

      travel_to(dec_1) do
        expect { described_class.perform_now }.not_to have_enqueued_job(Workflows::DispatchJob)
          .with("equity.exercise_window_closing", any_args)
      end
    end

    it "publishes only on Dec 1" do
      grant = exercised_grant
      year = Date.current.year
      create(:equity_grant_event, equity_grant: grant, kind: "exercise", quantity: 30,
             occurred_on: Date.new(year, 10, 1))

      [ Date.new(year, 11, 30), Date.new(year, 12, 2), Date.new(year, 12, 31) ].each do |day|
        travel_to(day) do
          expect { described_class.perform_now }.not_to have_enqueued_job(Workflows::DispatchJob)
            .with("equity.exercise_window_closing", any_args)
        end
      end
    end
  end

  it "publishes a nil value when the company has no price" do
    unpriced = create(:equity_company)
    grant = create(:equity_grant, :rsu, equity_company: unpriced, quantity: 10,
                   vesting_interval: nil, vesting_occurrences: nil, cliff_installments: 0,
                   grant_date: Date.current - 1.year,
                   custom_tranches: [ { "date" => (Date.current + 1).iso8601, "quantity" => 10 } ])

    expect { described_class.perform_now }
      .to have_enqueued_job(Workflows::DispatchJob)
      .with("equity.vest_upcoming", household.id.to_s, "EquityGrant", grant.id.to_s,
            hash_including("value" => nil))
  end
end
