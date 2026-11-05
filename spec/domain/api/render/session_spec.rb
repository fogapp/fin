require "rails_helper"

# The frontend auth store reads this envelope from login, household switch,
# and household delete alike — pin the exact shape (keys and order) so a
# change to any one endpoint can't hand it a variant.
RSpec.describe Api::Render::Session do
  let(:user)      { create(:user, email: "pat@example.com", name: "Pat") }
  let(:household) { Household.create!(name: "Home") }
  let(:token)     { double("session token", raw_token: "tok_123") }

  describe "#serialize" do
    it "returns the token, user and household blocks" do
      json = described_class.new.serialize(user: user, household: household, token: token, role: Role::Admin).to_json

      expect(json).to eq({
        token: "tok_123",
        user: { id: user.id, email: "pat@example.com", name: "Pat" },
        household: { id: household.id, name: "Home", role: "admin" }
      }.to_json)
    end
  end

  describe "#me" do
    it "drops the token and adds the household settings" do
      json = described_class.new.me(user: user, household: household, role: nil).to_json

      expect(json).to eq({
        user: { id: user.id, email: "pat@example.com", name: "Pat" },
        household: {
          id: household.id, name: "Home", role: nil,
          workflow_log_level: household.workflow_log_level,
          include_unvested_equity: household.include_unvested_equity
        }
      }.to_json)
    end
  end
end
