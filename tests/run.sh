#!/bin/bash
# comicdown test runner: sources every tests/*.test.sh and reports totals.
set -u
cd "$(dirname "$0")" || exit 1
ROOT=$(cd .. && pwd)
# shellcheck disable=SC2034  # used by tests/*.test.sh, sourced dynamically below
PDF2CBZ="$ROOT/bin/pdf2cbz"
PASS=0 FAIL=0 CURRENT=""

begin() { CURRENT="$1"; }
ok()    { PASS=$((PASS + 1)); printf 'ok   %s\n' "$CURRENT"; }
fail()  { FAIL=$((FAIL + 1)); printf 'FAIL %s: %s\n' "$CURRENT" "$1"; }

assert_eq()    { if [ "$1" = "$2" ]; then ok; else fail "expected [$2] got [$1]"; fi; }
assert_match() { case "$1" in *"$2"*) ok ;; *) fail "output [$1] missing [$2]" ;; esac; }
assert_file()  { if [ -f "$1" ]; then ok; else fail "missing file $1"; fi; }
assert_absent(){ if [ ! -e "$1" ]; then ok; else fail "unexpected file $1"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/comicdown-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

for t in ./*.test.sh; do
  # shellcheck disable=SC1090
  . "$t"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
