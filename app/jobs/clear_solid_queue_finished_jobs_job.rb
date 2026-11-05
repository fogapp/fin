# typed: true

class ClearSolidQueueFinishedJobsJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { params(retain_days: Integer, max_executions: Integer).void }
  def perform(retain_days: 30, max_executions: 0)
    scope = SolidQueue::Job.finished

    if retain_days.to_i > 0
      scope = scope.where("finished_at < ?", retain_days.to_i.days.ago)
    end

    if max_executions.to_i > 0
      cutoff_time = SolidQueue::Job.finished
                                   .order(finished_at: :desc)
                                   .offset(max_executions.to_i)
                                   .limit(1)
                                   .pick(:finished_at)
      scope = scope.where("finished_at <= ?", cutoff_time) if cutoff_time
    end

    scope.in_batches(of: 500) { |batch| batch.delete_all; sleep 0.1 }
  end
end
