# Fixes a gap in 20260514000000_convert_application_ids_to_uuids.
#
# That migration converted PK and FK columns from bigint to uuid by walking
# Rails-tracked foreign_keys(table). rule_executions.rule_id and
# rule_executions.triggered_by_execution_id were declared in the original
# CreateRuleExecutions migration as plain `t.integer` (not `t.references`),
# so they had no FK constraint and were silently skipped.
#
# The result: rule_executions.rule_id remained `integer` while the rules.id
# it points at became `uuid`. CycleDetector compares rule.id (uuid string)
# against ancestor exec.rule_id (integer 2), they never match, and the rules
# engine recurses forever until SystemStackError.
#
# This migration converts both columns to uuid. rule_executions is small (the
# PruneRuleExecutionsJob keeps it under ~30 days of rows) and any existing
# integer rows can't be mapped onto real UUIDs anyway, so the column type
# change uses USING NULL — historical executions lose their rule linkage but
# the schema is correct going forward.
class FixRuleExecutionLegacyColumns < ActiveRecord::Migration[8.0]
  def up
    return unless connection.adapter_name == "PostgreSQL"

    %w[rule_id triggered_by_execution_id].each do |column|
      col = connection.columns(:rule_executions).find { |c| c.name == column }
      next if col.nil? || col.sql_type == "uuid"

      execute %(ALTER TABLE "rule_executions" ALTER COLUMN "#{column}" TYPE uuid USING NULL)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
