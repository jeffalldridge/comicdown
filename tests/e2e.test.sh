#!/bin/bash
# End-to-end tests over fixture PDFs.

begin "e2e jpeg-book: produces cbz"
cp fixtures/jpeg-book.pdf "$WORK/"
OUT=$("$PDF2CBZ" "$WORK/jpeg-book.pdf" 2>&1)
assert_file "$WORK/jpeg-book.cbz"

begin "e2e jpeg-book: reports all pages lossless"
assert_match "$OUT" "3/3 pages lossless"

begin "e2e jpeg-book: no sidecar log for a clean book"
assert_absent "$WORK/jpeg-book.cbz.log"

begin "e2e jpeg-book: images byte-identical to embedded streams"
mkdir -p "$WORK/ref" "$WORK/got"
pdfimages -all fixtures/jpeg-book.pdf "$WORK/ref/img" 2>/dev/null
unzip -qo "$WORK/jpeg-book.cbz" -d "$WORK/got"
REFS=("$WORK"/ref/img-*.jpg)
GOTS=("$WORK"/got/*.jpg)
SAME=1
[ "${#REFS[@]}" -eq 3 ] || SAME=0
[ "${#GOTS[@]}" -eq 3 ] || SAME=0
if [ "$SAME" = 1 ]; then
  for i in 0 1 2; do
    cmp -s "${REFS[$i]}" "${GOTS[$i]}" || SAME=0
  done
fi
assert_eq "$SAME" 1

begin "e2e png-book: flate pages come out as png, lossless"
cp fixtures/png-book.pdf "$WORK/"
OUT=$("$PDF2CBZ" "$WORK/png-book.pdf" 2>&1)
assert_match "$OUT" "2/2 pages lossless"

begin "e2e png-book: cbz contains 2 png pages"
mkdir -p "$WORK/gotpng"
unzip -qo "$WORK/png-book.cbz" -d "$WORK/gotpng"
N=$(find "$WORK/gotpng" -name '*.png' | wc -l | tr -d ' ')
assert_eq "$N" "2"

begin "e2e gnarly filename: spaces, apostrophe, parens"
cp fixtures/jpeg-book.pdf "$WORK/My Comic's Vol. 2 (2019).pdf"
OUT=$("$PDF2CBZ" "$WORK/My Comic's Vol. 2 (2019).pdf" 2>&1)
assert_file "$WORK/My Comic's Vol. 2 (2019).cbz"
assert_match "$OUT" "3/3 pages lossless"

begin "e2e read-only dir: fails loudly, no false success"
mkdir "$WORK/ro"
cp fixtures/jpeg-book.pdf "$WORK/ro/"
chmod 555 "$WORK/ro"
if OUT=$("$PDF2CBZ" "$WORK/ro/jpeg-book.pdf" 2>&1); then
  fail "expected nonzero exit"
else
  ok
fi
chmod 755 "$WORK/ro"
case "$OUT" in
  *"pages lossless"*) fail "output falsely claims success: $OUT" ;;
  *) ok ;;
esac

begin "e2e masked-page: converts with fallback"
cp fixtures/masked-page.pdf "$WORK/"
OUT=$("$PDF2CBZ" "$WORK/masked-page.pdf" 2>&1)
assert_file "$WORK/masked-page.cbz"

begin "e2e masked-page: summary reports the rendered page"
assert_match "$OUT" "1/2 pages lossless"

begin "e2e masked-page: summary names page 2"
assert_match "$OUT" "rendered: 2 (72 DPI)"

begin "e2e masked-page: sidecar log written with reason"
assert_file "$WORK/masked-page.cbz.log"
LOG=$(cat "$WORK/masked-page.cbz.log")
assert_match "$LOG" "page 2: mask — rendered at 72 DPI"

begin "e2e masked-page: cbz still has 2 pages"
mkdir -p "$WORK/gotmask"
unzip -qo "$WORK/masked-page.cbz" -d "$WORK/gotmask"
N=$(find "$WORK/gotmask" -type f -size +0 | wc -l | tr -d ' ')
assert_eq "$N" "2"

begin "e2e multi-image-page: layered page falls back, other stays lossless"
cp fixtures/multi-image-page.pdf "$WORK/"
OUT=$("$PDF2CBZ" "$WORK/multi-image-page.pdf" 2>&1)
assert_match "$OUT" "1/2 pages lossless"

begin "e2e multi-image-page: log says multi-image"
LOG=$(cat "$WORK/multi-image-page.cbz.log")
assert_match "$LOG" "page 2: multi-image"

begin "e2e collision: second run writes ' (1).cbz'"
"$PDF2CBZ" "$WORK/jpeg-book.pdf" >/dev/null 2>&1
assert_file "$WORK/jpeg-book (1).cbz"

begin "e2e batch: two files in one call"
mkdir -p "$WORK/batch"
cp fixtures/jpeg-book.pdf fixtures/png-book.pdf "$WORK/batch/"
OUT=$("$PDF2CBZ" "$WORK/batch/jpeg-book.pdf" "$WORK/batch/png-book.pdf" 2>&1)
assert_file "$WORK/batch/jpeg-book.cbz"
assert_file "$WORK/batch/png-book.cbz"

begin "e2e batch: missing file fails but doesn't sink the batch"
mkdir -p "$WORK/batch2"
cp fixtures/jpeg-book.pdf "$WORK/batch2/"
if "$PDF2CBZ" "$WORK/nope.pdf" "$WORK/batch2/jpeg-book.pdf" >/dev/null 2>&1; then
  fail "expected nonzero exit"
else
  ok
fi
begin "e2e batch: the good file still converted"
assert_file "$WORK/batch2/jpeg-book.cbz"

begin "e2e bad input: non-PDF is rejected cleanly"
printf 'not a pdf' > "$WORK/junk.pdf"
if "$PDF2CBZ" "$WORK/junk.pdf" >/dev/null 2>&1; then fail "expected nonzero exit"; else ok; fi
begin "e2e bad input: no cbz produced for junk"
assert_absent "$WORK/junk.cbz"

begin "e2e notify: --notify flag is accepted"
cp fixtures/jpeg-book.pdf "$WORK/notify.pdf"
if "$PDF2CBZ" --notify "$WORK/notify.pdf" >/dev/null 2>&1; then ok; else fail "nonzero exit"; fi

begin "e2e render failure: 0-byte render fails loudly with captured stderr"
mkdir -p "$WORK/shim"
cat > "$WORK/shim/pdftoppm" <<'SHIM'
#!/bin/bash
# Parse the output prefix (last arg) and fake a truncated write.
eval "prefix=\${$#}"
: > "${prefix}-2.jpg"
echo "SHIM: could not write image data (disk full)" >&2
exit 0
SHIM
chmod +x "$WORK/shim/pdftoppm"
mkdir -p "$WORK/renderfail"
cp fixtures/masked-page.pdf "$WORK/renderfail/"
OUT=$(PATH="$WORK/shim:$PATH" "$PDF2CBZ" "$WORK/renderfail/masked-page.pdf" 2>&1)
RC=$?
if [ "$RC" -ne 0 ]; then ok; else fail "expected nonzero exit"; fi
begin "e2e render failure: captured stderr surfaced"
assert_match "$OUT" "SHIM: could not write image data"
begin "e2e render failure: no cbz shipped"
assert_absent "$WORK/renderfail/masked-page.cbz"
