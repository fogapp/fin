# typed: strict

module Tax
  module Sections
    # Every section is a stateless builder over the shared Context; the
    # base class only carries that context so sections stay one-liner
    # constructions in YearReport.
    class Base
      extend T::Sig

      sig { params(context: Context).void }
      def initialize(context:)
        @context = T.let(context, Context)
      end
    end
  end
end
