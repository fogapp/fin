# typed: true

module Api
  module V1
    # Settings → Household → Time zone: instance-wide settings that belong to
    # no household (InstanceSetting). Anyone signed in may read them — every
    # member sees dates computed in this zone. Changing one is gated like the
    # other instance-wide action, backups: any household admin may. That
    # suits a single-family instance; one open to strangers should turn
    # FIN_OPEN_REGISTRATION off (INSTALL.md says so), since registering
    # founds a household its registrant administers.
    class InstanceSettingsController < BaseController
      before_action -> { require_household_admin!("Only a household admin can change instance settings.") },
                    only: :update

      # GET /api/v1/instance_settings
      def show
        render json: serialized(InstanceSetting.time_zone)
      end

      # PATCH /api/v1/instance_settings
      # Accepts an IANA identifier or a Rails zone name; stores the IANA one.
      def update
        setting = InstanceSetting.current
        setting.update!(time_zone: params.require(:time_zone).to_s)
        if setting.saved_change_to_time_zone?
          Activity.record(source: "settings", event: "instance.time_zone_changed",
                          summary: "#{Current.user.email} set the time zone to #{setting.time_zone}")
        end
        render json: serialized(setting.time_zone)
      end

      private

      def serialized(time_zone)
        { time_zone: time_zone, time_zones: InstanceSetting.selectable_time_zones }
      end
    end
  end
end
