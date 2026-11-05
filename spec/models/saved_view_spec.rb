require "rails_helper"

RSpec.describe SavedView, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:filter_params) }
  end
end
