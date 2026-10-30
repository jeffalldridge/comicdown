#!/bin/bash
# Cloud placeholders (iCloud Drive "not downloaded" files). CI has no
# iCloud, so `stat` and `osascript` are shimmed: the shimmed stat reports
# the SF_DATALESS flag until the shimmed osascript "downloads" the file.

mkdir -p "$WORK/cloudshim" "$WORK/cloud"
cat > "$WORK/cloudshim/stat" <<'SHIM'
#!/bin/bash
# Last arg is the file. Dataless until a ".downloaded" marker exists.
eval "f=\${$#}"
if [ -e "$f.downloaded" ]; then echo 40; else echo 40000040; fi
SHIM
cat > "$WORK/cloudshim/osascript" <<'SHIM'
#!/bin/bash
# Record the call; "download" (create the marker) unless told to fail.
eval "f=\${$#}"
printf '%s\n' "$f" >> "${f%/*}/osascript.calls"
if [ ! -e "${f%/*}/offline" ]; then : > "$f.downloaded"; fi
SHIM
chmod +x "$WORK/cloudshim/stat" "$WORK/cloudshim/osascript"

begin "cloud: a regular local file is not dataless"
if ( . "$PDF2CBZ"; is_dataless fixtures/jpeg-book.pdf ); then
  fail "local fixture reported as dataless"
else
  ok
fi

begin "cloud: local file converts without a download attempt"
cp fixtures/jpeg-book.pdf "$WORK/cloud/local.pdf"
: > "$WORK/cloud/local.pdf.downloaded"
OUT=$(PATH="$WORK/cloudshim:$PATH" "$PDF2CBZ" "$WORK/cloud/local.pdf" 2>&1)
assert_absent "$WORK/cloud/osascript.calls"

begin "cloud: placeholder is downloaded before conversion"
cp fixtures/jpeg-book.pdf "$WORK/cloud/remote.pdf"
OUT=$(PATH="$WORK/cloudshim:$PATH" "$PDF2CBZ" "$WORK/cloud/remote.pdf" 2>&1)
assert_match "$OUT" "3/3 pages lossless"
begin "cloud: download was requested for the placeholder"
assert_eq "$(cat "$WORK/cloud/osascript.calls" 2>/dev/null)" "$WORK/cloud/remote.pdf"
begin "cloud: cbz written next to the placeholder"
assert_file "$WORK/cloud/remote.cbz"

begin "cloud: failed download fails loudly, no false success"
mkdir -p "$WORK/cloud/off"
cp fixtures/jpeg-book.pdf "$WORK/cloud/off/away.pdf"
: > "$WORK/cloud/off/offline"
if OUT=$(PATH="$WORK/cloudshim:$PATH" "$PDF2CBZ" "$WORK/cloud/off/away.pdf" 2>&1); then
  fail "expected nonzero exit"
else
  ok
fi
begin "cloud: failed download names the cause"
assert_match "$OUT" "could not be downloaded"
begin "cloud: no cbz produced when the download fails"
assert_absent "$WORK/cloud/off/away.cbz"
