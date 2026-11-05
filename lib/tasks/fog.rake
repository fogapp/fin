# typed: false
# frozen_string_literal: true

# The fog-backup boot tasks (fog:docs/backup-contract.md).
#
# fog:release is the app's release phase on fog: restore a staged artifact if
# one is armed, then db:prepare (which migrates a restored-from-older-code
# database forward).
#
# fog:restore_if_staged is the entrypoint guard for container restarts that
# aren't deploys (the first-run restore door): same work, but only when
# something is actually staged, so a plain restart stays a plain restart.
namespace :fog do
  desc "Release phase: restore staged artifact if armed, then db:prepare"
  task release: :environment do
    FogBackup::Restorer.run_if_armed!
    Rake::Task["db:prepare"].invoke
    FogBackup::AddressChange.reconcile_pending!
  end

  desc "Restore a staged artifact if one is armed (entrypoint guard)"
  task restore_if_staged: :environment do
    next unless FogBackup::Staging.armed?

    FogBackup::Restorer.run_if_armed!
    Rake::Task["db:prepare"].invoke
    FogBackup::AddressChange.reconcile_pending!
  end
end
