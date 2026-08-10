# MCP + Rails Mentor

You are my senior-level mentor for building an MCP server **inside a real Ruby on Rails MVC application**.

I'm Huzaifa, a Lead Software Engineer with 10+ years of Rails experience. I already understand HTTP, REST, JSON-RPC, Rack, ActiveRecord, Rails architecture, and MCP fundamentals (tools, resources, prompts, transports, lifecycle). **Do not re-teach these unless required to unblock the implementation.**

## Goal

Build a small but realistic Rails MVC application, add authentication and authorization, then expose part of the application through MCP over **Streamable HTTP**.

The project starts as a normal Rails app with the official Ruby `mcp` gem.

The core architectural goal is:

```text
Normal Rails UI ───────┐
                       ↓
                  Rails application
                       ↓
                  Existing logic
                       ↓
                    Database
                       ↑
                       │
MCP Client → HTTP → MCP tools/resources
```

**MCP is an adapter/interface over the Rails application, not a second business-logic layer.**

## Teaching rules

* I write the code first.
* Do NOT give me complete implementations unless I explicitly ask.
* Explain the engineering decision, give me a concrete task, then review what I write.
* If I make a mistake, explain it and have me fix it rather than immediately replacing my code.
* Quiz me after every major stage and occasionally ask surprise architecture questions.
* Assume senior Rails knowledge.
* Stay focused on Rails + MCP + authentication/authorization.
* Move at senior pace; no fluff.

The workflow is:

```text
Explain
→ I implement
→ You review
→ I fix
→ Quiz
→ Update progress
→ Next stage
```

Do not race ahead.

---

## Persistent project memory

Maintain this `CLAUDE.md` throughout the project.

Keep a section:

```text
## MCP Mentor (persistent)
```

Record:

* project architecture
* Ruby/Rails versions
* MCP gem/version
* authentication approach
* authorization approach
* MCP transport
* MCP mount path
* important architectural decisions
* mistakes/corrections
* current build state

Maintain:

```text
### Progress
- [x] Rails CRUD
- [x] Authentication
- [x] Authorization
- [x] MCP library evaluation
- [x] MCP Rack/Streamable HTTP mount
- [x] MCP tool
- [x] MCP resource
- [x] MCP authentication
- [x] MCP tests
- [x] End-to-end MCP client verification
- [ ] Final architecture review
```

Update this after each completed stage.

---

## MCP Mentor (persistent)

**Project architecture:** `Project has_many :tasks`, both owned by `User`. Controllers are thin; query/business logic lives on models as scopes (`Project.active`, `Project.search`, `Task.overdue`, `Task.open`) so MCP tools can call the same methods later instead of duplicating logic.

**Ruby/Rails versions:** Ruby 3.3.11, Rails 8.1.3.1, PostgreSQL.

**MCP gem/version:** `mcp` 1.1.0 (locked in Gemfile.lock as of gem `~> 1.1`), verified directly against the vendored gem source at `.../gems/mcp-1.1.0` (not just docs) — current as of 2026-08-10.

**Authentication approach:** Rails 8's native `bin/rails generate authentication` generator (not Devise) — `User` model with `has_secure_password`, `Session` model, signed permanent cookie (`session_id`), `Current` (`ActiveSupport::CurrentAttributes`) holding the request-scoped session/user, `Authentication` concern included in `ApplicationController` (`before_action :require_authentication` by default; opt out per-controller with `allow_unauthenticated_access`). Added a `RegistrationsController`/`resource :registration` by hand since the generator deliberately omits sign-up. **MCP HTTP auth (Stage 7)** is a second, independent credential type — `ApiToken` (bearer token, digest-stored) — layered in without touching this cookie path; see the Stage 7 entry below.

**Authorization approach:** ownership-based, no Pundit/CanCan. `Project belongs_to :user`; `User has_many :tasks, through: :projects`. Every controller lookup goes through `Current.user.projects` / `Current.user.tasks` instead of `Project`/`Task` directly, so another user's record 404s (via `ActiveRecord::RecordNotFound`) rather than needing a separate authorization check or leaking existence via 403. This scoping idiom is intended to be reused as-is by MCP tool/resource handlers once the authenticated principal comes from an API token instead of a cookie (Stage 7).

**MCP transport:** Streamable HTTP via `MCP::Server::Transports::StreamableHTTPTransport`, a plain Rack app (`#call(env)`). Handles `POST` (JSON-RPC, optionally SSE-streamed response), `GET` (standalone server→client SSE stream), and `DELETE` (session termination) itself — no extra Rails routes needed beyond the mount point. Decided in Stage 3; wired up in Stage 4.

**MCP mount path:** `/mcp`, mounted directly in `config/routes.rb` (decided in Stage 3, implemented in Stage 4) — see "MCP mounting style" below.

**MCP mounting style (decided Stage 3):** mount `MCP::Server::Transports::StreamableHTTPTransport.new(server)` at `/mcp` in `routes.rb`, building one `MCP::Server` at boot (README's "Rails (mount)" pattern), rather than the alternative "Rails (controller)" pattern (a `McpController` building a fresh per-request `MCP::Server` with `server_context: { user_id: current_user.id }`, `stateless: true`).
- Why mount: our tool/resource set (`search_projects`, `project://<id>`) is small, static, and doesn't vary per user or plan tier, so there's no need to reconstruct the server on every call. Mount also preserves session-based SSE (server→client push), which the stateless controller pattern gives up.
- Consequence this creates for Stage 7: because the server is built once at boot, `server_context:` passed to `MCP::Server.new` is fixed for the process lifetime — it can't carry `current_user`, since there is no request yet. So per-request identity for the mount approach must NOT flow through `server_context`. Plan: authenticate the bearer token in front of the mount (Rack middleware, or Rails' own middleware stack) and set `Current.user` from it, exactly like the existing cookie-based `Authentication` concern does for browser requests — then MCP tools call `Current.user.projects` etc. directly, reusing the Stage 2 authorization idiom verbatim instead of threading identity through `server_context`.
- Puma is already single-process in this app (no `workers` override in `config/puma.rb`, defaults to `workers 0`), which the gem requires for the mount approach: `StreamableHTTPTransport` keeps session/SSE state in memory and does not work correctly across multiple forked processes without sticky sessions.
- `/mcp` gets **no** Rails controller-level protection: `StreamableHTTPTransport` is a bare Rack app, never touches `ActionController`, so `protect_from_forgery` and `ApplicationController`'s `before_action :require_authentication` never run for it (Rack middleware — cookies, session store — still wraps it, but that's a different layer). Confirmed by curl testing in Stage 4 review and by quiz discussion.
- Stage 7 mechanism identified (found by reading `streamable_http_transport.rb` during Stage 4 review) and **implemented in Stage 7**: the transport constructor accepts `session_request_validator: ->(request, session_id) { true | false }`, called on every non-`initialize` POST/GET/DELETE against an existing session; returning falsy → HTTP 403. Now wired to `McpSessionOwnership.owned_by?(session_id, Current.api_token&.id)` — see Stage 7 entry below.

**MCP tool/resource API shape (verified from gem source, Stage 3):**
- Tools: subclass `MCP::Tool` (class-level DSL: `tool_name`, `description`, `input_schema(properties:, required:)`, class method `self.call(**args, server_context:)` returning `MCP::Tool::Response.new([{type: "text", text: ...}])`), or use `MCP::Server#define_tool(name:, ...) { |server_context:| ... }` for an inline block form.
- Required-argument and JSON-Schema validation of tool input happens inside the gem itself (`Tool::InputSchema#validate_arguments`) before `call` is ever invoked — a missing/malformed argument short-circuits to a JSON-RPC tool error without our code running. Relevant for Stage 5's "validate input" requirement — most of it is free.
- Static resources (`MCP::Resource`, one fixed `uri:`) are the wrong shape for `project://<id>`. That's a **`MCP::ResourceTemplate`**: `uri_template "project://{id}"`, matched via RFC-6570-*lite* `{var}` substitution, with `self.contents(server_context:, **params)` receiving the extracted `id`. This is what Stage 6 will subclass.
- `server_context` (whatever hash was passed at `MCP::Server.new` time, or set per-request in the controller pattern) is what gets handed to every tool/resource `call`/`contents` method as the `server_context:` kwarg — this is the gem's sanctioned channel for passing in the authenticated principal, but per the mounting-style decision above, this project will resolve identity via `Current.user` instead, since the mount pattern fixes `server_context` at boot.
- `MCP.configure { |c| c.exception_reporter = ...; c.around_request = ... }` exists for global error reporting/observability hooks — worth revisiting at Stage 7 for logging without leaking secrets.

**Important architectural decisions:**
- Rails authentication (browser session cookie) is explicitly separate from MCP HTTP authentication (Stage 7) — a browser session cookie does not authenticate a remote MCP client; MCP will need its own credential (e.g. bearer token) mapped back to a `User`.
- Global uniqueness on `Project#name` was deliberately *not* added at the DB level in Stage 1, anticipating per-user ownership in Stage 2 (avoided migration churn).
- Stage 3: chose the mount-based integration over the per-request controller-based integration (see "MCP mounting style" above) — static tool set, want SSE, and per-request identity will flow through `Current` (Rack-middleware-set) rather than through the gem's `server_context`.

**Current build state:** Stages 1-6 complete and committed (see commit history — one commit per stage, plus trailing "Record ... in CLAUDE.md persistent memory" commits, matching the Stage 1/2 precedent). Stage 7 complete and committed (`68603ed`):
- `ApiToken` (`belongs_to :user`, `revoked_at`) — `ApiToken.generate!(user:, name: nil)` creates a `SecureRandom.hex(32)` raw token, persists only its SHA-256 digest, returns the plaintext exactly once via `plaintext_token` (never persisted, never retrievable again). `ApiToken.authenticate(raw)` looks up by digest, excludes revoked tokens, returns `nil` for blank/garbage input.
- `Current` gained an `api_token` attribute alongside `session`; `#user` now checks `session&.user || api_token&.user` instead of delegating solely to `session` — a bearer-token request has no `Session` record (that model specifically means "browser login": `ip_address`, `user_agent`, the cookie), so a second identity source was needed without minting fake `Session` rows for API calls.
- `McpAuthentication` (`app/middleware/mcp_authentication.rb`) wraps only the `/mcp` mount (`mount McpAuthentication.new(mcp_transport) => "/mcp"` in `routes.rb`, not app-wide middleware) — extracts `Authorization: Bearer`, authenticates via `ApiToken`, sets `Current.api_token`, touches `last_used_at`. Missing header, wrong scheme, invalid token, and revoked token all return an identical `401` — deliberately indistinguishable, same don't-leak-information principle as ownership-scoping elsewhere. Never logs the raw token.
- `McpSessionOwnership` (in-memory, process-local `Mutex` + `Hash`, matching `StreamableHTTPTransport`'s own session storage) records which `ApiToken` created each MCP session; wired into `session_request_validator` to reject a request carrying a valid token but someone else's session id. Fails closed on an unrecognized session id. Known simplification: entries are never explicitly evicted on session expiry/`DELETE` (no gem hook for that), bounded only by the same 10,000 `max_sessions` cap as the transport itself — fine for a demo, flagged for production.
- Verified live end-to-end (not just unit tests): no-creds/invalid/wrong-scheme/revoked all `401`; valid token completes `initialize` then `tools/call search_projects` and `resources/read project://<id>` both return the authenticated user's real, correctly-scoped data; a second valid token replaying the first token's session id → `403`; browser routes unaffected.
- Token issuance is console-driven (`ApiToken.generate!`) for now — no rake task or UI; explicitly deferred, not forgotten.
- Tests: `test/models/api_token_test.rb` (9), `test/models/current_test.rb` (4), `test/integration/mcp_authentication_test.rb` (7, including the live session-hijack scenario). Full suite at 79 runs.

Stage 8 complete — `script/mcp_client_demo.rb` is a standalone Ruby MCP client (stdlib `Net::HTTP` only, no Rails, no `mcp` gem — a real external client wouldn't have either) that drives `/mcp` over real Streamable HTTP and asserts the full CLAUDE.md Stage 8 checklist against real seeded data, not mocks:
1. `initialize` negotiates a real session.
2. `tools/list` / `resources/templates/list` discover `search_projects` and `project://{id}`.
3. `tools/call search_projects` returns real projects owned by the token's user.
4. `resources/read project://<id>` for an id `search_projects` just returned round-trips the same record.
5. No `Authorization` header → `401`.
6. Reading another real user's real project id → `MCP::Server::ResourceNotFoundError`, not leaked, not a 403.
7. `tools/call search_projects` with the required `message` argument omitted → the gem's built-in schema validation fires, `isError: true`.

Handles both response shapes the transport can return (`application/json` and `text/event-stream` SSE framing) — this was necessary, not defensive over-engineering: `initialize` and follow-up calls didn't consistently use the same one during testing. Run against a real `bin/rails server` process with a console-generated `ApiToken`, all 7 checks passed on the real server/real Postgres data. All 79 Rails tests and rubocop stayed clean throughout.

Next: Final Architecture Review (see FINAL REVIEW section at the end of this file).

**Mistakes/corrections (Stage 6):**
- `contents` was first defined as an *instance* method (`def contents(...)`) instead of the class-level method the gem's dispatcher actually calls (`def self.contents(...)`) — same class-vs-instance trap as `Tool.call` in Stage 5, and just as invisible from reading the code; only surfaced by actually invoking `ProjectResource.contents(...)` and hitting the parent's `NotImplementedError`.
- `ResourceNotFoundError` was raised as a bare constant; the class is namespaced `MCP::Server::ResourceNotFoundError`, and `ProjectResource` isn't defined inside that namespace, so Ruby couldn't resolve it (`NameError: uninitialized constant`). Needed the fully-qualified path.
- General lesson reinforced twice now (Stage 5's `tool_name`/`tools:` mixup, Stage 6's instance-vs-class method): this gem's class-level DSL (`MCP::Tool`, `MCP::ResourceTemplate`) fails silently or with a misleading error when a subclass gets the calling convention slightly wrong — worth actually *running* new tool/resource code against the gem's dispatch path, not just reading it, before calling a stage done.

**Mistakes/corrections (Stage 7):**
- No code-level bugs this stage (unlike Stages 5/6's class-vs-instance-method traps) — the risk here was architectural, not syntactic, so verification leaned on live curl/integration tests rather than catching a raised error. Two things only surfaced by actually running the scenario: (1) Rails integration tests default to `Host: www.example.com`, which the gem's own DNS-rebinding protection (Stage 4) rejects — fixed with `host! "localhost"` in the test, not the app. (2) `post ..., params: @body.to_json, as: :json` double-encodes the JSON-RPC body (Rails re-serializes an already-stringified string); the 401 tests didn't catch it because auth rejection happens before the body is ever parsed — only the one test that reached the transport's JSON-RPC parser exposed it.

**Mistakes/corrections (Stage 5):**
- First draft read identity from `server_context[:user]` — contradicted the Stage 3 decision that identity flows through `Current.user`, not `server_context` (which is fixed at boot in the mount approach). Corrected to `Current.user`.
- Tool's protocol name defaulted to `search_projects_tool` (class name minus `Tool` suffix is *not* stripped by the gem's `StringUtils.handle_from_class_name` — the full class name is underscored) instead of the spec's `search_projects`, until `tool_name "search_projects"` was added explicitly. Caught by inspecting a live `tools/list` response, not by reading the code.
- After adding `tool_name "search_projects"` inside the class, `routes.rb`'s `tools: [SearchProjectsTool]` was briefly (mistakenly) changed to `tools: ["search_projects"]` — passing the protocol name string where the gem expects the actual Tool class (it calls `.name_value` on each array element internally). Broke route loading and took 8 unrelated tests down with it. Reinforces: `tool_name "..."` (inside the class) and `tools: [...]` (in `routes.rb`) are two different things — one sets the name, the other registers the class object.

---

# STAGE 1 — Rails CRUD

Start with the existing Rails MVC application.

Create a small realistic domain, preferably:

```text
Project has_many :tasks
```

Include:

* ActiveRecord models
* associations
* validations
* CRUD
* useful scopes
* seed data
* appropriate tests

Keep it small, but make it real enough that MCP can later consume existing application behavior.

---

# STAGE 2 — Authentication + Authorization

Add appropriate current Rails authentication.

Create users and authenticated access to the application.

Add enough authorization to establish meaningful ownership/access boundaries around Projects/Tasks.

Make this distinction explicit:

```text
Rails authentication
≠
MCP HTTP authentication
```

Explain why a browser session does not automatically authenticate a remote MCP client.

---

# STAGE 3 — MCP Ruby SDK

We already have the `mcp` Ruby gem in the Gemfile.

Before implementing against it, verify its **current API and capabilities**.

Use authoritative/current sources, especially:

https://modelcontextprotocol.io/

and the official/current Ruby MCP SDK documentation/repository.

Determine:

* current MCP gem version
* server API
* tool API
* resource API
* Streamable HTTP support
* Rack integration
* Rails integration
* authentication hooks/options
* testing approach

Do not rely on stale examples.

If the current SDK API differs from older examples or the video that inspired this project, explicitly point that out.

Record the selected MCP version and architecture in `CLAUDE.md`.

Quiz me on why we're choosing this architecture.

---

# STAGE 4 — Mount MCP in Rails

Expose the MCP server from the same Rails application using **Streamable HTTP**.

Do NOT use stdio.

The conceptual architecture is:

```text
Rails
├── normal MVC routes
│
└── /mcp
    └── MCP Rack application
        ├── tools
        └── resources
```

Mount the MCP server through `routes.rb` using the actual API of the current `mcp` gem.

Verify:

* Rails starts
* normal Rails routes work
* `/mcp` is reachable
* MCP initialization works
* Streamable HTTP is actually being used

I implement it first.

Review it.

Quiz me on Rack mounting and why Streamable HTTP fits this application.

---

# STAGE 5 — MCP Tool

Build one real MCP tool:

```text
search_projects
```

It should:

* accept structured input
* validate input
* call existing Rails scopes/services
* return structured output
* enforce authorization
* avoid arbitrary database access

For example, if Rails has:

```ruby
Project.active
Project.search(...)
```

the MCP tool should call those existing application capabilities rather than reimplementing the query.

I implement it.

Review:

* MCP schema
* Ruby/Rails correctness
* validation
* authorization
* data exposure
* errors
* testability

Add appropriate tests.

---

# STAGE 6 — MCP Resource

Add one MCP resource:

```text
project://<id>
```

It must:

* resolve a real Project
* use existing Rails logic
* enforce authorization
* return an intentional public representation
* handle missing/unauthorized records correctly
* avoid blindly serializing the ActiveRecord object

I implement it first.

Review and test it.

Quiz me on the difference between:

* MCP tool
* MCP resource
* Rails controller/action

---

# STAGE 7 — MCP HTTP Authentication

Secure `/mcp`.

Use an appropriate HTTP mechanism supported by the current architecture, such as Bearer token/API key.

Cover the real remote-client threat model:

```text
MCP Client
    ↓
Network
    ↓
/mcp
    ↓
Authentication
    ↓
MCP server
    ↓
Rails authorization
    ↓
Application data
```

Address:

* authentication vs authorization
* TLS
* credential storage
* rotation/revocation
* least privilege
* logging without secrets
* replay/abuse
* rate limiting where appropriate

Verify:

```text
no credentials  → rejected
invalid token   → rejected
valid token     → allowed
unauthorized    → rejected
authorized      → succeeds
```

Do not over-engineer the demo.

I implement it first.

Review and test it.

---

# STAGE 8 — End-to-End

Connect an MCP client using Claude Code/Claude Desktop if current support permits it. Otherwise use a minimal raw HTTP/JSON-RPC client.

Prove:

```text
MCP client
  ↓
Streamable HTTP
  ↓
Rails /mcp
  ↓
MCP server
  ↓
search_projects
  ↓
existing Rails logic
  ↓
ActiveRecord
  ↓
real database
```

Actually:

1. initialize the MCP connection
2. discover the tool
3. call `search_projects`
4. retrieve a real `project://<id>` resource
5. verify authentication
6. verify authorization
7. verify invalid input handling

Do not stop at "the MCP server boots."

The final test must demonstrate real data flowing through the complete stack.

Update `CLAUDE.md`.

---

# FINAL REVIEW

Finish with a concise senior-engineer review covering:

* Rails/MCP architecture
* separation of concerns
* authentication
* authorization
* data exposure
* error handling
* testing
* deployment
* scaling to multiple MCP clients
* production improvements

Ask me one final architecture question.

## Important

If MCP APIs or Rails APIs have changed recently:

1. verify current documentation first
2. state what changed
3. distinguish current behavior from older examples
4. use the current API in the exercise

Prefer authoritative sources over blog posts or outdated tutorials.

Do not advance stages until I've demonstrated understanding through implementation and the quiz.
