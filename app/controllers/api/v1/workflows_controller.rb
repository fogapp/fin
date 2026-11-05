# typed: true

module Api
  module V1
    class WorkflowsController < BaseController
      renders_with Api::Render::Workflow

      # trigger_config and step configs are JSON documents, not model
      # attributes, but they are still an allowlist: each permits exactly the
      # keys something reads (Workflow / Workflows::Schedule / Workflows::Monitor
      # for triggers, WorkflowStep and Workflows::Actions::PARAM_KEYS for
      # steps). Unknown keys are dropped rather than stored.
      CONDITION_KEYS = T.let([ :field, :operator, :value ].freeze, T::Array[Symbol])

      TRIGGER_CONFIG_KEYS = T.let([
        :subject, :match_all,                                        # monitor
        :frequency, :every_hours, :at, :day_of_week, :day_of_month,  # schedule
        { changed_fields: [], conditions: CONDITION_KEYS }           # record events / monitor
      ].freeze, T::Array[T.untyped])

      STEP_CONFIG_KEYS = T.let({
        "branch" => [ :match_all, :else, { conditions: CONDITION_KEYS } ],
        "action" => [ :action_type, :stop_on_error ],
        "wait"   => [ :duration_seconds ]
      }.freeze, T::Hash[String, T::Array[T.untyped]])

      def index
        render json: renderer.index
      end

      def show
        render json: renderer.show
      end

      def create
        workflow = Workflow.new(workflow_params)
        Workflow.transaction do
          workflow.save!
          workflow.replace_steps!(steps_param) if params.key?(:steps)
        end
        render json: renderer.serialize(workflow, include_steps: true), status: :created
      end

      def update
        workflow = Workflow.find(params[:id])
        Workflow.transaction do
          workflow.update!(workflow_params)
          workflow.replace_steps!(steps_param) if params.key?(:steps)
        end
        Workflows::Events.reset_cache
        render json: renderer.serialize(workflow.reload, include_steps: true)
      end

      def destroy
        workflow = Workflow.find(params[:id])
        if workflow.seed_key.present?
          return render json: { error: "System workflows can't be deleted — deactivate it instead." },
                        status: :unprocessable_content
        end

        workflow.destroy!
        Workflows::Events.reset_cache
        head :no_content
      end

      # Manual trigger. Monitors evaluate their subject scope now; event
      # workflows run against existing records of their trigger's model
      # (root branch conditions prefilter, same as apply-to-existing).
      def run_now
        workflow = Workflow.find(params[:id])
        if workflow.trigger_type == Workflows::Catalog::MONITOR_TRIGGER
          Workflows::EvaluateMonitorJob.perform_later(workflow.id)
          render_queued(mode: Workflows::Catalog::MONITOR_TRIGGER)
        elsif workflow.trigger_type == Workflows::Catalog::SCHEDULE_TRIGGER
          # Fire one occurrence now, the way ScheduleTickJob does, without
          # moving the schedule's clock — an apply-to-existing pass has no
          # records to act on for a subject-less scheduled workflow, so it
          # used to finish instantly having run nothing.
          run = workflow.runs.create!(
            household_id:  workflow.household_id,
            event_type:    "schedule.manual",
            event_payload: { "requested_at" => Time.current.iso8601 },
            status:        WorkflowRun::Status::Pending
          )
          Workflows::ExecuteRunJob.perform_later(run.id)
          render_queued(mode: Workflows::Catalog::SCHEDULE_TRIGGER, run_id: run.id)
        else
          Workflows::ApplyToExistingJob.perform_later(workflow.id)
          render_queued(mode: "apply_to_existing")
        end
      end

      def apply_to_existing
        workflow = Workflow.find(params[:id])
        Workflows::ApplyToExistingJob.perform_later(workflow.id)
        render_queued(workflow_id: workflow.id)
      end

      def revert_runs
        workflow = Workflow.find(params[:id])
        Workflows::RevertRunsJob.perform_later(workflow.id, params[:since].presence)
        render_queued(workflow_id: workflow.id)
      end

      def catalog
        render json: {
          triggers: Workflows::Catalog.trigger_types.map { |type|
            subject = Workflows::Catalog.subject_class_for(type)
            { type: type, subject_type: subject,
              fields: Workflows::Catalog.fields_for(subject).transform_values { |f| f.except(:type) } }
          },
          actions: Workflows::Actions.action_types
        }
      end

      private

      def workflow_params
        permitted = params.permit(:name, :description, :trigger_type, :active, :position)
        if params[:trigger_config].present?
          permitted[:trigger_config] = params.permit(trigger_config: TRIGGER_CONFIG_KEYS).fetch(:trigger_config, {}).to_h
        end
        permitted
      end

      def steps_param = permit_steps(params[:steps])

      # The step tree, rebuilt node by node: {kind, config, children}.
      # Accepts a JSON array or the indexed-hash form of a form post.
      def permit_steps(raw)
        nodes = raw.is_a?(ActionController::Parameters) ? raw.values : Array(raw)
        nodes.filter_map do |node|
          next unless node.is_a?(ActionController::Parameters)

          kind = node.permit(:kind)[:kind]
          { kind: kind, config: permit_step_config(kind.to_s, node[:config]), children: permit_steps(node[:children]) }
        end
      end

      def permit_step_config(kind, config)
        return {} unless config.is_a?(ActionController::Parameters)

        permitted = config.permit(STEP_CONFIG_KEYS.fetch(kind, [])).to_h
        if kind == "action" && config.key?(:params)
          param_keys = Workflows::Actions.param_keys(config[:action_type].to_s)
          permitted["params"] = config.permit(params: param_keys).fetch(:params, {}).to_h
        end
        permitted
      end
    end
  end
end
