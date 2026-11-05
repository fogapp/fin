# typed: true

module Api
  module V1
    # Shared skeleton for the provider settings controllers (Tiingo, Alpha
    # Vantage, CoinMarketCap, Coinbase, RentCast, Alchemy, Plaid): `show`
    # renders the serialized configuration, `update` assigns + saves and
    # re-renders it, and `test` wraps each provider's probe in the uniform
    # two-arm rescue policy. Subclasses declare their knobs with the
    # `provider_configuration` macro and supply `test_probe` (plus
    # `persist!` / `serialized` overrides where a provider does more than
    # the plain save).
    class ProviderConfigurationController < BaseController
      extend T::Sig

      class_attribute :configuration_class, :params_key, :permitted_attrs,
                      :provider_display_name, :provider_log_tag, :client_error_classes,
                      instance_writer: false

      sig do
        params(
          configuration_class: T.untyped,
          params_key: Symbol,
          permitted: T::Array[Symbol],
          display_name: String,
          log_tag: T.nilable(String),
          # Class names, not classes: several providers nest their Error
          # inside the client file (e.g. AlphaVantage::Error in
          # alpha_vantage/client.rb), which Zeitwerk can't resolve at
          # controller-load time — so constantize lazily at rescue time.
          client_errors: T::Array[String]
        ).void
      end
      def self.provider_configuration(configuration_class:, params_key:, permitted:, display_name:, log_tag: nil, client_errors: [])
        self.configuration_class   = configuration_class
        self.params_key            = params_key
        self.permitted_attrs       = permitted
        self.provider_display_name = display_name
        self.provider_log_tag      = log_tag || display_name
        self.client_error_classes  = client_errors
      end

      def show
        render json: serialized
      end

      def update
        persist!(configuration)
        render json: serialized
        # ActiveRecord::RecordInvalid / ParameterMissing are rescued in
        # BaseController; anything else (network, NoMethodError) should
        # bubble to render_internal_error instead of leaking via e.message.
      end

      def test
        render json: test_probe
      rescue *client_error_classes.map(&:constantize) => e
        # Typed errors from our own client are already user-facing.
        render json: { ok: false, error: e.message }, status: :unprocessable_content
      rescue => e
        # Anything else (TCP timeouts, JSON parse, NoMethodError, etc.) could
        # leak internal hostnames or stack info — log it and return a static
        # message.
        Rails.logger.error("[#{provider_log_tag} test] #{e.class}: #{e.message}")
        render json: { ok: false, error: "#{provider_display_name} connection failed" },
               status: :unprocessable_content
      end

      private

      # Most providers are a household-singleton row; Plaid overrides this to
      # scope through Current.household.
      def configuration
        configuration_class.current
      end

      # Template method: providers that react to configuration flips
      # (repinning routes, kicking a first-configure sync) override around
      # this so they can capture state before the save.
      def persist!(config)
        config.assign_attributes(configuration_params)
        config.save!
      end

      def configuration_params
        params.require(params_key).permit(*permitted_attrs)
      end

      # The single-api-key shape most providers share; the rest override.
      def serialized
        config = configuration
        { api_key_set: config.api_key.present?, configured: config.configured? }
      end

      # Success body for #test — providers with a routed test action must
      # implement this.
      def test_probe
        raise NotImplementedError, "#{self.class.name} must implement #test_probe"
      end
    end
  end
end
