# Sets Current.household and Current.user for each example, so factories
# that create household-scoped records get their household_id filled in
# automatically by HouseholdScoped#assign_household_from_current.
#
# Specs that need cross-household isolation (e.g. "a token from household A
# can't see household B's accounts") can create additional Household /
# HouseholdMembership records and Current.set(household: other) { ... } as
# needed.
RSpec.configure do |config|
  config.before(:each) do
    household = Household.first || Household.create!(name: "Test Household")
    user      = User.first      || User.create!(email: "test@example.com", name: "Test User")
    HouseholdMembership.find_or_create_by!(user: user, household: household) { |m| m.role = "admin" }
    Current.user      = user
    Current.household = household
  end

  config.after(:each) do
    Current.reset
  end
end
