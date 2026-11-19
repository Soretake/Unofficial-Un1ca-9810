#!/usr/bin/env bash
# Copyright (c) 2026 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later
#
# extract-r7-payloads.sh
#
# First-pass helper that populates the r7 (Galaxy Note10 Lite, SM-N770F)
# device-stack payloads from EXTRACTED N770F stock firmware:
#
#   device_port/device/r7/{system,vendor,product,odm}   (device overlays)
#   unica/patches/.../nfc/r7/vendor                      (S3NRN82 NFC payload)
#
# It mirrors the crownlte overlay as a template: for every file the crownlte
# (Note9) overlay ships, it locates the N770F equivalent by the same partition-
# relative path and copies it into the r7 overlay. It also pulls N770F's own
# device-specific RRO overlays, Trustonic mcRegistry trustlets and the two NFC
# device files wholesale.
#
# This is a STARTING POINT, not a guaranteed-complete extraction. Device
# bring-up is iterative: after the first build+boot you will add/remove files
# from the r7 overlay based on logcat/dmesg. Items that cannot be copied blindly
# (the auto-generated RRO overlays, differently-named device apps) are reported
# so you can handle them by hand.
#
# Usage:
#   ./extract-r7-payloads.sh <extracted-N770F-fw-dir>
# e.g.
#   ./extract-r7-payloads.sh out/fw/SM-N770F_OXM
#
# The firmware dir must be the EXTRACTED tree (what `unica extract_fw` produces),
# containing system/, vendor/, odm/ (and usually system/system/, system/product/).

set -u

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
    echo "Usage: $0 <extracted-N770F-fw-dir>   (e.g. out/fw/SM-N770F_OXM)" >&2
    exit 1
fi
SRC="$(cd "$SRC" && pwd)"

ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT="$ROOT/unica/patches/exynos9810_device_stack/embedded/exynos9810_legacy_port/device_port/device"
NFC="$ROOT/unica/patches/exynos9810_device_stack/nfc"
TMPL="$PORT/crownlte"          # template overlay (closest analogue)
DST="$PORT/r7"                 # r7 overlay to create

for d in "$PORT" "$NFC" "$TMPL"; do
    [ -d "$d" ] || { echo "ERROR: expected repo path missing: $d" >&2; exit 1; }
done

copied=0; missing=0; manual=0

# Locate a partition-relative path inside the extracted firmware. Samsung stock
# uses system-as-root, so a /system/<x> file can live at system/<x>,
# system/system/<x> or just <x> under the system dir. Try the common layouts.
locate_in_fw() {
    # $1 = partition (system|vendor|product|odm), $2 = path relative to /<partition>
    local part="$1" rel="$2" c
    for c in \
        "$SRC/$part/$part/$rel" \
        "$SRC/$part/$rel" \
        "$SRC/system/$part/$rel" \
        "$SRC/system/system/$rel"; do
        [ -f "$c" ] && { echo "$c"; return 0; }
    done
    # last resort: search by the tail path
    c="$(find "$SRC" -path "*/$rel" -type f 2>/dev/null | head -n1)"
    [ -n "$c" ] && { echo "$c"; return 0; }
    return 1
}

copy_one() {
    # $1 = partition, $2 = partition-relative path (as in the crownlte overlay)
    local part="$1" rel="$2" found dst
    found="$(locate_in_fw "$part" "$rel")" || {
        printf '  MISS  %-7s %s\n' "$part" "$rel"; missing=$((missing+1)); return 1
    }
    dst="$DST/$part/$rel"
    mkdir -p "$(dirname "$dst")"
    cp -a "$found" "$dst"
    printf '  OK    %-7s %s\n' "$part" "$rel"; copied=$((copied+1))
}

echo "== r7 payload extraction =="
echo "source (N770F fw): $SRC"
echo "dest   (r7 overlay): $DST"
echo

# ---------------------------------------------------------------------------
# 1. Mirror the crownlte overlay template, partition by partition.
#    Device-named Note9 files (e.g. LedCoverAppCrown) are skipped with a note:
#    the Note10 Lite has no official LED View cover, and its own device apps
#    have different names.
# ---------------------------------------------------------------------------
for part in system vendor product odm; do
    [ -d "$TMPL/$part" ] || continue
    echo "-- $part --"
    while IFS= read -r f; do
        rel="${f#"$TMPL/$part/"}"
        case "$rel" in
            *LedCoverAppCrown*|*Crown*|*crown*)
                printf '  SKIP  %-7s %s  (Note9-specific; review r7 equivalent)\n' "$part" "$rel"
                manual=$((manual+1)); continue ;;
        esac
        copy_one "$part" "$rel"
    done < <(find "$TMPL/$part" -type f | sort)
    echo
done

# ---------------------------------------------------------------------------
# 2. Pull N770F's OWN device-specific blobs wholesale, where "take all of the
#    device's" is correct rather than "match the Note9 list":
#      - Trustonic mcRegistry (Keymaster/TA trustlets differ per device)
#      - vendor RRO overlays (auto-generated per device)
#      - product RRO overlays
# ---------------------------------------------------------------------------
echo "-- N770F device-specific blobs (wholesale) --"
if [ -d "$SRC/vendor/app/mcRegistry" ]; then
    mkdir -p "$DST/vendor/app/mcRegistry"
    cp -a "$SRC/vendor/app/mcRegistry/." "$DST/vendor/app/mcRegistry/"
    echo "  OK    vendor  app/mcRegistry/ ($(find "$SRC/vendor/app/mcRegistry" -type f | wc -l) trustlets)"
    copied=$((copied+1))
else
    echo "  MISS  vendor  app/mcRegistry/ (not found in N770F fw)"; missing=$((missing+1))
fi
for ov in \
    "vendor:vendor/overlay/framework-res__auto_generated_rro_vendor.apk" \
    "product:system/product/overlay/framework-res__auto_generated_rro_product.apk"; do
    part="${ov%%:*}"; p="${ov#*:}"
    if [ -f "$SRC/$p" ]; then
        dst="$DST/$part/${p##*/overlay/}"
        case "$part" in
            vendor)  dst="$DST/vendor/overlay/$(basename "$p")" ;;
            product) dst="$DST/product/overlay/$(basename "$p")" ;;
        esac
        mkdir -p "$(dirname "$dst")"; cp -a "$SRC/$p" "$dst"
        echo "  OK    $part  $(basename "$p")  (verify it is N770F's own RRO, not a stale copy)"
        copied=$((copied+1))
    else
        echo "  NOTE  $part  RRO overlay not at expected path; locate N770F's own framework-res RRO and place it under $part/overlay/"
        manual=$((manual+1))
    fi
done
echo

# ---------------------------------------------------------------------------
# 3. NFC payload: the Note10 Lite uses the same Samsung S3NRN82 NFC controller,
#    so only the two device files (RF calibration + device firmware) are needed;
#    the HAL/libs live in nfc/common and are shared.
# ---------------------------------------------------------------------------
echo "-- NFC (S3NRN82) device files --"
nfc_ok=0
for nf in \
    "etc/nfc/sec_s3nrn82_rfreg.bin" \
    "firmware/nfc/sec_s3nrn82_firmware.bin"; do
    found="$(locate_in_fw vendor "$nf")" || { echo "  MISS  nfc/r7/vendor/$nf"; missing=$((missing+1)); continue; }
    dst="$NFC/r7/vendor/$nf"; mkdir -p "$(dirname "$dst")"; cp -a "$found" "$dst"
    echo "  OK    nfc/r7/vendor/$nf"; copied=$((copied+1)); nfc_ok=$((nfc_ok+1))
done
[ "$nfc_ok" -eq 2 ] || echo "  WARN  NFC will not initialise without both files; find them in N770F vendor."
echo

# ---------------------------------------------------------------------------
# Summary + manual follow-ups
# ---------------------------------------------------------------------------
echo "== summary: $copied copied, $missing missing, $manual need manual review =="
cat <<'NOTE'

Manual follow-ups (cannot be done blindly):
  * RRO overlays (vendor/product framework-res): confirm the copied APKs are
    N770F's OWN auto-generated RROs. If the Note10 Lite needs resource overrides
    the Note9 ones don't cover (navbar, cutout, density), regenerate them.
  * Face unlock libs (face.default.so, libFaceService.so, libsecfr_engine.so):
    verify the N770F variants loaded and that face.default.so matches the Noble
    face HAL ABI the ROM's audit expects.
  * TARGET_FINGERPRINT_CONFIG_SENSOR: the Note10 Lite has an OPTICAL in-display
    sensor. Read the real string from N770F stock framework.jar:
      - decompile system/system/framework/framework.jar
      - find com.samsung.android.bio.fingerprint
        .SemFingerprintManager$Characteristic.mConfig
      - set it in target/r7/config.sh (format: google_touch_display_<type>,...)
  * Camera: replace target/r7/camera/camera-feature.xml with the real N770F
    triple-rear (12+12+12) matrix from N770F stock
    system/system/cameradata/camera-feature.xml (keep SUPPORT_QR_CODE_DETECTION).
  * After the first build+boot, add any device libs/firmware the logs show
    missing to device_port/device/r7/, and remove anything that does not apply.
NOTE

echo "Done. Review the r7 overlay, then rebuild: source buildenv.sh r7 && unica make_rom -z --fs-type ext4"
