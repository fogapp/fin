Rails.application.routes.draw do
  # Sign in with fog (fog:docs/signin-proposal.md §15): plain OpenID Connect,
  # so any provider OIDC_ISSUER names works the same way.
  scope "auth/oidc", controller: "auth/oidc" do
    get  "start",       action: :start,       as: :oidc_start
    get  "callback",    action: :callback,    as: :oidc_callback
    post "backchannel", action: :backchannel, as: :oidc_backchannel
    post "link",        action: :link,        as: :oidc_link
  end

  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"
  namespace :api do
    namespace :v1 do
      # First-run surface: fresh-instance check + the fog-backup restore
      # door (account creation itself is open passkey registration).
      get  "setup",         to: "setup#show"
      post "setup/restore", to: "setup#restore"
      # The console trades a fog sign-in's one-time code for its session.
      resource :handoff, only: :create

      # Manual fog-backup/2 artifacts (Settings → Backup), instance owner only.
      resources :backups, only: [ :index, :create, :destroy ] do
        collection { post :keys }
        member do
          post :download
          get  :artifact
        end
      end

      resource  :preferences, only: [ :show, :update ]
      # Instance-wide settings (the time zone); updates are household-admin only.
      resource  :instance_settings, only: [ :show, :update ]
      resources :api_tokens, only: [ :index, :create, :destroy ]
      # The consent page behind /connect/<ticket> (fog-integration/1): what
      # fog asks for an app, and a household admin's answer.
      resources :fog_connections, only: :show, param: :ticket do
        member do
          post :approve
          post :decline
        end
      end
      resources :device_invites, only: [ :create ]
      resources :webauthn_credentials, only: [ :index, :update, :destroy ]
      resources :cash_transactions, only: [ :index, :show, :create, :update, :destroy ] do
        collection do
          post :bulk_update
          post :filter
          get  :transfer_search
        end
        member do
          get    :similar
          get    :context
          post   :add_tag
          delete :remove_tag
        end
      end
      resources :saved_views, only: [ :index, :create, :update, :destroy ]
      resources :saved_reports, only: [ :index, :create, :destroy ]
      resources :issues, only: [ :index, :destroy ] do
        post :dismiss_all, on: :collection
      end
      resources :security_conversions, only: [ :index, :create, :destroy ] do
        member do
          post :confirm
          post :dismiss
        end
      end
      get "search", to: "search#index"
      get    "review",              to: "reviews#show"
      get    "budget",              to: "budget#show"
      get    "budget/calendar",     to: "budget#calendar"
      get    "budget/line_history", to: "budget#line_history"
      get    "budget/suggestions",  to: "budget#suggestions"
      put    "budget/line",         to: "budget#upsert_line"
      delete "budget/line",         to: "budget#destroy_line"
      put    "budget/period",       to: "budget#upsert_period"
      post   "budget/autofill",     to: "budget#autofill"
      post "reconciliation/accept",     to: "reconciliation#accept"
      post "reconciliation/accept_all", to: "reconciliation#accept_all"
      resources :loans, only: [ :index, :show, :create, :update, :destroy ] do
        member { get :candidate_transactions }
      end
      resources :real_estate_properties, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :refresh
          post   "valuations",              action: :create_valuation
          delete "valuations/:valuation_id", action: :destroy_valuation
        end
      end
      resources :merchants, only: [ :index, :show, :create, :update, :destroy ] do
        member { post :exclude; post :include }
      end
      resources :brokers, only: [ :index, :show, :create, :update, :destroy ]
      resources :accounts, only: [ :index, :show, :create, :update ] do
        resources :balance_snapshots, only: [ :index ], controller: "account_balance_snapshots"
        get :holdings, on: :member
      end
      resources :categories, only: [ :index, :show, :create, :update, :destroy ]
      resources :tags, only: [ :index, :show, :create, :destroy ]
      get "me",         to: "me#show"
      get "about",      to: "about#show"

      namespace :auth do
        scope :passkey, controller: "passkeys" do
          post "register/begin",      action: :register_begin
          post "register/finish",     action: :register_finish
          post "login/begin",         action: :login_begin
          post "login/finish",        action: :login_finish
          post "device_invite/begin", action: :device_invite_begin
          post "device_invite/finish", action: :device_invite_finish
          # The fog link page's proof that an account is yours.
          post "link/begin",          action: :link_begin
          post "link/finish",         action: :link_finish
        end
        post "switch_household", to: "sessions#switch_household"
      end
      resources :invites, only: [ :index, :create, :show, :destroy ], param: :code
      resources :households,             only: [ :index, :create, :update, :destroy ]
      resources :household_memberships,  only: [ :index, :update, :destroy ]
      get "dashboard",  to: "dashboard#index"
      get "net_worth",  to: "net_worth#index"
      get "net_worth/projection", to: "net_worth#projection"
      get "cashflow",              to: "cashflow#index"
      resources :subscriptions, only: [ :index, :show, :create, :update, :destroy ] do
        get :upcoming, on: :collection
        get :calendar, on: :collection
        member do
          post :accept
          post :dismiss
          post :restore
          post :end, action: :end_subscription
          post "occurrences/:occurrence_id/detach", action: :detach_occurrence
          post "occurrences/:occurrence_id/skip",   action: :skip_occurrence
        end
      end
      get "cashflow/activity",      to: "cashflow#activity"
      get "cashflow/sankey",        to: "cashflow#sankey"
      get "cashflow/spend_breakdown", to: "cashflow#spend_breakdown"
      get "portfolio",             to: "portfolio#index"
      get "portfolio/performance", to: "portfolio#performance"
      get "stats",      to: "stats#index"
      get "stats/:key", to: "stats#show", constraints: { key: /[a-z0-9_]+/ }
      get "cost_basis",  to: "cost_basis#index"
      patch "security_labels/:security_id", to: "security_labels#update"
      post "investment_lots/generate", to: "investment_lots#generate"
      resources :investment_lots, only: [ :index, :create, :update, :destroy ]
      resources :workflows, only: [ :index, :show, :create, :update, :destroy ] do
        get :catalog, on: :collection
        post :apply_to_existing, on: :member
        post :revert_runs, on: :member
        post :run_now, on: :member
      end
      resources :workflow_runs, only: [ :index, :show ] do
        post :revert, on: :member
      end
      get "activity", to: "activity#index"
      get "activity/trace/:trace_id", to: "activity#trace", as: :activity_trace
      get "system_health", to: "system_health#show"
      resources :notifications, only: [ :index ] do
        post :read, on: :member
        post :read_all, on: :collection
      end
      resources :transfers, only: [ :index, :create, :update, :destroy ] do
        collection do
          get  :candidates
          get  :for_transaction
          post :scan
        end
        member do
          post :confirm
          post :dismiss
        end
      end
      get "tax_profile", to: "tax_profiles#show"
      put "tax_profile", to: "tax_profiles#update"
      namespace :tax do
        get "report", to: "reports#show"
        get "export", to: "exports#show"
        resources :estimated_payments, only: [ :create, :destroy ]
        resources :checklist_items,    only: [ :create, :update, :destroy ]
        resources :adjustments,        only: [ :create, :update, :destroy ]
      end
      namespace :equity do
        get "summary", to: "summary#show"
        post "grants/:id/exercise_plan", to: "exercise_plans#create"
        resources :companies, only: [ :create, :update, :destroy ] do
          resources :fmv_entries, only: [ :create ]
        end
        resources :fmv_entries, only: [ :destroy ]
        resources :grants, only: [ :create, :update, :destroy ] do
          resources :events, only: [ :create ]
        end
        resources :events, only: [ :destroy ]
      end
      get "benchmarks",         to: "benchmarks#index"
      get "benchmarks/:symbol", to: "benchmarks#show"
      resources :investment_transactions, only: [ :index, :create ] do
        member { post :reprocess }
      end
      resources :securities, only: [ :index, :show ], path: "market" do
        collection do
          post :watch
          get  :search
          get  :summary
        end
        member do
          delete :unwatch
          post   :refresh
          get    :news
          get    :candles
        end
      end
      resources :buys,      only: [ :index ]
      resources :sells,     only: [ :index ]
      resources :dividends, only: [ :index ]
      resources :crypto,    only: [ :index ]
      resources :imports, only: [ :create ] do
        collection do
          post :preview
          get :spreadsheet_format
        end
      end
      namespace :coin_market_cap do
        resource :configuration, only: [ :show, :update ] do
          post :test, on: :member
        end
      end
      namespace :alpha_vantage do
        resource :configuration, only: [ :show, :update ] do
          post :test, on: :member
        end
      end
      namespace :tiingo do
        resource :configuration, only: [ :show, :update, :destroy ] do
          post :test, on: :member
        end
      end
      namespace :rentcast do
        resource :configuration, only: [ :show, :update, :destroy ] do
          post :test, on: :member
        end
      end
      # The Office integration: spreadsheets built from Fin's datatables
      # in the household's Office instance, and sheets imported back.
      namespace :office do
        resource :configuration, only: [ :show, :update, :destroy ] do
          post :test, on: :member
        end
        resources :sheet_exports, only: [ :index, :create, :destroy ] do
          post :refresh, on: :member
        end
        # Office spreadsheets read back in as account transactions.
        resources :spreadsheets, only: [ :index ] do
          member do
            get :preview
            post :import
          end
        end
      end
      namespace :coinbase do
        resource :configuration, only: [ :show, :update ] do
          post :test, on: :member
        end
        resources :accounts, only: [ :index ]
        resource :sync, only: [ :create ], controller: "sync"
      end
      namespace :alchemy do
        resource :configuration, only: [ :show, :update ] do
          post :test, on: :member
        end
        resources :wallets, only: [ :index, :create, :update, :destroy ] do
          member { post :backfill }
        end
        resource :sync, only: [ :create ], controller: "sync"
      end
      namespace :plaid do
        resource :link_token, only: [ :create ]
        resource :configuration, only: [ :show, :update ]
        resources :items, only: [ :index, :create, :destroy ] do
          member { post :sync }
        end
        resources :accounts, only: [ :index, :update ] do
          member do
            post :sync
          end
        end
      end
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Inbound provider webhooks: no bearer token — authenticated by each
  # provider's payload signature (see Webhooks::AlchemyController).
  namespace :webhooks do
    post :alchemy, to: "alchemy#create"
  end

  # MCP server (Streamable HTTP): JSON-RPC over POST, authenticated with the
  # same bearer ApiTokens as the REST API. GET/DELETE answer 405 — we don't
  # serve SSE streams or server-side sessions — and defining GET explicitly
  # keeps /mcp out of the SPA catch-all below.
  post  "mcp", to: "mcp#handle"
  match "mcp", to: "mcp#method_not_allowed", via: [ :get, :delete ]

  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # fog-backup machine surface (fog:docs/backup-contract.md): fog drives
  # delegated backups and restores through here, authenticated by the
  # fog-injected FOG_API_TOKEN — never by API tokens or sessions.
  scope "fog", controller: :fog, defaults: { format: :json } do
    get "backup", action: :descriptor
    post "backup", action: :create_backup
    get "backup/jobs/:id", action: :job_status, as: :fog_backup_job
    get "backup/jobs/:id/artifact", action: :artifact, as: :fog_backup_artifact
    delete "backup/jobs/:id", action: :destroy_job
    post "restore", action: :restore, as: :fog_restore
  end

  # fog-integration/1 (fog:docs/integrations-contract.md): fog connects
  # another app to Fin through here, with a household admin's consent at
  # /connect/<ticket> in between. Same FOG_API_TOKEN bearer.
  scope "fog", defaults: { format: :json } do
    resources :integrations, controller: :fog_integrations, only: [ :create, :show, :destroy ], as: :fog_integrations do
      member { post :claim }
    end
  end

  root "spa#index"

  # SPA catch-all for client-side routing (must be last)
  get "*path", to: "spa#index", constraints: ->(req) {
    !req.path.start_with?("/api", "/rails", "/assets", "/fog", "/auth/oidc") &&
    !req.path.match?(/\.[a-z0-9]+$/i)
  }
end
