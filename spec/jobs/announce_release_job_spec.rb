require "rails_helper"

RSpec.describe AnnounceReleaseJob, type: :job do
  let(:sha) { "eaa1efa0123456789abcdef0123456789abcdef0" }

  around do |example|
    original = ENV["GIT_SHA"]
    ENV["GIT_SHA"] = sha
    example.run
  ensure
    ENV["GIT_SHA"] = original
  end

  it "records the release and notifies every household" do
    other = create(:household)

    expect { described_class.perform_now }.to change(Release, :count).by(1)

    notifications = Notification.unscoped.where(title: "Fin updated")
    expect(notifications.pluck(:household_id)).to contain_exactly(Current.household.id, other.id)
    expect(notifications.first).to have_attributes(
      body: "Now running eaa1efa", severity: Severity::Info, href: "/settings#topic=about"
    )
  end

  it "does nothing when the release was already announced" do
    described_class.perform_now

    expect { described_class.perform_now }.not_to change(Notification.unscoped, :count)
  end

  it "does nothing without a GIT_SHA" do
    ENV["GIT_SHA"] = nil

    expect { described_class.perform_now }.not_to change(Release, :count)
  end
end
