# typed: strict

module Workflows
  # Tiny mustache-lite interpolation for user-authored action params:
  # "{{description}} posted for {{amount}}" — placeholders resolve against
  # catalog-whitelisted subject fields plus a few safe extras, never via
  # arbitrary public_send.
  module Template
    extend T::Sig

    EXTRA_KEYS = T.let(%w[id event_type workflow_name].freeze, T::Array[String])

    sig { params(template: T.nilable(String), run: WorkflowRun, subject: T.untyped).returns(String) }
    def self.render(template, run:, subject:)
      template.to_s.gsub(/{{\s*([\w?.]+)\s*}}/) do
        key = T.must(Regexp.last_match(1))
        resolve(key, run: run, subject: subject).to_s
      end
    end

    sig { params(key: String, run: WorkflowRun, subject: T.untyped).returns(T.untyped) }
    def self.resolve(key, run:, subject:)
      case key
      when "id"            then subject&.id
      when "event_type"    then run.event_type
      when "workflow_name" then run.workflow&.name
      else
        return run.event_payload[key] if run.event_payload.key?(key)
        return nil if subject.nil?
        return nil unless Catalog.valid_field?(subject.class.name, key)
        return nil unless subject.respond_to?(key)

        subject.public_send(key)
      end
    end
  end
end
