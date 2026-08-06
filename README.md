# comicdown

Losslessly convert comic-book PDFs to CBZ on macOS — from the terminal or a
Finder right-click.

Most comic PDFs are just a wrapper: each page is one full-page JPEG inside
PDF structure. Converters that "print" pages re-encode that JPEG and smear
detail. comicdown instead copies the embedded images out **byte-for-byte**
(via poppler's `pdfimages`) and zips them into a CBZ. Pages that can't come
out losslessly (soft masks, layered images, fax encodings, vector pages) are
rendered at the page's own inherent pixel density (72–600 DPI, from the
source images' effective ppi; 300 for pure vector pages) — and clearly
reported, so you always know exactly what you got.

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
Another.cbz: 22/24 pages lossless; rendered: 3 (96 DPI), 17 (300 DPI)
```

A `.cbz.log` sidecar appears only when fallback occurred, recording the
per-page reasons and the DPI each was rendered at: `mask`, `multi-image`,
`cmyk`, `no-image`, `enc:<encoding>` (e.g. `enc:ccitt`, `enc:jbig2`), or the
rare `missing-extraction`.

## Roadmap

- `--optimize`: lossless ImageOptim-style squeeze (jpegtran + oxipng)
- `--enhance`: 2x Real-ESRGAN upscale then perceptual recompress, for books
  with badly compressed source art (opt-in; not lossless)
- Homebrew tap

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports with a problem PDF
attached are the most valuable contribution there is.

MIT © Jeff Alldridge
