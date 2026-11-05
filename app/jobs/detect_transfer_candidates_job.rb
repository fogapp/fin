# typed: true

class DetectTransferCandidatesJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { params(household_id: T.nilable(String)).void }
  def perform(household_id: nil)
    scope = household_id ? Household.where(id: household_id) : Household.all
    each_household(scope: scope) { Transfers::CandidateDetector.new.call }
  end
end
