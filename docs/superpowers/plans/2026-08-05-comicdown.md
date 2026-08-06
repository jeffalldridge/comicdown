# comicdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS CLI (`bin/pdf2cbz`) that losslessly extracts embedded page images from comic PDFs into CBZ files, with 300 DPI fallback for imperfect pages, a Finder Quick Action, tests, CI, and a public GitHub repo.

**Architecture:** Single bash script wrapping poppler (`pdfinfo`/`pdfimages`/`pdftoppm`) and macOS built-ins (`zip`, `sips`, `osascript`). A page classifier parses `pdfimages -list` to decide lossless vs fallback per page. Tests are plain bash over committed fixture PDFs generated once by a stdlib-only Python script.

**Tech Stack:** bash 3.2 (macOS system bash), poppler via Homebrew, GitHub Actions on `macos-latest`.

**Spec:** `docs/superpowers/specs/2026-08-05-comicdown-design.md`

## Environment notes (read first)

- Repo: `/Users/jeffalldridge/Documents/GitHub/comicdown` (git already initialized, spec committed).
- `pdfimages`, `pdfinfo`, `pdftoppm` are installed at `/opt/homebrew/bin` (brew poppler). Verify with `pdfimages -help`.
- **Target `/bin/bash` 3.2.** No associative arrays, no `${var,,}`, and `"${arr[@]}"` on an *empty* array errors under `set -u` — only expand arrays after checking `${#arr[@]}`.
- `pdfimages -p -all` writes files like `img-PPP-NNN.ext` (page, image number, both zero-padded). **Do not assume padding width** — the code parses page numbers out of filenames instead. During Task 5, eyeball the actual filenames once to confirm the `prefix-page-num.ext` shape.
- `python3` is needed only to generate test fixtures (once, committed). It's the Xcode CLT python at `/usr/bin/python3`.

---

### Task 1: Repo scaffolding

**Files:**
- Create: `.gitignore`, `LICENSE`, `README.md` (stub — full README in Task 10)

- [ ] **Step 1: Create `.gitignore`**

```gitignore
.DS_Store
```

- [ ] **Step 2: Create `LICENSE` (MIT)**

```text
MIT License

Copyright (c) 2026 Jeff Alldridge

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Create stub `README.md`**

```markdown
# comicdown

Losslessly convert comic-book PDFs to CBZ on macOS. Full README coming with v0.1.
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore LICENSE README.md
git commit -m "chore: repo scaffolding (MIT license, gitignore, README stub)"
```

---

### Task 2: Test harness + CLI skeleton

**Files:**
- Create: `tests/run.sh`, `tests/cli.test.sh`, `bin/pdf2cbz`

- [ ] **Step 1: Write the harness `tests/run.sh`**

```bash
#!/bin/bash
# comicdown test runner: sources every tests/*.test.sh and reports totals.
set -u
cd "$(dirname "$0")" || exit 1
ROOT=$(cd .. && pwd)
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
```

- [ ] **Step 2: Write the first tests `tests/cli.test.sh`**

```bash
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
```

- [ ] **Step 3: Run to verify failure**

```bash
chmod +x tests/run.sh
tests/run.sh
```

Expected: 4 FAIL lines (pdf2cbz doesn't exist yet), exit nonzero.

- [ ] **Step 4: Write the skeleton `bin/pdf2cbz`**

```bash
#!/bin/bash
# pdf2cbz — losslessly convert comic-book PDFs to CBZ.
# Part of comicdown: https://github.com/jeffalldridge/comicdown
#
# Targets macOS system bash 3.2: no associative arrays; never expand an
# array that may be empty while set -u is active.

VERSION="0.1.0"
RENDER_DPI=300
RENDER_QUALITY=90
NOTIFY=0

die() { printf 'pdf2cbz: %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: pdf2cbz [--notify] file.pdf [more.pdf ...]

Losslessly extracts the embedded page images from comic-book PDFs and packs
them into a .cbz next to each source file. Pages that cannot be extracted
losslessly are rendered at 300 DPI and reported.

Options:
  --notify     Also report via macOS notification (used by the Quick Action)
  --version    Print version
  -h, --help   Show this help
EOF
}

notify() {
  osascript -e "display notification \"${1//\"/\\\"}\" with title \"comicdown\"" \
    >/dev/null 2>&1 || true
}

check_deps() {
  local cmd missing=""
  for cmd in pdfinfo pdfimages pdftoppm; do
    command -v "$cmd" >/dev/null || missing="$missing $cmd"
  done
  if [ -n "$missing" ]; then
    local msg="missing$missing — install with: brew install poppler"
    if [ "$NOTIFY" = 1 ]; then notify "$msg"; fi
    die "$msg"
  fi
}

main() {
  local files_count=0
  FILES=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --notify) NOTIFY=1 ;;
      --version) printf 'pdf2cbz %s\n' "$VERSION"; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      -*) die "unknown option: $1 (see --help)" ;;
      *) FILES[$files_count]="$1"; files_count=$((files_count + 1)) ;;
    esac
    shift
  done
  [ "$files_count" -gt 0 ] || { usage >&2; exit 1; }
  check_deps
  die "conversion not implemented yet"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  main "$@"
fi
```

Note: `set -euo pipefail` lives inside the execution guard so tests can `source` the script for unit testing without inheriting `-e`.

- [ ] **Step 5: Run tests to verify pass**

```bash
chmod +x bin/pdf2cbz
tests/run.sh
```

Expected: `4 passed, 0 failed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add bin/pdf2cbz tests/run.sh tests/cli.test.sh
git commit -m "feat: pdf2cbz CLI skeleton with bash test harness"
```

---

### Task 3: Fixture generator + committed fixtures

**Files:**
- Create: `tests/make-fixtures.py`, `tests/fixtures/*.pdf` (generated, committed)

- [ ] **Step 1: Write `tests/make-fixtures.py`**

Stdlib-only PDF writer. Images are embedded exactly as `pdfimages` will extract them: JPEG bytes with `/DCTDecode` (real JPEGs produced via `sips`), raw RGB with `/FlateDecode`.

```python
#!/usr/bin/env python3
"""Generate comicdown test fixture PDFs. Run once; commit the output.

Stdlib only, plus macOS `sips` to produce real JPEG data. Images are
embedded as-is (DCTDecode / FlateDecode XObjects) so lossless extraction
is byte-comparable against the embedded stream.
"""
import os
import struct
import subprocess
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "fixtures")
W, H = 50, 40  # image pixel dims; tiny keeps fixtures a few KB


def png_bytes(w, h, rgb):
    """Minimal solid-color RGB PNG."""
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(
            ">I", zlib.crc32(c) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


def jpeg_bytes(rgb):
    """Real JPEG data for a solid color, via sips (PNG -> JPEG)."""
    png_path = os.path.join(OUT, "_tmp.png")
    jpg_path = os.path.join(OUT, "_tmp.jpg")
    with open(png_path, "wb") as f:
        f.write(png_bytes(W, H, rgb))
    subprocess.run(
        ["sips", "-s", "format", "jpeg", png_path, "--out", jpg_path],
        check=True, capture_output=True)
    with open(jpg_path, "rb") as f:
        data = f.read()
    os.remove(png_path)
    os.remove(jpg_path)
    return data


def flate_rgb(rgb):
    """Zlib-compressed raw RGB — pdfimages writes this back out as PNG."""
    return zlib.compress(bytes(rgb) * (W * H))


class PDF:
    def __init__(self):
        self.objs = [None]  # object numbers are 1-indexed

    def add(self, body):
        self.objs.append(body)
        return len(self.objs) - 1

    def write(self, path):
        out = bytearray(b"%PDF-1.5\n")
        offsets = [0]
        for i, body in enumerate(self.objs[1:], 1):
            offsets.append(len(out))
            out += b"%d 0 obj\n" % i + body + b"\nendobj\n"
        xref = len(out)
        out += b"xref\n0 %d\n" % len(self.objs)
        out += b"0000000000 65535 f \n"
        for off in offsets[1:]:
            out += b"%010d 00000 n \n" % off
        out += (b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n"
                % (len(self.objs), xref))
        with open(path, "wb") as f:
            f.write(out)


def image_obj(filt, data, colorspace=b"/DeviceRGB", extra=b""):
    return (b"<< /Type /XObject /Subtype /Image /Width %d /Height %d "
            b"/ColorSpace %s /BitsPerComponent 8 /Filter %s /Length %d %s>>"
            b"\nstream\n" % (W, H, colorspace, filt, len(data), extra)
            ) + data + b"\nendstream"


def build(path, pages):
    """pages: list of page specs. Each spec is a list of image dicts:
    {"filt": b"/DCTDecode"|b"/FlateDecode", "data": bytes,
     "colorspace": bytes (optional), "smask_data": bytes (optional,
     flate-compressed 8-bit gray, adds a /SMask sub-image)}.
    Every listed image is drawn full-page (layered in order)."""
    # Object layout: 1 catalog, 2 pages tree, then per page:
    #   page, contents, image..., [smask for that image]
    ids = {}
    next_id = 3
    for i, imgs in enumerate(pages):
        img_ids, smask_ids = [], []
        page_id, contents_id = next_id, next_id + 1
        next_id += 2
        for img in imgs:
            img_ids.append(next_id)
            next_id += 1
            if "smask_data" in img:
                smask_ids.append(next_id)
                next_id += 1
            else:
                smask_ids.append(None)
        ids[i] = (page_id, contents_id, img_ids, smask_ids)

    pdf = PDF()
    kids = b" ".join(b"%d 0 R" % ids[i][0] for i in range(len(pages)))
    assert pdf.add(b"<< /Type /Catalog /Pages 2 0 R >>") == 1
    assert pdf.add(b"<< /Type /Pages /Kids [%s] /Count %d >>"
                   % (kids, len(pages))) == 2
    for i, imgs in enumerate(pages):
        page_id, contents_id, img_ids, smask_ids = ids[i]
        xnames = b" ".join(b"/Im%d %d 0 R" % (j, oid)
                           for j, oid in enumerate(img_ids))
        got = pdf.add(b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 306 396] "
                      b"/Resources << /XObject << %s >> >> /Contents %d 0 R >>"
                      % (xnames, contents_id))
        assert got == page_id
        ops = b"".join(b"q 306 0 0 396 0 0 cm /Im%d Do Q\n" % j
                       for j in range(len(imgs)))
        got = pdf.add(b"<< /Length %d >>\nstream\n" % len(ops)
                      + ops + b"\nendstream")
        assert got == contents_id
        for j, img in enumerate(imgs):
            extra = b""
            if smask_ids[j] is not None:
                extra = b"/SMask %d 0 R " % smask_ids[j]
            got = pdf.add(image_obj(
                img["filt"], img["data"],
                img.get("colorspace", b"/DeviceRGB"), extra))
            assert got == img_ids[j]
            if smask_ids[j] is not None:
                got = pdf.add(image_obj(
                    b"/FlateDecode", img["smask_data"], b"/DeviceGray"))
                assert got == smask_ids[j]
    pdf.write(path)
    print("wrote", path)


def main():
    os.makedirs(OUT, exist_ok=True)
    red = jpeg_bytes((200, 40, 40))
    green = jpeg_bytes((40, 200, 40))
    blue = jpeg_bytes((40, 40, 200))
    gray_mask = zlib.compress(b"\x80" * (W * H))

    build(os.path.join(OUT, "jpeg-book.pdf"), [
        [{"filt": b"/DCTDecode", "data": red}],
        [{"filt": b"/DCTDecode", "data": green}],
        [{"filt": b"/DCTDecode", "data": blue}],
    ])
    build(os.path.join(OUT, "png-book.pdf"), [
        [{"filt": b"/FlateDecode", "data": flate_rgb((200, 40, 40))}],
        [{"filt": b"/FlateDecode", "data": flate_rgb((40, 40, 200))}],
    ])
    build(os.path.join(OUT, "masked-page.pdf"), [
        [{"filt": b"/DCTDecode", "data": red}],
        [{"filt": b"/DCTDecode", "data": green, "smask_data": gray_mask}],
    ])
    build(os.path.join(OUT, "multi-image-page.pdf"), [
        [{"filt": b"/DCTDecode", "data": red}],
        [{"filt": b"/DCTDecode", "data": green},
         {"filt": b"/DCTDecode", "data": blue}],
    ])


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Generate and sanity-check the fixtures**

```bash
python3 tests/make-fixtures.py
for f in tests/fixtures/*.pdf; do echo "== $f"; pdfinfo "$f" | grep Pages; pdfimages -list "$f"; done
```

Expected: 4 PDFs written. `jpeg-book.pdf` shows 3 pages / 3 `image` rows with `enc` = `jpeg`; `png-book.pdf` 2 rows with `enc` = `image`; `masked-page.pdf` shows an `smask` row on page 2; `multi-image-page.pdf` shows two `image` rows on page 2. If `pdfimages -list` errors on a fixture, the PDF writer has a bug — fix the generator, don't hand-edit PDFs.

- [ ] **Step 3: Commit (fixtures included — they're the test contract)**

```bash
git add tests/make-fixtures.py tests/fixtures
git commit -m "test: fixture generator and committed fixture PDFs"
```

---

### Task 4: Page classifier

**Files:**
- Modify: `bin/pdf2cbz` (add `classify_pages` after `check_deps`)
- Create: `tests/classifier.test.sh`

`classify_pages` reads `pdfimages -list` text on stdin, takes the page count as `$1`, and prints one line per page: `<page> lossless -` or `<page> fallback <reason>`. Reasons: `mask`, `multi-image`, `enc:<enc>`, `cmyk`, `no-image`.

- [ ] **Step 1: Write failing unit tests `tests/classifier.test.sh`**

The tests source the script (execution guard makes this safe) and feed synthetic `-list` output — this is where CCITT/JBIG2/JPX/CMYK coverage lives, since those are impractical to fixture.

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `tests/run.sh`
Expected: the 10 classifier tests FAIL (`classify_pages: command not found` surfaces as empty output mismatches); cli tests still pass.

- [ ] **Step 3: Implement `classify_pages` in `bin/pdf2cbz`** (insert after `check_deps`)

```bash
# classify_pages: stdin = `pdfimages -list` output, $1 = page count.
# Prints one line per page: "<page> lossless -" or "<page> fallback <reason>".
# Lossless requires exactly one real raster image, encoded as jpeg (DCT) or
# image (flate), in a non-CMYK colorspace, with no masks/stencils on the page.
classify_pages() {
  awk -v pages="$1" '
    NR <= 2 { next }          # header + separator
    NF < 9 { next }
    {
      page = $1; type = $3; color = $6; comp = $7; enc = $9
      if (type == "image") {
        count[page]++
        if (count[page] > 1 && !(page in reason)) reason[page] = "multi-image"
        if (enc != "jpeg" && enc != "image" && !(page in reason)) reason[page] = "enc:" enc
        if ((color == "cmyk" || comp == 4) && !(page in reason)) reason[page] = "cmyk"
      } else if (!(page in reason)) {
        reason[page] = "mask"   # smask/stencil rows need compositing
      }
    }
    END {
      for (p = 1; p <= pages; p++) {
        if (p in reason)          print p, "fallback", reason[p]
        else if (count[p] == 1)   print p, "lossless", "-"
        else if (count[p] == "")  print p, "fallback", "no-image"
        else                      print p, "fallback", "multi-image"
      }
    }'
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `tests/run.sh`
Expected: `14 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add bin/pdf2cbz tests/classifier.test.sh
git commit -m "feat: page classifier over pdfimages -list output"
```

---

### Task 5: Lossless happy path end-to-end

**Files:**
- Modify: `bin/pdf2cbz` (add helpers + `convert_pdf`, replace `main`'s die)
- Create: `tests/e2e.test.sh`

- [ ] **Step 1: Write failing e2e tests `tests/e2e.test.sh`**

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `tests/run.sh`
Expected: e2e tests FAIL with `conversion not implemented yet`; 12 prior tests pass.

- [ ] **Step 3: Implement the pipeline in `bin/pdf2cbz`**

Add after `classify_pages` (fallback pages are *detected* here but rendering arrives in Task 6 — they fail loudly for now):

```bash
page_count() { pdfinfo "$1" 2>/dev/null | awk '/^Pages:/ {print $2}'; }

# find_page_image tmpdir page -> path of the single extracted image for page.
# Filenames look like img-PPP-NNN.ext (padding unknown); parse, don't assume.
find_page_image() {
  local dir="$1" page="$2" f base p
  for f in "$dir"/img-*; do
    [ -e "$f" ] || continue
    base="${f##*/}"
    p="${base#img-}"
    p="${p%%-*}"
    if [ "$((10#$p))" -eq "$page" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

# out_path pdf -> collision-free sibling .cbz path
out_path() {
  local base="${1%.[Pp][Dd][Ff]}"
  [ "$base" = "$1" ] && base="$1"
  local out="$base.cbz" n=1
  while [ -e "$out" ]; do
    out="$base ($n).cbz"
    n=$((n + 1))
  done
  printf '%s\n' "$out"
}

# convert_pdf pdf -> prints one summary line on success
convert_pdf() {
  local pdf="$1"
  [ -f "$pdf" ] || { printf '%s: no such file\n' "$pdf" >&2; return 1; }
  local pages
  pages=$(page_count "$pdf")
  case "$pages" in
    ''|*[!0-9]*) printf '%s: could not read page count (not a PDF?)\n' "$pdf" >&2; return 1 ;;
  esac

  local tmp stage
  tmp=$(mktemp -d "$TMP_ROOT/pdf.XXXXXX")
  stage="$tmp/stage"
  mkdir "$stage"

  local plan
  plan=$(pdfimages -list "$pdf" 2>/dev/null | classify_pages "$pages")
  pdfimages -p -all "$pdf" "$tmp/img" 2>/dev/null || true

  local width=${#pages}
  if [ "$width" -lt 3 ]; then width=3; fi
  # NOTE: never use `[ cond ] && cmd` for optional steps in this script —
  # under set -e a false condition aborts the whole run. Always if/then.

  local page status reason src ext dest
  local fallback_list="" fallback_count=0
  : > "$tmp/reasons.txt"
  while read -r page status reason; do
    src=""
    if [ "$status" = "lossless" ]; then
      src=$(find_page_image "$tmp" "$page") || reason="missing-extraction"
    fi
    if [ -z "$src" ]; then
      render_page "$pdf" "$page" "$tmp" || {
        printf '%s: page %s failed to render\n' "$pdf" "$page" >&2; return 1; }
      src=$(find "$tmp/render-$page" -type f | head -n 1)
      fallback_list="${fallback_list:+$fallback_list, }$page"
      fallback_count=$((fallback_count + 1))
      printf 'page %s: %s — rendered at %s DPI\n' "$page" "$reason" "$RENDER_DPI" >> "$tmp/reasons.txt"
    fi
    ext="${src##*.}"
    dest=$(printf '%s/%0*d' "$stage" "$width" "$page")
    case "$ext" in
      tif|tiff) sips -s format png "$src" --out "$dest.png" >/dev/null ;;
      jpeg)     cp "$src" "$dest.jpg" ;;
      *)        cp "$src" "$dest.$ext" ;;
    esac
  done <<EOF
$plan
EOF

  local out name
  out=$(out_path "$pdf")
  (cd "$stage" && zip -q -0 -X "$tmp/out.zip" -- *)
  mv "$tmp/out.zip" "$out"
  name=$(basename "$out")

  local ok=$((pages - fallback_count)) summary
  if [ "$fallback_count" -eq 0 ]; then
    summary="$name: $pages/$pages pages lossless"
  else
    summary="$name: $ok/$pages pages lossless; rendered at $RENDER_DPI DPI: $fallback_list"
    { printf '%s\n\n' "$summary"; cat "$tmp/reasons.txt"; } > "$out.log"
  fi
  printf '%s\n' "$summary"
}

# Rendering lands in Task 6; until then fallback pages are a hard error.
render_page() {
  printf 'pdf2cbz: page %s needs fallback rendering (not implemented yet)\n' "$2" >&2
  return 1
}
```

Replace the `die "conversion not implemented yet"` line in `main` with:

```bash
  TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/comicdown.XXXXXX")
  trap 'rm -rf "$TMP_ROOT"' EXIT

  local i=0 failures=0 summary summaries=""
  while [ "$i" -lt "$files_count" ]; do
    if summary=$(convert_pdf "${FILES[$i]}"); then
      printf '%s\n' "$summary"
      summaries="${summaries:+$summaries
}$summary"
    else
      failures=$((failures + 1))
      summaries="${summaries:+$summaries
}$(basename "${FILES[$i]}"): FAILED"
    fi
    i=$((i + 1))
  done
  if [ "$NOTIFY" = 1 ]; then notify "$summaries"; fi
  [ "$failures" -eq 0 ]
```

Note `convert_pdf` runs in a command substitution (subshell), so its `return 1` cannot kill the whole run under `set -e` — per-file failure isolation comes free.

- [ ] **Step 4: Run tests to verify pass**

Run: `tests/run.sh`
Expected: `20 passed, 0 failed`. If the byte-identity test fails, diff the actual extracted filenames (`ls` the ref dir) — the `img-PPP-NNN.ext` parse in `find_page_image` is the first suspect.

- [ ] **Step 5: Commit**

```bash
git add bin/pdf2cbz tests/e2e.test.sh
git commit -m "feat: lossless extraction pipeline with byte-identity e2e tests"
```

---

### Task 6: Fallback rendering

**Files:**
- Modify: `bin/pdf2cbz` (replace the stub `render_page`)
- Modify: `tests/e2e.test.sh` (append tests)

- [ ] **Step 1: Append failing tests to `tests/e2e.test.sh`**

```bash
begin "e2e masked-page: converts with fallback"
cp fixtures/masked-page.pdf "$WORK/"
OUT=$("$PDF2CBZ" "$WORK/masked-page.pdf" 2>&1)
assert_file "$WORK/masked-page.cbz"

begin "e2e masked-page: summary reports the rendered page"
assert_match "$OUT" "1/2 pages lossless"

begin "e2e masked-page: summary names page 2"
assert_match "$OUT" "rendered at 300 DPI: 2"

begin "e2e masked-page: sidecar log written with reason"
assert_file "$WORK/masked-page.cbz.log"
LOG=$(cat "$WORK/masked-page.cbz.log")
assert_match "$LOG" "page 2: mask"

begin "e2e masked-page: cbz still has 2 pages"
mkdir -p "$WORK/gotmask"
unzip -qo "$WORK/masked-page.cbz" -d "$WORK/gotmask"
N=$(find "$WORK/gotmask" -type f | wc -l | tr -d ' ')
assert_eq "$N" "2"

begin "e2e multi-image-page: layered page falls back, other stays lossless"
cp fixtures/multi-image-page.pdf "$WORK/"
OUT=$("$PDF2CBZ" "$WORK/multi-image-page.pdf" 2>&1)
assert_match "$OUT" "1/2 pages lossless"

begin "e2e multi-image-page: log says multi-image"
LOG=$(cat "$WORK/multi-image-page.cbz.log")
assert_match "$LOG" "page 2: multi-image"
```

- [ ] **Step 2: Run to verify failure**

Run: `tests/run.sh`
Expected: new tests FAIL with `needs fallback rendering (not implemented yet)`.

- [ ] **Step 3: Replace the `render_page` stub**

```bash
# render_page pdf page tmp: render one page to $tmp/render-$page/ as JPEG.
render_page() {
  local pdf="$1" page="$2" tmp="$3"
  mkdir -p "$tmp/render-$page"
  pdftoppm -jpeg -jpegopt "quality=$RENDER_QUALITY" -r "$RENDER_DPI" \
    -f "$page" -l "$page" "$pdf" "$tmp/render-$page/page" 2>/dev/null
  [ -n "$(find "$tmp/render-$page" -type f | head -n 1)" ]
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `tests/run.sh`
Expected: `28 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add bin/pdf2cbz tests/e2e.test.sh
git commit -m "feat: 300 DPI fallback rendering with sidecar log"
```

---

### Task 7: Collisions, batches, and bad input

**Files:**
- Modify: `tests/e2e.test.sh` (append tests)
- Modify: `bin/pdf2cbz` (only if a test exposes a bug — the logic exists)

- [ ] **Step 1: Append tests to `tests/e2e.test.sh`**

```bash
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
```

- [ ] **Step 2: Run tests**

Run: `tests/run.sh`
Expected: `36 passed, 0 failed` — this logic shipped in Task 5, so these should pass immediately. Any failure here is a real bug: fix `bin/pdf2cbz`, don't weaken the test.

- [ ] **Step 3: Commit**

```bash
git add tests/e2e.test.sh
git commit -m "test: collisions, batch isolation, junk input, --notify"
```

---

### Task 8: shellcheck clean + CI

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `bin/pdf2cbz`, `tests/*.sh` (whatever shellcheck flags)

- [ ] **Step 1: Run shellcheck locally**

```bash
brew list shellcheck >/dev/null 2>&1 || brew install shellcheck
shellcheck bin/pdf2cbz tests/run.sh tests/*.test.sh
```

Expected: warnings likely. Fix every finding (quote variables, etc.). Use targeted `# shellcheck disable=SCXXXX` comments *only* where the finding is a false positive (e.g. SC1090 for dynamic `source`), never blanket-disabled.

- [ ] **Step 2: Re-run tests after fixes**

Run: `tests/run.sh`
Expected: `36 passed, 0 failed`.

- [ ] **Step 3: Create `.github/workflows/ci.yml`**

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: brew install poppler shellcheck
      - name: Lint
        run: shellcheck bin/pdf2cbz tests/run.sh tests/*.test.sh
      - name: Test
        run: tests/run.sh
```

The macOS runner is load-bearing: tests use `sips` and target the system bash.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml bin/pdf2cbz tests
git commit -m "ci: shellcheck + test suite on macos-latest"
```

---

### Task 9: Quick Action workflow bundle

**Files:**
- Create: `quick-action/PDF to CBZ.workflow/Contents/Info.plist`
- Create: `quick-action/PDF to CBZ.workflow/Contents/document.wflow`

Automator bundles are just directories of plists — these are hand-authored, then verified once in Automator (which may normalize them on save; commit whatever Automator writes back).

- [ ] **Step 1: Create `quick-action/PDF to CBZ.workflow/Contents/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSBackgroundColorName</key>
			<string>background</string>
			<key>NSIconName</key>
			<string>NSActionTemplate</string>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>PDF to CBZ</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict/>
			<key>NSSendFileTypes</key>
			<array>
				<string>com.adobe.pdf</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Create `document.wflow` with the runner script**

The embedded shell script (input passed as arguments, `/bin/zsh`):

```zsh
for d in "$HOME/Documents/GitHub/comicdown/bin" /opt/homebrew/bin /usr/local/bin; do
  if [ -x "$d/pdf2cbz" ]; then
    exec "$d/pdf2cbz" --notify "$@"
  fi
done
osascript -e 'display notification "pdf2cbz not found — clone jeffalldridge/comicdown or put pdf2cbz on PATH" with title "comicdown"'
```

Full `quick-action/PDF to CBZ.workflow/Contents/document.wflow` (the script above lives in `COMMAND_STRING`; it contains no XML-special characters, so it embeds verbatim — keep it that way, or entity-escape `& < >` if it ever changes):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>528</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>for d in "$HOME/Documents/GitHub/comicdown/bin" /opt/homebrew/bin /usr/local/bin; do
  if [ -x "$d/pdf2cbz" ]; then
    exec "$d/pdf2cbz" --notify "$@"
  fi
done
osascript -e 'display notification "pdf2cbz not found — clone jeffalldridge/comicdown or put pdf2cbz on PATH" with title "comicdown"'</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/zsh</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>6ED0087B-3A22-4F33-8FB4-8C69C1420AC7</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
				</array>
				<key>OutputUUID</key>
				<string>27A6A6B8-9B7E-4A65-8FF5-2C0745BB1B0F</string>
				<key>UUID</key>
				<string>3F5A78E4-6C9B-4A38-9C61-1B0E7C7C1A55</string>
				<key>ignoresInput</key>
				<false/>
			</dict>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 3: Verify the bundle parses**

```bash
plutil -lint "quick-action/PDF to CBZ.workflow/Contents/Info.plist" "quick-action/PDF to CBZ.workflow/Contents/document.wflow"
```

Expected: both `OK`.

- [ ] **Step 4: MANUAL verification (needs the user or a GUI session)**

Open `quick-action/PDF to CBZ.workflow` in Automator: it should load as a Quick Action ("Workflow receives current PDF files in Finder") with the Run Shell Script action intact. If Automator normalizes the file on save, commit its version. Then double-click to install and right-click a real PDF → Quick Actions → PDF to CBZ; confirm the notification and the `.cbz`. If loading fails, rebuild the workflow inside Automator with the same shell script (input: as arguments) and export over the committed bundle — the hand-written plist is a convenience, not a hill to die on.

- [ ] **Step 5: Commit**

```bash
git add quick-action
git commit -m "feat: Finder Quick Action bundle"
```

---

### Task 10: README, CONTRIBUTING, issue templates

**Files:**
- Modify: `README.md` (replace stub)
- Create: `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/pdf-converts-wrong.yml`, `.github/ISSUE_TEMPLATE/bug-or-feature.yml`

- [ ] **Step 1: Write the full `README.md`**

````markdown
# comicdown

Losslessly convert comic-book PDFs to CBZ on macOS — from the terminal or a
Finder right-click.

Most comic PDFs are just a wrapper: each page is one full-page JPEG inside
PDF structure. Converters that "print" pages re-encode that JPEG and smear
detail. comicdown instead copies the embedded images out **byte-for-byte**
(via poppler's `pdfimages`) and zips them into a CBZ. Pages that can't come
out losslessly (soft masks, layered images, fax encodings, vector pages) are
rendered at 300 DPI instead — and clearly reported, so you always know
exactly what you got.

For personal archives and DRM-free comics you already own.

## Install

```sh
brew install poppler
git clone https://github.com/jeffalldridge/comicdown.git
```

Optionally add `comicdown/bin` to your `PATH`.

**Quick Action:** double-click `quick-action/PDF to CBZ.workflow` and choose
Install. Then right-click any PDF in Finder → Quick Actions → **PDF to CBZ**.

## Use

```sh
pdf2cbz "Some Comic.pdf" [more.pdf ...]
```

Writes `Some Comic.cbz` next to the source (existing files are never
overwritten — you get ` (1).cbz`). Typical output:

```
Some Comic.cbz: 24/24 pages lossless
Another.cbz: 22/24 pages lossless; rendered at 300 DPI: 3, 17
```

When any page needed rendering, a `.cbz.log` sidecar records which pages and
why (`mask`, `multi-image`, `enc:ccitt`, `cmyk`, `no-image`).

## Roadmap

- `--optimize`: lossless ImageOptim-style squeeze (jpegtran + oxipng)
- `--enhance`: 2x Real-ESRGAN upscale then perceptual recompress, for books
  with badly compressed source art (opt-in; not lossless)
- Homebrew tap

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports with a problem PDF
attached are the most valuable contribution there is.

MIT © Jeff Alldridge
````

- [ ] **Step 2: Write `CONTRIBUTING.md`**

```markdown
# Contributing to comicdown

Thanks for helping! The most valuable contribution is a **bug report with a
problem PDF attached** — real-world PDFs are weird in ways our fixtures
aren't.

## Reporting a bad conversion

1. Include the output of `pdfimages -list yourfile.pdf`.
2. If the file is shareable (DRM-free, no copyright concerns), attach it —
   or just one problem page: `pdfseparate -f N -l N yourfile.pdf page.pdf`.
3. Open a "PDF converts wrong" issue.

## Development

- `bin/pdf2cbz` targets the macOS **system bash 3.2**: no associative
  arrays, and don't expand possibly-empty arrays under `set -u`.
- Runtime dependencies are brew poppler + macOS built-ins, nothing else.
  Don't add dependencies without an issue discussion first.
- Lint: `shellcheck bin/pdf2cbz tests/run.sh tests/*.test.sh` must pass.
- Tests: `tests/run.sh`. Every behavior change needs a test.

## Turning a bad PDF into a fixture

Fixtures are generated by `tests/make-fixtures.py` (Python stdlib + `sips`)
and committed. Add a builder that reproduces the problem PDF's *structure*
(see the masked/multi-image builders), regenerate, and add a case to
`tests/e2e.test.sh`.
```

- [ ] **Step 3: Write `.github/ISSUE_TEMPLATE/pdf-converts-wrong.yml`**

```yaml
name: PDF converts wrong
description: A PDF produced a broken, incomplete, or unexpectedly non-lossless CBZ
labels: [bug, pdf-sample]
body:
  - type: textarea
    id: what-happened
    attributes:
      label: What happened
      description: What did pdf2cbz report, and what does the CBZ actually look like?
    validations:
      required: true
  - type: textarea
    id: pdfimages-list
    attributes:
      label: Output of `pdfimages -list yourfile.pdf`
      render: text
    validations:
      required: true
  - type: textarea
    id: sample
    attributes:
      label: Sample file
      description: >-
        If the PDF is shareable (DRM-free, no copyright concerns), attach it
        or a single problem page (`pdfseparate -f N -l N file.pdf page.pdf`).
        Samples become test fixtures.
```

- [ ] **Step 4: Write `.github/ISSUE_TEMPLATE/bug-or-feature.yml`**

```yaml
name: Bug report or feature request
description: Anything that isn't a specific PDF converting wrong
body:
  - type: textarea
    id: description
    attributes:
      label: What's up
      description: Describe the bug (with steps to reproduce) or the feature you'd like.
    validations:
      required: true
```

- [ ] **Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md .github/ISSUE_TEMPLATE
git commit -m "docs: README, CONTRIBUTING, issue templates"
```

---

### Task 11: Publish to GitHub + verify CI

- [ ] **Step 1: Final local check**

```bash
tests/run.sh && shellcheck bin/pdf2cbz tests/run.sh tests/*.test.sh
```

Expected: all pass, shellcheck silent.

- [ ] **Step 2: Create the public repo and push**

```bash
gh auth status
gh repo create comicdown --public --source . --push \
  --description "Losslessly convert comic-book PDFs to CBZ on macOS, with a Finder Quick Action"
```

Expected: repo at `https://github.com/jeffalldridge/comicdown`, `main` pushed. If `gh` is missing or unauthenticated, use the GitHub MCP tools (`create_repository`, then `git remote add origin … && git push -u origin main`).

- [ ] **Step 3: Verify CI is green**

```bash
gh run watch --repo jeffalldridge/comicdown --exit-status || gh run list --repo jeffalldridge/comicdown
```

Expected: the CI workflow completes successfully on macos-latest. If it fails, read the log (`gh run view --log-failed`), fix, push, re-verify.

- [ ] **Step 4: Tag v0.1.0**

```bash
git tag -a v0.1.0 -m "comicdown v0.1.0"
git push origin v0.1.0
gh release create v0.1.0 --title "comicdown 0.1.0" --notes "First release: lossless PDF→CBZ extraction with 300 DPI fallback, Finder Quick Action."
```

---

### Task 12: MANUAL — Shortcut export (user step)

The `.shortcut` file can't be generated programmatically; Jeff creates it once:

- [ ] **Step 1 (Jeff):** Shortcuts app → New Shortcut → add **Run Shell Script** action, shell `zsh`, input **as arguments**, paste the same runner script used in the Quick Action (Task 9 Step 2). In shortcut settings (ⓘ): enable **Use as Quick Action** → **Finder**; set input types to PDFs.
- [ ] **Step 2 (Jeff):** File → Export (or share) the shortcut as `shortcuts/PDF to CBZ.shortcut`, commit:

```bash
git add "shortcuts/PDF to CBZ.shortcut"
git commit -m "feat: exported Shortcut mirroring the Quick Action"
git push
```

README already notes the Shortcut is a regenerated artifact of the workflow script.
