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
