require "rails_helper"

RSpec.describe TaxScanJob, type: :job do
  let(:household) { Current.household }

  # Pin the clock so "current year" and day-offsets are deterministic:
  # April 1, 2026 is exactly 14 days before the Q1 due date (April 15).
  let(:today) { Date.new(2026, 4, 1) }

  before do
    %w[tax.quarterly_due_approaching tax.safe_harbor_behind tax.contribution_limit_approaching
       tax.document_overdue tax.wash_sale_detected].each do |type|
      create(:workflow, name: type, trigger_type: type)
    end
    Workflows::Events.reset_cache
  end

  def complete_profile(**attrs)
    create(:tax_profile, tax_year: 2026, projected_wages: 300_000,
           prior_year_total_tax: 40_000, prior_year_agi: 200_000,
           ytd_withholding_federal: 50_000, ytd_withholding_state: 50_000, **attrs)
  end

  def dispatches
    enqueued_jobs.select { |j| j["job_class"] == "Workflows::DispatchJob" }
                 .map { |j| j["arguments"].first(2) + [ j["arguments"][4] ] }
  end

  it "does nothing without a complete current-year profile" do
    travel_to(today) do
      create(:tax_profile, tax_year: 2026, projected_wages: 0)

      expect { described_class.perform_now }.not_to have_enqueued_job(Workflows::DispatchJob)
    end
  end

  it "publishes quarterly_due_approaching exactly 14 days out when the window has no payments" do
    travel_to(today) do
      complete_profile
      # A state Q1 payment silences the state event; federal still fires.
      create(:estimated_tax_payment, tax_year: 2026, jurisdiction: "state",
             paid_on: Date.new(2026, 3, 20), amount: 4_000)

      expect { described_class.perform_now }
        .to have_enqueued_job(Workflows::DispatchJob)
        .with("tax.quarterly_due_approaching", household.id.to_s, "Household", household.id.to_s,
              hash_including("jurisdiction" => "federal", "label" => "Q1", "date" => "2026-04-15"))

      state_events = dispatches.select { |type, _, payload|
        type == "tax.quarterly_due_approaching" && payload["jurisdiction"] == "state"
      }
      expect(state_events).to be_empty
    end
  end

  it "publishes quarterly_due_approaching 3 days out" do
    travel_to(Date.new(2026, 4, 12)) do
      complete_profile

      expect { described_class.perform_now }
        .to have_enqueued_job(Workflows::DispatchJob)
        .with("tax.quarterly_due_approaching", household.id.to_s, "Household", household.id.to_s,
              hash_including("jurisdiction" => "federal", "label" => "Q1"))
    end
  end

  it "publishes safe_harbor_behind per uncovered jurisdiction" do
    travel_to(today) do
      # 110% × 40,000 = 44,000 required; federal covered, state behind.
      complete_profile(ytd_withholding_federal: 50_000, ytd_withholding_state: 1_000)

      expect { described_class.perform_now }
        .to have_enqueued_job(Workflows::DispatchJob)
        .with("tax.safe_harbor_behind", household.id.to_s, "Household", household.id.to_s,
              hash_including("jurisdiction" => "state", "required_annual" => 44_000.0, "paid" => 1_000.0))

      federal_events = dispatches.select { |type, _, payload|
        type == "tax.safe_harbor_behind" && payload["jurisdiction"] == "federal"
      }
      expect(federal_events).to be_empty
    end
  end

  it "publishes contribution_limit_approaching in the 90–100% band only" do
    travel_to(today) do
      complete_profile
      # 23,000 / 24,500 = 93.9% → fires; HSA over the limit → silent.
      create(:tax_adjustment, kind: "contribution", bucket: "401k", label: "Payroll", amount: 23_000)
      create(:tax_adjustment, kind: "contribution", bucket: "hsa", label: "HSA", amount: 5_000)

      expect { described_class.perform_now }
        .to have_enqueued_job(Workflows::DispatchJob)
        .with("tax.contribution_limit_approaching", household.id.to_s, "Household", household.id.to_s,
              hash_including("bucket" => "401k", "contributed" => 23_000.0, "limit" => 24_500))

      hsa_events = dispatches.select { |type, _, payload|
        type == "tax.contribution_limit_approaching" && payload["bucket"] == "hsa"
      }
      expect(hsa_events).to be_empty
    end
  end

  it "publishes document_overdue for expected items past their window (prior tax year)" do
    travel_to(today) do
      complete_profile
      create(:tax_checklist_item, tax_year: 2025, kind: "w2", source_label: "Employer",
             status: "expected") # deadline Feb 15, 2026 — overdue
      create(:tax_checklist_item, tax_year: 2025, kind: "1099_consolidated", source_label: "Vanguard",
             status: "received") # already received — silent
      create(:tax_checklist_item, tax_year: 2026, kind: "1098", source_label: "Home Loan",
             status: "expected") # deadline Feb 15, 2027 — not yet due

      expect { described_class.perform_now }
        .to have_enqueued_job(Workflows::DispatchJob)
        .with("tax.document_overdue", household.id.to_s, "Household", household.id.to_s,
              hash_including("kind" => "w2", "source_label" => "Employer", "tax_year" => 2025))

      overdue = dispatches.select { |type, _, _| type == "tax.document_overdue" }
      expect(overdue.length).to eq(1)
    end
  end

  it "publishes wash_sale_detected for findings with a sale in the last 45 days" do
    travel_to(today) do
      complete_profile
      tt_sale     = create(:transaction_type, :sale)
      tt_purchase = create(:transaction_type, :purchase)
      brokerage   = create(:account, name: "Brokerage")
      ira         = create(:account, name: "IRA", tax_treatment: "traditional_ira")
      security    = create(:security, ticker: "AAA")

      create(:investment_transaction, account: brokerage, transaction_type: tt_sale,
             security: security, trade_date: Date.new(2026, 3, 20), gl_short_usd: -400)
      create(:investment_transaction, account: ira, transaction_type: tt_purchase,
             security: security, trade_date: Date.new(2026, 3, 25))

      # An old finding (sale > 45 days ago) stays quiet.
      create(:investment_transaction, account: brokerage, transaction_type: tt_sale,
             security: security, trade_date: Date.new(2026, 1, 10), gl_short_usd: -100)
      create(:investment_transaction, account: brokerage, transaction_type: tt_purchase,
             security: security, trade_date: Date.new(2026, 1, 15))

      expect { described_class.perform_now }
        .to have_enqueued_job(Workflows::DispatchJob)
        .with("tax.wash_sale_detected", household.id.to_s, "Household", household.id.to_s,
              hash_including("security_label" => "AAA", "sale_date" => "2026-03-20",
                             "purchase_account" => "IRA", "loss" => -400.0, "permanent" => true))

      wash_events = dispatches.select { |type, _, _| type == "tax.wash_sale_detected" }
      expect(wash_events.length).to eq(1)
    end
  end
end
