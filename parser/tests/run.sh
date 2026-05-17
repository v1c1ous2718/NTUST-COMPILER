#!/usr/bin/env bash
# Run every spec test and verify positive (00–99) parses cleanly,
# negative (N*) emits expected error count.
set -u
cd "$(dirname "$0")/.."
[ -x ./parser ] || make >/dev/null

pass=0
fail=0

run_pos() {
    local f="$1"
    local out err rc
    out=$(./parser "$f" 2>&1)
    rc=$?
    err=$(printf '%s\n' "$out" | grep -E "^line [0-9]+: " | grep -v "warning:" | wc -l)
    if [ "$rc" -eq 0 ] && [ "$err" -eq 0 ]; then
        printf '  PASS  %s\n' "$f"
        pass=$((pass+1))
    else
        printf '  FAIL  %s (rc=%d, errors=%d)\n' "$f" "$rc" "$err"
        printf '%s\n' "$out" | sed 's/^/        /'
        fail=$((fail+1))
    fi
}

run_neg() {
    local f="$1"
    local want="$2"
    local out err
    out=$(./parser "$f" 2>&1)
    err=$(printf '%s\n' "$out" | grep -E "^line [0-9]+: " | grep -v "warning:" | wc -l)
    if [ "$err" -ge "$want" ]; then
        printf '  PASS  %s (got %d, want >= %d errors)\n' "$f" "$err" "$want"
        pass=$((pass+1))
    else
        printf '  FAIL  %s (got %d, want >= %d errors)\n' "$f" "$err" "$want"
        printf '%s\n' "$out" | sed 's/^/        /'
        fail=$((fail+1))
    fi
}

echo "== Positive tests =="
for f in tests/0*.p tests/begin_empty_end.p tests/spec_full.p; do
    [ -f "$f" ] && run_pos "$f"
done

echo
echo "== Negative tests =="
run_neg tests/N1_const_reassign.p     1
run_neg tests/N2_assign_type.p        1
run_neg tests/N3_array_index.p        2
run_neg tests/N4_call_arity.p         3
run_neg tests/N5_proc_in_expr.p       2
run_neg tests/N6_for_counter.p        3
run_neg tests/N7_end_id.p             3
run_neg tests/N8_undeclared.p         4
run_neg tests/N9_nested_subprog.p     1
run_neg tests/N10_cond_must_bool.p    4
run_neg tests/N11_return.p            3
run_neg tests/N12_const_init_only.p   2
run_neg tests/spec_negs.p             9

echo
printf 'Total: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
