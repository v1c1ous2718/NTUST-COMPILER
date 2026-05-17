#!/usr/bin/env bash
# Sanity-check sweep for the Delphi- -> Java-assembly compiler.
#
# Convention:
#   tests/SNN_NAME.del   - success case
#       1. compiler must accept it (no `line N: ...` errors)
#       2. javaa must assemble the produced .jasm
#       3. `java -cp tests/. SNN_NAME` must run with exit code 0
#   tests/FNN_NAME.del   - fail case
#       1. compiler must emit at least one `line N: ...` diagnostic
#
# Usage:
#   tests/run.sh                # run every .del under tests/
#   tests/run.sh S03 F05        # run only matching prefixes
#   VERBOSE=1 tests/run.sh      # also print each program's stdout
#
# Exits non-zero if anything regresses.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER=$ROOT/compiler
JAVAA=$ROOT/javaa/javaa
TESTS=$ROOT/tests

if [ ! -x "$COMPILER" ]; then
    echo "compiler binary not found at $COMPILER -- run 'make' first" >&2
    exit 2
fi
if [ ! -x "$JAVAA" ]; then
    echo "javaa binary not found at $JAVAA" >&2
    exit 2
fi
if ! command -v java >/dev/null; then
    echo "java not on PATH" >&2
    exit 2
fi

shopt -s nullglob
if [ $# -eq 0 ]; then
    files=( "$TESTS"/*.del )
else
    files=()
    for pat in "$@"; do
        files+=( "$TESTS"/${pat}*.del )
    done
fi

pass=0
fail=0

run_success() {
    local f=$1 name=$2

    local cout
    cout=$("$COMPILER" "$f" 2>&1)
    if echo "$cout" | grep -qE '^line [0-9]+: '; then
        printf 'BAD %-40s compile error: %s\n' "$name" \
            "$(echo "$cout" | grep -E '^line ' | head -1)"
        return 1
    fi

    local jasm=$TESTS/$name.jasm
    if [ ! -s "$jasm" ]; then
        printf 'BAD %-40s no .jasm produced\n' "$name"
        return 1
    fi

    local aout
    aout=$(cd "$TESTS" && "$JAVAA" "$name.jasm" 2>&1)
    if [ ! -s "$TESTS/$name.class" ]; then
        printf 'BAD %-40s javaa failed: %s\n' "$name" \
            "$(echo "$aout" | tail -1)"
        return 1
    fi

    local rout rc
    rout=$(java -cp "$TESTS/." "$name" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        printf 'BAD %-40s java exit=%d output=%s\n' "$name" "$rc" \
            "$(echo "$rout" | head -1)"
        return 1
    fi

    printf 'OK  %s\n' "$name"
    if [ "${VERBOSE:-}" = 1 ] && [ -n "$rout" ]; then
        echo "$rout" | sed 's/^/    | /'
    fi
    return 0
}

run_fail() {
    local f=$1 name=$2

    local cout err
    cout=$("$COMPILER" "$f" 2>&1)
    err=$(echo "$cout" | grep -E '^line [0-9]+: ' | head -1)
    if [ -n "$err" ]; then
        printf 'OK  %-40s %s\n' "$name" "$err"
        return 0
    else
        printf 'BAD %-40s expected an error, got none\n' "$name"
        return 1
    fi
}

for f in "${files[@]}"; do
    name=$(basename "$f" .del)
    case $name in
        F*) if run_fail    "$f" "$name"; then pass=$((pass+1)); else fail=$((fail+1)); fi ;;
        *)  if run_success "$f" "$name"; then pass=$((pass+1)); else fail=$((fail+1)); fi ;;
    esac
done

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
