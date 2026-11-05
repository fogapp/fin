require "rails_helper"

RSpec.describe Recurring::DetectJob, type: :job do
  it "runs the full pipeline: matches accepted series, then suggests new ones" do
    accepted_merchant = create(:merchant, name: "Spotify")
    accepted = create(:recurring_series, :active,
                      merchant: accepted_merchant, series_key: "merchant:#{accepted_merchant.id}",
                      average_amount: 10.99, last_amount: 10.99, next_expected_date: Date.current)
    create(:recurring_occurrence, recurring_series: accepted,
           expected_date: Date.current, status: "due", expected_amount: 10.99)
    create(:cash_transaction, :credit_card, :sale,
           merchant: accepted_merchant, amount: -10.99, transaction_date: Date.current)

    new_merchant = create(:merchant, name: "Netflix")
    6.times do |i|
      create(:cash_transaction, :credit_card, :sale,
             merchant: new_merchant, amount: -15.99,
             transaction_date: (Date.current.beginning_of_month >> -(5 - i)) + 14)
    end

    expect { described_class.perform_now }.to change(RecurringSeries, :count).by(1)

    expect(accepted.reload.recurring_occurrences.paid_like.count).to eq(1)
    suggestion = RecurringSeries.suggested.sole
    expect(suggestion.name).to eq("Netflix")

    expect(ActivityEntry.where(source: "recurring_detection")).to exist
  end

  it "does not re-suggest what the matcher already attached" do
    merchant = create(:merchant)
    series = create(:recurring_series, :active,
                    merchant: merchant, series_key: "merchant:#{merchant.id}",
                    average_amount: 15.99, last_amount: 15.99, next_expected_date: Date.current)
    create(:recurring_occurrence, recurring_series: series,
           expected_date: Date.current, status: "due", expected_amount: 15.99)
    create(:cash_transaction, :credit_card, :sale,
           merchant: merchant, amount: -15.99, transaction_date: Date.current)

    expect { described_class.perform_now }.not_to change(RecurringSeries, :count)
  end
end
