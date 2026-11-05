# typed: true

module Api
  module V1
    class DeviceInvitesController < BaseController
      # POST /api/v1/device_invites
      # Creates a signed token that lets the bearer register a new passkey
      # without going through the normal login flow (Auth::DeviceInvite).
      #
      # With no params: a fifteen-minute invite for the current user, to add
      # a device at this address.
      #
      # With `address`: a week-long sign-in link redeemable only at that
      # address — how members get back in after the instance moves, since
      # their passkeys stay bound to the old one. An admin may pass `user_id`
      # to issue one for another member of the household.
      def create
        address = nil
        if params[:address].present?
          address = ::Auth::DeviceInvite.parse_address(params[:address].to_s)
          return render_address_invalid if address.nil?
        end

        user = invite_target(moving: !address.nil?)
        return if performed?

        issued = ::Auth::DeviceInvite.issue(user: user, host: address&.host)
        record_sign_in_link(user, address) if address

        render json: {
          token:      issued.token,
          expires_at: issued.expires_at,
          host:       address&.host,
          url:        address&.join_url(issued.token)
        }, status: :created
      end

      private

      # The current user, or — for a move, and only for an admin — another
      # member of this household. Issuing for someone else hands out a way
      # into their account, so it never extends past the household.
      def invite_target(moving:)
        requested = params[:user_id].presence
        return Current.user if requested.nil? || requested == Current.user.id

        unless moving
          render json: { error: "A link for another member needs the address it will be used at." },
                 status: :unprocessable_content
          return
        end
        unless current_admin?
          render json: { error: "Only admins can issue sign-in links for other members." }, status: :forbidden
          return
        end

        Current.household.household_memberships.find_by!(user_id: requested).user
      end

      def render_address_invalid
        render json: { error: "Enter the new address as a hostname or URL, e.g. fin.example.com" },
               status: :unprocessable_content
      end

      def record_sign_in_link(user, address)
        Activity.record(
          source: "backup", event: "sign_in_link.issued", subject: user,
          summary: "#{Current.user.email} issued a sign-in link for #{user.email} at #{address.host}",
          payload: { host: address.host }
        )
      end
    end
  end
end
