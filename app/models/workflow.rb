# typed: true

class Workflow < ApplicationRecord
  extend T::Sig

  include HouseholdScoped

  has_many :steps, -> { order(:position) }, class_name: "WorkflowStep", dependent: :destroy
  has_many :runs, class_name: "WorkflowRun", dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :household_id }
  validates :trigger_type, presence: true
  validate  :trigger_type_in_catalog
  validate  :monitor_config_shape
  validate  :schedule_config_shape
  before_save :compute_next_scheduled_at, if: :schedule_trigger?

  scope :due_scheduled, -> {
    active.where(trigger_type: Workflows::Catalog::SCHEDULE_TRIGGER)
          .where(next_scheduled_at: ..Time.current)
  }

  scope :active,      -> { where(active: true) }
  scope :for_trigger, ->(type) { where(trigger_type: type) }

  # An AssociationRelation of WorkflowStep (subclass of Relation).
  sig { returns(ActiveRecord::Relation) }
  def root_steps
    steps.where(parent_id: nil)
  end

  # Replaces the whole step tree from a nested array of
  # {kind:, config:, children: [...]} hashes — the builder UI submits the
  # full tree on save. Runs keep their historical run_steps (the FK
  # nullifies) but reference no live step afterwards.
  sig { params(tree: T::Array[T.untyped]).void }
  def replace_steps!(tree)
    transaction do
      steps.destroy_all
      create_step_level(tree, parent: nil)
    end
  end

  # Depth-first serialization of the step tree for the API.
  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def steps_tree
    subtree(steps.group_by(&:parent_id), nil)
  end

  # Event-level filtering before a run is even created — e.g. an `updated`
  # trigger that only cares when certain attributes changed.
  sig { params(payload: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
  def trigger_matches?(payload)
    watched = Array(trigger_config["changed_fields"]).map(&:to_s)
    return true if watched.empty?

    changed = Array(payload["changes"] || payload[:changes]).map(&:to_s)
    (watched & changed).any?
  end

  # Root-level branch prefilter shared by DispatchJob and ApplyToExistingJob:
  # a subject qualifies when any root branch matches (if/elsif semantics mean
  # the run would take exactly one), or when there are no root branches at
  # all (unconditional workflows). Root steps are memoized because
  # apply-to-existing calls this once per record of a whole table, and read
  # from preloaded steps when the caller loaded them for many workflows.
  sig { params(subject: T.untyped).returns(T::Boolean) }
  def roots_match?(subject)
    branches = @root_branches_for_match ||=
      (steps.loaded? ? steps.select { |step| step.parent_id.nil? } : root_steps).select(&:branch?)
    return true if branches.empty?

    branches.any? do |branch|
      branch.else_branch? ||
        Workflows::ConditionCheck.match?(subject, branch.conditions, match_all: branch.match_all?)
    end
  end

  def schedule_trigger?
    trigger_type == Workflows::Catalog::SCHEDULE_TRIGGER
  end

  # Advance the clock hand past `now` (called by the tick job after firing).
  # Hourly/interval schedules anchor to the previous next_scheduled_at rather
  # than the tick time so the cadence doesn't drift by the tick granularity
  # each firing; if the schedule fell far behind (downtime), catch up from
  # `from - interval` so the next occurrence lands at/after now instead of
  # replaying every missed slot. Calendar schedules (daily/weekly/monthly)
  # are already anchored by their at/day config.
  # Re-resolve every pending daily/weekly/monthly schedule in the current
  # Time.zone — run after the instance time zone changes, so "daily at
  # 05:30" means 05:30 in the new zone from its very next firing. Hourly
  # schedules don't depend on the zone, and one already due is left for the
  # tick to fire rather than skipped.
  sig { void }
  def self.reanchor_calendar_schedules!
    now = Time.current
    unscoped.active.where(trigger_type: Workflows::Catalog::SCHEDULE_TRIGGER)
            .where("next_scheduled_at > ?", now).find_each do |workflow|
      config = workflow.trigger_config
      next if Workflows::Schedule.validation_error(config)
      next if Workflows::Schedule::Frequency.try_deserialize(config["frequency"].to_s) == Workflows::Schedule::Frequency::Hourly

      workflow.update_columns(next_scheduled_at: Workflows::Schedule.next_occurrence(config, from: now))
    end
  end

  def advance_schedule!(from: Time.current)
    config = trigger_config
    anchor = from
    if Workflows::Schedule::Frequency.try_deserialize(config["frequency"].to_s) == Workflows::Schedule::Frequency::Hourly
      previous = T.unsafe(self).next_scheduled_at
      anchor   = [ previous, from - config["every_hours"].to_i.hours ].max if previous.present?
    end
    update!(next_scheduled_at: Workflows::Schedule.next_occurrence(config, from: anchor))
  end

  private

  # Recursive half of steps_tree. This is a method rather than the lambda it
  # used to be because a lambda that calls itself reads as nil to Sorbet — the
  # local isn't bound yet while its own body is being checked.
  sig do
    params(by_parent: T::Hash[T.nilable(String), T::Array[WorkflowStep]], parent_id: T.nilable(String))
      .returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def subtree(by_parent, parent_id)
    (by_parent[parent_id] || []).sort_by(&:position).map do |step|
      { id: step.id, kind: step.kind, config: step.config,
        children: subtree(by_parent, step.id) }
    end
  end

  sig { params(nodes: T::Array[T.untyped], parent: T.nilable(WorkflowStep)).void }
  def create_step_level(nodes, parent:)
    nodes.each_with_index do |node, index|
      step = steps.create!(
        parent:   parent,
        position: index,
        kind:     node[:kind] || node["kind"],
        config:   (node[:config] || node["config"] || {}).deep_stringify_keys
      )
      children = node[:children] || node["children"] || []
      create_step_level(children, parent: step)
    end
  end

  def trigger_type_in_catalog
    return if Workflows::Catalog.trigger_types.include?(trigger_type)

    errors.add(:trigger_type, "is not a known trigger")
  end

  def compute_next_scheduled_at
    return if next_scheduled_at.present? && !trigger_config_changed? && !trigger_type_changed?

    self.next_scheduled_at = Workflows::Schedule.next_occurrence(trigger_config, from: Time.current)
  end

  def schedule_config_shape
    return unless schedule_trigger?

    error = Workflows::Schedule.validation_error(trigger_config)
    errors.add(:trigger_config, error) if error
  end

  def monitor_config_shape
    return unless trigger_type == Workflows::Catalog::MONITOR_TRIGGER

    unless Workflows::Catalog::RECORD_MODELS.key?(trigger_config["subject"].to_s)
      errors.add(:trigger_config, "monitor needs a valid subject model")
    end
    if Array(trigger_config["conditions"]).empty?
      errors.add(:trigger_config, "monitor needs at least one condition")
    end
  end
end
