#!/usr/bin/env bash
set -Eeuo pipefail

# Install Windows 10 Pro dari VPS Ubuntu 22.04 — satu perintah, tanpa upload file.
#
# Jalankan di VPS (repo GitHub harus PUBLIC):
#   curl -fsSL https://raw.githubusercontent.com/asepmaries/bininstallw10/main/linkgithubsaya.sh | sudo bash
#
# Atau:
#   curl -fsSL https://raw.githubusercontent.com/asepmaries/bininstallw10/main/linkgithubsaya.sh -o linkgithubsaya.sh
#   sudo bash linkgithubsaya.sh

GITHUB_OWNER="${GITHUB_OWNER:-asepmaries}"
GITHUB_REPO="${GITHUB_REPO:-bininstallw10}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
CONFHOME="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/${GITHUB_BRANCH}"
REINSTALL_URL="${CONFHOME}/reinstall.sh"

IMAGE_NAME="${IMAGE_NAME:-Windows 10 Pro}"
LANGUAGE="${LANGUAGE:-en-us}"
ADMIN_USERNAME="${ADMIN_USERNAME:-administrator}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-zona10aman}"
RDP_PORT="${RDP_PORT:-7777}"
WORK_DIR="${WORK_DIR:-/tmp/win10-reinstall}"

# ISO utama: Cloudflare R2 | cadangan: archive.org
WINDOWS_ISO_URL_PRIMARY="${WINDOWS_ISO_URL_PRIMARY:-https://pub-453249fbfe80408a8bb5bf8cce54f391.r2.dev/windows_10_v_22h2_updated_oct_2025_x64.iso}"
WINDOWS_ISO_URL_FALLBACK="${WINDOWS_ISO_URL_FALLBACK:-https://ia801506.us.archive.org/10/items/en-us_windows_10_consumer_editions_version_22h2_updated_feb_2023_x64_dvd_c29e4bb3/en-us_windows_10_consumer_editions_version_22h2_updated_feb_2023_x64_dvd_c29e4bb3.iso}"
# Override manual (skip auto-pick): export WINDOWS_ISO_URL=...

log() {
  printf '\n==> %s\n' "$*" >&2
}

fail() {
  printf '\n[ERROR] %s\n' "$*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "Jalankan sebagai root: sudo bash linkgithubsaya.sh"

[ -r /etc/os-release ] || fail "Tidak bisa membaca /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] && [ "${VERSION_ID:-}" = "22.04" ] || \
  fail "VPS harus Ubuntu 22.04. OS terdeteksi: ${PRETTY_NAME:-unknown}"

patch_confhome() {
  local target=$1
  sed -i \
    -e "s|^confhome=.*|confhome=$CONFHOME|" \
    -e "s|^confhome_cn=.*|confhome_cn=$CONFHOME|" \
    "$target"
}

download_reinstall() {
  local url

  log "Download reinstall.sh dari GitHub Anda"
  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"

  for url in \
    "$REINSTALL_URL" \
    "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"; do
    if wget -O reinstall.sh "$url"; then
      ok_dl "$url"
      chmod +x reinstall.sh
      patch_confhome reinstall.sh
      return 0
    fi
    warn "Gagal: $url"
  done

  fail "Tidak bisa download reinstall.sh. Pastikan repo $GITHUB_OWNER/$GITHUB_REPO sudah PUBLIC."
}

ok_dl() {
  printf '    [OK] %s\n' "$*" >&2
}

warn() {
  printf '    [WARN] %s\n' "$*" >&2
}

iso_url_reachable() {
  local url=$1
  curl -fsSL --connect-timeout 15 --max-time 60 -r 0-1048575 "$url" -o /dev/null 2>/dev/null
}

pick_windows_iso_url() {
  if [ -n "${WINDOWS_ISO_URL:-}" ]; then
    printf '%s\n' "$WINDOWS_ISO_URL"
    return 0
  fi

  log "Cek ketersediaan ISO utama (Cloudflare R2)"
  if iso_url_reachable "$WINDOWS_ISO_URL_PRIMARY"; then
    ok_dl "$WINDOWS_ISO_URL_PRIMARY"
    printf '%s\n' "$WINDOWS_ISO_URL_PRIMARY"
    return 0
  fi

  warn "ISO R2 tidak terjangkau, coba cadangan archive.org"
  log "Cek ketersediaan ISO cadangan (archive.org)"
  if iso_url_reachable "$WINDOWS_ISO_URL_FALLBACK"; then
    ok_dl "$WINDOWS_ISO_URL_FALLBACK"
    printf '%s\n' "$WINDOWS_ISO_URL_FALLBACK"
    return 0
  fi

  fail "Semua URL ISO gagal (R2 dan archive.org). Cek koneksi VPS."
}

install_packages() {
  log "Installing required tools"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl wget coreutils util-linux grep gawk
}

show_info() {
  log "VPS info"
  printf 'OS       : %s\n' "${PRETTY_NAME:-Ubuntu 22.04}"
  printf 'RAM      : %s MB\n' "$(awk '/MemTotal/ {printf "%.0f", $2 / 1024}' /proc/meminfo)"
  printf 'Mirror   : %s\n' "$CONFHOME"
  printf 'RDP      : %s / %s / port %s\n' "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "$RDP_PORT"
  lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS
}

run_reinstall() {
  local iso_url
  iso_url=$(pick_windows_iso_url | awk 'NF && $0 ~ /^https?:\/\// { url=$0 } END { print url }')
  [ -n "$iso_url" ] || fail "Gagal menentukan URL ISO"

  log "Install Windows dengan ISO:"
  printf '  %s\n' "$iso_url"

  bash ./reinstall.sh windows \
    --image-name "$IMAGE_NAME" \
    --lang "$LANGUAGE" \
    --username "$ADMIN_USERNAME" \
    --password "$ADMIN_PASSWORD" \
    --rdp-port "$RDP_PORT" \
    --iso "$iso_url"
}

main() {
  install_packages
  show_info
  download_reinstall

  log "Menyiapkan Windows reinstall boot entry"
  run_reinstall

  log "Rebooting. SSH Ubuntu akan putus."
  printf 'Tunggu 10-20 menit, lalu RDP:\n'
  printf '  IP_VPS:%s\n' "$RDP_PORT"
  printf '  %s / %s\n' "$ADMIN_USERNAME" "$ADMIN_PASSWORD"
  sleep 3
  reboot
}

main "$@"