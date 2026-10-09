# MCP + Rails Demo

A small, realistic Rails MVC application — Projects and Tasks owned by Users —
with real authentication/authorization, exposed to MCP clients over
**Streamable HTTP** at `/mcp`.

The architectural point of this project: **MCP is a thin adapter over the
Rails application, not a second business-logic layer.** The MCP tool and
resource call the exact same `ActiveRecord` scopes and authorization idiom
(`Current.user.projects`) that the Rails controllers use.

```text
Normal Rails UI ───────┐
                        ↓
                  Rails application
                        ↓
                  Existing logic (scopes on Project / Task)
                        ↓
                    PostgreSQL
                        ↑
                        │
MCP Client → HTTP → /mcp → MCP tools/resources
```

## Stack

* Ruby 4.0.7, Rails ~> 8.1.3, PostgreSQL
* `mcp` gem ~> 1.1 (official Ruby MCP SDK) for the server side
* `faraday` + `event_stream_parser` for the `MCP::Client` demo script only

## Domain

```text
User
  ├── has_many :projects
  └── has_many :tasks, through: :projects

Project belongs_to :user
Project has_many :tasks

Project.active, Project.search(query)
Task.open, Task.overdue
```

Controllers are thin; query logic lives on the models as scopes so the MCP
layer can reuse it instead of duplicating it.

## Authentication & authorization

Two independent credential types:

* **Browser auth** — Rails 8's native `bin/rails generate authentication`
  generator (`User` + `has_secure_password`, `Session`, signed cookie,
  `Current.session`). A hand-written `RegistrationsController` adds sign-up,
  which the generator omits.
* **MCP HTTP auth** — a separate bearer `ApiToken` (SHA-256 digest stored,
  plaintext shown exactly once on creation), checked by the `McpAuthentication`
  Rack middleware in front of `/mcp` only. It sets `Current.api_token`, and
  `Current#user` resolves from `session&.user || api_token&.user`.

A browser session cookie does **not** authenticate a remote MCP client — it's
a different transport, with no session store shared with the client.

Authorization is ownership-based (no Pundit/CanCan): every lookup, whether
from a controller, the MCP tool, or the MCP resource, goes through
`Current.user.projects` / `Current.user.tasks`, so another user's record
raises `ActiveRecord::RecordNotFound` (a 404, or an MCP "not found" — never a
403 that would leak existence).

## MCP server

* **Transport**: `MCP::Server::Transports::StreamableHTTPTransport`, mounted
  directly in `config/routes.rb` at `/mcp` (wrapped by `McpAuthentication`).
  One `MCP::Server` is built once at boot — no extra Rails routes or
  controller needed; the transport is a bare Rack app handling
  `POST`/`GET`/`DELETE` (JSON-RPC, SSE, session teardown) itself.
* **Tool** — `search_projects`: searches the authenticated user's active
  projects by name (`Current.user.projects.active.search(message)`), input
  validated by the gem's own JSON-Schema validation before `call` runs.
* **Resource template** — `project://{id}`: resolves a real `Project` scoped
  to `Current.user`, returns an intentional JSON representation (not the raw
  AR object), and raises `MCP::Server::ResourceNotFoundError` for missing or
  unauthorized ids.
* **Session ownership** — `McpSessionOwnership` (in-memory) records which
  `ApiToken` created each MCP session and is wired into the transport's
  `session_request_validator`, so a valid token can't be used to ride another
  token's session id.

Because `StreamableHTTPTransport` keeps session/SSE state in memory, the app
must run single-process Puma (`workers 0`, the default here) — it isn't
safe to scale horizontally without moving that state to shared storage.

## Getting started

```bash
bin/setup        # bundle install, db create/migrate, db/seeds
bin/rails server
```

Normal Rails routes (`/`, `/projects`, `/session`, `/registration`, ...) work
as any Rails app. Issue an MCP API token from the console:

```ruby
user = User.first
token = ApiToken.generate!(user: user, name: "demo")
token.plaintext_token # => shown once, save it now
```

### Using it with Claude Code / Claude Desktop

```bash
claude mcp add --transport http mcp-rails-demo http://localhost:3000/mcp \
  --header "Authorization: Bearer <token>"
```

Then ask it something like "search my projects for Website", or attach
`project://<id>` directly as a resource.

### Using the standalone demo scripts

* `script/mcp_client_demo.rb` — a plain-Ruby (stdlib `Net::HTTP` only, no
  `mcp` gem) client that drives `/mcp` over real Streamable HTTP and
  exercises the full checklist: initialize, discover, call the tool, read
  the resource, and verify the auth/authorization/validation failure modes.
* `script/mcp_gem_client_demo.rb` — the same checklist, but through
  `MCP::Client`/`MCP::Client::HTTP` (the gem's client half) instead of raw
  HTTP.

Both expect `bin/rails server` running locally and a valid `ApiToken`
(edit the token constant at the top of the script, or pass it as
instructed in the script's header).

## Tests

```bash
bin/rails test
bin/rubocop
```

Covers models, controllers, the MCP tool, the MCP resource, and an
integration test for `McpAuthentication` (missing/invalid/wrong-scheme/revoked
token, and a live session-hijack scenario).

## Project log

This project was built stage by stage (Rails CRUD → auth → MCP SDK
evaluation → mount → tool → resource → MCP auth → end-to-end verification →
final architecture review). The full build log, architectural decisions, and
mistakes/corrections made along the way are recorded in `CLAUDE.md`.
