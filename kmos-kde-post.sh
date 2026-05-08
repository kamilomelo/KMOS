#!/bin/bash
# KMOS KDE Post Install
# Copyright (c) 2026 Kamilo Melo, KM-RoBoTa
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
MOUNT_POINT="/mnt"
KDE_PROFILE="${KMOS_KDE_PROFILE:-test}"
ASSET_WALLPAPER="$SCRIPT_DIR/assets/KM-R-wallpaper.png"

UI_RESET=""
UI_BOLD=""
UI_INFO=""
UI_SUCCESS=""
UI_WARN=""
UI_DANGER=""
SUCCESS_ICON="▸"
FINAL_SUCCESS_ICON="✔"

init_ui() {
  if [[ -t 2 && "${TERM:-dumb}" != "dumb" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_INFO=$'\033[37m'
    UI_SUCCESS=$'\033[32m'
    UI_WARN=$'\033[33m'
    UI_DANGER=$'\033[31m'
  fi

  if [[ "${TERM:-}" == "linux" || "${ASCII_UI:-${KMOS_ASCII_UI:-0}}" == "1" ]]; then
    SUCCESS_ICON=">"
    FINAL_SUCCESS_ICON="OK"
  fi
}

log() {
  printf '%s\n' "$*" >&2
}

success() {
  printf '%b%s%b %s\n' "$UI_SUCCESS" "$SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

final_success() {
  printf '%b%s%b %s\n' "$UI_SUCCESS" "$FINAL_SUCCESS_ICON" "$UI_RESET" "$*" >&2
}

die() {
  printf '%bERROR:%b %s\n' "${UI_DANGER}${UI_BOLD}" "$UI_RESET" "$*" >&2
  exit 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        shift
        [[ $# -gt 0 ]] || die "--target requires a mount point."
        MOUNT_POINT="$1"
        ;;
      --profile)
        shift
        [[ $# -gt 0 ]] || die "--profile requires a value."
        KDE_PROFILE="$1"
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run this script as root."
}

verify_target() {
  findmnt -rn --mountpoint "$MOUNT_POINT" >/dev/null 2>&1 || die "$MOUNT_POINT is not mounted."
  [[ -d "$MOUNT_POINT/etc" ]] || die "$MOUNT_POINT does not look like an installed system."
}

write_ksplash_none() {
  local target="$1"

  install -Dm0644 /dev/stdin "$target" <<'EOF'
[KSplash]
Engine=none
Theme=None
EOF
}

apply_splash_defaults() {
  local home_dir=""
  local username=""

  write_ksplash_none "$MOUNT_POINT/etc/xdg/ksplashrc"
  write_ksplash_none "$MOUNT_POINT/etc/skel/.config/ksplashrc"
  write_ksplash_none "$MOUNT_POINT/root/.config/ksplashrc"

  if [[ -d "$MOUNT_POINT/home" ]]; then
    while IFS= read -r -d '' home_dir; do
      username="$(basename "$home_dir")"
      write_ksplash_none "$home_dir/.config/ksplashrc"
      arch-chroot "$MOUNT_POINT" chown "$username:$username" "/home/$username/.config" "/home/$username/.config/ksplashrc" 2>/dev/null || true
    done < <(find "$MOUNT_POINT/home" -mindepth 1 -maxdepth 1 -type d -print0)
  fi

  success "Splash screen disabled by default."
}

apply_sddm_defaults() {
  local target_wallpaper="/opt/kmos/assets/KM-R-wallpaper.png"

  [[ -r "$ASSET_WALLPAPER" ]] || die "Missing wallpaper asset: $ASSET_WALLPAPER"

  install -Dm0644 "$ASSET_WALLPAPER" "$MOUNT_POINT$target_wallpaper"

  install -Dm0644 /dev/stdin "$MOUNT_POINT/etc/sddm.conf.d/kmos-theme.conf" <<'EOF'
[Theme]
Current=breeze
EOF

  install -Dm0644 /dev/stdin "$MOUNT_POINT/usr/share/sddm/themes/breeze/theme.conf.user" <<EOF
[General]
type=image
background=$target_wallpaper
color=#000000
EOF

  success "SDDM Breeze theme configured."
}

record_profile() {
  install -Dm0644 /dev/stdin "$MOUNT_POINT/usr/share/kmos/kde-profile" <<EOF
$KDE_PROFILE
EOF
}

apply_post_tweaks() {
  apply_splash_defaults
  apply_sddm_defaults
  record_profile
  success "KDE post-install hook executed."
}

main() {
  init_ui
  parse_args "$@"
  require_root
  verify_target
  apply_post_tweaks
  final_success "KDE post-install stage complete."
}

main "$@"
