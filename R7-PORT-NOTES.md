# Adding `r7` (Galaxy Note10 Lite, SM-N770F) to Unofficial UN1CA 9810

Status notes for porting One UI 8.0 / Android 16 to the **Galaxy Note10 Lite
(SM-N770F, codename `r7`, Exynos 9810)** on top of this UN1CA 9810 build system.

These notes record what was done, why, and exactly what remains before the ROM
boots. They are written for the device owner, who builds kernels and flashes the
real device.

---

## TL;DR

* **The r7 target is defined and the firmware-independent shared code is wired.**
  `source buildenv.sh r7` now produces a valid, correct build config.
* **A booting ROM is NOT producible from the cloud session**, for three reasons,
  none of which is a source bug and all of which need the device/firmware:
  1. **Donor firmware cannot be downloaded here** — the cloud environment's
     network policy blocks both Samsung FUS/FOTA and the public firmware
     mirrors (samfw, sammobile). Confirmed: every relevant host returns a proxy
     `403`/unreachable. So `unica make_rom` cannot run (it needs the S22 system
     base + N770F vendor donor extracted into `out/fw/`).
  2. **There is no r7 kernel.** The in-repo DS-ACK kernels only contain device
     trees for the six S9/S9+/Note9 models (`floyd/{G960F,G960N,G965F,G965N,
     N960F,N960N}-{kernel,dtb}`). The Note10 Lite has its own board/panel/touch
     device tree and needs its own `floyd/N770F-*` kernel+DTB.
  3. **The Exynos 9810 "device stack" is hard-gated to the three existing
     codenames** and each device needs per-device bring-up payloads
     (`device_port/device/<codename>/` overlays + an `nfc/<codename>/` payload)
     that must be curated from the device's own firmware.
* Everything that does **not** depend on firmware or on-device iteration is done
  and committed to branch `r7-port`.

---

## 1. What defines a target in this project

A "target" is a device. Three layers combine at build time:

1. **`target/<codename>/`** — the per-device definition. `buildenv.sh` discovers
   targets by listing this directory. A target contributes:
   * `config.sh` — device variables (`TARGET_CODENAME`, `TARGET_NAME`,
     `TARGET_PLATFORM`, `TARGET_ASSERT_MODEL`, `TARGET_FIRMWARE`, API levels,
     and `TARGET_*` feature overrides). Sourced by
     `scripts/internal/gen_config_file.sh`.
   * `camera/camera-feature.xml` — Samsung camera feature matrix.
   * `vintf/compatibility_matrix.device.xml` — framework<->vendor VINTF matrix.
   * `debloat.sh` — per-device package removals.
   * `sff.sh` — per-device SEC Floating Feature overrides (optional; only
     devices that need them, e.g. S Pen).
   * `installer/` — recovery installer pieces: `install-start.edify`,
     `install-end.edify`, `customize.sh`, `update-binary` (ARM64 recovery
     updater), optional `root/`.
   * optional extras the siblings use: `vendor/etc/permissions/*.xml`,
     `system/etc/power/system.prop`, `patches/`.

2. **`platform/<platform>/`** — the shared SoC layer. `config.sh` here provides
   defaults that `gen_config_file.sh` layers **under** the target config (target
   wins). For r7 this is `platform/exynos9810/` and it supplies partition sizes,
   filesystem defaults, the installer (kernel flash, repartition, ramdisk) and
   most feature defaults. The exynos9810 vendor base is **Note10 Lite VNDK33**.

3. **`unica/`** — the ROM itself (One UI 8 patches and mods), largely
   device-agnostic. The device-specific heavy lifting for Exynos 9810 lives in
   `unica/patches/exynos9810_device_stack/`.

`gen_config_file.sh` sourcing order (target overrides platform):
`version.sh` -> `target/<codename>/config.sh` -> `platform/<platform>/config.sh`
-> `target/<codename>/config.sh` again -> the SSI config (`essi.sh`).

The build pipeline: `buildenv.sh <codename>` -> `unica make_rom -z --fs-type
<ext4|erofs>` -> `make_rom.sh` (download/extract firmware, create work_dir,
apply platform+device+ROM patches and mods, build APKs/JARs, verify, build
target-files zip) -> `build_flashable_zip.sh` -> `verify_exynos9810_flashable.sh`.

The Exynos 9810 device steps in `make_rom.sh` are gated on
`TARGET_PLATFORM = exynos9810` (which r7 sets), **not** on codename — only a few
S9/Note9-specific post-build *verifies* (wallpapers, Brief, Dynamic Island,
privacy indicator, FaceunlockFix, release-defaults) are codename-gated and are
safely skipped for r7. So `make_rom.sh` itself needs no changes for r7.

---

## 2. The N770F (Galaxy Note10 Lite) specifics

| Attribute | Value | Note vs S9/Note9 family |
|---|---|---|
| Codename | `r7` | new |
| Model(s) | SM-N770F, SM-N770F/DS, SM-N770FD (and /DSM) | dual-SIM, single Exynos SKU |
| SoC | Exynos 9810 | **same** |
| GPU | Mali-G72 MP18 | **same** (`S9MaliG72` gfx driver reused) |
| Display | flat 6.7" **FHD+ 2400x1080** Super AMOLED, 60Hz | S9/Note9 are **QHD+ 1440x2960** |
| Density | 420 (411dp width) | S9=640, S9+/Note9=560 (WQHD native) |
| Resolution switcher | **off** (no WQHD) | on for S9/S9+/Note9 |
| Fingerprint | **optical under-display** | S9/Note9 are rear capacitive |
| Iris scanner | **none** | S9/S9+/Note8/Note9 have iris |
| Rear camera | **triple** 12 + 12(UW) + 12(tele) | S9 single, S9+/Note9 dual |
| Front camera | 32 MP | — |
| Speakers | **mono** (single bottom) | S9/Note9 stereo |
| S Pen | **yes**, Bluetooth LE + Air actions | like Note9 |
| Launch OS | Android 10 (API 29) | S9=26, Note9=27 |
| Battery | 4500 mAh, 25W | — |
| Storage | UFS 2.1, `/dev/block/sda`, `11120000.ufs` UFS node | **same SoC node** |

The display/density, fingerprint, iris, speaker and camera differences are the
ones that matter for correctness; they are all reflected in `target/r7/config.sh`
and in the device-stack identity/density cases.

### Fingerprint

The Note10 Lite uses an **optical** under-display sensor. The exact Samsung
`SemFingerprintManager$Characteristic.mConfig` string must be read from extracted
N770F stock `framework.jar` and set as `TARGET_FINGERPRINT_CONFIG_SENSOR` in
`target/r7/config.sh`. Until then r7 inherits the platform rear-sensor default
(stable, but shows the wrong sensor UI in Settings). Useful format hint: the S22
donor's own string is `google_touch_display_ultrasonic`, so display sensors use
`google_touch_display_<type>`; r7's optical variant is likely
`google_touch_display_optical` (confirm against stock).

---

## 3. What was done on branch `r7-port`

### 3a. `target/r7/` — the target definition (commit "add Galaxy Note10 Lite ... target")

* `config.sh` — full N770F definition. Key overrides vs the shared platform
  defaults: `TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL=false`,
  `TARGET_AUDIO_SUPPORT_DUAL_SPEAKER=false`,
  `TARGET_PRODUCT_SHIPPING_API_LEVEL=29`, N770F `TARGET_ASSERT_MODEL`.
* `camera/camera-feature.xml` — based on crownlte (multi-cam + QR detection).
  **TODO:** replace with the real N770F triple-camera matrix once stock is
  extracted (ultrawide tuning in particular).
* `vintf/compatibility_matrix.device.xml` — identical to the sibling targets.
* `debloat.sh`, `sff.sh` (S Pen), `installer/` (install-start passes `r7`).
* No heart-rate permission file (the Note10 Lite has no HR sensor).

`source buildenv.sh r7` was verified to generate a correct `out/config.sh`
(codename r7, SM-N770F models, API 29, board 33, density/speaker/resolution
overrides applied).

### 3b. Shared-code wiring (commit "wire r7/N770F into shared installer ...")

All changes are guarded so starlte/star2lte/crownlte behaviour is byte-for-byte
unchanged:

* `platform/exynos9810/installer/repartition/repartition.sh` — add the `r7`
  first-install layout (system 9500 / vendor 1300 / odm 700 / cache 600 MiB,
  same as the S9/S9+ group). Applied with `sgdisk --pretend` first, so a device
  whose reclaimable region is too small aborts before the GPT is touched.
* `platform/exynos9810/installer/repartition/preflight.sh` — detect `r7`
  explicitly and map an `*N770*` bootloader to r7.
* `platform/exynos9810/installer/customize.sh` — the DS-ACK kernel model list
  and default package are now codename-derived. For r7 the bundled prebuilt
  (S9-family only) is **not** used; r7 expects `floyd/N770F-{kernel,dtb}`
  supplied via `EXYNOS9810_KERNEL_ZIP`, and errors clearly if absent.
* `scripts/internal/verify_exynos9810_flashable.sh` — kernel model loop and
  baseline DTB are codename-derived; the fixed S9 kernel SHA pin does not apply
  to r7 unless `EXYNOS9810_EXPECTED_KERNEL_SHA256` is set.
* `unica/patches/exynos9810_device_stack/customize.sh` — add the r7
  **product/vendor identity** case (`SM-N770F`, `r7xx`; vendor identity stays
  genuine N770F because `EXYNOS9810_PRESERVE_N770_VENDOR_IDENTITY` defaults to
  true) and the r7 **display density** case (420/420, FHD+ native). These are
  **forward-prep**: the device-stack main gate still excludes r7 (see §4c), so
  they only take effect once that gate is opened.
* `scripts/internal/source-inputs.json` — register the 9 `target/r7` inputs.

---

## 4. What remains before r7 boots (the real bring-up)

### 4a. Donor firmware (blocked in the cloud session)

`make_rom` needs two firmwares extracted into `out/fw/` with a `.extracted`
marker (a bare zip is not enough):

* **System base (donor):** `SM-S901B` (Galaxy S22, EUX) — fixed by the project
  (`SOURCE_FIRMWARE`), extracted to `out/fw/SM-S901B_EUX`.
* **Target vendor/kernel/modem:** `SM-N770F` (the owner runs **N770FXXS9HXA3**,
  Android 13 / VNDK 33), extracted to `out/fw/SM-N770F_<CSC>`.

The project's own `unica download_fw` uses `samloader` against Samsung FUS. In
this cloud environment **every firmware host is blocked by the network policy**
(FUS `neofussvr`/`cloud-neofussvr`/`ospserver`, and the mirrors samfw/sammobile,
all return proxy `403`/unreachable). So firmware must be obtained elsewhere:

1. On a machine with firmware access, download the two firmwares (Frija / samfw
   / samloader) and extract with this repo's `unica extract_fw` (or place the
   extracted partitions + a `.extracted` marker under `out/fw/<MODEL>_<CSC>/`).
2. Set `TARGET_FIRMWARE` in `target/r7/config.sh` to your region's CSC and a
   valid IMEI/serial (currently `SM-N770F/OXM/000000000000000`). `samloader`
   always pulls the *latest* build for a model/CSC, so the exact version is not
   critical for a vendor donor as long as it is A13/VNDK33.

### 4b. An r7 kernel + device tree (owner's domain)

The installer flashes a DS-ACK kernel zip whose payload is keyed per model
(`floyd/<MODEL>-{kernel,dtb}`). The repo's prebuilts only carry the six
S9/S9+/Note9 models. You must build/obtain an **enforcing DS-ACK (or compatible)
r7 kernel** that produces `floyd/N770F-kernel` and `floyd/N770F-dtb`, in both
**erofs** and **ext4** DTB variants, then point the build at it:

```bash
export EXYNOS9810_KERNEL_ZIP=/path/to/DS-ACK-...-N770F-<fs>-dtb.zip
# optionally pin it:
export EXYNOS9810_EXPECTED_KERNEL_SHA256=<sha256 of that zip>
```

The r7-aware kernel validation (installer + `verify_exynos9810_flashable.sh`)
then validates and flashes it. If you would rather flash your own r7 kernel/boot
**separately** and have the UN1CA zip skip the kernel step, remove the kernel
steps from `target/r7/installer/install-end.edify` and relax the
`Installing Exynos9810 kernel zip` / `kernel.zip` checks in
`verify_exynos9810_flashable.sh` — but bundling the kernel (the default path
here) keeps the installer's enforcing-kernel and fs-match safety guarantees.

### 4c. Per-device bring-up payloads + open the device-stack gate

`unica/patches/exynos9810_device_stack/customize.sh` is the heart of the port
(vendor restore, HAL bridges, NFC, keymaster, radio, fstab, boot props, identity,
density). Its **main entry gate** currently returns early for any codename that
is not `starlte|star2lte|crownlte`:

```sh
EXYNOS9810_DEVICE="$TARGET_CODENAME"
case "$EXYNOS9810_DEVICE" in
    starlte|star2lte|crownlte) ;;
    *) LOGW "No legacy Exynos9810 donor device overlay mapping ..."; return 0 ;;
esac
```

To enable r7 you must **add `r7` to that case** AND provide the per-device
payloads it then consumes:

* `embedded/exynos9810_legacy_port/device_port/device/r7/` — the r7 `system/`,
  `vendor/`, `product/`, `odm/` overlays (the siblings have ~190 files each,
  LFS-tracked, curated from the device's firmware/overlays). Because the whole
  exynos9810 vendor base is already N770F, much of r7's overlay may be thin, but
  it must at least exist and provide the device bits the common layer does not.
* `embedded/.../nfc/r7/vendor/` — the r7 NFC payload (S3NRN82). Without it
  `_EXYNOS9810_APPLY_NFC_STACK` aborts the build.
* The r7 `identity` and `density` cases are already in place (§3b).
* Review the other per-codename spots (S Pen `spen/`, iris `irisscannerfix/` —
  note r7 has **no iris**, so iris enrollment should stay disabled — audio,
  display/external-display) and add r7 handling as needed. These are iterative
  and need on-device logs.

This step is genuine device bring-up: it needs the extracted N770F firmware and
repeated build+flash+logcat cycles on the real device. It is the main remaining
work and is expected to take several iterations.

---

## 5. Building r7 (once 4a/4b/4c are satisfied)

```bash
# EXT4 (recommended first — the owner's current r7 recovery may lack EROFS):
export EXYNOS9810_KERNEL_ZIP=/path/to/r7-ext4-kernel.zip
source buildenv.sh r7
unica make_rom -z --fs-type ext4
```

EROFS is the project default and can be switched to later (`--fs-type erofs`
with an EROFS r7 kernel zip) once a recovery with EROFS support is in place.
The flashable zip lands in `out/` as `UN1CA_<version>_<date>_r7...zip`.

Build host deps (Ubuntu 24.04): `clang`, `llvm` (for `llvm-readelf`), `secilc`,
`git-lfs`, a JDK, plus `git submodule update --init --recursive` and
`git lfs pull`. The dependency preflight checks these before building.

---

## 6. Flashing (what the owner needs to know)

* **Back up EFS and modem first**, plus any data you care about. The **first**
  install repartitions `/dev/block/sda` (the Exynos 9810 UFS) to the One UI 8
  layout, which **erases data and internal storage**. Updating a later r7 build
  keeps data.
* Copy the ROM zip to a **microSD or USB-OTG** drive (internal storage is wiped
  on first install).
* Flash through a recovery that supports **large (>5 GB) zips** and your chosen
  filesystem. For the first attempt prefer **ext4** (`--fs-type ext4`): the
  owner's existing r7 recovery is old and may lack EROFS. EROFS is the project
  default and can be adopted later with an EROFS-capable recovery + EROFS r7
  kernel.
* Install flow (same as the siblings): the installer checks battery and zip
  integrity, repartitions if needed (first install), writes system/vendor/odm,
  flashes the bundled r7 kernel, then formats cache/omr/preload. If it stops on
  a partition/recovery refresh error, reboot recovery, **Wipe > Format Data**
  (type `yes`), and flash again.
* The repartition layout for r7 reuses the S9/S9+ sizes and reads the existing
  GPT by partition **name** (`SYSTEM`, `VENDOR`, `ODM`, `CACHE`, `USERDATA`...),
  which Samsung Exynos devices share. It is applied with `sgdisk --pretend`
  first and backs up the GPT to `gpt-before-repartition.bin`, but it has **not**
  been validated on a real Note10 Lite — verify the first repartition carefully
  and keep the EFS/modem backup.

---

## 7. Quick status checklist

| Item | State |
|---|---|
| `target/r7/` target definition | **Done**, committed |
| `source buildenv.sh r7` config generation | **Done**, verified |
| repartition / preflight r7 case | **Done**, committed |
| kernel-model-aware installer + flashable verifier | **Done**, committed |
| device-stack r7 identity + density (forward-prep) | **Done**, committed |
| `source-inputs.json` registration | **Done**, committed |
| Donor firmware (S22 + N770F) in `out/fw/` | **Blocked** in cloud (network policy); owner-supplied |
| r7 kernel + DTB (`floyd/N770F-*`, erofs+ext4) | **Needed** (owner builds) |
| `device_port/device/r7/` overlays + `nfc/r7/` payload | **Needed** (device bring-up) |
| Open the device-stack gate for r7 | **Needed** (after payloads exist) |
| Fingerprint/camera matrices verified from N770F stock | **Needed** (after extraction) |
| Booting ROM | **Pending** the above |
