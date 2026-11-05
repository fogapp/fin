# typed: strict

module Transfers
  # The detection signals for payment matching (docs/credit-card-payments.md §B).
  # S1 (structure) is evaluated by PaymentMatcher's counterpart queries; this
  # module scores the corroborating signals that decide the confidence tier:
  #
  #   S2 — Plaid PFC tagged the leg as a loan/credit-card payment
  #   S3 — the description carries a payment signature
  #   S4 — cadence: a confirmed payment already links the same account pair
  #
  # Signatures are deliberately specific (never a bare "PAYMENT") so
  # person-to-person payments ("Zelle payment to ...") can never match.
  module PaymentSignals
    extend T::Sig

    SIGNATURE_PATTERN = T.let(
      /AUTOPAY|AUTOMATIC\s+PAYMENT|PAYMENT\s*-?\s*THANK|EPAY|GSBANK|CARDMEMBER\s+SERV/i,
      Regexp
    )

    CC_PAYMENT_RAW_CATEGORY = KindClassifier::CC_PAYMENT_RAW_CATEGORY
    LOAN_RAW_CATEGORY_PREFIX = KindClassifier::LOAN_RAW_CATEGORY_PREFIX

    # Trailing processor tags whose value changes every time ("WEB ID:
    # 9999999999", "PPD ID: 1234567890").
    PROCESSOR_TAG_PATTERN = T.let(/\b(?:WEB|PPD|CCD|ARC|TEL|POS)\s+ID:?\s*\S*/i, Regexp)
    # Short dates banks append to online payments ("09/02", "08/26/26").
    DATE_TOKEN_PATTERN    = T.let(%r{\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b}, Regexp)
    # A token with this many digits is a reference number, not a name.
    REFERENCE_DIGITS      = 5

    # The stable text of a descriptor: reference numbers, processor tags and
    # dates stripped, so two occurrences of the same recurring payment
    # compare equal ("Online Payment 10000000001 To Auto Loan 1111 09/02"
    # and "Online Payment 10000000002 To Auto Loan 1111 04/02" both become
    # "Online Payment To Auto Loan 1111"). Mirrored by normalizeDescription
    # in frontend/src/lib/transactions.ts — keep the two in step.
    sig { params(description: T.nilable(String)).returns(String) }
    def self.normalize_description(description)
      description.to_s
        .gsub(PROCESSOR_TAG_PATTERN, " ")
        .gsub(DATE_TOKEN_PATTERN, " ")
        .gsub(/\S+/) { |token| token.count("0-9") >= REFERENCE_DIGITS ? " " : token }
        .squeeze(" ")
        .strip
        .sub(/[\s\-#:*]+\z/, "")
    end

    # Does this leg carry any payment signal on its own (before a
    # counterpart is known)? Gates the cadence tier so an ordinary debit can
    # never inherit a one-sided payment link.
    sig { params(txn: CashTransaction).returns(T::Boolean) }
    def self.payment_shaped?(txn)
      txn.transaction_type == CashTransaction::TransactionType::Payment.serialize ||
        txn.raw_category.to_s.start_with?(LOAN_RAW_CATEGORY_PREFIX) ||
        signature?(txn.description)
    end

    sig { params(description: T.nilable(String)).returns(T::Boolean) }
    def self.signature?(description)
      description.to_s.match?(SIGNATURE_PATTERN)
    end

    sig { params(legs: T::Array[CashTransaction]).returns(T::Boolean) }
    def self.pfc_payment?(legs)
      legs.any? { |leg| leg.raw_category.to_s.start_with?(LOAN_RAW_CATEGORY_PREFIX) }
    end

    sig { params(legs: T::Array[CashTransaction]).returns(T::Boolean) }
    def self.loan_marked?(legs)
      legs.any? { |leg| leg.loan_id.present? } || legs.any? do |leg|
        raw = leg.raw_category.to_s
        raw.start_with?(LOAN_RAW_CATEGORY_PREFIX) && raw != CC_PAYMENT_RAW_CATEGORY
      end
    end

    # Cadence: some earlier payment between the same two accounts was already
    # confirmed (by any source), so this pair shape is established.
    sig { params(from_account_id: T.nilable(String), to_account_id: T.nilable(String)).returns(T::Boolean) }
    def self.established_pair?(from_account_id, to_account_id)
      return false if from_account_id.blank? || to_account_id.blank?

      Transfer.confirmed.payments
        .joins("JOIN cash_transactions from_legs ON from_legs.id = transfers.from_transaction_id AND transfers.from_transaction_type = 'CashTransaction'")
        .joins("JOIN cash_transactions to_legs   ON to_legs.id   = transfers.to_transaction_id   AND transfers.to_transaction_type   = 'CashTransaction'")
        .where(from_legs: { account_id: from_account_id }, to_legs: { account_id: to_account_id })
        .exists?
    end

    # The tier decision for a structurally matched (S1) pair.
    sig { params(from: CashTransaction, to: CashTransaction).returns(T::Boolean) }
    def self.auto_confirmable?(from, to)
      legs = [ from, to ]
      pfc_payment?(legs) ||
        legs.any? { |leg| signature?(leg.description) } ||
        established_pair?(from.account_id, to.account_id)
    end
  end
end
