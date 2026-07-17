<!-- markdownlint-disable MD013 -->

# Plan 005: Make bin expiration consistent, atomic, and idempotent

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 024bc84..HEAD -- AGENTS.md config/runtime.exs lib/request_bin/bin.ex lib/request_bin/bins/bin.ex lib/request_bin/oban_jobs/delete_bin.ex lib/request_bin_web/live/index_live/index.ex test/request_bin/bin_test.exs test/request_bin/oban_jobs/delete_bin_test.exs test/request_bin_web/live/index_live_expiration_test.exs test/request_bin_web/live/bin_live_test.exs`
> Plans 003–004 are declared prerequisites and add unrelated settings to
> `config/runtime.exs`; preserve those settings. They should not change the
> bin schema/context, deletion job, or index LiveView. Stop if any bin-lifecycle
> code differs semantically from the excerpts below.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/004-preserve-original-collected-requests.md`
- **Category**: bug
- **Planned at**: commit `024bc84`, 2026-07-17

## Why this matters

Bin retention currently has three conflicting sources of truth. The database field is documented as days, the Oban job uses an environment value as days without persisting it, and the browser expiry event interprets the persisted number as hours. Bin insertion and job insertion are also separate operations, so an Oban failure can leave captured request data with no scheduled deletion. This plan validates one retention value, stores it on the bin, uses one expiry function everywhere, inserts the bin/job atomically, and makes cleanup safe to retry.

## Current state

Relevant files:

- `config/runtime.exs` — should parse and validate `RETENTION_PERIOD` once for every environment.
- `lib/request_bin/bin.ex` (`RequestBin.Bins`) — creates a bin, computes deletion time, and inserts an Oban job in separate operations.
- `lib/request_bin/bins/bin.ex` — schema default and ineffective changeset validation.
- `priv/repo/migrations/20250210083201_create_bins.exs` — establishes the authoritative database constraints: retention is positive and no more than 365 days.
- `lib/request_bin/oban_jobs/delete_bin.ex` — deletes requests/bin in a transaction but raises when the bin is already absent and retries only three times.
- `lib/request_bin_web/live/index_live/index.ex` — sends an incorrect hours-based `expires_at` value and pattern-matches success.
- New tests under `test/request_bin/` and `test/request_bin_web/live/` — create them using the baseline from Plan 002.

Current create/schedule sequence:

```elixir
# lib/request_bin/bin.ex:5-24
def create_and_schedule_bin() do
  {:ok, bin} = BinsRepo.create_bin()

  retention_period = String.to_integer(System.get_env("RETENTION_PERIOD") || "2")

  remove_time =
    DateTime.utc_now()
    |> DateTime.add(retention_period * 24, :hour)

  Oban.insert!(
    Oban.Job.new(%{bin_id: bin.id},
      worker: DeleteBinJob,
      scheduled_at: remove_time,
      queue: :default
    )
  )

  {:ok, bin}
end
```

Problems visible in that excerpt:

- Environment parsing happens during a user event and can raise.
- `retention_period` is not passed to `create_bin`, so the row remains at its default even when the job uses another value.
- The bin transaction commits before job insertion.
- Bang calls turn recoverable failures into LiveView process crashes.

Current schema validation does not enforce the existing database contract:

```elixir
# lib/request_bin/bins/bin.ex:17-21
def changeset(bin, attrs) do
  bin
  |> cast(attrs, [:retention_period])
  |> validate_required([])
end
```

Current UI unit mismatch:

```elixir
# lib/request_bin_web/live/index_live/index.ex:83-85
def handle_event("create_bin", _value, socket) do
  {:ok, bin} = Bins.create_and_schedule_bin()
  expires_at = DateTime.add(bin.inserted_at, bin.retention_period, :hour)
```

Current cleanup is not idempotent:

```elixir
# lib/request_bin/oban_jobs/delete_bin.ex:9-19
def perform(%Oban.Job{args: args}) do
  %{"bin_id" => bin_id} = args

  Repo.transaction(fn ->
    Requests.delete_for_bin(bin_id)
    Repo.get!(Bin, bin_id) |> Repo.delete()
  end)

  :ok
end
```

Database constraints already define the intended unit/range:

```elixir
# priv/repo/migrations/20250210083201_create_bins.exs:8-21
# retention_period (days)
add :retention_period, :integer, default: 2, null: false
# ...
create constraint(:bins, :retention_period_must_be_positive, check: "retention_period > 0")
create constraint(:bins, :retention_period_must_be_less_than_a_year,
  check: "retention_period <= 365"
)
```

Repository conventions:

- The application is now Phoenix 1.8.9 / LiveView 1.2.7. The index render already begins with `<Layouts.app flash={@flash}>`, and `test/request_bin_web/live/bin_live_test.exs` exercises the `#create-bin` control. Modify only the event handler; preserve the Phoenix 1.8 layout, existing hooks, and product UI required by `AGENTS.md`.
- Domain orchestration belongs in `RequestBin.Bins`; persistence uses `RequestBin.Repo`/Ecto and jobs use `Oban.Worker`.
- Test database isolation uses `RequestBin.DataCase` and fixtures from Plan 002.
- Oban is configured with `testing: :manual` in tests; use `Oban.Testing`, not sleeps or a running queue.
- Public errors shown in LiveView should be stable user messages without database/changeset details.

## Target lifecycle contract

- `RETENTION_PERIOD` means whole days and defaults to 2.
- Allowed values are integers `1..365`, matching the existing constraints.
- Parsed value lives at `Application.fetch_env!(:request_bin, :retention_period_days)`.
- Every new bin persists that exact value.
- `RequestBin.Bins.expires_at/1` is the only expiry calculation and adds `days * 86_400` seconds to `bin.inserted_at` for compatibility with the project’s Elixir requirement.
- Bin and Oban job insertions occur in one `Ecto.Multi`/Repo transaction.
- If either insertion fails, neither row commits and callers receive `{:error, reason}`.
- Deletion succeeds when the bin exists or is already gone; real database failures remain retryable.

## Commands you will need

| Purpose                  | Command                                                             | Expected on success                   |
| ------------------------ | ------------------------------------------------------------------- | ------------------------------------- |
| Strict compile           | `MIX_ENV=test mix compile --warnings-as-errors`                     | Exit 0.                               |
| Bin tests                | `mix test test/request_bin/bin_test.exs`                            | Exit 0, `0 failures`.                 |
| Job tests                | `mix test test/request_bin/oban_jobs/delete_bin_test.exs`           | Exit 0, `0 failures`.                 |
| LiveView expiry tests    | `mix test test/request_bin_web/live/index_live_expiration_test.exs` | Exit 0, `0 failures`.                 |
| Full tests               | `mix test`                                                          | Exit 0, `0 failures`.                 |
| Format                   | `mix format --check-formatted`                                      | Exit 0.                               |
| Required repository gate | `mix precommit`                                                     | Exit 0 and tests report `0 failures`. |
| Diff hygiene             | `git diff --check`                                                  | Exit 0.                               |

## Scope

**In scope** — the only files you should modify or create:

- `config/runtime.exs`
- `lib/request_bin/bin.ex`
- `lib/request_bin/bins/bin.ex`
- `lib/request_bin/oban_jobs/delete_bin.ex`
- `lib/request_bin_web/live/index_live/index.ex`
- `test/request_bin/bin_test.exs` — create.
- `test/request_bin/oban_jobs/delete_bin_test.exs` — create.
- `test/request_bin_web/live/index_live_expiration_test.exs` — create.
- `plans/README.md` — status update only.

**Out of scope** — do not touch:

- Existing migrations or database constraints.
- Request-table foreign-key behavior, cascade deletion, or request indexes.
- Existing bins/jobs already in production; do not write an unrequested backfill.
- User-selectable retention, manual deletion, or separate collector/inspector tokens.
- Request capture, trusted IP, rate-limit, or inspector code from Plans 003–004.
- Local-storage hook cleanup or historical local-storage entries.
- A recurring fallback cleanup job; atomic scheduling and reliable retries are sufficient here.

## Git workflow

- Branch: `advisor/005-atomic-bin-expiration`
- Prefer two commits: `fix: create bins and deletion jobs atomically`, then `test: cover bin expiration lifecycle`.
- Do not push or open a PR unless the operator explicitly requests it.

## Steps

### Step 1: Parse and validate retention at runtime

In `config/runtime.exs`, preserve all settings introduced by Plans 003–004 and add all-environment parsing for `RETENTION_PERIOD` before the production-only block:

1. Read `RETENTION_PERIOD`, defaulting to string `"2"`.
2. Use `Integer.parse/1` and require that the entire value was consumed.
3. Accept only `1..365`.
4. On success:

   ```elixir
   config :request_bin, :retention_period_days, retention_period_days
   ```

5. On failure, raise a concise message naming `RETENTION_PERIOD` and the allowed range. Do not include unrelated environment data.

Remove all `System.get_env("RETENTION_PERIOD")` calls from application modules later in this plan.

**Verify valid configuration**:

```bash
RETENTION_PERIOD=7 MIX_ENV=test mix run --no-start -e 'IO.puts(Application.fetch_env!(:request_bin, :retention_period_days))'
```

Expected: exit 0 and output `7`.

**Verify invalid configuration fails closed**:

```bash
if RETENTION_PERIOD=0 MIX_ENV=test mix run --no-start -e ':ok' >/tmp/request-bin-invalid-retention 2>&1; then
  echo 'invalid retention unexpectedly succeeded'
  exit 1
else
  grep -q 'RETENTION_PERIOD' /tmp/request-bin-invalid-retention
fi
```

Expected: the shell command exits 0 because config evaluation rejected zero and emitted the named configuration error. Repeat with a nonnumeric value during implementation.

### Step 2: Make the Bin changeset match database constraints

Update `RequestBin.Bins.Bin.changeset/2`:

- `validate_required([:retention_period])`
- `validate_number(:retention_period, greater_than: 0, less_than_or_equal_to: 365)`
- Add `check_constraint/3` entries using the exact existing names:
  - `retention_period_must_be_positive`
  - `retention_period_must_be_less_than_a_year`

Keep the schema default of 2 and the unit comment “days”. Do not change the migration.

Add tests for values 1, 365, 0, 366, an explicit nil, and a noninteger cast input. Also assert that omitted attributes retain the schema default of 2 and remain valid. Assert field errors with `errors_on/1`; do not assert full changeset inspection strings.

**Verify**:

```bash
MIX_ENV=test mix compile --warnings-as-errors &&
MIX_ENV=test mix run --no-start -e '
alias RequestBin.Bins.Bin

for {value, expected_valid?} <- [{1, true}, {365, true}, {0, false}, {366, false}, {nil, false}] do
  changeset = Bin.changeset(%Bin{}, %{retention_period: value})

  if changeset.valid? != expected_valid? do
    raise "unexpected validity for retention_period=#{inspect(value)}"
  end
end
'
```

Expected: exit 0; valid boundary values pass and invalid values fail validation.

### Step 3: Insert the bin and deletion job in one transaction

Refactor `RequestBin.Bins`:

1. Alias/import `Ecto.Multi`, `RequestBin.Repo`, `RequestBin.Bins.Bin`, and `DeleteBinJob` as needed.
2. Add public `expires_at/1` for a persisted `%Bin{}`:

   ```elixir
   DateTime.add(bin.inserted_at, bin.retention_period * 86_400, :second)
   ```

   Do not use `:day`; the project supports Elixir versions where `DateTime.add/3` expects system time units.

3. In `create_and_schedule_bin/0`, fetch `:retention_period_days` from application config.
4. Build an `Ecto.Multi`:
   - `Multi.insert(:bin, Bin.changeset(%Bin{}, %{retention_period: days}))`
   - `Oban.insert(:delete_job, fn %{bin: bin} -> DeleteBinJob.new(%{bin_id: bin.id}, scheduled_at: expires_at(bin), queue: :default) end)`
5. Execute with `Repo.transaction/1`.
6. Normalize the result while retaining the existing success contract:
   - `{:ok, %{bin: bin, delete_job: _job}}` → `{:ok, bin}`
   - `{:error, _operation, reason, _changes}` → `{:error, reason}`
7. Remove `BinsRepo.create_bin/0`, `String.to_integer/1`, `DateTime.utc_now/0`, and `Oban.insert!/1` from this function. Do not delete `BinsRepo`; tests and other callers still use it.

Use Oban’s documented Ecto.Multi API, not `Ecto.Multi.run` around a separate `Oban.insert!` call.

**Verify**:

```bash
grep -q 'Ecto.Multi' lib/request_bin/bin.ex &&
grep -q 'Oban.insert' lib/request_bin/bin.ex &&
! grep -q 'Oban.insert!' lib/request_bin/bin.ex &&
! grep -q 'System.get_env("RETENTION_PERIOD")' lib/request_bin/bin.ex &&
MIX_ENV=test mix compile --warnings-as-errors
```

Expected: exit 0.

### Step 4: Test persisted retention and scheduled deletion together

Create `test/request_bin/bin_test.exs` using `RequestBin.DataCase` and:

```elixir
use Oban.Testing, repo: RequestBin.Repo
```

The tests must not be async because they temporarily change application configuration.

Cover:

1. Changeset boundaries from Step 2.
2. With `Application.put_env(:request_bin, :retention_period_days, 7)`, `create_and_schedule_bin/0`:
   - returns `{:ok, bin}`,
   - persists `bin.retention_period == 7`,
   - enqueues `DeleteBinJob` with the bin ID,
   - schedules it at `Bins.expires_at(bin)` using Oban Testing’s timestamp delta support.
3. `expires_at/1` differs from `inserted_at` by exactly `days * 86_400` seconds.
4. Restore the prior application value with `on_exit`.

Do not assert exact wall-clock `DateTime.utc_now`; derive expected time from the returned persisted bin.

Atomicity itself comes from the single `Ecto.Multi` transaction. Do not add test-only dependency injection or corrupt the Oban table merely to force a job-insert failure.

**Verify**: `mix test test/request_bin/bin_test.exs` → exit 0 and `0 failures`.

### Step 5: Make deletion idempotent and preserve retries

Refactor `DeleteBinJob.perform/1` while preserving a single database transaction:

1. Extract the `bin_id` from the known internal job argument.
2. Inside `Repo.transaction/1`:
   - delete requests for that bin using the existing `Requests.delete_for_bin/1`,
   - use `Repo.get(Bin, bin_id)` rather than `Repo.get!/2`,
   - if no bin exists, return `:ok`,
   - if a bin exists, delete it with a raising or explicitly checked Repo operation so a real delete error rolls back the request deletion and causes an Oban retry.
3. Convert `{:ok, _}` transaction success to `:ok`.
4. Convert `{:error, reason}` to `{:error, reason}`; do not discard real database failures.
5. Increase `max_attempts` from 3 to 20, or remove the override only if the installed Oban default is confirmed to be 20. Prefer explicit `max_attempts: 20` so the retention policy is visible.

Create `test/request_bin/oban_jobs/delete_bin_test.exs` using `RequestBin.DataCase`:

1. Create a bin and at least two request fixtures, call `perform/1`, and assert bin plus requests are gone.
2. Call `perform/1` a second time with the same job and assert `:ok`.
3. Call `perform/1` for a never-existing valid UUID and assert `:ok`.
4. Do not test malformed job args; only this application creates these jobs.

**Verify**: `mix test test/request_bin/oban_jobs/delete_bin_test.exs` → exit 0 and `0 failures`.

### Step 6: Use the shared expiry calculation and handle creation errors in LiveView

Update `handle_event("create_bin", ...)` in `BinLive.Index`:

- Replace the success pattern match with a `case`.
- On `{:ok, bin}`:
  - compute `expires_at = Bins.expires_at(bin)`,
  - push the same `store_bin` payload shape,
  - navigate to the inspector as today.
- On `{:error, _reason}`:
  - remain on the index,
  - set a stable error flash such as “Could not create a request bin. Please try again.”,
  - do not expose changeset/database/Oban details and do not push a local-storage event.

Create `test/request_bin_web/live/index_live_expiration_test.exs` using `RequestBinWeb.ConnCase`, `Phoenix.LiveViewTest`, and Oban Testing if needed. Cover:

1. Configure a known retention day count and click the create control.
2. Assert a `store_bin` event is pushed with an ISO-8601 expiry.
3. Load the created bin and assert the pushed expiry equals `Bins.expires_at(bin)` rather than `inserted_at + retention hours`.
4. Assert navigation targets that bin’s inspector.
5. Restore application configuration with `on_exit`.

If asserting the pushed event after `push_navigate` is awkward in the installed LiveView test version, test the event payload through the appropriate `assert_push_event/3` API and separately assert `Bins.expires_at/1`; do not weaken the requirement to a source-string assertion alone.

**Verify**: `mix test test/request_bin_web/live/index_live_expiration_test.exs` → exit 0 and `0 failures`.

### Step 7: Run full verification and confirm scope

**Verify**:

```bash
mix format --check-formatted &&
MIX_ENV=test mix compile --warnings-as-errors &&
mix test &&
mix precommit &&
git diff --check
```

Expected: exit 0 and tests report `0 failures`.

Verify stale patterns are gone:

```bash
! grep -R 'DateTime.add(bin.inserted_at, bin.retention_period, :hour)' lib/request_bin_web/live/index_live/index.ex &&
! grep -R 'System.get_env("RETENTION_PERIOD")' lib --include='*.ex' &&
! grep -R 'Repo.get!(Bin, bin_id)' lib/request_bin/oban_jobs/delete_bin.ex &&
! grep -R 'Oban.insert!' lib/request_bin/bin.ex
```

Expected: exit 0.

Verify scope:

```bash
git diff --name-only | grep -Ev '^((config/runtime\.exs|lib/request_bin/bin\.ex|lib/request_bin/bins/bin\.ex|lib/request_bin/oban_jobs/delete_bin\.ex|lib/request_bin_web/live/index_live/index\.ex|test/request_bin/bin_test\.exs|test/request_bin/oban_jobs/delete_bin_test\.exs|test/request_bin_web/live/index_live_expiration_test\.exs|plans/README\.md))$' | tee /tmp/request-bin-plan-005-out-of-scope
test ! -s /tmp/request-bin-plan-005-out-of-scope
```

Expected: exit 0 and the temporary report is empty.

## Test plan

- `test/request_bin/bin_test.exs`
  - changeset range/required checks
  - configured days persisted
  - job enqueued in the same successful operation
  - exact shared expiry calculation
- `test/request_bin/oban_jobs/delete_bin_test.exs`
  - delete bin with requests
  - second delivery is harmless
  - already-missing bin is harmless
- `test/request_bin_web/live/index_live_expiration_test.exs`
  - browser receives days-based expiry matching the job/domain calculation
  - navigation remains correct

Follow Plan 002’s `DataCase`, `ConnCase`, and fixture conventions. Use Oban Testing in manual mode; never wait for real scheduled execution.

Final verification: `mix test` → exit 0 and `0 failures`.

## Done criteria

- [ ] `RETENTION_PERIOD` is parsed once at runtime, defaults to 2 days, and rejects values outside `1..365`.
- [ ] New bins persist the configured day count.
- [ ] Bin and Oban job insertions occur in one `Ecto.Multi` transaction.
- [ ] `Bins.expires_at/1` is used for both scheduling and the browser event.
- [ ] UI expiry differs from insertion by `retention_period * 86_400` seconds.
- [ ] LiveView handles creation errors without crashing or exposing internals.
- [ ] Deletion is safe when delivered twice or when the bin is already absent.
- [ ] Real deletion transaction failures remain retryable, with up to 20 attempts.
- [ ] No migration was added or changed.
- [ ] All targeted/full tests, strict compile, formatting, `mix precommit`, and diff checks pass.
- [ ] `plans/README.md` marks Plan 005 `DONE`.

## STOP conditions

Stop and report back instead of improvising if:

- Plan 004 is incomplete or `config/runtime.exs` does not contain the expected prior proxy/body-limit settings.
- Production intentionally uses a retention unit other than whole days despite the schema comment and database constraints.
- Existing production bins/jobs must be corrected retroactively; that needs a separately reviewed backfill/reconciliation plan.
- Oban’s installed version cannot insert a job changeset into `Ecto.Multi` using the documented API.
- Achieving atomicity requires a schema migration or job-table customization.
- The deletion transaction cannot distinguish an already-absent bin from a real database failure.
- LiveView event assertions require browser/E2E infrastructure not present in the project; report the exact limitation rather than deleting the regression case.
- `mix precommit` changes `mix.exs`, `mix.lock`, or another out-of-scope file.
- Any verification command fails twice after a reasonable correction.

## Maintenance notes

- Treat `retention_period` as days everywhere. Future UI/config changes should call `Bins.expires_at/1` rather than duplicating time arithmetic.
- The bin row and Oban job are the lifecycle source of truth; local storage is only a recent-bin convenience.
- Existing bins created before this change may have a persisted value that differs from their scheduled job. This plan deliberately does not infer or rewrite historical schedules.
- A future foreign-key cascade could simplify deletion, but it should be paired with the deferred request-index/history work and a migration review.
- Reviewers should scrutinize transaction boundaries and error normalization more than formatting; silent unscheduled bins are the failure this plan must eliminate.
