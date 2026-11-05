# typed: false
# frozen_string_literal: true

namespace :fin do
  # Break-glass for a fog-only Fin (fog:docs/signin-proposal.md §15): when
  # fog itself is broken, the operator — who has a shell, by definition —
  # mints a single-use link that signs in Fin's first admin. Nothing
  # reachable from the network can do this, and Fin keeps no standing
  # credential for it. ADDRESS is where Fin is reached (default: the
  # passkey relying party, FIN_WEBAUTHN_RP_ID).
  #
  #   bin/rails "fin:recovery_link[fin.example.com]"
  desc "Print a single-use, ten-minute sign-in link for Fin's first admin"
  task :recovery_link, [ :address ] => :environment do |_, args|
    raw = args[:address].presence || ENV["FIN_WEBAUTHN_RP_ID"].presence
    abort "usage: bin/rails \"fin:recovery_link[address]\"" if raw.nil?
    address = Auth::DeviceInvite.parse_address(raw.to_s)
    abort "#{raw} is not a hostname or URL" if address.nil?

    membership = HouseholdMembership.where(role: Role::Admin.serialize).order(:created_at).first
    abort "Fin has no admin yet" if membership.nil?

    admin = membership.user
    session = Auth::SessionToken.mint!(user: admin, household: membership.household, label: "recovery link",
      expires_at: 1.day.from_now)
    code = session.issue_handoff!(ttl: 10.minutes)
    Activity.record(source: "signin", event: "signin.recovery_link", severity: Severity::Warning,
      household_id: membership.household_id, subject: admin,
      summary: "A recovery sign-in link was minted for #{admin.email} from the console")
    puts "#{address.origin}/auth/complete##{URI.encode_www_form('handoff' => code, 'return_to' => '/')}"
    puts "Valid for ten minutes, for one use."
  end
end
