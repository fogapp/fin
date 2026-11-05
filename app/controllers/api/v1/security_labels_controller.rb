# typed: true

module Api
  module V1
    # Per-household display names for securities. Keyed by security_id rather
    # than by the label row's own id so the holdings UI — which only ever
    # knows the security — can set and clear a label with one endpoint.
    class SecurityLabelsController < BaseController
      def update
        security = Security.find(params[:security_id])
        label    = params[:label].to_s.strip

        if label.blank?
          SecurityLabel.find_by(security_id: security.id)&.destroy!
        else
          upsert_label!(security, label)
        end

        render json: { security_id: security.id, label: label.presence }
      end

      private

      # Setting the same label twice is the same request, not a conflict: two
      # in-flight saves of a first label would otherwise race the unique index
      # and 409 the loser. Retry into the row the winner just wrote.
      def upsert_label!(security, label)
        record = SecurityLabel.find_or_initialize_by(security_id: security.id)
        record.label = label
        record.save!
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Depending on when the winner committed, the loser trips either the
        # unique index or the model's uniqueness validation.
        existing = SecurityLabel.find_by(security_id: security.id)
        raise unless existing

        existing.update!(label: label)
      end
    end
  end
end
