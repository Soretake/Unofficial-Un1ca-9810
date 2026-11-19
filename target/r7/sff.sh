# Copyright (c) 2026 Eend15
# SPDX-License-Identifier: GPL-3.0-or-later

# SEC Floating Feature configuration for Galaxy Note10 Lite (Exynos)
#
# The Note10 Lite ships a garage (insert) S Pen with a Bluetooth LE controller
# and Air actions, like the Note9/Note10. These are the same values the working
# One UI 8 Exynos Note ports use and that the One UI 8 AirCommand parser
# understands. If Air-action buttons misbehave on r7, confirm SPEN_VERSION and
# the BLE spec against extracted N770F stock floating_feature.xml.
SEC_FLOATING_FEATURE_FRAMEWORK_CONFIG_SPEN_GARAGE_SPEC=type=insert, bundled=true
SEC_FLOATING_FEATURE_FRAMEWORK_CONFIG_SPEN_VERSION=40

# BLE S Pen remote: the One UI 8 donor ships a device spec that makes the BLE
# controller factory return null (AirCommandUiService NPE). The user-proven fix
# used on the Note9 replaces it with the builtin spec, which keeps the
# controller alive and enables the button/remote features.
SEC_FLOATING_FEATURE_COMMON_SUPPORT_BLE_SPEN=TRUE
SEC_FLOATING_FEATURE_COMMON_CONFIG_BLE_SPEN_SPEC=builtin,button

# Keep the Note10 Lite hardware identity visible to S Pen / regulatory settings.
# The S Pen FCC ID (SEC_FLOATING_FEATURE_SETTINGS_CONFIG_SPEN_FCC_ID) is
# cosmetic (Settings > regulatory) and is intentionally left unset until the
# correct N770F value is confirmed; a wrong value is worse than none.
SEC_FLOATING_FEATURE_SETTINGS_CONFIG_FCC_ID=SM-N770F
