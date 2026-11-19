# Copyright (c) 2026 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# Device configuration file for Galaxy Note10 Lite (Exynos) (r7)
#
# SM-N770F, codename "r7", Exynos 9810 (same SoC as starlte/star2lte/crownlte),
# Mali-G72 MP18. This target reuses the shared platform/exynos9810 layer; only
# the values that genuinely differ from the S9/S9+/Note9 family are overridden
# here. See R7-PORT-NOTES.md for the full rationale behind every value and for
# the items that still need to be confirmed from extracted N770F stock.
TARGET_NAME="Galaxy Note10 Lite (Exynos)"
TARGET_CODENAME="r7"
# The artifact is topology-neutral. Samsung EFS factory.prop selects single or
# dual SIM during early boot; accept every Exynos r7 model at install.
# SM-N770F is the only Exynos variant (global/DS and the /DSM Russia-India SKU);
# there is no Snapdragon or N-suffix Exynos r7.
TARGET_SIM_VARIANT="auto"
case "$TARGET_SIM_VARIANT" in
    auto)
        TARGET_ASSERT_MODEL=("SM-N770F" "SM-N770F/DS" "SM-N770FD" "SM-N770X")
        ;;
    *)
        printf 'Unsupported TARGET_SIM_VARIANT for r7: %s\n' "$TARGET_SIM_VARIANT" >&2
        return 1
        ;;
esac
TARGET_PLATFORM="exynos9810"
# Vendor/kernel/modem donor. The owner's device is on N770FXXS9HXA3 (A13 /
# One UI 5, VNDK 33). samloader always pulls the *latest* firmware for a
# model/CSC, so set TARGET_FIRMWARE to your region's CSC plus a valid IMEI or
# serial. OXM is the common multi-EU CSC; replace with yours (DBT, BTU, XEO...).
# The exact build is not critical for a vendor donor as long as it is A13/VNDK33.
TARGET_FIRMWARE="SM-N770F/OXM/000000000000000"
# Temporarily disabled like the sibling targets: Samsung's FUS backend currently
# refuses these legacy firmwares regardless of IMEI/TAC validity. Re-enable once
# obtainable, or drop the extracted firmware into out/fw/ manually.
TARGET_EXTRA_FIRMWARES=()
# Matches the sibling targets and the shared platform vendor base (Note10 Lite
# VNDK33). ro.build.version.sdk of the One UI 8 system image is what ships; the
# platform treats 31 as the Exynos9810 compatibility SDK. If an A13 N770F donor
# makes a prop check complain, export EXYNOS9810_TARGET_PLATFORM_SDK_VERSION=33.
TARGET_PLATFORM_SDK_VERSION="${EXYNOS9810_TARGET_PLATFORM_SDK_VERSION:-31}"
# ro.product.first_api_level: the Note10 Lite launched on Android 10 (API 29),
# unlike the S9 (26) and Note9 (27) which launched on Oreo.
TARGET_PRODUCT_SHIPPING_API_LEVEL=29
TARGET_BOARD_API_LEVEL=33
# odm/cache partition sizes are inherited from platform/exynos9810/config.sh
# (odm=700MiB, cache=600MiB). The first-install repartition entry for r7 lives
# in platform/exynos9810/installer/repartition/repartition.sh and uses the same
# 9500/1300/700/600 layout as starlte/star2lte.

# SEC Product Feature
TARGET_DVFSAPP_CONFIG_SSRM_POLICY_FILENAME="ssrm_default"
# Exynos9810 has physical SIM support only; keep donor eSIM capability off.
TARGET_COMMON_SUPPORT_EMBEDDED_SIM=false
# The Note10 Lite panel is a flat 6.7" Full HD+ (2400x1080) Super AMOLED. It is
# NOT a WQHD+ panel, so the resolution switcher must stay OFF (unlike the real
# 1440x2960 QHD+ panels on the S9/S9+/Note9, which set this true). The shared
# platform default is true for those devices, so r7 explicitly overrides it.
TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL=false
# Single bottom-firing speaker; the Note10 Lite has no stereo pair. The shared
# platform default is true (S9/Note9 are stereo), so override to false here.
TARGET_AUDIO_SUPPORT_DUAL_SPEAKER=false
TARGET_CAMERA_SUPPORT_SDK_SERVICE=false

# Fingerprint: the Note10 Lite uses an OPTICAL under-display sensor, not the
# rear/side capacitive sensor of the S9/Note9. The exact Samsung mConfig string
# (SemFingerprintManager$Characteristic.mConfig in framework.jar) must be read
# from extracted N770F stock and set here; until then r7 inherits the platform
# rear-sensor default, which keeps enrollment stable but shows the wrong sensor
# animation in Settings. See R7-PORT-NOTES.md "Fingerprint".
# TARGET_FINGERPRINT_CONFIG_SENSOR="<extract from N770F stock framework.jar>"
