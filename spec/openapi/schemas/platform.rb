# Platform schemas: identity and sessions, households, integrations
# (Plaid, Coinbase, CoinMarketCap, Alpha Vantage, Tiingo, Alchemy, Office),
# workflows and their runs, the activity log, notifications, system health
# and first-run setup.
module OpenapiSchemas
  module Platform
    TIMESTAMP          = { type: :string, format: "date-time" }.freeze
    NULLABLE_TIMESTAMP = { type: :string, format: "date-time", nullable: true }.freeze
    UUID               = { type: :string, format: :uuid }.freeze
    NULLABLE_UUID      = { type: :string, format: :uuid, nullable: true }.freeze
    NULLABLE_STRING    = { type: :string, nullable: true }.freeze
    ROLE               = { type: :string, enum: %w[admin member] }.freeze
    SEVERITY           = { type: :string, enum: ::Severity.values.map(&:serialize) }.freeze
    LOG_LEVEL          = { type: :string, enum: %w[none info debug] }.freeze
    # Free-form JSON blobs (event payloads, step configs and outputs).
    JSON_OBJECT        = { type: :object, additionalProperties: true }.freeze
    NULLABLE_JSON      = { type: :object, additionalProperties: true, nullable: true }.freeze

    # A nullable reference. OpenAPI 3.0 ignores siblings of $ref, so the
    # reference is wrapped in allOf for `nullable` to take effect.
    def self.nullable_ref(name) = { allOf: [ { "$ref" => "#/components/schemas/#{name}" } ], nullable: true }

    PAGE_META = {
      type: :object,
      properties: {
        page:     { type: :integer },
        per_page: { type: :integer },
        total:    { type: :integer }
      },
      required: %w[page per_page total]
    }.freeze

    SCHEMAS = {
      # ── Identity & sessions ────────────────────────────────────────────────
      SessionUser: {
        type: :object,
        properties: { id: UUID, email: { type: :string }, name: NULLABLE_STRING },
        required: %w[id email name]
      },
      # Returned by passkey register/login/device-invite finish, household
      # switch and household delete — the bearer token for the new session.
      Session: {
        type: :object,
        properties: {
          token: { type: :string },
          user:  { "$ref" => "#/components/schemas/SessionUser" },
          household: {
            type: :object,
            properties: { id: UUID, name: { type: :string }, role: ROLE.merge(nullable: true) },
            required: %w[id name role]
          }
        },
        required: %w[token user household]
      },
      Me: {
        type: :object,
        properties: {
          user: { "$ref" => "#/components/schemas/SessionUser" },
          household: {
            type: :object,
            properties: {
              id:                      UUID,
              name:                    { type: :string },
              role:                    ROLE.merge(nullable: true),
              workflow_log_level:      LOG_LEVEL,
              include_unvested_equity: { type: :boolean }
            },
            required: %w[id name role workflow_log_level include_unvested_equity]
          }
        },
        required: %w[user household]
      },
      # WebAuthn ceremony start: options are the browser's
      # PublicKeyCredentialCreation/RequestOptionsJSON, passed through untyped.
      PasskeyChallenge: {
        type: :object,
        properties: {
          options:         JSON_OBJECT,
          challenge_token: { type: :string }
        },
        required: %w[options challenge_token]
      },
      # The fog link page's proof that the person holds an account's passkey:
      # the bearer for POST /auth/oidc/link, bound to one pending sign-in and
      # good for five minutes. Not a session.
      PasskeyLinkProof: {
        type: :object,
        properties: { link_token: { type: :string } },
        required: %w[link_token]
      },
      WebauthnCredential: {
        type: :object,
        properties: {
          id:           UUID,
          nickname:     NULLABLE_STRING,
          created_at:   TIMESTAMP,
          last_used_at: NULLABLE_TIMESTAMP
        },
        required: %w[id nickname created_at last_used_at]
      },
      # `host` and `url` are set on a sign-in link issued for another address
      # (an instance move); a plain device invite is for this one.
      DeviceInvite: {
        type: :object,
        properties: {
          token:      { type: :string },
          expires_at: TIMESTAMP,
          host:       NULLABLE_STRING,
          url:        NULLABLE_STRING
        },
        required: %w[token expires_at host url]
      },
      About: {
        type: :object,
        properties: {
          rails_version: { type: :string },
          ruby_version:  { type: :string },
          rails_env:     { type: :string },
          git_sha:       NULLABLE_STRING,
          git_sha_short: NULLABLE_STRING,
          hostname:      { type: :string }
        },
        required: %w[rails_version ruby_version rails_env git_sha git_sha_short hostname]
      },
      # Instance-wide settings (InstanceSetting): the time zone every request
      # and job runs in, and the zones Settings offers.
      InstanceSettings: {
        type: :object,
        properties: {
          time_zone:  { type: :string, description: "IANA time zone identifier, e.g. America/Los_Angeles" },
          time_zones: {
            type: :array,
            description: "Selectable zones: IANA location zones, the zones Rails names, and Etc/UTC",
            items: {
              type: :object,
              properties: {
                id:         { type: :string, description: "IANA identifier" },
                name:       NULLABLE_STRING.merge(description: "Rails' friendly name, when it has one"),
                utc_offset: { type: :string, description: "Current offset from UTC, e.g. -07:00" }
              },
              required: %w[id name utc_offset]
            }
          }
        },
        required: %w[time_zone time_zones]
      },
      Preferences: {
        type: :object,
        properties: { data: JSON_OBJECT.merge(description: "Arbitrary key-value preference blob") },
        required: %w[data]
      },
      ApiTokenCreated: {
        allOf: [
          { "$ref" => "#/components/schemas/ApiToken" },
          {
            type: :object,
            properties: { token: { type: :string, description: "Raw token; only returned at creation" } },
            required: %w[token]
          }
        ]
      },
      # fog-integration/1 consent (FogIntegrations): what fog asks on behalf
      # of an app at /connect/<ticket>, and a household admin's answer.
      FogConnection: {
        type: :object,
        properties: {
          consumer: { type: :string, description: "The fog app that would read Fin" },
          offer: {
            type: :object,
            properties: { id: { type: :string }, title: { type: :string }, blurb: { type: :string } },
            required: %w[id title blurb]
          },
          state: {
            type: :string, enum: %w[pending approved declined claimed expired],
            description: "Only pending can be answered"
          },
          expires_at: TIMESTAMP
        },
        required: %w[consumer offer state expires_at]
      },
      FogConnectionAnswer: {
        type: :object,
        properties: {
          state:     { type: :string, enum: %w[approved declined] },
          return_to: { type: :string, description: "Where on fog to send the browser next, carrying the answer" }
        },
        required: %w[state return_to]
      },
      IssuesDismissed: {
        type: :object,
        properties: { dismissed: { type: :integer } },
        required: %w[dismissed]
      },
      # signin: sign in with an OpenID provider (fog) — offered when
      # configured, and the only way in once Fin has proven it runs on fog.
      SetupStatus: {
        type: :object,
        properties: {
          setup_required: { type: :boolean },
          signin: {
            type: :object,
            properties: { enabled: { type: :boolean }, fog_only: { type: :boolean } },
            required: %w[enabled fog_only]
          }
        },
        required: %w[setup_required signin]
      },
      # fog-backup preflight verdict on an uploaded backup artifact.
      RestorePreflight: {
        type: :object,
        properties: {
          ok:       { type: :boolean },
          errors:   { type: :array, items: { type: :string } },
          warnings: { type: :array, items: { type: :string } },
          artifact: NULLABLE_JSON.merge(description: "The manifest's app/created_at/produced_by/identity, when readable")
        },
        required: %w[ok errors warnings artifact]
      },
      SetupRestoreResult: {
        type: :object,
        properties: {
          restarting: { type: :boolean },
          errors:     { type: :array, items: { type: :string } },
          preflight:  { "$ref" => "#/components/schemas/RestorePreflight" }
        }
      },

      # ── Backups (Settings → Backup) ────────────────────────────────────────
      # One manually requested fog-backup/2 artifact. The artifact fields are
      # null until the job completes.
      Backup: {
        type: :object,
        properties: {
          id:           { type: :string },
          status:       { type: :string, enum: %w[running completed failed] },
          progress:     NULLABLE_STRING,
          error:        NULLABLE_STRING,
          started_at:   NULLABLE_TIMESTAMP,
          requested_by: NULLABLE_STRING,
          bytes:        { type: :integer, nullable: true },
          sha256:       NULLABLE_STRING,
          created_at:   NULLABLE_TIMESTAMP,
          expires_at:   NULLABLE_TIMESTAMP.merge(description: "When the staged artifact is swept from the server"),
          filename:     NULLABLE_STRING
        },
        required: %w[id status progress error started_at requested_by bytes sha256 created_at expires_at filename]
      },
      BackupOverview: {
        type: :object,
        properties: {
          backups: { type: :array, items: { "$ref" => "#/components/schemas/Backup" } },
          # Where this instance's passkeys are bound — what an artifact
          # produced here records as its identity.
          address: {
            type: :object,
            properties: { host: { type: :string }, rp_id: NULLABLE_STRING },
            required: %w[host rp_id]
          },
          # The secrets an artifact's data depends on, by fingerprint only.
          keys: {
            type: :array,
            items: {
              type: :object,
              properties: { name: { type: :string }, fingerprint: { type: :string } },
              required: %w[name fingerprint]
            }
          },
          retention_hours: { type: :integer },
          last_restore: {
            type: :object, nullable: true,
            properties: {
              restored_at:         TIMESTAMP,
              artifact_created_at: NULLABLE_TIMESTAMP,
              moved_from:          { type: :string },
              moved_to:            { type: :string }
            }
          }
        },
        required: %w[backups address keys retention_hours last_restore]
      },
      BackupDownload: {
        type: :object,
        properties: { url: { type: :string }, expires_at: TIMESTAMP },
        required: %w[url expires_at]
      },
      BackupKeys: {
        type: :object,
        properties: {
          keys: {
            type: :array,
            items: {
              type: :object,
              properties: { name: { type: :string }, value: { type: :string }, fingerprint: { type: :string } },
              required: %w[name value fingerprint]
            }
          }
        },
        required: %w[keys]
      },

      # ── Households ─────────────────────────────────────────────────────────
      InviteCreated: {
        allOf: [
          { "$ref" => "#/components/schemas/Invite" },
          {
            type: :object,
            properties: { accept_url: { type: :string } },
            required: %w[accept_url]
          }
        ]
      },
      # Public GET /invites/{code}: what an invitee sees before registering.
      InvitePreview: {
        type: :object,
        properties: {
          code:       { type: :string },
          role:       ROLE,
          expires_at: NULLABLE_TIMESTAMP,
          household: {
            type: :object,
            properties: { id: UUID, name: { type: :string } },
            required: %w[id name]
          }
        },
        required: %w[code role expires_at household]
      },

      # ── Async job acknowledgement ──────────────────────────────────────────
      Queued: {
        type: :object,
        properties: {
          status:      { type: :string, enum: %w[queued] },
          item_id:     { type: :string, format: :uuid, description: "Plaid item sync only" },
          workflow_id: { type: :string, format: :uuid, description: "Workflow apply/revert only" },
          plaid_account_id: { type: :string, format: :uuid, description: "Plaid account sync only" },
          mode:        { type: :string, enum: %w[monitor schedule apply_to_existing], description: "Workflow run_now only" },
          run_id:      { type: :string, format: :uuid, description: "Workflow run_now on a scheduled workflow only" }
        },
        required: %w[status]
      },

      # ── Provider configurations ────────────────────────────────────────────
      ApiKeyConfiguration: {
        type: :object,
        description: "CoinMarketCap, Alpha Vantage and Tiingo share this shape.",
        properties: { api_key_set: { type: :boolean }, configured: { type: :boolean } },
        required: %w[api_key_set configured]
      },
      ConnectionTestResult: {
        type: :object,
        properties: {
          ok:      { type: :boolean },
          message: { type: :string },
          error:   { type: :string },
          tools:   { type: :array, items: { type: :string }, description: "Office only: names of the tools the server exposes" }
        },
        required: %w[ok]
      },
      CoinbaseConfiguration: {
        type: :object,
        properties: {
          api_key_id_set:     { type: :boolean },
          api_key_secret_set: { type: :boolean },
          configured:         { type: :boolean }
        },
        required: %w[api_key_id_set api_key_secret_set configured]
      },
      CoinbaseAccount: {
        type: :object,
        properties: {
          id:          { type: :string },
          name:        { type: :string },
          currency:    NULLABLE_STRING,
          balance:     { type: :string, nullable: true, description: "Decimal string as Coinbase reports it" },
          type:        NULLABLE_STRING,
          balance_usd: { type: :number, nullable: true }
        },
        required: %w[id name currency balance type balance_usd]
      },
      PlaidConfiguration: {
        type: :object,
        properties: {
          environment:   { type: :string, enum: %w[sandbox production] },
          client_id_set: { type: :boolean },
          secret_set:    { type: :boolean },
          configured:    { type: :boolean },
          source:        { type: :string, enum: %w[database environment] }
        },
        required: %w[environment client_id_set secret_set configured source]
      },
      PlaidLinkToken: {
        type: :object,
        properties: { link_token: { type: :string } },
        required: %w[link_token]
      },
      # A Plaid account as nested in its item (GET /plaid/items).
      PlaidItemAccount: {
        type: :object,
        properties: {
          id:                UUID,
          name:              { type: :string },
          display_name:      { type: :string },
          mask:              NULLABLE_STRING,
          account_type:      { type: :string },
          account_subtype:   NULLABLE_STRING,
          linked:            { type: :boolean },
          account_id:        NULLABLE_UUID,
          bank_count:        { type: :integer },
          credit_card_count: { type: :integer }
        },
        required: %w[id name display_name mask account_type account_subtype linked account_id bank_count credit_card_count]
      },
      PlaidItem: {
        type: :object,
        properties: {
          id:               UUID,
          institution_name: { type: :string },
          institution_id:   { type: :string },
          status:           { type: :string, enum: %w[active error] },
          last_synced_at:   NULLABLE_TIMESTAMP,
          plaid_accounts:   { type: :array, items: { "$ref" => "#/components/schemas/PlaidItemAccount" } }
        },
        required: %w[id institution_name institution_id status last_synced_at plaid_accounts]
      },
      # A Plaid account from the standalone /plaid/accounts endpoints.
      PlaidAccount: {
        type: :object,
        properties: {
          id:                 UUID,
          name:               { type: :string },
          display_name:       { type: :string },
          mask:               NULLABLE_STRING,
          account_type:       { type: :string },
          account_subtype:    NULLABLE_STRING,
          linked:             { type: :boolean },
          account_id:         NULLABLE_UUID,
          plaid_item_id:      UUID,
          institution_name:   { type: :string },
          balance_current:    { type: :number, nullable: true },
          balance_available:  { type: :number, nullable: true },
          balance_limit:      { type: :number, nullable: true },
          balance_currency:   NULLABLE_STRING,
          balance_updated_at: NULLABLE_TIMESTAMP
        },
        required: %w[id name display_name mask account_type account_subtype linked account_id plaid_item_id
                     institution_name balance_current balance_available balance_limit balance_currency balance_updated_at]
      },
      AlchemyConfiguration: {
        type: :object,
        properties: {
          api_key_set:                 { type: :boolean },
          configured:                  { type: :boolean },
          transactions_enabled:        { type: :boolean },
          sync_frequency:              { type: :string, enum: %w[realtime every_5_minutes every_15_minutes hourly every_6_hours daily] },
          auth_token_set:              { type: :boolean },
          webhook_base_url:            NULLABLE_STRING,
          suggested_webhook_base_url:  { type: :string },
          transactions_last_synced_at: NULLABLE_TIMESTAMP,
          webhooks: {
            type: :array,
            items: {
              type: :object,
              properties: {
                network:          { type: :string },
                status:           { type: :string, enum: %w[active error] },
                last_received_at: NULLABLE_TIMESTAMP,
                last_error:       NULLABLE_STRING
              },
              required: %w[network status last_received_at last_error]
            }
          }
        },
        required: %w[api_key_set configured transactions_enabled sync_frequency auth_token_set webhook_base_url
                     suggested_webhook_base_url transactions_last_synced_at webhooks]
      },
      AlchemyWallet: {
        type: :object,
        properties: {
          id:             UUID,
          address:        { type: :string },
          name:           NULLABLE_STRING,
          display_name:   { type: :string },
          networks:       { type: :array, items: { type: :string } },
          active:         { type: :boolean },
          last_synced_at: NULLABLE_TIMESTAMP,
          last_error:     NULLABLE_STRING,
          account: {
            type: :object,
            nullable: true,
            properties: { id: UUID, name: { type: :string }, balance: { type: :number, nullable: true } },
            required: %w[id name balance]
          },
          syncs: {
            type: :array,
            items: {
              type: :object,
              properties: {
                network:                 { type: :string },
                last_synced_at:          NULLABLE_TIMESTAMP,
                backfill_status:         { type: :string, enum: %w[pending running completed failed] },
                backfill_transfer_count: { type: :integer },
                last_error:              NULLABLE_STRING
              },
              required: %w[network last_synced_at backfill_status backfill_transfer_count last_error]
            }
          }
        },
        required: %w[id address name display_name networks active last_synced_at last_error account syncs]
      },
      OfficeConfiguration: {
        type: :object,
        properties: {
          configured:        { type: :boolean },
          api_key_set:       { type: :boolean },
          base_url:          NULLABLE_STRING,
          default_folder_id: { type: :integer, nullable: true },
          source:            { type: :string, enum: %w[configuration environment], nullable: true },
          datasets: {
            type: :array,
            items: {
              type: :object,
              properties: { key: { "$ref" => "#/components/schemas/OfficeDataset" }, label: { type: :string } },
              required: %w[key label]
            }
          },
          sheet_count: { type: :integer }
        },
        required: %w[configured api_key_set base_url default_folder_id source datasets sheet_count]
      },
      OfficeSpreadsheet: {
        type: :object,
        properties: {
          id:         { type: :integer },
          title:      { type: :string },
          folder:     NULLABLE_STRING,
          updated_at: NULLABLE_TIMESTAMP,
          url:        NULLABLE_STRING
        },
        required: %w[id title folder updated_at url]
      },
      OfficeSpreadsheetPreview: {
        type: :object,
        properties: {
          id:         { type: :integer },
          title:      { type: :string },
          folder:     NULLABLE_STRING,
          updated_at: NULLABLE_TIMESTAMP,
          url:        NULLABLE_STRING,
          sheets: {
            type: :array,
            items: {
              type: :object,
              properties: { name: { type: :string }, used_range: NULLABLE_STRING },
              required: %w[name used_range]
            }
          },
          sheet:   { type: :string, nullable: true, description: "The sheet that was read" },
          preview: { "$ref" => "#/components/schemas/ImportPreview" }
        },
        required: %w[id title folder updated_at url sheets sheet preview]
      },
      OfficeDataset: { type: :string, enum: %w[transactions holdings portfolio] },
      OfficeSheetExport: {
        type: :object,
        properties: {
          id:               UUID,
          dataset:          { "$ref" => "#/components/schemas/OfficeDataset" },
          dataset_label:    { type: :string },
          title:            { type: :string },
          document_id:      { type: :integer },
          sheet_name:       NULLABLE_STRING,
          url:              NULLABLE_STRING,
          filters:          { type: :object, additionalProperties: { type: :string } },
          row_count:        { type: :integer, description: "Data rows, excluding the header" },
          last_exported_at: NULLABLE_TIMESTAMP,
          last_error:       NULLABLE_STRING,
          created_at:       TIMESTAMP
        },
        required: %w[id dataset dataset_label title document_id sheet_name url filters row_count
                     last_exported_at last_error created_at]
      },

      # ── Workflows ──────────────────────────────────────────────────────────
      WorkflowStepKind: { type: :string, enum: %w[branch action wait] },
      # Step configs are keyed by kind (branch: conditions, action:
      # action_type + params, wait: duration/until) and each action type has
      # its own params, so they stay a free-form object rather than a oneOf.
      WorkflowStep: {
        type: :object,
        properties: {
          id:       UUID,
          kind:     { "$ref" => "#/components/schemas/WorkflowStepKind" },
          config:   JSON_OBJECT,
          children: { type: :array, items: { "$ref" => "#/components/schemas/WorkflowStep" } }
        },
        required: %w[id kind config children]
      },
      Workflow: {
        type: :object,
        properties: {
          id:                UUID,
          name:              { type: :string },
          description:       NULLABLE_STRING,
          trigger_type:      { type: :string },
          trigger_config:    JSON_OBJECT,
          active:            { type: :boolean },
          position:          { type: :integer },
          seed_key:          NULLABLE_STRING,
          next_scheduled_at: NULLABLE_TIMESTAMP,
          schedule_summary:  NULLABLE_STRING,
          created_at:        TIMESTAMP,
          updated_at:        TIMESTAMP
        },
        required: %w[id name description trigger_type trigger_config active position seed_key
                     next_scheduled_at schedule_summary created_at updated_at]
      },
      WorkflowSummary: {
        allOf: [
          { "$ref" => "#/components/schemas/Workflow" },
          {
            type: :object,
            properties: {
              run_count:       { type: :integer },
              last_run_status: nullable_ref("WorkflowRunStatus"),
              last_run_at:     NULLABLE_TIMESTAMP
            },
            required: %w[run_count last_run_status last_run_at]
          }
        ]
      },
      WorkflowDetail: {
        allOf: [
          { "$ref" => "#/components/schemas/Workflow" },
          {
            type: :object,
            properties: { steps: { type: :array, items: { "$ref" => "#/components/schemas/WorkflowStep" } } },
            required: %w[steps]
          }
        ]
      },
      RegistryField: {
        type: :object,
        properties: {
          operators: { type: :array, items: { type: :string } },
          values:    { type: :array, items: { type: :string } }
        },
        required: %w[operators]
      },
      WorkflowCatalog: {
        type: :object,
        properties: {
          triggers: {
            type: :array,
            items: {
              type: :object,
              properties: {
                type:         { type: :string },
                subject_type: NULLABLE_STRING,
                fields:       { type: :object, additionalProperties: { "$ref" => "#/components/schemas/RegistryField" } }
              },
              required: %w[type subject_type fields]
            }
          },
          actions: { type: :array, items: { type: :string } }
        },
        required: %w[triggers actions]
      },
      WorkflowRunStatus: { type: :string, enum: %w[pending running waiting completed failed cancelled] },
      WorkflowRun: {
        type: :object,
        properties: {
          id:            UUID,
          workflow_id:   UUID,
          workflow_name: NULLABLE_STRING,
          event_type:    { type: :string },
          event_payload: NULLABLE_JSON,
          subject_type:  NULLABLE_STRING,
          subject_id:    NULLABLE_UUID,
          status:        { "$ref" => "#/components/schemas/WorkflowRunStatus" },
          error:         NULLABLE_STRING,
          started_at:    NULLABLE_TIMESTAMP,
          finished_at:   NULLABLE_TIMESTAMP,
          created_at:    TIMESTAMP,
          reverted_at:   NULLABLE_TIMESTAMP,
          revertible:    { type: :boolean }
        },
        required: %w[id workflow_id workflow_name event_type event_payload subject_type subject_id status error
                     started_at finished_at created_at reverted_at revertible]
      },
      WorkflowRunStep: {
        type: :object,
        properties: {
          id:         UUID,
          step_id:    NULLABLE_UUID,
          step_kind:  nullable_ref("WorkflowStepKind"),
          status:     { type: :string, enum: %w[matched not_matched applied skipped error waiting] },
          output:     NULLABLE_JSON,
          resume_at:  NULLABLE_TIMESTAMP,
          created_at: TIMESTAMP
        },
        required: %w[id step_id step_kind status output resume_at created_at]
      },
      WorkflowRunDetail: {
        allOf: [
          { "$ref" => "#/components/schemas/WorkflowRun" },
          {
            type: :object,
            properties: { steps: { type: :array, items: { "$ref" => "#/components/schemas/WorkflowRunStep" } } },
            required: %w[steps]
          }
        ]
      },
      WorkflowRunsResponse: {
        type: :object,
        properties: {
          runs: { type: :array, items: { "$ref" => "#/components/schemas/WorkflowRun" } },
          meta: { "$ref" => "#/components/schemas/PageMeta" }
        },
        required: %w[runs meta]
      },
      WorkflowRunGroup: {
        type: :object,
        properties: {
          trace_id:      UUID,
          workflow_id:   UUID,
          workflow_name: NULLABLE_STRING,
          event_type:    { type: :string },
          count:         { type: :integer },
          statuses:      { type: :object, additionalProperties: { type: :integer }, description: "Run count by WorkflowRunStatus" },
          reverted:      { type: :integer },
          first_at:      TIMESTAMP,
          last_at:       TIMESTAMP,
          run:           nullable_ref("WorkflowRun")
        },
        required: %w[trace_id workflow_id workflow_name event_type count statuses reverted first_at last_at run]
      },
      WorkflowRunGroupsResponse: {
        type: :object,
        properties: {
          groups: { type: :array, items: { "$ref" => "#/components/schemas/WorkflowRunGroup" } },
          meta:   { "$ref" => "#/components/schemas/PageMeta" }
        },
        required: %w[groups meta]
      },
      WorkflowRunRevertResult: {
        type: :object,
        properties: {
          status:     { type: :string, enum: %w[reverted] },
          reverted:   { type: :integer },
          conflicted: { type: :integer },
          skipped:    { type: :integer }
        },
        required: %w[status reverted conflicted skipped]
      },
      PageMeta: PAGE_META,

      # ── Activity, notifications, health ────────────────────────────────────
      ActivitySeverity: SEVERITY,
      ActivityEntry: {
        type: :object,
        properties: {
          id:             UUID,
          occurred_at:    TIMESTAMP,
          source:         { type: :string },
          event:          { type: :string },
          severity:       { "$ref" => "#/components/schemas/ActivitySeverity" },
          summary:        { type: :string },
          payload:        JSON_OBJECT,
          subject_type:   NULLABLE_STRING,
          subject_id:     NULLABLE_UUID,
          trace_id:       NULLABLE_UUID,
          caused_by_type: NULLABLE_STRING,
          caused_by_id:   NULLABLE_UUID,
          duration_ms:    { type: :integer, nullable: true }
        },
        required: %w[id occurred_at source event severity summary payload subject_type subject_id trace_id
                     caused_by_type caused_by_id duration_ms]
      },
      ActivityResponse: {
        type: :object,
        properties: {
          entries: { type: :array, items: { "$ref" => "#/components/schemas/ActivityEntry" } },
          meta:    { "$ref" => "#/components/schemas/PageMeta" }
        },
        required: %w[entries meta]
      },
      ActivityGroup: {
        type: :object,
        properties: {
          trace_id:   NULLABLE_UUID,
          count:      { type: :integer },
          severities: { type: :object, additionalProperties: { type: :integer }, description: "Entry count by ActivitySeverity" },
          sources:    { type: :array, items: { type: :string } },
          first_at:   TIMESTAMP,
          last_at:    TIMESTAMP,
          lead:       { "$ref" => "#/components/schemas/ActivityEntry" }
        },
        required: %w[trace_id count severities sources first_at last_at lead]
      },
      ActivityGroupsResponse: {
        type: :object,
        properties: {
          groups: { type: :array, items: { "$ref" => "#/components/schemas/ActivityGroup" } },
          meta:   { "$ref" => "#/components/schemas/PageMeta" }
        },
        required: %w[groups meta]
      },
      ActivityTraceResponse: {
        type: :object,
        properties: {
          trace_id:      UUID,
          entries:       { type: :array, items: { "$ref" => "#/components/schemas/ActivityEntry" } },
          workflow_runs: { type: :array, items: { "$ref" => "#/components/schemas/WorkflowRun" } },
          notifications: {
            type: :array,
            items: {
              type: :object,
              properties: {
                id:         UUID,
                title:      { type: :string },
                severity:   { "$ref" => "#/components/schemas/ActivitySeverity" },
                created_at: TIMESTAMP
              },
              required: %w[id title severity created_at]
            }
          }
        },
        required: %w[trace_id entries workflow_runs notifications]
      },
      AppNotification: {
        type: :object,
        properties: {
          id:           UUID,
          title:        { type: :string },
          body:         NULLABLE_STRING,
          severity:     { "$ref" => "#/components/schemas/ActivitySeverity" },
          href:         NULLABLE_STRING,
          subject_type: NULLABLE_STRING,
          subject_id:   NULLABLE_UUID,
          read_at:      NULLABLE_TIMESTAMP,
          created_at:   TIMESTAMP
        },
        required: %w[id title body severity href subject_type subject_id read_at created_at]
      },
      NotificationsResponse: {
        type: :object,
        properties: {
          notifications: { type: :array, items: { "$ref" => "#/components/schemas/AppNotification" } },
          unread_count:  { type: :integer }
        },
        required: %w[notifications unread_count]
      },
      SystemHealth: {
        type: :object,
        properties: {
          sources: {
            type: :array,
            items: {
              type: :object,
              properties: {
                source:      { type: :string },
                event:       { type: :string },
                severity:    { "$ref" => "#/components/schemas/ActivitySeverity" },
                summary:     { type: :string },
                occurred_at: TIMESTAMP,
                duration_ms: { type: :integer, nullable: true }
              },
              required: %w[source event severity summary occurred_at duration_ms]
            }
          },
          workflows: {
            type: :object,
            properties: {
              runs_7d:   { type: :integer },
              failed_7d: { type: :integer },
              waiting:   { type: :integer }
            },
            required: %w[runs_7d failed_7d waiting]
          },
          errors_24h: { type: :integer },
          market_data: {
            type: :object,
            properties: {
              providers: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    provider:    { type: :string },
                    instruments: { type: :integer },
                    failing:     { type: :integer },
                    last_error:  NULLABLE_STRING
                  },
                  required: %w[provider instruments failing last_error]
                }
              },
              stale_held_instruments: { type: :integer },
              open_drift_findings:    { type: :integer }
            },
            required: %w[providers stale_held_instruments open_drift_findings]
          }
        },
        required: %w[sources workflows errors_24h market_data]
      }
    }.freeze
  end

  register(Platform::SCHEMAS)
end
