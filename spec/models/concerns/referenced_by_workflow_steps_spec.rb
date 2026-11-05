require "rails_helper"

RSpec.describe ReferencedByWorkflowSteps do
  shared_examples "flags orphaned workflow steps" do |action_type, param, value_shape: :scalar|
    let(:ref_value) { value_shape == :array ? [ record.id ] : record.id }

    it "raises an issue for each #{action_type} step pointing at the destroyed record" do
      step  = create(:workflow_step, config: { "action_type" => action_type, "params" => { param => ref_value } })
      other = create(:workflow_step, config: { "action_type" => action_type, "params" => { param => SecureRandom.uuid } })

      expect { record.destroy! }.to change(Issue, :count).by(1)

      issue = Issue.find_by(key: "orphaned_workflow_step:#{step.id}")
      expect(issue.title).to eq("Workflow step references deleted #{record.class.model_name.human.downcase}")
      expect(issue.source).to eq("workflow:#{step.workflow_id}")
      expect(Issue.find_by(key: "orphaned_workflow_step:#{other.id}")).to be_nil
    end

    it "ignores steps of other action types that share the param name" do
      create(:workflow_step, config: { "action_type" => "set_memo", "params" => { param => ref_value } })
      expect { record.destroy! }.not_to change(Issue, :count)
    end
  end

  describe Loan do
    let(:record) { create(:loan) }
    include_examples "flags orphaned workflow steps", "set_loan", "loan_id"
  end

  describe Category do
    let(:record) { create(:category) }
    include_examples "flags orphaned workflow steps", "assign_category", "category_id"
  end

  describe Merchant do
    let(:record) { create(:merchant) }
    include_examples "flags orphaned workflow steps", "assign_merchant", "merchant_id"
  end

  describe Tag do
    let(:record) { create(:tag) }
    include_examples "flags orphaned workflow steps", "add_tag", "tag_id"
    include_examples "flags orphaned workflow steps", "add_tag", "tag_id", value_shape: :array
  end

  describe Account do
    let(:record) { create(:account) }
    include_examples "flags orphaned workflow steps", "assign_account", "account_id"
    include_examples "flags orphaned workflow steps", "transfer_to_account", "account_id"
  end
end
