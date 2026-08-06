#!/bin/bash
# CLI surface: help, version, bad args.

begin "cli: --version prints version"
OUT=$("$PDF2CBZ" --version)
assert_match "$OUT" "pdf2cbz 0.1.0"

begin "cli: --help mentions usage"
OUT=$("$PDF2CBZ" --help)
assert_match "$OUT" "Usage: pdf2cbz"

begin "cli: no args exits nonzero"
if "$PDF2CBZ" >/dev/null 2>&1; then fail "exited zero"; else ok; fi

begin "cli: unknown flag exits nonzero"
if "$PDF2CBZ" --bogus >/dev/null 2>&1; then fail "exited zero"; else ok; fi
