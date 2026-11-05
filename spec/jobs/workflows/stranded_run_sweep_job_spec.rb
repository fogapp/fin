require "rails_helper"

RSpec.describe Workflows::StrandedRunSweepJob, type: :job do
  let(:workflow) { create(:workflow) }

  def running_run(started_at:)
    create(:workflow_run, workflow: workflow, status: "running", started_at: started_at)
  end

  it "re-enqueues runs stuck in running past the stranded threshold" do
    stuck = running_run(started_at: 45.minutes.ago)

    expect { described_class.perform_now }
      .to have_enqueued_job(Workflows::ExecuteRunJob).with(stuck.id)
    expect(stuck.reload.status).to eq(WorkflowRun::Status::Running)
  end

  it "leaves recently started runs alone" do
    running_run(started_at: 5.minutes.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Workflows::ExecuteRunJob)
  end

  it "marks day-old stranded runs failed with an error activity instead of retrying forever" do
    dead = running_run(started_at: 2.days.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Workflows::ExecuteRunJob)

    expect(dead.reload.status).to eq(WorkflowRun::Status::Failed)
    expect(dead.error).to match(/stranded/)
    expect(dead.finished_at).to be_present

    entry = ActivityEntry.where(event: "run.stranded").sole
    expect(entry.severity).to eq(Severity::Error)
  end

  it "ignores finished and waiting runs regardless of age" do
    create(:workflow_run, workflow: workflow, status: "completed", started_at: 2.days.ago)
    create(:workflow_run, workflow: workflow, status: "waiting",   started_at: 2.days.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Workflows::ExecuteRunJob)
    expect(WorkflowRun.where(status: "failed")).to be_empty
  end
end
