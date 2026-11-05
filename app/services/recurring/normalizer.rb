# typed: strict

module Recurring
  # Cleans raw statement descriptions into a stable grouping key for
  # transactions that have no resolved merchant. Processor prefixes are
  # stripped BEFORE the *token pass so "PAYPAL *SPOTIFY" keys on SPOTIFY
  # instead of collapsing every PayPal charge into one group.
  module Normalizer
    extend T::Sig

    PROCESSOR_PREFIX = /\A(SQ\s*\*|TST\*\s*|PAYPAL\s*\*|PP\*|PY\s*\*|IN\s*\*)/i

    sig { params(desc: T.nilable(String)).returns(String) }
    def self.normalize(desc)
      s = desc.to_s.upcase
      s = s.sub(PROCESSOR_PREFIX, "")
      s = s.gsub(/\s+#?\d{4,}/, " ")                                # store/order/reference numbers
      s = s.gsub(%r{\b\d{2}[/\-]\d{2}(?:[/\-]\d{2,4})?\b}, "")      # embedded dates
      s = s.gsub(/\*\w+/, "")                                       # *token suffixes
      s.squeeze(" ").strip
    end
  end
end
