# typed: strict

module Workflows
  # Per-household knob (households.workflow_log_level) for how much run
  # telemetry the engine persists. The engine always keeps what it needs
  # operationally — runs that applied actions (revert data), parked waits,
  # and failures — the level controls how much of the rest survives:
  #
  #   Debug — keep every run, even ones that matched nothing, and write an
  #           activity entry for every finish. The old always-on behavior;
  #           useful while building or troubleshooting a workflow.
  #   Info  — the default. Workflows whose root branches reject the subject
  #           are skipped at dispatch (no run row at all); runs that matched
  #           a branch are kept, but activity entries are written only when
  #           a run applies an action, hits an action error, or fails.
  #   None  — additionally discard completed runs that had no effect (even
  #           when a branch matched), and log activity only for failures.
  class LogLevel < T::Enum
    include ApplicationEnum

    enums do
      None = new("none")
      Info = new("info")
      Debug = new("debug")
    end
  end
end
