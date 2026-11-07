# typed: strict

module Workflows
  # The single choke point for publishing domain events into the workflow
  # engine. Publishing is cheap when nothing listens: the set of active
  # trigger types per household is memoized briefly, so the per-save overhead
  # for registry models is a hash lookup most of the time.
  module Events
    extend T::Sig

    CACHE_TTL_SECONDS = T.let(10, Integer)

    # Threadsafe memo of active trigger types per household. Puma serves
    # requests from multiple threads and each publish reads (and may refresh)
    # this — a plain Hash mutated without synchronization corrupts under
    # concurrent rehash. Entries are immutable once stored; a racing refresh
    # just wastes one query and last-writer-wins.
    CACHE = Concurrent::Map.new

    # Runs the block with event publishing disabled. Used by reverts: writing
    # back old values must not re-trigger the very workflow being reverted.
    sig { params(blk: T.proc.returns(T.untyped)).returns(T.untyped) }
    def self.suppress(&blk)
      previous = Thread.current[:workflow_events_suppressed]
      Thread.current[:workflow_events_suppressed] = true
      blk.call
    ensure
      Thread.current[:workflow_events_suppressed] = previous
    end

    sig { returns(T::Boolean) }
    def self.suppressed?
      Thread.current[:workflow_events_suppressed] == true
    end

    sig { params(type: String, subject: T.untyped, payload: T::Hash[T.untyped, T.untyped]).void }
    def self.publish(type, subject:, payload: {})
      return if suppressed?

      household_id = Current.household&.id || subject.try(:household_id)
      return if household_id.nil?

      any_alias = Catalog.any_alias_for(type)
      if active?(household_id, type) || (any_alias && active?(household_id, any_alias))
        DispatchJob.perform_later(type, household_id.to_s, subject.class.name, subject.id.to_s, payload)
      end

      # Monitors get re-evaluated when a record of their watched model
      # changes (created/updated), independent of exact-type listeners.
      if type.end_with?(".created", ".updated") &&
         monitored_models_for(household_id.to_s).include?(subject.class.name)
        EvaluateMonitorsJob.perform_later(household_id.to_s, subject.class.name, subject.id.to_s)
      end
    end

    sig { params(household_id: String, type: String).returns(T::Boolean) }
    def self.active?(household_id, type)
      active_types_for(household_id).include?(type)
    end

    sig { params(household_id: String).returns(T::Set[String]) }
    def self.active_types_for(household_id)
      cache_entry(household_id).fetch(:types)
    end

    sig { params(household_id: String).returns(T::Set[String]) }
    def self.monitored_models_for(household_id)
      cache_entry(household_id).fetch(:monitored)
    end

    sig { void }
    def self.reset_cache
      CACHE.clear
    end

    sig { params(household_id: String).returns(T::Hash[Symbol, T.untyped]) }
    def self.cache_entry(household_id)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      entry = CACHE[household_id]
      if entry.nil? || (now - entry.fetch(:at)) > CACHE_TTL_SECONDS
        rows = Workflow.unscoped.active.where(household_id: household_id)
                       .pluck(:trigger_type, :trigger_config)
        types = Set.new(rows.map(&:first))
        monitored = rows.filter_map { |(type, config)|
          Catalog::RECORD_MODELS[config["subject"].to_s] if type == Catalog::MONITOR_TRIGGER
        }
        entry = { at: now, types: types.freeze, monitored: Set.new(monitored).freeze }.freeze
        CACHE[household_id] = entry
      end
      entry
    end
    private_class_method :cache_entry
  end
end
