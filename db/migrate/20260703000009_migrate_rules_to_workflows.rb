# Converts every legacy rules-engine Rule into an equivalent workflow
# (docs/workflow_engine_design.md phase E) and deactivates the originals so
# the two engines never double-apply. Rules data stays in place read-only
# until the UI cutover removes the old engine.
class MigrateRulesToWorkflows < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:rules) && table_exists?(:workflows)
    # The rules engine (models + converter) was removed after this migration
    # shipped; on databases migrated past this point the constants are gone.
    return unless defined?(Rule) && defined?(Workflows::RuleConverter)

    say_with_time "converting rules to workflows" do
      converted = 0
      Rule.unscoped.where(active: true).find_each do |rule|
        workflow = Workflows::RuleConverter.convert!(rule)
        converted += 1 if workflow
      rescue => e
        say "rule #{rule.id} (#{rule.name}) failed to convert: #{e.message}", true
      end
      converted
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
