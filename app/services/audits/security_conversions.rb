# typed: strict

module Audits
  # Proposes conversions the ledger never recorded (Instruments::
  # ConversionDetector) and keeps one open issue per suggestion; confirming
  # or dismissing a suggestion resolves its issue.
  class SecurityConversions
    extend T::Sig

    sig { void }
    def call
      Instruments::ConversionDetector.new.call
      suggested = SecurityConversion.suggested.includes(:from_security, :to_security).to_a
      suggested.each(&:raise_issue!)

      open_keys = suggested.map(&:issue_key).to_set
      Issue.active.where("key LIKE ?", "#{SecurityConversion::ISSUE_KEY_PREFIX}%").pluck(:key).each do |key|
        Issue.resolve!(key) unless open_keys.include?(key)
      end
    end
  end
end
