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
