#!/bin/bash
# Unit tests for classify_pages, using synthetic `pdfimages -list` output.
# shellcheck disable=SC1090
. "$PDF2CBZ"

HEADER='page   num  type   width height color comp bpc  enc interp  object ID x-ppi y-ppi size ratio
--------------------------------------------------------------------------------------------'

begin "classifier: clean jpeg pages are lossless"
OUT=$(printf '%s\n   1     0 image     100   150  rgb     3   8  jpeg   no        10  0   300   300  15K 9.6%%\n   2     1 image     100   150  rgb     3   8  jpeg   no        12  0   300   300  15K 9.6%%\n' "$HEADER" | classify_pages 2)
assert_eq "$OUT" "1 lossless -
2 lossless -"

begin "classifier: flate (enc=image) is lossless"
OUT=$(printf '%s\n   1     0 image     100   150  rgb     3   8  image  no        10  0   300   300  15K 9.6%%\n' "$HEADER" | classify_pages 1)
assert_eq "$OUT" "1 lossless -"

begin "classifier: smask forces fallback"
OUT=$(printf '%s\n   1     0 image     100   150  rgb     3   8  jpeg   no        10  0   300   300  15K 9.6%%\n   1     1 smask     100   150  gray    1   8  image  no        11  0   300   300  5K  9.6%%\n' "$HEADER" | classify_pages 1)
assert_eq "$OUT" "1 fallback mask"

begin "classifier: two images on a page forces fallback"
OUT=$(printf '%s\n   1     0 image     100   150  rgb     3   8  jpeg   no        10  0   300   300  15K 9.6%%\n   1     1 image     100   150  rgb     3   8  jpeg   no        11  0   300   300  15K 9.6%%\n' "$HEADER" | classify_pages 1)
assert_eq "$OUT" "1 fallback multi-image"

begin "classifier: ccitt encoding forces fallback"
OUT=$(printf '%s\n   1     0 image     100   150  gray    1   1  ccitt  no        10  0   300   300  2K  9.6%%\n' "$HEADER" | classify_pages 1)
assert_eq "$OUT" "1 fallback enc:ccitt"

begin "classifier: jbig2 encoding forces fallback"
OUT=$(printf '%s\n   1     0 image     100   150  gray    1   1  jbig2  no        10  0   300   300  2K  9.6%%\n' "$HEADER" | classify_pages 1)
assert_eq "$OUT" "1 fallback enc:jbig2"

begin "classifier: cmyk jpeg forces fallback"
OUT=$(printf '%s\n   1     0 image     100   150  cmyk    4   8  jpeg   no        10  0   300   300  15K 9.6%%\n' "$HEADER" | classify_pages 1)
assert_eq "$OUT" "1 fallback cmyk"

begin "classifier: page with no raster image falls back (vector/text page)"
OUT=$(printf '%s\n   2     0 image     100   150  rgb     3   8  jpeg   no        10  0   300   300  15K 9.6%%\n' "$HEADER" | classify_pages 2)
assert_eq "$OUT" "1 fallback no-image
2 lossless -"

begin "classifier: icc 4-component jpeg forces fallback"
OUT=$(printf '%s\n   1     0 image     100   150  icc     4   8  jpeg   no        10  0   300   300  15K 9.6%%\n' "$HEADER" | classify_pages 1)
assert_eq "$OUT" "1 fallback cmyk"

begin "classifier: icc 3-component jpeg is lossless"
OUT=$(printf '%s\n   1     0 image     100   150  icc     3   8  jpeg   no        10  0   300   300  15K 9.6%%\n' "$HEADER" | classify_pages 1)
assert_eq "$OUT" "1 lossless -"
