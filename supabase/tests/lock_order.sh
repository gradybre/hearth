#!/usr/bin/env bash
# Two sessions, because a deadlock needs two (B02).
#
# `schema_guards.sql` is one psql session, and a lock-order bug is invisible
# from inside one: every statement it runs succeeds. This drives the real
# `reserve_ai_spend` and `settle_ai_spend` from two connections at once and
# fails if Postgres has to break the tie.
#
# The shape it catches: `settle_ai_spend` locks the month's `ai_usage` row and
# then deletes its reservation. If `reserve_ai_spend` takes those two the
# other way round — sweeping expired reservations *before* it locks the month
# — the two wait on each other, Postgres aborts one, and the reserve comes
# back to the Edge Function as a throw. `Budget.reserve` cannot tell that from
# an unreadable ledger, so it answers 503 and refuses an import whose budget
# was never the problem.
#
# It reproduces only when a reservation is settled *after* it has expired —
# an isolate that stalled past the TTL — which is why it needs staging rather
# than load.
set -euo pipefail

DB=${HEARTH_DB_CONTAINER:-supabase_db_hearth}
RID='11111111-1111-1111-1111-111111111111'

psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }

cleanup() {
  psql -q -c "delete from public.ai_reservations where id = '$RID';" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# A reservation whose call is only now coming back, already past its TTL.
psql -v ON_ERROR_STOP=1 -q <<EOF
insert into public.ai_usage (month) values (date_trunc('month', now())::date)
  on conflict (month) do nothing;
delete from public.ai_reservations where id = '$RID';
insert into public.ai_reservations (id, month, mode, amount_usd, expires_at)
values ('$RID', date_trunc('month', now())::date, 'extract', 0.17,
        now() - interval '1 minute');
EOF

# The settling session. It takes the month's row exactly as `record_ai_usage`
# does inside `settle_ai_spend`, waits where a real settle would be mid-flight,
# and then runs the real settle — so the lock order under test is the
# function's own, not this script's.
settling=$(mktemp)
(
  psql -v ON_ERROR_STOP=1 <<EOF
begin;
select cost_usd from public.ai_usage
  where month = date_trunc('month', now())::date for update;
select pg_sleep(4);
select cost_usd from public.settle_ai_spend('$RID', 1000, 2000, 0.0330);
commit;
EOF
) >"$settling" 2>&1 &
settler=$!

# And the real reserve, arriving while that settle is in flight.
reserving=$(mktemp)
(
  sleep 1
  psql -v ON_ERROR_STOP=1 -c \
    "select allowed from public.reserve_ai_spend(0.17, 'extract', 25.0, 300);"
) >"$reserving" 2>&1 &
reserver=$!

reserve_ok=0; wait $reserver || reserve_ok=$?
settle_ok=0;  wait $settler  || settle_ok=$?

# Undo the spending this test recorded. Not a household's real money.
psql -q -c "update public.ai_usage
              set calls = calls - 1, input_tokens = input_tokens - 1000,
                  output_tokens = output_tokens - 2000,
                  cost_usd = cost_usd - 0.0330
            where month = date_trunc('month', now())::date
              and calls > 0;" >/dev/null

if grep -qi 'deadlock detected' "$reserving" "$settling"; then
  echo 'FAIL: reserve_ai_spend and settle_ai_spend deadlock.'
  echo '      They take ai_usage and ai_reservations in opposite orders; a'
  echo '      reserve aborted this way reaches the app as 503 "cannot check'
  echo "      this month's AI spending\" with nothing actually wrong."
  grep -i -A2 'deadlock detected' "$reserving" "$settling" || true
  exit 1
fi

if [ "$reserve_ok" -ne 0 ] || [ "$settle_ok" -ne 0 ]; then
  echo "FAIL: a session errored (reserve=$reserve_ok settle=$settle_ok)."
  cat "$reserving" "$settling"
  exit 1
fi

echo 'AI ledger lock-order guard passed'
