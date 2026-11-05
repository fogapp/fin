# typed: true
# frozen_string_literal: true

class Loan < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion
  include EmitsWorkflowEvents
  belongs_to :account, optional: true
  belongs_to :merchant, optional: true
  # The property a mortgage finances. Display only — the loan stays a
  # liability and the property a gross asset, so net worth is unaffected.
  belongs_to :real_estate_property, optional: true
  has_many :cash_transactions, dependent: :nullify

  include ReferencedByWorkflowSteps
  flags_orphaned_workflow_steps "set_loan", param: "loan_id", action_label: "link to loan"

  after_save { @current_balance = nil }

  # What the loan finances.
  class LoanType < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Mortgage = new("mortgage")
      Auto = new("auto")
      Student = new("student")
      Personal = new("personal")
      Heloc = new("heloc")
      Business = new("business")
      Other = new("other")
    end
  end

  # Lifecycle: only active loans count as liabilities.
  class Status < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Active = new("active")
      PaidOff = new("paid_off")
      Refinanced = new("refinanced")
    end
  end

  typed_enum :loan_type, LoanType
  typed_enum :status, Status

  validates :name, presence: true
  validates :original_principal, :interest_rate, :term_months, :start_date, presence: true
  validates :original_principal, numericality: { greater_than: 0 }
  validates :interest_rate, numericality: { greater_than_or_equal_to: 0 }
  validates :term_months, numericality: { greater_than: 0, only_integer: true }
  validates :escrow_property_tax, :escrow_insurance, :escrow_other,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :escrow_leaves_principal_and_interest

  # What the lender collects each month on top of principal and interest and
  # holds in escrow — property taxes, homeowners insurance, and anything else
  # bundled into the payment (PMI, flood insurance).
  sig { returns(BigDecimal) }
  def escrow_payment
    [ escrow_property_tax, escrow_insurance, escrow_other ].sum(BigDecimal("0")) { |amount| amount.to_d }
  end

  # The full monthly payment the lender collects: the entered amount when
  # there is one, otherwise the computed principal and interest plus escrow.
  sig { returns(BigDecimal) }
  def computed_monthly_payment
    return monthly_payment.to_d if monthly_payment.present?

    principal_and_interest_payment + escrow_payment
  end

  # The part of the payment that services the debt, and so the only part that
  # amortizes. An entered monthly payment includes escrow, so it comes off.
  sig { returns(BigDecimal) }
  def principal_and_interest_payment
    return [ monthly_payment.to_d - escrow_payment, BigDecimal("0") ].max if monthly_payment.present?

    i = monthly_rate
    return BigDecimal("0") if i.zero?

    p = original_principal.to_d
    return (p * i).round(2) if interest_only?

    (p * i * (1 + i)**term_months / ((1 + i)**term_months - 1)).round(2)
  end

  sig { returns(BigDecimal) }
  def total_scheduled_interest
    return (principal_and_interest_payment * term_months).round(2) if interest_only?

    (principal_and_interest_payment * term_months - original_principal.to_d).round(2)
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def amortization_schedule
    schedule = []
    balance = T.let(original_principal.to_d, BigDecimal)
    i = monthly_rate
    escrow = escrow_payment

    if interest_only?
      term_months.times do |n|
        interest = (balance * i).round(2)
        schedule << {
          payment_number: n + 1,
          payment_date:   start_date >> (n + 1),
          payment:        (interest + escrow).to_f,
          principal:      0.0,
          interest:       interest.to_f,
          escrow:         escrow.to_f,
          balance:        balance.to_f
        }
      end
    else
      pmt = principal_and_interest_payment
      term_months.times do |n|
        interest = (balance * i).round(2)
        principal = [ pmt - interest, balance ].min.round(2)
        balance = (balance - principal).round(2)

        schedule << {
          payment_number: n + 1,
          payment_date:   start_date >> (n + 1),
          payment:        (pmt + escrow).to_f,
          principal:      principal.to_f,
          interest:       interest.to_f,
          escrow:         escrow.to_f,
          balance:        [ balance, 0 ].max.to_f
        }

        break if balance <= 0
      end
    end

    schedule
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def payment_stats
    start = amortization_start
    start_balance = start.first

    total_paid     = T.let(BigDecimal("0"), BigDecimal)
    principal_paid = T.let(BigDecimal("0"), BigDecimal)
    interest_paid  = T.let(BigDecimal("0"), BigDecimal)
    escrow_paid    = T.let(BigDecimal("0"), BigDecimal)
    balance        = start_balance

    each_payment(start) do |_txn, amount, interest, principal, escrow, balance_after|
      total_paid     += amount
      interest_paid  += interest
      principal_paid += principal
      escrow_paid    += escrow
      balance         = balance_after
    end

    {
      total_paid:        total_paid.round(2),
      principal_paid:    principal_paid.round(2),
      interest_paid:     interest_paid.round(2),
      escrow_paid:       escrow_paid.round(2),
      property_tax_paid: escrow_share(escrow_paid, escrow_property_tax),
      insurance_paid:    escrow_share(escrow_paid, escrow_insurance),
      other_escrow_paid: escrow_share(escrow_paid, escrow_other),
      current_balance:   balance,
      # Every linked payment, anchor or not: the frontend marks this many
      # rows of the origination-based amortization_schedule as paid.
      payments_count:    cash_transactions.length
    }
  end

  # Just the balance after the last linked payment — what property equity,
  # LTV and net worth need — without payment_stats' full set of sums.
  # Memoized because a property page reads it several times per loan;
  # cleared on reload/save so an edited loan never serves a stale balance.
  sig { returns(BigDecimal) }
  def current_balance
    @current_balance ||= T.let(
      begin
        start = amortization_start
        balance = T.let(start[0], BigDecimal)
        each_payment(start) { |*, balance_after| balance = balance_after }
        balance
      end,
      T.nilable(BigDecimal)
    )
  end

  sig { params(options: T.untyped).returns(T.self_type) }
  def reload(*options)
    @current_balance = nil
    super
  end

  # Interest portion of linked payments dated inside `range`. The balance must
  # be carried through ALL payments to split each one correctly, but only
  # in-range interest is credited. Powers the tax center's per-year mortgage
  # interest fact.
  sig { params(range: T::Range[Date]).returns(BigDecimal) }
  def interest_paid_between(range)
    interest_in_range = T.let(BigDecimal("0"), BigDecimal)

    each_payment do |txn, _amount, interest, _principal, _escrow, _balance_after|
      interest_in_range += interest if range.cover?(txn.transaction_date)
    end

    interest_in_range.round(2)
  end

  # Remaining-balance breakpoints over time as [[date, balance], ...] sorted
  # ascending: the balance starts at origination (or the balance anchor when
  # one is set) and steps down with each linked payment. Lets callers value
  # the loan as a liability on any historical date by carrying the last
  # breakpoint forward.
  sig { returns(T::Array[T::Array[T.untyped]]) }
  def balance_breakpoints
    start = amortization_start
    start_balance, start_point, _txns = start
    points = [ [ start_point, start_balance ] ]

    return points if interest_only?

    each_payment(start) do |txn, _amount, _interest, _principal, _escrow, balance_after|
      points << [ txn.transaction_date, balance_after ]
    end

    points
  end

  private

  # Starting balance, starting date, and the ordered payments that apply to
  # it: from the balance anchor when one is set, otherwise from origination.
  # sort_by (not .order) so a preloaded association is used as-is — the loans
  # index preloads cash_transactions for every loan, and .order would
  # re-query per loan.
  sig { returns([ BigDecimal, Date, T::Array[CashTransaction] ]) }
  def amortization_start
    if balance_anchor_amount.present? && balance_anchor_date.present?
      anchor_date = T.must(balance_anchor_date)
      [
        balance_anchor_amount.to_d,
        anchor_date,
        cash_transactions.select { |t| t.transaction_date > anchor_date }.sort_by(&:transaction_date)
      ]
    else
      [ original_principal.to_d, start_date, cash_transactions.sort_by(&:transaction_date) ]
    end
  end

  # The single amortization walk: carries the running balance through every
  # linked payment and yields (txn, amount, interest, principal, escrow,
  # balance_after) per payment. All the public aggregates fold over this so
  # the interest/principal split can never diverge between them. Callers that
  # already hold the amortization_start tuple pass it in to skip re-filtering
  # and re-sorting the payments.
  #
  # The escrow amount comes off the top of each payment (capped at the
  # payment) before the rest is split, so taxes and insurance collected with
  # the payment never count as principal. Interest is capped at what's left;
  # a payment smaller than accrued interest amortizes negatively (the
  # balance grows).
  sig do
    params(
      start: T.nilable([ BigDecimal, Date, T::Array[CashTransaction] ]),
      block: T.proc.params(
        txn: CashTransaction, amount: BigDecimal, interest: BigDecimal,
        principal: BigDecimal, escrow: BigDecimal, balance_after: BigDecimal
      ).void
    ).void
  end
  def each_payment(start = nil, &block)
    start ||= amortization_start
    balance = T.let(start[0], BigDecimal)
    txns = start[2]
    i = monthly_rate
    scheduled_escrow = escrow_payment

    txns.each do |txn|
      amount  = txn.amount.abs.to_d
      escrow  = [ scheduled_escrow, amount ].min
      applied = amount - escrow

      if interest_only?
        interest  = applied
        principal = BigDecimal("0")
      else
        accrued   = (balance * i).round(2)
        principal = [ applied - accrued, balance ].min.round(2)
        interest  = [ accrued, applied ].min.round(2)
        balance   = [ balance - principal, 0 ].max.round(2)
      end

      yield txn, amount, interest, principal, escrow, balance
    end
  end

  # One escrow line's slice of the escrow collected so far, in proportion to
  # its share of the monthly escrow amount.
  sig { params(escrow_paid: BigDecimal, line: T.nilable(BigDecimal)).returns(BigDecimal) }
  def escrow_share(escrow_paid, line)
    total = escrow_payment
    return BigDecimal("0") if total.zero? || line.blank?

    (escrow_paid * line.to_d / total).round(2)
  end

  sig { void }
  def escrow_leaves_principal_and_interest
    return if monthly_payment.blank? || escrow_payment.zero?
    return if monthly_payment.to_d > escrow_payment

    errors.add(:monthly_payment, "must be more than the escrow amounts it includes")
  end

  sig { returns(BigDecimal) }
  def monthly_rate
    (interest_rate.to_d / 100 / 12).round(10)
  end
end
