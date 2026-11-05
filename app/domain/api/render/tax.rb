# typed: strict

module Api
  module Render
    # Serializes the tax center's record types (estimated payments,
    # checklist items, adjustments) for the CRUD endpoints and
    # ::Tax::YearReport. Numbers are floats; quarters are derived from
    # paid_on, never stored.
    class Tax < Api::Render::Base
      extend T::Sig

      sig { params(payment: ::EstimatedTaxPayment).returns(T::Hash[Symbol, T.untyped]) }
      def estimated_payment(payment)
        {
          id:           payment.id,
          tax_year:     payment.tax_year,
          jurisdiction: payment.jurisdiction,
          paid_on:      payment.paid_on,
          amount:       payment.amount.to_f,
          notes:        payment.notes,
          quarter:      ::Tax::DueDates.quarter_for(payment.tax_year, payment.paid_on)
        }
      end

      sig { params(item: ::TaxChecklistItem).returns(T::Hash[Symbol, T.untyped]) }
      def checklist_item(item)
        {
          id:           item.id,
          tax_year:     item.tax_year,
          kind:         item.kind,
          source_label: item.source_label,
          status:       item.status,
          auto_seeded:  item.auto_seeded,
          reference_id: item.reference_id,
          notes:        item.notes
        }
      end

      sig { params(adjustment: ::TaxAdjustment).returns(T::Hash[Symbol, T.untyped]) }
      def adjustment(adjustment)
        {
          id:           adjustment.id,
          tax_year:     adjustment.tax_year,
          kind:         adjustment.kind,
          jurisdiction: adjustment.jurisdiction,
          label:        adjustment.label,
          amount:       adjustment.amount.to_f,
          bucket:       adjustment.bucket,
          notes:        adjustment.notes
        }
      end
    end
  end
end
