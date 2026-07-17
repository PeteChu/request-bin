<!-- markdownlint-disable MD013 -->

# Plan 002: Establish a green, portable test and CI baseline

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the “STOP conditions” section occurs, stop and
> report—do not improvise. When done, update the status row for this plan in
> `plans/README.md` unless a reviewer told you they maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 024bc84..HEAD -- AGENTS.md mix.exs config/test.exs test/support test/request_bin test/request_bin_web/live/bin_live_test.exs .github/workflows/ci.yml .tool-versions`
> The CI workflow, tool-version file, fixture module, and repository tests are
> expected not to exist yet. If an existing path changed, compare it with the
> excerpts below and treat a semantic mismatch as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none; Plan 001 was satisfied independently by commit `024bc84`
- **Category**: tests
- **Planned at**: commit `024bc84`, 2026-07-17

## Why this matters

The Phoenix 1.8 upgrade independently fixed the stale root-route test and the
application warning identified by the original audit, but the repository still
has no CI workflow, no checked-in runtime pin, no repository-level tests, and a
test database configuration tied to one local credential set. The current
format and strict-compile gates pass, but the suite could not be run during
reconciliation because PostgreSQL was not available on `localhost:5432`.
Plans 003–005 change security-sensitive request handling and lifecycle logic;
they need a portable, database-backed verification baseline first.

## Current state

Relevant files and confirmed facts at `024bc84`:

- `mix.exs` declares `elixir: "~> 1.17"` and has a required `precommit` alias:

  ```elixir
  # mix.exs:94
  precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
  ```

- `config/test.exs:9-17` accepts `POSTGRES_PORT`, but fixes the host, username,
  password, and database name:

  ```elixir
  config :request_bin, RequestBin.Repo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
    database: "request_bin_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
  ```

- `compose.yaml` now provides PostgreSQL 17 for local development. Reuse that
  major version in CI; do not introduce a second local database convention.
- `test/support/data_case.ex` and `test/support/conn_case.ex` use
  `Ecto.Adapters.SQL.Sandbox.start_owner!/2`; keep this ownership pattern.
- `test/request_bin_web/live/bin_live_test.exs` already covers the Phoenix 1.8
  layout, the `#create-bin` interaction, inspector mount, and copied-URL flash.
  Use it as the LiveView test exemplar; do not create a duplicate index smoke
  test.
- `test/request_bin_web/controllers/page_controller_test.exs` already asserts
  the `/` to `/bin` redirect. The old generated assertion is gone.
- `lib/request_bin/request.ex` no longer has the unused `require Logger`.
- `.github/workflows/ci.yml`, `.tool-versions`, `test/support/fixtures.ex`, and
  `test/request_bin/*_test.exs` are absent.
- Reconciliation ran `mix format --check-formatted` and
  `MIX_ENV=test mix compile --warnings-as-errors` successfully. The latter
  emitted dependency/toolchain warnings under local Elixir 1.20.2, but no
  application warning and a zero exit status.
- `AGENTS.md` requires running `mix precommit` after all changes. It also says
  tests must use `start_supervised!/1` for processes and must not use
  `Process.sleep/1`; the tests in this plan start no custom process and use
  deterministic timestamps.

Repository conventions:

- Use `RequestBin.DataCase` for repository tests and
  `RequestBinWeb.ConnCase` for endpoint/LiveView tests.
- Persistence goes through `RequestBin.BinsRepo`, `RequestBin.RequestsRepo`, and
  `RequestBin.Repo`.
- Test files are named `*_test.exs`; fixture helpers belong under
  `test/support/` and should be imported by both case templates.
- Keep Phoenix 1.8 and existing product UI/hooks unchanged.

## Commands you will need

| Purpose                  | Command                                                                                                                           | Expected on success                            |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| Start local DB           | `docker compose up -d postgres`                                                                                                   | Exit 0; PostgreSQL 17 service becomes healthy. |
| Fetch test dependencies  | `MIX_ENV=test mix deps.get`                                                                                                       | Exit 0.                                        |
| Strict compile           | `MIX_ENV=test mix compile --warnings-as-errors`                                                                                   | Exit 0; no application warnings.               |
| Format check             | `mix format --check-formatted`                                                                                                    | Exit 0.                                        |
| Targeted tests           | `mix test test/request_bin test/request_bin_web/live/bin_live_test.exs test/request_bin_web/controllers/page_controller_test.exs` | Exit 0 and `0 failures`.                       |
| Full tests               | `mix test`                                                                                                                        | Exit 0 and `0 failures`.                       |
| Required repository gate | `mix precommit`                                                                                                                   | Exit 0 and tests report `0 failures`.          |
| Diff hygiene             | `git diff --check`                                                                                                                | Exit 0.                                        |

For local verification, after the Compose service is healthy:

```bash
export TEST_DATABASE_URL="ecto://postgres:postgres@localhost:${POSTGRES_PORT:-5432}/request_bin_test"
```

These are disposable local test credentials from `compose.yaml`; never copy or
reference production credentials.

## Scope

**In scope**—the only files to modify or create:

- `config/test.exs`
- `test/support/data_case.ex`
- `test/support/conn_case.ex`
- `test/support/fixtures.ex`—create
- `test/request_bin/bins_repo_test.exs`—create
- `test/request_bin/requests_repo_test.exs`—create
- `.github/workflows/ci.yml`—create
- `.tool-versions`—create
- `plans/README.md`—status update only

**Out of scope**—do not touch:

- `mix.exs`, `mix.lock`, application source under `lib/`, or migrations.
- Existing controller and LiveView tests; they are already green exemplars.
- Request capture, trusted IP, rate limiting, retention, or deletion behavior.
- Production database/runtime configuration.
- Frontend tests/tooling, coverage thresholds, Credo, or Dialyzer.
- DNS clustering; it is intentionally disabled.
- README/deployment documentation.

## Git workflow

- Branch: `advisor/002-verification-baseline`
- Prefer two commits: `test: add repository verification baseline`, then
  `ci: run Elixir checks with PostgreSQL`.
- Do not push or open a PR unless the operator explicitly requests it.

## Steps

### Step 1: Make the test database portable and test-specific

Refactor only the Repo configuration in `config/test.exs`:

1. Read `TEST_DATABASE_URL`.
2. When absent, preserve the current username, password, host, port, database,
   Sandbox pool, and pool-size behavior exactly.
3. When present, use that URL while retaining Sandbox and pool size.
4. Preserve `MIX_TEST_PARTITION`: when nonempty, append the partition suffix to
   the URL database path before passing it to Ecto. Use `URI`, not a new
   dependency, and reject a URL without a database path.
5. Never read or fall back to production `DATABASE_URL`.
6. Build one keyword list and call `config` once; do not duplicate the whole
   Repo block.

**Verify**:

```bash
MIX_ENV=test mix compile --warnings-as-errors &&
TEST_DATABASE_URL="ecto://postgres:postgres@localhost:${POSTGRES_PORT:-5432}/request_bin_test" \
  MIX_ENV=test mix compile --force --warnings-as-errors
```

Expected: both invocations exit 0.

### Step 2: Add reusable repository fixtures

Create `RequestBin.Fixtures` in `test/support/fixtures.ex`:

- `bin_fixture(attrs \\ %{})` calls `RequestBin.BinsRepo.create_bin/1`,
  pattern-matches `{:ok, bin}`, and returns the bin.
- `request_fixture(bin, attrs \\ %{})` supplies deterministic valid defaults
  for method, headers, raw/parsed body, query params, path, IP, and `bin_id`;
  merge overrides with `Map.merge/2`, call
  `RequestBin.RequestsRepo.create_request/1`, and return the request.
- Do not call `RequestBin.Bins.create_and_schedule_bin/0`; repository fixtures
  must not enqueue deletion jobs.

Import `RequestBin.Fixtures` in the quoted `using` blocks of both `DataCase` and
`ConnCase` so Plans 003–005 share one fixture convention.

**Verify**: `MIX_ENV=test mix compile --warnings-as-errors` → exit 0.

### Step 3: Add deterministic repository smoke tests

Create `test/request_bin/bins_repo_test.exs` with `RequestBin.DataCase`:

1. `create_bin/1` persists a bin with a valid binary UUID and default retention.
2. `get_bin/1` returns it; a different valid UUID returns `nil`.

Create `test/request_bin/requests_repo_test.exs` with `RequestBin.DataCase`:

1. `request_fixture/2` persists required metadata and the requested `bin_id`.
2. `list_requests_by_bin/1` excludes another bin and returns newest first.

For ordering, do not sleep. The schema uses second-resolution UTC timestamps;
set distinct known `inserted_at` values with `Repo.update_all/3`, then assert the
exact ID order.

**Verify**:

```bash
TEST_DATABASE_URL="ecto://postgres:postgres@localhost:${POSTGRES_PORT:-5432}/request_bin_test" \
  mix test test/request_bin
```

Expected: exit 0 and `0 failures`.

### Step 4: Pin the current runtime and add CI

Create `.tool-versions`:

```text
erlang 28.3
elixir 1.20.2-otp-28
```

Create `.github/workflows/ci.yml` with:

- push to `main` and pull-request triggers;
- Ubuntu runner;
- PostgreSQL `17-alpine` service with a health check and disposable CI-only
  credentials;
- workflow-level `MIX_ENV: test` and `TEST_DATABASE_URL` targeting that service;
- `actions/checkout@v4` and `erlef/setup-beam@v1` pinned to Elixir 1.20.2 / OTP
  28.3, matching `.tool-versions`;
- optional cache keyed by OS, runtime versions, and `mix.lock`;
- ordered commands: `mix deps.get`, `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, and `mix test`.

Do not run `mix precommit` in CI because its `format` step rewrites files; CI
must use check mode. Do not add deployment steps or secrets.

**Verify**:

```bash
grep -q 'postgres:17-alpine' .github/workflows/ci.yml &&
grep -q 'mix compile --warnings-as-errors' .github/workflows/ci.yml &&
grep -q 'mix test' .github/workflows/ci.yml &&
grep -q 'elixir 1.20.2-otp-28' .tool-versions &&
git diff --check
```

Expected: exit 0.

### Step 5: Run the full local equivalent and required precommit alias

With PostgreSQL healthy and `TEST_DATABASE_URL` exported, run:

```bash
MIX_ENV=test mix deps.get &&
mix format --check-formatted &&
MIX_ENV=test mix compile --warnings-as-errors &&
mix test &&
mix precommit
```

Expected: exit 0 and every test run reports `0 failures`. Review the diff after
`mix precommit`; `mix.exs` and `mix.lock` must remain unchanged.

### Step 6: Confirm scope and record status

```bash
git diff --name-only | grep -Ev '^((config/test\.exs|test/support/(data_case|conn_case|fixtures)\.ex|test/request_bin/(bins_repo|requests_repo)_test\.exs|\.github/workflows/ci\.yml|\.tool-versions|plans/README\.md))$' | tee /tmp/request-bin-plan-002-out-of-scope
test ! -s /tmp/request-bin-plan-002-out-of-scope
```

Expected: exit 0 and the report is empty.

## Test plan

- `test/request_bin/bins_repo_test.exs`: default creation, UUID validity,
  successful lookup, missing lookup.
- `test/request_bin/requests_repo_test.exs`: required-field persistence,
  bin isolation, deterministic newest-first ordering.
- Existing `test/request_bin_web/live/bin_live_test.exs`: retain and run as the
  Phoenix 1.8 LiveView integration baseline.
- Existing page/error tests: retain and run through the full suite.

Final verification: `mix precommit` → exit 0 and `0 failures` against the
isolated PostgreSQL test database.

## Done criteria

- [ ] `TEST_DATABASE_URL` configures only the test Repo and preserves partition suffixes.
- [ ] Existing local defaults still work when `TEST_DATABASE_URL` is absent.
- [ ] Shared fixtures are imported through `DataCase` and `ConnCase`.
- [ ] Bin and request repository tests exist and pass.
- [ ] `.tool-versions` and CI use Elixir 1.20.2 / OTP 28.3.
- [ ] CI uses PostgreSQL 17 and runs format check, strict compile, and all tests.
- [ ] `mix format --check-formatted` exits 0.
- [ ] `MIX_ENV=test mix compile --warnings-as-errors` exits 0.
- [ ] `mix test` and `mix precommit` exit 0 with `0 failures`.
- [ ] `mix.exs`, `mix.lock`, application source, and existing UI tests are unchanged.
- [ ] `plans/README.md` marks Plan 002 `DONE`.

## STOP conditions

Stop and report instead of improvising if:

- A real isolated PostgreSQL database cannot be provisioned; do not mark this
  plan done without a full `mix test` pass.
- Elixir 1.20.2 / OTP 28.3 is unavailable in `erlef/setup-beam`; report the
  exact available patch rather than floating an unpinned runtime.
- Strict compilation reports an application warning or exits nonzero.
- The current `/bin` LiveView or root redirect tests fail before scoped changes.
- Repository tests require schema, migration, application, request-capture,
  rate-limit, or retention changes.
- `mix precommit` changes `mix.exs` or `mix.lock`.
- A verification command fails twice after a reasonable scoped correction.

## Maintenance notes

- Keep `TEST_DATABASE_URL` test-specific; reviewers should reject any fallback
  to production `DATABASE_URL`.
- Future context and LiveView tests should reuse `RequestBin.Fixtures`,
  `DataCase`, and `ConnCase`.
- CI intentionally omits deployment, browser E2E, Credo, Dialyzer, and assets.
- If the declared minimum Elixir 1.17 becomes a compatibility concern, add a
  separate minimum-version CI job after this baseline is green; do not expand
  this plan while security/correctness plans are waiting.
