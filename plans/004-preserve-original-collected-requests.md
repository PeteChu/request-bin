<!-- markdownlint-disable MD013 -->

# Plan 004: Preserve original request bodies, methods, and media types

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 024bc84..HEAD -- AGENTS.md config/config.exs config/runtime.exs lib/request_bin/request.ex lib/request_bin/bins/request.ex lib/request_bin_web/endpoint.ex lib/request_bin_web/router.ex lib/request_bin_web/controllers/bin_controller.ex lib/request_bin_web/plugs/request_capture.ex test/request_bin/request_test.exs test/request_bin_web/plugs/request_capture_test.exs test/request_bin_web/controllers/bin_controller_test.exs`
> Plan 003 is a declared dependency and intentionally changes
> `config/config.exs`, `config/runtime.exs`, the endpoint, and the router. Read
> Plan 003 and confirm its `TrustedClientIp` and collector-only `RateLimit` work
> is present before continuing. Any other mismatch from the excerpts or the
> expected Plan 003 result is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/003-trust-client-ip-and-scope-rate-limits.md`
- **Category**: bug
- **Planned at**: commit `024bc84`, 2026-07-17

## Why this matters

RequestBin exists to inspect the request that another system actually sent. Today, endpoint parsers consume JSON, form, and multipart bodies before the collector reads them, so the stored raw body is empty for common webhook media types. Malformed JSON is rejected before it can be inspected, non-JSON `Accept` headers are rejected by the collector pipeline, and `Plug.MethodOverride` can mutate the method before persistence. This plan gives collector routes a bounded, non-raising capture path while preserving normal Phoenix parsing for non-collector routes.

## Current state

Relevant files:

- `lib/request_bin_web/endpoint.ex` — installs `Plug.Parsers`, `Plug.MethodOverride`, and `Plug.Head` before routing.
- `lib/request_bin_web/router.ex` — collector pipeline currently requires JSON through `accepts`; after Plan 003 it also contains the collector-only rate limiter.
- `lib/request_bin/request.ex` — reads an already-consumed body and then decodes/stores it.
- `lib/request_bin_web/controllers/bin_controller.ex` — returns HTML responses and can pass an arbitrary error term to `html/2`.
- `lib/request_bin/bins/request.ex` — declares `body_raw` as `:string` although the migration column is binary.
- `priv/repo/migrations/20250210100018_create_requests.exs` — existing `body_raw` column is `:binary`; no migration is needed to align the schema type.
- `lib/request_bin_web/plugs/request_capture.ex` — create; it will capture collector bodies and delegate normal parsing for all other paths.

Current parser order:

```elixir
# lib/request_bin_web/endpoint.ex:51-57
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library()

plug Plug.MethodOverride
plug Plug.Head
```

Current raw-body read occurs after those parsers:

```elixir
# lib/request_bin/request.ex:20-29
headers =
  format_headers(req_headers)
  |> Map.filter(fn {key, _value} ->
    !String.starts_with?(key, "fly-") ||
      !String.starts_with?(key, "x-") ||
      key != "via"
  end)

{:ok, raw_body, _conn} = Plug.Conn.read_body(conn)
```

A runtime characterization probe with a JSON body produced an empty `body_raw` while `body_params` contained the decoded map. A malformed JSON body raised `Plug.Parsers.ParseError` before routing. Those are confirmed regressions, not hypotheses.

Current format restriction:

```elixir
# lib/request_bin_web/router.ex:17-20
pipeline :no_csrf_protection do
  plug :accepts, ["json"]
end
```

Current persistence performs a second decode and can pass a non-map JSON value to an Ecto `:map` field:

```elixir
# lib/request_bin/request.ex:107-123
formatted_body_parsed =
  case request_info.body do
    body when is_map(body) -> body
    body when is_binary(body) and body != "" ->
      case Jason.decode(body) do
        {:ok, parsed} -> parsed
        _ -> %{"raw" => body}
      end
    _ -> %{}
  end
```

The migration/schema mismatch is:

```elixir
# lib/request_bin/bins/request.ex:12
field :body_raw, :string

# priv/repo/migrations/20250210100018_create_requests.exs:10
add :body_raw, :binary
```

Repository conventions:

- The application is now Phoenix 1.8.9 / LiveView 1.2.7. `AGENTS.md` requires preserving the custom RemoteIp/rate-limit behavior, existing hooks, and product UI. This plan must retain Plan 003’s hardened versions of those plugs and must not modify LiveView templates or JavaScript.
- Web boundary logic lives in a Plug/controller; persistence flows through `RequestBin.Requests` and `RequestBin.RequestsRepo`.
- Controller tests use `RequestBinWeb.ConnCase`; database/context tests use `RequestBin.DataCase` and `RequestBin.Fixtures` from Plan 002.
- Error responses should expose stable public messages, not changeset or exception internals.
- Keep the public collector routes and 200/404/422 status contracts unless this plan explicitly adds 413 for oversized bodies.

## Target behavior

For the existing exact collector path `/bin/:id` and methods handled by the router:

1. Read at most the configured body limit once, before `Plug.Parsers`.
2. Store the exact bytes in `conn.private[:request_bin_raw_body]`.
3. Store the pre-override method in `conn.private[:request_bin_original_method]`.
4. Parse JSON and URL-encoded data non-raising for the `body_parsed` map.
5. Preserve malformed and multipart payloads as raw bytes even when no safe parsed representation exists.
6. Return 413 without persistence when the body exceeds the configured limit.
7. Do not enforce a response `Accept` format on collection routes.
8. For every non-collector path, preserve the existing `Plug.Parsers` and `Plug.MethodOverride` behavior.

Use an explicit default limit of 8,000,000 bytes, matching Plug’s current default. This plan makes the existing bound visible and enforceable; lowering it or adding per-bin storage quotas is a separate deferred finding.

## Commands you will need

| Purpose | Command | Expected on success |
| --- | --- | --- |
| Strict compile | `MIX_ENV=test mix compile --warnings-as-errors` | Exit 0. |
| Plug unit tests | `mix test test/request_bin_web/plugs/request_capture_test.exs` | Exit 0, `0 failures`. |
| Request unit tests | `mix test test/request_bin/request_test.exs` | Exit 0, `0 failures`. |
| Collector integration tests | `mix test test/request_bin_web/controllers/bin_controller_test.exs` | Exit 0, `0 failures`. |
| Full tests | `mix test` | Exit 0, `0 failures`. |
| Format | `mix format --check-formatted` | Exit 0. |
| Routes | `mix phx.routes` | Existing collector/browser routes remain present. |
| Required repository gate | `mix precommit` | Exit 0 and tests report `0 failures`. |
| Diff hygiene | `git diff --check` | Exit 0. |

## Scope

**In scope** — the only files you should modify or create:

- `config/config.exs`
- `config/runtime.exs`
- `lib/request_bin_web/plugs/request_capture.ex` — create.
- `lib/request_bin_web/endpoint.ex`
- `lib/request_bin_web/router.ex`
- `lib/request_bin_web/controllers/bin_controller.ex`
- `lib/request_bin/request.ex`
- `lib/request_bin/bins/request.ex`
- `test/request_bin_web/plugs/request_capture_test.exs` — create.
- `test/request_bin/request_test.exs` — create.
- `test/request_bin_web/controllers/bin_controller_test.exs` — create.
- `plans/README.md` — status update only.

**Out of scope** — do not touch:

- Existing migrations or create a new migration; the database column is already binary.
- Wildcard subpaths, additional explicit router methods, or replay/export features.
- Repeated-header storage; the existing map representation remains unchanged.
- The ineffective header-filter predicate at `request.ex:22-28`; preserve its current behavior because it is a separately deferred finding. In particular, do not “fix” it by broadly removing all `x-*` webhook headers.
- Inspector rendering of stored bodies; that is another deferred finding.
- Request pagination, per-bin quotas, or a lower body-size policy.
- Trusted client IP and rate-limit logic delivered by Plan 003.
- Authentication or collector/inspector token changes.

## Git workflow

- Branch: `advisor/004-preserve-original-requests`
- Prefer two commits: `fix: capture raw request bodies before parsing`, then `test: cover collector request fidelity`.
- Do not push or open a PR unless the operator explicitly requests it.

## Steps

### Step 1: Add explicit capture-size configuration

In `config/config.exs`, add:

```elixir
config :request_bin, :request_capture,
  max_body_bytes: 8_000_000
```

In `config/runtime.exs`, preserve all Plan 003 proxy settings and optionally override this value from `MAX_REQUEST_BODY_BYTES`:

- Parse with `Integer.parse/1`, requiring the whole string to be consumed.
- Require a positive integer.
- Raise a concise `ArgumentError` on invalid input without printing unrelated environment values.
- Keep 8,000,000 when the variable is absent.

The runtime value must remain application configuration; do not read the environment inside request-processing code.

**Verify**:

```bash
MAX_REQUEST_BODY_BYTES=1024 MIX_ENV=test mix run --no-start -e 'IO.inspect(Application.fetch_env!(:request_bin, :request_capture))'
```

Expected: exit 0 and output containing `max_body_bytes: 1024`.

Also verify failure is closed:

```bash
if MAX_REQUEST_BODY_BYTES=invalid MIX_ENV=test mix run --no-start -e ':ok' >/tmp/request-bin-invalid-body-limit 2>&1; then
  echo 'invalid body limit unexpectedly succeeded'
  exit 1
else
  grep -q 'MAX_REQUEST_BODY_BYTES' /tmp/request-bin-invalid-body-limit
fi
```

Expected: the shell command exits 0 because startup/config evaluation rejected the invalid value and emitted the named configuration error.

### Step 2: Create a conditional, bounded request-capture plug

Create `RequestBinWeb.Plugs.RequestCapture` implementing `Plug`.

Initialization and delegation:

- Accept the same options currently passed to `Plug.Parsers`.
- In `init/1`, retain `Plug.Parsers.init/1` output for normal-path delegation.
- Classify a collector request only when `conn.path_info` is exactly `["bin", id]` with a nonempty ID and the original method is one of `GET`, `HEAD`, `POST`, `PUT`, `PATCH`, or `DELETE`.
- For non-collector requests, call `Plug.Parsers.call/2` with the initialized parser options and return its result unchanged.

Collector capture path:

1. Save `conn.method` to `conn.private[:request_bin_original_method]` and set `conn.private[:request_bin_collector]` to `true`.
2. Fetch query parameters with `Plug.Conn.fetch_query_params/1`.
3. Read the body with `Plug.Conn.read_body/2`, using:
   - `length: max_body_bytes` from application config,
   - a bounded `read_length` no larger than 1,000,000,
   - the normal finite read timeout.
4. Handle results explicitly:
   - `{:ok, body, conn}` — continue and store the exact binary in `conn.private[:request_bin_raw_body]`.
   - `{:more, _partial, conn}` — send text status 413, halt, and never route/persist the partial body.
   - `{:error, :timeout}` — send text status 408 and halt.
   - any other read error — send text status 400 and halt; log only the error class/reason, never body contents.
5. Set `body_params` to `%{}` and set/fetch `params` so Phoenix Router can merge query and path parameters without invoking a body parser.

Do not accumulate beyond `max_body_bytes`, spool request bodies to disk, or store them in the process dictionary.

Replace `plug Plug.Parsers` in `RequestBinWeb.Endpoint` with this plug, passing the same parsers, `pass`, and JSON decoder options.

**Verify**: `MIX_ENV=test mix compile --warnings-as-errors` → exit 0.

### Step 3: Preserve original methods while retaining non-collector method override

Replace direct `plug Plug.MethodOverride` with an endpoint-local wrapper function or a small clause in the capture plug integration:

- When `conn.private[:request_bin_collector]` is true, skip `Plug.MethodOverride`.
- Otherwise delegate to `Plug.MethodOverride` with its normal initialized options.
- Keep `Plug.Head`. `HEAD` may route through the existing GET route, but persistence must use `:request_bin_original_method` and therefore record `HEAD`, not `GET`.

Do not remove method override globally; future browser forms may rely on it.

Add unit tests proving:

- A collector POST with an override header/body remains POST in the private original-method field and in later request extraction.
- A non-collector POST still follows normal `Plug.MethodOverride` behavior.
- A collector HEAD stores original method HEAD even if `Plug.Head` later routes it as GET.

**Verify**: `mix test test/request_bin_web/plugs/request_capture_test.exs` → exit 0 and `0 failures`.

### Step 4: Refactor request extraction to consume captured bytes without raising

Update `RequestBin.Requests.extract_request_info/1`:

- Read raw bytes from `conn.private[:request_bin_raw_body]`; do not call `Plug.Conn.read_body/2` again.
- Read method from `conn.private[:request_bin_original_method]`, falling back to `conn.method` only for direct/unit callers.
- Preserve host, path, query params, remote IP, and current header-map/filter behavior.
- Return `{:error, :body_not_captured}` if a collector connection lacks the expected private key rather than silently storing an empty body.
- Produce a `body_parsed` map with these rules:
  - Empty body → `%{}`.
  - Valid JSON object → that map.
  - Valid top-level JSON array/scalar → `%{"_json" => decoded_value}` so the Ecto map field remains valid.
  - Malformed JSON → `%{"_parse_error" => "invalid_json"}`; do not include exception text.
  - Valid URL-encoded data → decoded map using `Plug.Conn.Query.decode/1` inside non-raising error handling.
  - Malformed URL-encoded data → `%{"_parse_error" => "invalid_urlencoded"}`.
  - Multipart or any other media type → `%{}` for now; the exact raw bytes remain available in `body_raw`.
- Recognize `application/json` and `application/*+json` using parsed media-type components, not a case-sensitive substring test.

Refactor `create_request/2` to accept `request_info.body_raw` and `request_info.body_parsed` directly. It may normalize a non-map parsed value defensively, but it must not decode the body a second time or duplicate the raw body inside the parsed map.

Delete the now-unused `body_params` dependency from the extraction function.

Create `test/request_bin/request_test.exs` covering:

1. Exact raw JSON bytes and parsed object.
2. Top-level JSON array normalization.
3. Malformed JSON parse marker with raw bytes preserved.
4. URL-encoded parsing and malformed marker.
5. Text and multipart payloads preserve raw bytes with an empty parsed map.
6. Original method wins over a mutated `conn.method`.
7. Missing capture private returns `{:error, :body_not_captured}`.

**Verify**: `mix test test/request_bin/request_test.exs` → exit 0 and `0 failures`.

### Step 5: Align the Ecto schema with the existing binary column

Change only the schema declaration:

```elixir
# lib/request_bin/bins/request.ex
field :body_raw, :binary
```

Do not alter the migration or create a new migration. Add a test that the changeset accepts a binary body containing bytes that are not valid UTF-8, proving the schema no longer incorrectly imposes string semantics.

**Verify**: `mix test test/request_bin/request_test.exs` → exit 0 and `0 failures`.

### Step 6: Remove content negotiation from the collector and normalize responses

In `lib/request_bin_web/router.ex` after Plan 003:

- Rename `:no_csrf_protection` to `:collector` for clarity.
- Preserve `plug RequestBinWeb.Plugs.RateLimit`.
- Remove `plug :accepts, ["json"]` and do not replace it with another `accepts` call.
- Pipe the five existing routes through `:collector`.

In `BinController`:

- Return plain text via `text/2` for success and known errors, independent of the request `Accept` header.
- Keep 200 for successful capture and 404 for a missing bin.
- Map `:invalid_params`, `:body_not_captured`, and `%Ecto.Changeset{}` persistence failures to stable 400/422 text responses as appropriate.
- Never render `inspect(error)`, changeset details, stack traces, or body content to the caller.

Do not add authentication or CSRF checks to collector routes; cross-site form protection is intentionally not applicable to an inbound webhook endpoint.

**Verify**: `mix phx.routes` → exit 0 and the existing collection routes remain present.

### Step 7: Add collector integration tests

Create `test/request_bin_web/controllers/bin_controller_test.exs` using `RequestBinWeb.ConnCase` and fixtures from Plan 002. Cover at least:

1. JSON request with `Accept: text/plain` returns 200 and persists exact raw bytes plus parsed map.
2. Malformed JSON returns 200 for a valid bin and persists raw bytes plus the non-sensitive parse marker.
3. Top-level JSON array persists in the normalized `_json` map.
4. URL-encoded and text bodies preserve exact raw bytes.
5. Multipart input preserves exact raw bytes without requiring parsed upload structs to be database-serializable.
6. Method-override input is persisted with its original HTTP method.
7. A valid-format but nonexistent bin ID returns 404 and persists nothing.
8. With `max_body_bytes` temporarily set to a small value, an oversized body returns 413 and persists nothing.
9. A browser route still receives normal parser/method behavior, guarding conditional delegation.

Restore application configuration with `on_exit` in any test that changes the body limit. Use a unique bin per test and query `RequestsRepo.list_requests_by_bin/1`; do not rely on global request counts.

**Verify**:

```bash
mix test test/request_bin_web/plugs/request_capture_test.exs test/request_bin/request_test.exs test/request_bin_web/controllers/bin_controller_test.exs
```

Expected: exit 0 and `0 failures`.

### Step 8: Run full verification and confirm scope

**Verify**:

```bash
mix format --check-formatted &&
MIX_ENV=test mix compile --warnings-as-errors &&
mix test &&
mix precommit &&
mix phx.routes >/tmp/request-bin-plan-004-routes &&
grep -q '/bin/:id' /tmp/request-bin-plan-004-routes &&
git diff --check
```

Expected: exit 0 and all tests report `0 failures`.

Then verify scope:

```bash
git diff --name-only | grep -Ev '^((config/(config|runtime)\.exs|lib/request_bin/request\.ex|lib/request_bin/bins/request\.ex|lib/request_bin_web/(endpoint|router)\.ex|lib/request_bin_web/controllers/bin_controller\.ex|lib/request_bin_web/plugs/request_capture\.ex|test/request_bin/request_test\.exs|test/request_bin_web/plugs/request_capture_test\.exs|test/request_bin_web/controllers/bin_controller_test\.exs|plans/README\.md))$' | tee /tmp/request-bin-plan-004-out-of-scope
test ! -s /tmp/request-bin-plan-004-out-of-scope
```

Expected: exit 0 and the temporary report is empty.

## Test plan

- `test/request_bin_web/plugs/request_capture_test.exs`
  - collector classification
  - bounded body read outcomes
  - original-method preservation
  - non-collector delegation
- `test/request_bin/request_test.exs`
  - JSON object/array/scalar handling
  - malformed JSON and URL-encoded handling
  - text/multipart raw preservation
  - missing capture state
  - binary schema compatibility
- `test/request_bin_web/controllers/bin_controller_test.exs`
  - end-to-end persistence and statuses for valid, malformed, missing-bin, and oversized requests
  - non-JSON `Accept` behavior
  - no request persisted on 404/413

Use `RequestBinWeb.ConnCase`, `RequestBin.DataCase`, and `RequestBin.Fixtures` established by Plan 002. Do not mock Plug, Ecto, or the controller; the critical regression is at their integration boundary.

Final verification: `mix test` → exit 0 and `0 failures`.

## Done criteria

- [ ] Parsed JSON/form collector requests persist the exact nonempty raw body.
- [ ] Malformed JSON reaches a valid bin, returns 200, and persists raw bytes plus a stable parse marker.
- [ ] Top-level JSON arrays/scalars persist in a map-compatible representation.
- [ ] Collector requests with non-JSON `Accept` headers are not rejected with 406.
- [ ] The original collector method is persisted despite method/head middleware.
- [ ] Bodies over the configured limit receive 413 and create no request row.
- [ ] Non-collector routes still use normal `Plug.Parsers` and `Plug.MethodOverride` behavior.
- [ ] The Ecto schema uses `:binary` for the existing binary database column.
- [ ] Controller errors never expose changesets, exceptions, or body data.
- [ ] All targeted and full tests pass with `0 failures`.
- [ ] Strict compile, formatting, `mix precommit`, routes, and diff checks pass.
- [ ] Plan 003’s trusted-IP and collector-rate-limit behavior remains intact.
- [ ] `plans/README.md` marks Plan 004 `DONE`.

## STOP conditions

Stop and report back instead of improvising if:

- Plan 003 is incomplete or its trusted-IP/rate-limit tests are not green.
- The current endpoint/router does not match the expected Plan 003 state.
- Reading the body once before routing cannot be made compatible with the adapter without buffering beyond the configured maximum.
- Phoenix Router cannot merge path/query params after collector body parsing is skipped without modifying framework internals.
- Aligning `body_raw` to `:binary` unexpectedly requires a database migration or breaks existing persisted rows.
- Capturing malformed requests would require globally making non-collector JSON parsing lenient.
- Multipart preservation requires persisting temporary upload paths or file contents outside the existing raw-body column.
- The fix starts changing header filtering, wildcard routing, inspector rendering, or per-bin quotas.
- `mix precommit` changes `mix.exs`, `mix.lock`, or another out-of-scope file.
- Any verification command fails twice after a reasonable correction.

## Maintenance notes

- `RequestCapture` path classification must be updated if wildcard collection paths or new methods are added later; otherwise those routes may fall back to normal parsers and lose raw bytes.
- The body-size limit is a resource boundary. Reviewers should check every body-read branch for bounded allocation and ensure partial oversized bodies are never persisted.
- Parse markers are deliberately stable and non-sensitive. Do not store decoder exception text, which can change across versions and may echo payload fragments.
- Header filtering and repeated-header fidelity remain known deferred work. Preserve webhook signature headers when that follow-up is planned.
- Inspector body rendering is deferred; this plan only guarantees that correct data is available in persistence.
