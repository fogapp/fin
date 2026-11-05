# typed: false
# frozen_string_literal: true

namespace :fin do
  # The operator's way back in when nobody can sign in — after a restore at
  # a new address with no sign-in links issued beforehand (the old instance
  # is gone), or a member who lost every device. Holding a shell on the
  # server is the proof of identity; the link does the rest.
  #
  #   bin/rails "fin:sign_in_link[you@example.com,fin.example.com]"
  desc "Print a sign-in link that registers a new passkey for EMAIL at ADDRESS"
  task :sign_in_link, [ :email, :address ] => :environment do |_, args|
    abort "usage: bin/rails \"fin:sign_in_link[email,address]\"" if args[:email].blank? || args[:address].blank?

    user = User.find_by("LOWER(email) = ?", args[:email].to_s.downcase.strip)
    abort "No user with email #{args[:email]}" if user.nil?
    address = Auth::DeviceInvite.parse_address(args[:address].to_s)
    abort "#{args[:address]} is not a hostname or URL" if address.nil?

    issued = Auth::DeviceInvite.issue(user: user, host: address.host)
    puts address.join_url(issued.token)
    puts "Valid until #{issued.expires_at.utc.iso8601}, at #{address.host} only, for one use."
  end
end
