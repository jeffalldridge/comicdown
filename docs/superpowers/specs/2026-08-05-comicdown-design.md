# comicdown — Design Spec

**Date:** 2026-08-05
**Status:** Approved by Jeff (with future-roadmap addition)

## Purpose

Convert comic-book PDFs into CBZ files by **losslessly extracting the embedded
page images** (byte-for-byte, no re-encoding) rather than re-rendering pages.
Usable from the terminal and from Finder as a right-click Quick Action on macOS.

Most comic PDFs are containers where each page is a single full-page JPEG
(DCTDecode stream). Poppler's `pdfimages -all` copies those streams out
unmodified; a CBZ is just those images zipped in page order. comicdown wraps
that recipe with verification, fallback, and reporting.

## Success criteria

- A clean one-JPEG-per-page PDF produces a CBZ whose images are **byte-identical**
  to the embedded streams.
- Imperfect PDFs still produce a working CBZ, with the non-lossless pages
  clearly reported.
- Right-clicking one or more PDFs in Finder → Quick Actions → "PDF to CBZ"
  produces `.cbz` files next to the sources with a completion notification.

## Non-goals (v1)

- ComicInfo.xml metadata generation
- CBR/RAR output or input
- Folder watching / batch daemon
- Any GUI beyond the Quick Action

## Architecture

```
comicdown/
├── bin/pdf2cbz                        # bash CLI, ~150 lines — all logic lives here
├── quick-action/PDF to CBZ.workflow/  # Automator bundle; double-click installs to ~/Library/Services
├── shortcuts/PDF to CBZ.shortcut      # exported Shortcut (build artifact of the workflow)
├── tests/
│   ├── fixtures/                      # tiny committed sample PDFs
│   └── run.sh                         # asserts lossless identity + fallback behavior
├── .github/
│   ├── workflows/ci.yml               # shellcheck + tests on macos-latest
│   └── ISSUE_TEMPLATE/                # "PDF converts wrong" + general
├── docs/superpowers/specs/
├── CONTRIBUTING.md
├── LICENSE                            # MIT
└── README.md
```

**Dependencies:** Homebrew poppler (`pdfimages`, `pdfinfo`, `pdftoppm`) plus
macOS built-ins (`zip`, `sips`, `osascript`). No Python, no Go, no Node.

## CLI behavior

`pdf2cbz file.pdf [more.pdf …]`

Per file:

1. **Probe** — `pdfinfo` for page count; `pdfimages -list` for the image map
   (which images on which pages, which are soft-masks/stencils).
2. **Extract** — `pdfimages -p -all` into a temp dir (`-p` embeds page numbers
   in filenames; `-all` writes native formats without transcoding).
3. **Verify per page** — a page passes as *lossless* when it has exactly one
   real image (masks excluded) in JPEG or PNG form. TIFF output gets a
   lossless `sips` conversion to PNG and still counts. Everything else —
   multi-image pages, image+smask compositing, CCITT/JBIG2 fax scans,
   JPEG2000, extraction-count mismatches — marks the page for fallback.
4. **Fallback** — failed pages are individually rendered with
   `pdftoppm -r 300 -jpeg -f N -l N`, so one messy page never forces
   re-encoding the whole book.
5. **Assemble** — rename to zero-padded true page order (`001.jpg`,
   `002.png`, …), `zip -X -0`-style store into `Name.cbz` beside the source
   PDF. Never overwrite an existing `.cbz` silently (append ` (1)` etc.).
6. **Report** — stdout summary per file: `42/42 pages lossless` or
   `40 lossless, pages 3, 17 rendered at 300 DPI`. Under the Quick Action the
   same text goes to a macOS notification; a sidecar `Name.cbz.log` is written
   only when fallback occurred.

**Error handling:** missing poppler → actionable message/notification with
`brew install poppler`; a failing file doesn't abort the rest of the batch;
temp dirs cleaned up on every exit path (trap).

## Quick Action & Shortcut

- **Automator workflow** ("Run Shell Script", input: PDF files in Finder)
  calls `bin/pdf2cbz`. The `.workflow` bundle is committed — versionable in
  git, installed by double-click.
- **Shortcut** mirrors the workflow for iCloud sync across Macs. It is a
  signed export that can't be diffed; README documents that it's regenerated
  from the workflow logic whenever that changes.
- The workflow locates `pdf2cbz` via a small search path (repo checkout,
  `/usr/local/bin`, `/opt/homebrew/bin`) so installs survive repo moves.

## Testing

`tests/run.sh` over committed fixtures:

- **jpeg-book.pdf** — clean JPEG pages → assert CBZ images are byte-identical
  to `pdfimages` raw output, count matches `pdfinfo`.
- **png-book.pdf** — Flate images → lossless PNG path.
- **masked-page.pdf** — image + smask on one page → that page falls back,
  others stay lossless, log written.
- **ccitt-scan.pdf** — fax-encoded page → fallback render triggers.

## Open-source readiness

The repo lives publicly on GitHub (`jeffalldridge/comicdown`, created with
`gh repo create --public` or the GitHub API) and follows small-tool best
practices from day one:

- **LICENSE** — MIT: permissive, the norm for CLI utilities, zero friction
  for contributors.
- **README** — the storefront: what it does and why lossless matters (with a
  before/after explanation), install steps (`brew install poppler`, clone,
  double-click the Quick Action), CLI usage, how fallback reporting works,
  and a contributing pointer.
- **CONTRIBUTING.md** — how to run tests, shell style expectations
  (shellcheck-clean), and how to add a fixture when reporting a PDF that
  converts badly. Bug reports that attach a problem PDF are the most valuable
  contribution, and the docs say so.
- **CI (GitHub Actions)** — a `macos-latest` workflow on every push/PR:
  `brew install poppler`, `shellcheck bin/pdf2cbz`, then `tests/run.sh`.
  Tests require macOS built-ins (`sips`), so the macOS runner is load-bearing,
  not decorative.
- **Issue templates** — two lightweight forms: "PDF converts wrong" (asks for
  the `pdfimages -list` output and ideally the file) and a general
  bug/feature template.
- **Releases** — tagged versions with GitHub Releases once v1 lands; a
  Homebrew tap is a roadmap item alongside the enhancement pass.

## Future roadmap (designed-for, not built)

An optional **enhancement pass** slotted after fallback (step 4) and before
zipping in step 5, operating on the renamed temp-dir images:

- **AI upscale** — inspired by Upscayl's "Digital Art" model. Upscayl is a GUI
  over Real-ESRGAN ncnn models; the same models run headless via
  `upscayl-ncnn` / `realesrgan-ncnn-vulkan`, which fits the CLI pipeline.
  Would be opt-in (`--upscale`), clearly marked as no longer lossless.
- **Lossless optimize** — ImageOptim-style squeeze: `jpegtran` (lossless JPEG
  Huffman optimization) and `oxipng` for PNGs. Truly lossless, so could
  eventually be a default-on `--optimize` flag.

The v1 seam: the pipeline keeps all page images in a temp dir with final
names before zipping, so enhancement stages are pure
image-in/image-out filters requiring no changes to extract/verify/assemble.
