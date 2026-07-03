#!/usr/bin/env bash
set -Eeuo pipefail

# Install Windows 10 Pro dari VPS Ubuntu 22.04 — satu perintah, tanpa upload file.
#
# Jalankan di VPS (repo GitHub harus PUBLIC):
#   curl -fsSL https://raw.githubusercontent.com/asepmaries/bininstalwin10/main/linkgithubsaya.sh | sudo bash
#
# Atau:
#   curl -fsSL https://raw.githubusercontent.com/asepmaries/bininstalwin10/main/linkgithubsaya.sh -o linkgithubsaya.sh
#   sudo bash linkgithubsaya.sh

GITHUB_OWNER="${GITHUB_OWNER:-asepmaries}"
GITHUB_REPO="${GITHUB_REPO:-bininstalwin10}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
CONFHOME="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/${GITHUB_BRANCH}"
REINSTALL_URL="${CONFHOME}/reinstall.sh"

IMAGE_NAME="${IMAGE_NAME:-Windows 10 Pro}"
LANGUAGE="${LANGUAGE:-en-us}"
ADMIN_USERNAME="${ADMIN_USERNAME:-administrator}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-zona10aman}"
RDP_PORT="${RDP_PORT:-7777}"
WORK_DIR="${WORK_DIR:-/tmp/win10-reinstall}"

# Fallback ISO (uji coba teman — dipakai jika auto-find Microsoft gagal)
FALLBACK_ISO_URL="${FALLBACK_ISO_URL:-https://ts.buzzheavier.com/d/fuxscqu93mnn?v=IQlhLcTOTOjFJX6xQW2Ic3VlPNqif5bhzB0dKJl1BOkw1YmylCQsCnHz0fHDmBOvctVGHeKf9hYJvd7L0iWQSX_TZCNJn1xQy8F6Nhi18fAsIlQTWrhmg3oso_AoOV39fnrdi37667tr1HD9UTl45fy5SzQj_pXTYOmzqB0KS-3-b3fUDQcDMu4juzFdB0CUz65D_0WwpnWfFo9e6O9uJhGCAkAZovmZFA3sGCuGCgc4Y-XK_LeUuO0yC6NrBKBFdVvVi51xNnRslxTxpaB9zkUvqAgb-TkrN3kbmTDoPlepsHASDSQnxKvsysmLyxf-U-xGfjskd-2l6ARnjMEEng_09eaK7mWymG-imXJOkyc8Im8eST4P}"

log() {
  printf '\n==> %s\n' "$*"
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
  printf '    [OK] %s\n' "$*"
}

warn() {
  printf '    [WARN] %s\n' "$*" >&2
}

probe_microsoft_win10_catalog() {
  # Cek apakah katalog Microsoft (massgrave) terjangkau dari VPS ini.
  curl -fsSL --connect-timeout 15 --max-time 45 "https://massgrave.dev/" >/dev/null 2>&1
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
  local use_iso=$1
  local -a args

  args=(
    windows
    --image-name "$IMAGE_NAME"
    --lang "$LANGUAGE"
    --username "$ADMIN_USERNAME"
    --password "$ADMIN_PASSWORD"
    --rdp-port "$RDP_PORT"
  )

  if [ -n "$use_iso" ]; then
    args+=(--iso "$use_iso")
    log "Install dengan ISO: Buzzheavier (fallback)"
    bash ./reinstall.sh "${args[@]}"
    return $?
  fi

  log "Install dengan ISO: auto-find Microsoft (Windows 10 Pro)"
  log "Jika gagal, otomatis isi direct link Buzzheavier"
  printf '%s\n' "$FALLBACK_ISO_URL" | bash ./reinstall.sh "${args[@]}"
}

main() {
  install_packages
  show_info
  download_reinstall

  log "Menyiapkan Windows reinstall boot entry"

  if probe_microsoft_win10_catalog; then
    if run_reinstall ""; then
      :
    else
      warn "Auto-find Microsoft gagal, retry dengan ISO Buzzheavier"
      run_reinstall "$FALLBACK_ISO_URL"
    fi
  else
    warn "Katalog Microsoft tidak terjangkau dari VPS ini"
    run_reinstall "$FALLBACK_ISO_URL"
  fi

  log "Rebooting. SSH Ubuntu akan putus."
  printf 'Tunggu 10-20 menit, lalu RDP:\n'
  printf '  IP_VPS:%s\n' "$RDP_PORT"
  printf '  %s / %s\n' "$ADMIN_USERNAME" "$ADMIN_PASSWORD"
  sleep 3
  reboot
}

main "$@"