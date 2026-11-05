# typed: true

module Api
  module V1
    class PreferencesController < BaseController
      # Appearance follows the household, not the person: switching household
      # switches the look with it. These keys are stored per household under
      # HOUSEHOLD_SCOPED; the user-wide copy is the default for a household
      # that hasn't been given its own yet.
      APPEARANCE_KEYS = %w[theme font font_size].freeze
      HOUSEHOLD_SCOPED = "households"

      def show
        render json: { data: effective_data }
      end

      def update
        incoming = data_params.except(HOUSEHOLD_SCOPED)
        appearance = incoming.slice(*APPEARANCE_KEYS)
        merged = preference.data.deep_merge(incoming.except(*APPEARANCE_KEYS))
        merged = merged.deep_merge(HOUSEHOLD_SCOPED => { household_key => appearance }) if appearance.any?
        preference.update!(data: merged)
        render json: { data: effective_data }
      end

      private

      def preference
        @preference ||= Current.user.preference ||
                        Current.user.create_preference!(data: {})
      end

      def effective_data
        data = preference.data
        data.except(HOUSEHOLD_SCOPED).merge(data.dig(HOUSEHOLD_SCOPED, household_key) || {})
      end

      def household_key
        Current.household!.id.to_s
      end

      def data_params
        params.require(:data).to_unsafe_h
      end
    end
  end
end
