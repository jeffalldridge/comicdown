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
cp comicdown/bin/pdf2cbz /opt/homebrew/bin/
```

(Use `/usr/local/bin` on Intel Macs. Installing the script to a bin
directory matters for the Quick Action: macOS privacy protection blocks
services from executing scripts that live in `Documents`, `Desktop`, or
`Downloads`, so running it straight from a checkout there fails with
"Operation not permitted".)

**Quick Action:** install with

```sh
cp -R "quick-action/PDF to CBZ.workflow" ~/Library/Services/
```

(You can also double-click the `.workflow` and choose Install, but note macOS
*moves* the file there rather than copying it — restore your checkout with
`git checkout -- quick-action` afterward.)

Then enable it once: right-click any PDF in Finder → Quick Actions →
**Customize…** and check **PDF to CBZ**. From then on it's available at
right-click → Quick Actions → **PDF to CBZ** (it also appears under the
Services submenu).

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
