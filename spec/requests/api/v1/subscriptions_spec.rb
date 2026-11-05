require "rails_helper"

RSpec.describe "Api::V1::Subscriptions", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  def create_active_series(name: "Netflix", amount: 15.99)
    create(:recurring_series, :active, name: name, average_amount: amount, last_amount: amount)
  end

  describe "GET /api/v1/subscriptions/calendar" do
    it "returns 401 without authentication" do
      get "/api/v1/subscriptions/calendar"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists the month's occurrences across tracked series, history included" do
      month = Date.current.beginning_of_month
      series = create_active_series
      create(:recurring_occurrence, :paid, recurring_series: series,
             expected_date: month + 4, charged_date: month + 4, amount: -15.99)
      create(:recurring_occurrence, recurring_series: series,
             expected_date: month + 20, status: "upcoming", expected_amount: 15.99)
      # Outside the month — must not appear
      create(:recurring_occurrence, recurring_series: series,
             expected_date: month.next_month + 3, status: "upcoming")
      # Ended series are not tracked
      ended = create(:recurring_series, :active, name: "Gone").tap { |s| s.update!(status: "ended") }
      create(:recurring_occurrence, recurring_series: ended, expected_date: month + 6, status: "upcoming")

      get "/api/v1/subscriptions/calendar",
          params: { month: month.strftime("%Y-%m") }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["month"]).to eq(month.strftime("%Y-%m"))
      expect(body["occurrences"].length).to eq(2)
      expect(body["occurrences"].first).to include(
        "name" => "Netflix", "series_id" => series.id, "status" => "paid"
      )
      expect(body["occurrences"].map { |o| o["name"] }).not_to include("Gone")
    end

    it "rejects a malformed month with a 400" do
      # A bad month is a malformed request (BaseController's Date::Error
      # handler), not a lifecycle error.
      get "/api/v1/subscriptions/calendar", params: { month: "nope" }, headers: auth_headers
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("month must be YYYY-MM")
    end

    it "does not include another household's occurrences" do
      Current.set(household: create(:household)) do
        series = create(:recurring_series, :active, name: "Theirs")
        create(:recurring_occurrence, recurring_series: series,
               expected_date: Date.current.beginning_of_month + 2, status: "upcoming")
      end

      get "/api/v1/subscriptions/calendar", headers: auth_headers
      expect(response.parsed_body["occurrences"]).to be_empty
    end
  end

  describe "GET /api/v1/subscriptions" do
    it "returns 401 without authentication" do
      get "/api/v1/subscriptions"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns active series with the household summary" do
      create_active_series
      create(:recurring_series) # suggested

      get "/api/v1/subscriptions", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["series"].length).to eq(1)
      expect(body["series"].first).to include(
        "id", "name", "status", "kind", "cadence_description", "average_amount",
        "monthly_equivalent", "annual_equivalent", "confidence_label",
        "next_expected_date", "at_risk", "timeline"
      )
      expect(body["summary"]).to include(
        "active_count" => 1, "suggested_count" => 1, "lapsed_count" => 0
      )
      expect(body["summary"]["monthly_total"]).to be_within(0.01).of(15.99)
    end

    it "filters by status" do
      create_active_series
      suggestion = create(:recurring_series)

      get "/api/v1/subscriptions", params: { status: "suggested" }, headers: auth_headers
      expect(response.parsed_body["series"].map { |s| s["id"] }).to eq([ suggestion.id ])
    end

    it "rejects unknown statuses" do
      get "/api/v1/subscriptions", params: { status: "banana" }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not leak other households' series" do
      other = create(:household)
      Current.set(household: other) { create(:recurring_series, :active) }

      get "/api/v1/subscriptions", headers: auth_headers
      expect(response.parsed_body["series"]).to eq([])
    end

    it "sums month_paid and month_remaining from this month's occurrences (SQL parity with the old Ruby sums)" do
      series = create_active_series
      month_start = Date.current.beginning_of_month
      create(:recurring_occurrence, :paid, recurring_series: series,
             expected_date: month_start, charged_date: month_start, amount: 15.99)
      create(:recurring_occurrence, recurring_series: series, status: "paid_amount_changed",
             expected_date: month_start + 1, charged_date: month_start + 1, amount: 20.01)
      create(:recurring_occurrence, recurring_series: series, status: "upcoming",
             expected_date: Date.current.end_of_month, expected_amount: 9.99)
      # Outside the month and non-active series: excluded from both sums.
      create(:recurring_occurrence, :paid, recurring_series: series,
             expected_date: month_start - 1, charged_date: month_start - 1, amount: 50.0)
      suggested = create(:recurring_series)
      create(:recurring_occurrence, recurring_series: suggested,
             expected_date: month_start + 2, expected_amount: 4.0)

      get "/api/v1/subscriptions", headers: auth_headers

      summary = response.parsed_body["summary"]
      expect(summary["month_paid"]).to be_within(0.001).of(36.0)
      expect(summary["month_remaining"]).to be_within(0.001).of(9.99)
    end

    it "caps the timeline at the 10 most recent settled occurrences plus the next pending one" do
      series = create_active_series
      15.times do |i|
        create(:recurring_occurrence, :paid, recurring_series: series,
               expected_date: Date.current - (i + 1).months,
               charged_date: Date.current - (i + 1).months, amount: 15.99)
      end
      create(:recurring_occurrence, recurring_series: series, expected_date: Date.current + 10)
      create(:recurring_occurrence, recurring_series: series, expected_date: Date.current + 3)

      get "/api/v1/subscriptions", headers: auth_headers

      timeline = response.parsed_body["series"].sole["timeline"]
      expect(timeline.length).to eq(11)
      settled = timeline.first(10)
      expect(settled.map { |o| o["status"] }.uniq).to eq([ "paid" ])
      # The 10 settled entries are the most recent ones, ascending.
      expect(settled.map { |o| Date.parse(o["expected_date"]) })
        .to eq((1..10).map { |i| Date.current - i.months }.reverse)
      # Exactly one pending entry — the earliest upcoming — appended last.
      expect(timeline.last["status"]).to eq("upcoming")
      expect(timeline.last["expected_date"]).to eq((Date.current + 3).iso8601)
    end
  end

  describe "GET /api/v1/subscriptions/:id" do
    it "returns the occurrence timeline with transaction info" do
      series = create_active_series
      txn = create(:cash_transaction, :credit_card, :sale, amount: -15.99, description: "NETFLIX.COM")
      create(:recurring_occurrence, :paid, recurring_series: series, cash_transaction: txn, amount: 15.99)
      create(:recurring_occurrence, recurring_series: series, expected_date: Date.current + 10)

      get "/api/v1/subscriptions/#{series.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      occurrences = response.parsed_body["occurrences"]
      expect(occurrences.length).to eq(2)
      paid = occurrences.find { |o| o["status"] == "paid" }
      expect(paid["transaction"]).to include("description" => "NETFLIX.COM")
    end
  end

  describe "lifecycle actions" do
    it "accepts a suggestion and schedules its next occurrence" do
      series = create(:recurring_series)

      post "/api/v1/subscriptions/#{series.id}/accept", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(series.reload.status).to eq(RecurringSeries::Status::Active)
      expect(series.recurring_occurrences.pending.count).to eq(1)
    end

    it "dismisses a suggestion and clears pending forecasts" do
      series = create(:recurring_series)
      create(:recurring_occurrence, recurring_series: series, expected_date: Date.current + 5)

      post "/api/v1/subscriptions/#{series.id}/dismiss", headers: auth_headers

      expect(series.reload.status).to eq(RecurringSeries::Status::Dismissed)
      expect(series.recurring_occurrences.pending.count).to eq(0)
    end

    it "ends an active subscription" do
      series = create_active_series

      post "/api/v1/subscriptions/#{series.id}/end", headers: auth_headers

      expect(series.reload.status).to eq(RecurringSeries::Status::Ended)
      expect(series.ended_at).to be_present
    end

    it "restores a dismissed series to the review queue" do
      series = create(:recurring_series)
      series.dismiss!

      post "/api/v1/subscriptions/#{series.id}/restore", headers: auth_headers
      expect(series.reload.status).to eq(RecurringSeries::Status::Suggested)
    end

    it "rejects invalid transitions with 422" do
      series = create(:recurring_series) # suggested

      post "/api/v1/subscriptions/#{series.id}/end", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/cannot move suggested/)
      expect(series.reload.status).to eq(RecurringSeries::Status::Suggested)
    end

    it "hard-deletes a series with its occurrences" do
      series = create_active_series
      create(:recurring_occurrence, recurring_series: series)

      expect {
        delete "/api/v1/subscriptions/#{series.id}", headers: auth_headers
      }.to change(RecurringSeries, :count).by(-1).and change(RecurringOccurrence, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /api/v1/subscriptions (manual creation)" do
    it "creates an active manual series from a transaction" do
      txn = create(:cash_transaction, :credit_card, :sale, amount: -8.99, description: "PATREON MEMBER")

      post "/api/v1/subscriptions", headers: auth_headers, params: {
        name: "Patreon", granularity: "month", quantity: 1,
        anchor: { day_of_month: txn.transaction_date.day },
        average_amount: 8.99, description_pattern: "PATREON MEMBER",
        cash_transaction_id: txn.id
      }

      expect(response).to have_http_status(:created)
      series = RecurringSeries.find(response.parsed_body["id"])
      expect(series.status).to eq(RecurringSeries::Status::Active)
      expect(series.source).to eq(RecurringSeries::Source::Manual)
      expect(series.recurring_occurrences.paid_like.sole.cash_transaction_id).to eq(txn.id)
      expect(series.recurring_occurrences.pending.count).to eq(1)
    end

    it "adopts earlier charges as history and forecasts from the latest" do
      history = [ Date.new(2026, 3, 5), Date.new(2026, 4, 5) ].map do |d|
        create(:cash_transaction, :credit_card, :sale, amount: -8.99, description: "PATREON MEMBER", transaction_date: d)
      end
      txn = create(:cash_transaction, :credit_card, :sale, amount: -8.99, description: "PATREON MEMBER",
                   transaction_date: Date.new(2026, 5, 5))
      tracked = create(:cash_transaction, :credit_card, :sale, amount: -8.99, transaction_date: Date.new(2026, 2, 5))
      create(:recurring_occurrence, :paid, cash_transaction: tracked)

      post "/api/v1/subscriptions", headers: auth_headers, params: {
        name: "Patreon", granularity: "month", quantity: 1, anchor: { day_of_month: 5 },
        average_amount: 8.99, description_pattern: "PATREON MEMBER",
        cash_transaction_id: txn.id, history_transaction_ids: [ *history.map(&:id), tracked.id ]
      }

      expect(response).to have_http_status(:created)
      series = RecurringSeries.find(response.parsed_body["id"])
      expect(series.recurring_occurrences.paid_like.pluck(:cash_transaction_id)).to match_array([ *history.map(&:id), txn.id ])
      expect(series.first_charge_date).to eq(Date.new(2026, 3, 5))
      expect(series.last_charge_date).to eq(Date.new(2026, 5, 5))
      expect(series.recurring_occurrences.pending.sole.expected_date).to eq(Date.new(2026, 6, 5))
    end
  end

  describe "PATCH /api/v1/subscriptions/:id" do
    it "updates editable fields" do
      series = create_active_series

      patch "/api/v1/subscriptions/#{series.id}", headers: auth_headers,
            params: { name: "Netflix Premium", notes: "cancel before March", amount_tolerance: 0.2 }

      expect(series.reload.name).to eq("Netflix Premium")
      expect(series.notes).to eq("cancel before March")
      expect(series.amount_tolerance.to_f).to eq(0.2)
    end

    it "reschedules pending occurrences when the cadence changes" do
      series = create_active_series
      create(:recurring_occurrence, recurring_series: series, expected_date: Date.current + 2)

      patch "/api/v1/subscriptions/#{series.id}", headers: auth_headers,
            params: { granularity: "month", quantity: 1, anchor: { day_of_month: 28 } }

      series.reload
      expect(series.recurring_occurrences.pending.sole.expected_date.day).to eq(28)
    end
  end

  describe "occurrence actions" do
    it "detaches a transaction, reverting past occurrences to missed" do
      series = create_active_series
      txn = create(:cash_transaction, :credit_card, :sale, amount: -15.99)
      occ = create(:recurring_occurrence, :paid, recurring_series: series, cash_transaction: txn)

      post "/api/v1/subscriptions/#{series.id}/occurrences/#{occ.id}/detach", headers: auth_headers

      expect(occ.reload.status).to eq(RecurringOccurrence::Status::Missed)
      expect(occ.cash_transaction_id).to be_nil
    end

    it "skips an occurrence" do
      series = create_active_series
      occ = create(:recurring_occurrence, recurring_series: series, expected_date: 5.days.ago.to_date, status: "missed")

      post "/api/v1/subscriptions/#{series.id}/occurrences/#{occ.id}/skip", headers: auth_headers

      expect(occ.reload.status).to eq(RecurringOccurrence::Status::Skipped)
    end
  end

  describe "GET /api/v1/subscriptions/upcoming" do
    it "lists pending occurrences of active series within the horizon" do
      series = create_active_series
      create(:recurring_occurrence, recurring_series: series, expected_date: Date.current + 5, status: "upcoming")
      create(:recurring_occurrence, recurring_series: series, expected_date: Date.current + 60, status: "upcoming")
      suggestion = create(:recurring_series)
      create(:recurring_occurrence, recurring_series: suggestion, expected_date: Date.current + 3)

      get "/api/v1/subscriptions/upcoming", headers: auth_headers

      body = response.parsed_body["upcoming"]
      expect(body.length).to eq(1)
      expect(body.first["series_id"]).to eq(series.id)
    end
  end
end
