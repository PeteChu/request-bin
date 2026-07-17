<!-- markdownlint-disable MD013 -->

# Plan 003: Trust forwarded client IPs only from configured proxies

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 024bc84..HEAD -- AGENTS.md config/config.exs config/runtime.exs lib/request_bin/application.ex lib/request_bin/network/cidr.ex lib/request_bin_web/endpoint.ex lib/request_bin_web/router.ex lib/request_bin_web/plugs test/request_bin/network test/request_bin_web/plugs`
> Plans 001–002 should not change the existing endpoint, router, runtime
> configuration, or application supervision code. New plug/CIDR files should
> not exist. Stop if the live code differs semantically from the excerpts below.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/002-establish-verification-baseline.md`
- **Category**: security
- **Planned at**: commit `024bc84`, 2026-07-17

## Why this matters

The endpoint currently replaces the socket peer IP with any syntactically valid `fly-client-ip` request header. That rewritten value is both displayed to users and used as the sole Hammer rate-limit key. Unless every deployment edge removes caller-supplied copies of that header, a caller can forge attribution, bypass the limit, and create a large number of ETS counters. The safe default must be the actual peer IP; forwarded headers may be used only when the immediate peer is in an explicit trusted CIDR list.

## Current state

Relevant files:

- `lib/request_bin_web/endpoint.ex` — unconditionally trusts one forwarding header and applies one global rate limit to every route.
- `lib/request_bin_web/router.ex` — collector pipeline; the rate-limit plug should move here so static/UI/LiveView traffic does not consume the ingestion budget.
- `lib/request_bin/ratelimit.ex` — existing Hammer ETS backend; keep it.
- `lib/request_bin/application.ex` — starts the Hammer backend and is the correct place to validate runtime proxy configuration before serving traffic.
- `config/config.exs` — add safe defaults here.
- `config/runtime.exs` — read production proxy/header settings here.
- `lib/request_bin/network/cidr.ex` — create an owned IPv4/IPv6 CIDR matcher rather than depending on undocumented internals of `remote_ip`.
- `lib/request_bin_web/plugs/trusted_client_ip.ex` — create.
- `lib/request_bin_web/plugs/rate_limit.ex` — create.

Current trust and rate-limit path:

```elixir
# lib/request_bin_web/endpoint.ex:46-49
plug RemoteIp,
  headers: ~w"fly-client-ip"

plug :rate_limit
```

```elixir
# lib/request_bin_web/endpoint.ex:61-66
defp rate_limit(conn, _opts) do
  key = "web_requests:#{:inet.ntoa(conn.remote_ip)}"
  scale = :timer.minutes(1)
  limit = 100

  case RequestBin.RateLimit.hit(key, scale, limit) do
```

The collector pipeline currently only negotiates JSON:

```elixir
# lib/request_bin_web/router.ex:17-20
pipeline :no_csrf_protection do
  plug :accepts, ["json"]
end
```

Plan 004 will remove the inappropriate `accepts` restriction and change request parsing. In this plan, preserve that line and add the collector rate limiter after it to avoid mixing two behavioral changes.

The production listener binds on all interfaces (`config/runtime.exs:78-82`), while no trusted proxy topology is represented in code. A no-database runtime probe during the audit confirmed that a supplied forwarding header replaces an unrelated peer tuple.

Repository plug convention: endpoint plugs run before `RequestBinWeb.Router`; router pipeline plugs apply only to matching scopes. Error responses use `Plug.Conn.put_resp_header/3`, `send_resp/3`, and `halt/1` as shown by the current private rate-limit function. Preserve Hammer’s existing `{:allow, count} | {:deny, retry_after_ms}` contract.

`AGENTS.md` was added with the Phoenix 1.8 upgrade and explicitly requires preserving the custom `RemoteIp` and rate-limit behavior. This plan is a security hardening of those same features, not generated-code cleanup: keep the `remote_ip` dependency for parsing, keep Hammer and the existing 429 contract, and add regression tests proving both capabilities remain. Do not reintroduce DNS clustering or alter the product UI/hooks.

## Target configuration contract

Add these application settings with safe defaults:

```elixir
# config/config.exs — target shape
config :request_bin, :client_ip,
  header: nil,
  trusted_proxy_cidrs: []

config :request_bin, :collector_rate_limit,
  scale_ms: 60_000,
  limit: 100
```

`config/runtime.exs` must support:

- `CLIENT_IP_HEADER` — normalized lower-case header name; absent by default.
- `TRUSTED_PROXY_CIDRS` — comma-separated IPv4/IPv6 addresses or CIDRs; absent/blank by default.
- Safe mode is `{header: nil, trusted_proxy_cidrs: []}` and uses the socket peer.
- Forwarded mode is valid only when both a header and at least one valid trusted CIDR are configured.
- Supplying only one side or any malformed CIDR must fail application startup with a concise configuration error; do not log environment contents beyond the invalid item.

Do not give either setting an implicit Fly-specific production default. An operator must opt in after confirming the deployment topology.

## Commands you will need

| Purpose | Command | Expected on success |
| --- | --- | --- |
| Strict compile | `MIX_ENV=test mix compile --warnings-as-errors` | Exit 0. |
| CIDR tests | `mix test test/request_bin/network/cidr_test.exs` | Exit 0, `0 failures`. |
| Plug tests | `mix test test/request_bin_web/plugs` | Exit 0, `0 failures`. |
| Full tests | `mix test` | Exit 0, `0 failures`. |
| Format | `mix format --check-formatted` | Exit 0. |
| Routes | `mix phx.routes` | Exit 0; existing routes remain present. |
| Required repository gate | `mix precommit` | Exit 0 and tests report `0 failures`. |
| Diff hygiene | `git diff --check` | Exit 0. |

## Scope

**In scope** — the only files you should modify or create:

- `config/config.exs`
- `config/runtime.exs`
- `lib/request_bin/application.ex`
- `lib/request_bin/network/cidr.ex` — create.
- `lib/request_bin_web/endpoint.ex`
- `lib/request_bin_web/router.ex`
- `lib/request_bin_web/plugs/trusted_client_ip.ex` — create.
- `lib/request_bin_web/plugs/rate_limit.ex` — create.
- `test/request_bin/network/cidr_test.exs` — create.
- `test/request_bin_web/plugs/trusted_client_ip_test.exs` — create.
- `test/request_bin_web/plugs/rate_limit_test.exs` — create.
- `plans/README.md` — status update only.

**Out of scope** — do not touch:

- `lib/request_bin/ratelimit.ex`; continue using its Hammer ETS backend.
- Request body parsing or the collector’s `accepts` restriction; Plan 004 owns both.
- Per-bin request caps, persistence limits, pagination, or distributed rate limiting.
- Deployment firewall/load-balancer configuration.
- Header filtering in `RequestBin.Requests`.
- A new CIDR or rate-limit dependency.
- Authentication, API tokens, or changes to public response bodies beyond existing 429 semantics.

## Git workflow

- Branch: `advisor/003-trusted-client-ip`
- Prefer two logical commits: `fix: validate forwarded client IPs`, then `fix: scope rate limits to collection routes`.
- Do not push or open a PR unless the operator explicitly requests it.

## Steps

### Step 1: Add a small owned CIDR parser and matcher

Create `RequestBin.Network.CIDR` with a deliberately narrow API:

- `parse/1` accepts a string containing an IPv4/IPv6 address, optionally followed by a prefix length, and returns `{:ok, parsed}` or `{:error, reason}`.
- A bare IPv4 address means `/32`; a bare IPv6 address means `/128`.
- Reject prefixes outside `0..32` for IPv4 and `0..128` for IPv6.
- Use `:inet.parse_strict_address/1` so trailing characters and non-address forms are rejected.
- `contains?/2` accepts the parsed CIDR and a standard Erlang IP tuple and returns a boolean.
- Family mismatches return `false`.
- Convert addresses to unsigned integers and apply prefix masks with `Bitwise`; keep the representation private.

Do not use `RemoteIp.Block`: it has `@moduledoc false` and is not a stable public contract.

Create `test/request_bin/network/cidr_test.exs` covering:

1. Exact IPv4 and IPv6 addresses.
2. Positive and negative IPv4 `/24` membership.
3. Positive and negative IPv6 `/64` membership.
4. `/0`, `/32`, and `/128` boundaries.
5. Family mismatch.
6. Invalid address, nonnumeric prefix, and out-of-range prefix.

**Verify**: `mix test test/request_bin/network/cidr_test.exs` → exit 0 and `0 failures`.

### Step 2: Define safe runtime configuration and startup validation

Add safe defaults to `config/config.exs` using the target shape above.

In `config/runtime.exs` for all environments, before the production-only database block:

1. Read and trim `CLIENT_IP_HEADER`.
2. Split `TRUSTED_PROXY_CIDRS` on commas with `trim: true`; blank means an empty list.
3. Store only strings in application config; do not call application modules from the config file because config loads before compilation in some Mix tasks.
4. Keep both unset for safe peer-only mode.

In `RequestBinWeb.Plugs.TrustedClientIp`, expose `validate_config!/0`. It must:

- Accept peer-only mode.
- Require both header and nonempty CIDRs for forwarded mode.
- Require the header to be lower-case and a valid HTTP field name.
- Parse every CIDR through `RequestBin.Network.CIDR.parse/1`.
- Raise `ArgumentError` on invalid configuration without printing unrelated environment or secret values.

Call `TrustedClientIp.validate_config!()` at the beginning of `RequestBin.Application.start/2`, before constructing/starting children. That makes invalid production settings fail closed before the endpoint listens.

Add tests to `trusted_client_ip_test.exs` for safe default, missing header, missing CIDRs, invalid header, invalid CIDR, and valid configuration. Use `Application.put_env/3` with `on_exit` restoration so tests do not leak global config.

**Verify**:

```bash
mix test test/request_bin/network/cidr_test.exs test/request_bin_web/plugs/trusted_client_ip_test.exs
```

Expected: exit 0 and `0 failures`.

### Step 3: Replace unconditional `RemoteIp` use with a trusted-peer plug

Implement `RequestBinWeb.Plugs.TrustedClientIp` as a Plug:

1. Always save the original socket peer in `conn.private[:request_bin_peer_ip]`.
2. In peer-only mode, return the connection without changing `conn.remote_ip`.
3. In forwarded mode, parse the configured trusted CIDRs and check the **original peer** against them.
4. If the peer is not trusted, ignore all forwarding headers and leave `remote_ip` unchanged.
5. If the peer is trusted:
   - Read only the one configured header name.
   - Require exactly one header field occurrence; duplicate fields fail closed to the peer IP.
   - Pass that field to `RemoteIp.from/2` with `headers: [configured_header]` so existing RFC/header parsing is reused.
   - Update `remote_ip` only when parsing returns a valid IP tuple; malformed or absent values fail closed to the peer.
6. Never select among several differently named forwarding headers.

Replace the unconditional `plug RemoteIp, headers: ...` in `RequestBinWeb.Endpoint` with `plug RequestBinWeb.Plugs.TrustedClientIp` in the same position, before collector rate limiting and routing.

Add tests for:

- Untrusted peer plus a valid-looking configured header: header ignored.
- Trusted IPv4 peer plus valid header: client IP adopted.
- Trusted IPv6 peer plus valid header: client IP adopted.
- Trusted peer with missing, duplicate, or malformed header: peer retained.
- `:request_bin_peer_ip` always contains the original peer.

Use documentation-only address ranges in test data; do not use any production proxy address.

**Verify**: `mix test test/request_bin_web/plugs/trusted_client_ip_test.exs` → exit 0 and `0 failures`.

### Step 4: Extract and scope the Hammer rate-limit plug

Create `RequestBinWeb.Plugs.RateLimit`:

- It reads default `scale_ms` and `limit` from `Application.fetch_env!(:request_bin, :collector_rate_limit)` during `call/2`, so runtime/test overrides are honored.
- Explicit options passed to `init/1` may override defaults for unit tests.
- Key format: `collector_requests:<canonical client IP>` using the post-validation `conn.remote_ip` tuple.
- Continue using `RequestBin.RateLimit.hit/3`.
- On deny, send status 429, include a decimal `retry-after` header in **whole seconds rounded up with a minimum of 1**, send an empty body, and halt.
- On allow, return the unchanged connection.

In `RequestBinWeb.Endpoint`:

- Remove `plug :rate_limit`.
- Delete the private `rate_limit/2` function.

In the existing `:no_csrf_protection` router pipeline:

- Preserve `plug :accepts, ["json"]` for Plan 004.
- Add `plug RequestBinWeb.Plugs.RateLimit` after it.

Create plug tests that use unique documentation-only IPs/keys and a low explicit test limit:

1. Requests through the limit are not halted.
2. The next request is status 429, halted, and has a positive `retry-after` value.
3. Different client IPs have independent counters.
4. A browser route does not invoke the collector limiter. An integration test may set a low application limit, issue repeated `GET /` requests, and assert each remains the expected redirect rather than 429.

Do not inspect or clear the entire Hammer ETS table; unique keys keep tests isolated.

**Verify**: `mix test test/request_bin_web/plugs/rate_limit_test.exs` → exit 0 and `0 failures`.

### Step 5: Run full verification and inspect routes

Run format, strict compile, all tests, and route generation. Confirm all five existing collector routes and the browser/LiveView routes remain present.

**Verify**:

```bash
mix format --check-formatted &&
MIX_ENV=test mix compile --warnings-as-errors &&
mix test &&
mix precommit &&
mix phx.routes >/tmp/request-bin-routes &&
grep -q '/bin/:id' /tmp/request-bin-routes &&
git diff --check
```

Expected: exit 0, tests report `0 failures`, and the route grep succeeds.

### Step 6: Confirm scope and record status

**Verify**:

```bash
git diff --name-only | grep -Ev '^((config/(config|runtime)\.exs|lib/request_bin/application\.ex|lib/request_bin/network/cidr\.ex|lib/request_bin_web/(endpoint|router)\.ex|lib/request_bin_web/plugs/(trusted_client_ip|rate_limit)\.ex|test/request_bin/network/cidr_test\.exs|test/request_bin_web/plugs/(trusted_client_ip|rate_limit)_test\.exs|plans/README\.md))$' | tee /tmp/request-bin-plan-003-out-of-scope
test ! -s /tmp/request-bin-plan-003-out-of-scope
```

Expected: exit 0 and the temporary report is empty.

## Test plan

- `test/request_bin/network/cidr_test.exs`
  - IPv4/IPv6 parsing, masks, boundaries, family mismatch, invalid input.
- `test/request_bin_web/plugs/trusted_client_ip_test.exs`
  - peer-only safe mode, config validation, trusted and untrusted peers, malformed/duplicate headers, original-peer preservation.
- `test/request_bin_web/plugs/rate_limit_test.exs`
  - allow/deny boundary, positive retry value, per-IP isolation, no rate limit on browser routes.

Use `Plug.Test.conn/3` and `%{conn | remote_ip: tuple}` for plug unit tests. Follow `RequestBinWeb.ConnCase` from Plan 002 only for endpoint/router integration tests.

Final verification: `mix test` → exit 0 and `0 failures`.

## Done criteria

- [ ] With no proxy configuration, a forwarding header cannot change `conn.remote_ip`.
- [ ] Only a configured header from a peer inside a configured CIDR can change `remote_ip`.
- [ ] Missing, duplicate, or malformed forwarding headers fail closed to the peer.
- [ ] Invalid or half-configured proxy settings prevent application startup.
- [ ] The original peer is retained in `conn.private[:request_bin_peer_ip]`.
- [ ] Rate limiting applies to collector routes, not every endpoint request.
- [ ] The 429 `retry-after` header is at least 1 second.
- [ ] CIDR, client-IP, and rate-limit tests pass.
- [ ] `MIX_ENV=test mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix test`, and `mix precommit` all exit 0.
- [ ] No dependency was added.
- [ ] `plans/README.md` marks Plan 003 `DONE`.

## STOP conditions

Stop and report back instead of improvising if:

- Plans 001–002 are incomplete or their verification gates are not green.
- Production requires a forwarded client IP but the operator cannot state which immediate proxy CIDRs are trusted or cannot guarantee the edge rewrites/strips the configured header. Leave peer-only mode as the safe default; do not restore unconditional trust.
- The deployment uses a forwarding contract that cannot be represented as one configured header plus trusted peer CIDRs (for example, several unordered competing headers).
- Correct CIDR behavior would require an external dependency or platform-specific network lookup.
- Moving the limiter to the collector pipeline changes route dispatch or requires request-parser changes from Plan 004.
- A test requires clearing global Hammer state or becomes order-dependent.
- `mix precommit` changes `mix.exs`, `mix.lock`, or another out-of-scope file.
- Any verification command fails twice after a reasonable correction.

## Maintenance notes

- Trusted proxy ranges are an authorization boundary. Review every CIDR and confirm the application is not directly reachable around that proxy.
- If infrastructure changes header names or proxy networks, update both runtime settings together; startup validation intentionally rejects partial configuration.
- The ETS limiter remains node-local and resets on restart. Distributed/global limiting and per-bin storage limits are separate deferred findings.
- Plan 004 modifies the same endpoint/router area. Execute it after this plan and preserve `TrustedClientIp` plus the collector-only `RateLimit` plug.
