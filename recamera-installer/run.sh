#!/usr/bin/with-contenv bashio
set -euo pipefail

DOMAIN=recamera
REPOSITORY=https://github.com/yyling0101-a11y/recamera-ha
ARCHIVE=https://github.com/yyling0101-a11y/recamera-ha/archive/refs/heads/main.tar.gz
COMPONENTS=/config/custom_components
TARGET=${COMPONENTS}/${DOMAIN}
STAGE=${COMPONENTS}/.recamera-install.$$
SOURCE=$(mktemp -d)
BACKUP=/config/.recamera-backups/recamera-$(date +%Y%m%d-%H%M%S)-$$

cleanup() {
  rm -rf "${SOURCE}" "${STAGE}"
}
trap cleanup EXIT

test -d /config || { bashio::log.error "Home Assistant /config is unavailable"; exit 1; }
mkdir -p "${COMPONENTS}" /config/.recamera-backups
curl --fail --location --silent --show-error --max-time 90 "${ARCHIVE}" \
  | tar -xz --strip-components=1 -C "${SOURCE}"
PAYLOAD=${SOURCE}/custom_components/${DOMAIN}
test -s "${PAYLOAD}/manifest.json" && test -s "${PAYLOAD}/__init__.py" \
  || { bashio::log.error "Integration files missing from ${REPOSITORY}"; exit 1; }
grep -Eq '"domain"[[:space:]]*:[[:space:]]*"recamera"' "${PAYLOAD}/manifest.json" \
  || { bashio::log.error "Downloaded integration has the wrong domain"; exit 1; }

if test -e "${TARGET}" && ! test -f "${TARGET}/.recamera-installer-managed"; then
  bashio::log.error "An existing reCamera integration is managed outside this installer. Remove it with its current manager before using this app."
  exit 1
fi

mkdir "${STAGE}"
cp -a "${PAYLOAD}/." "${STAGE}/"
printf '%s\n' 'Managed by the reCamera Installer app' > "${STAGE}/.recamera-installer-managed"
if test -e "${TARGET}"; then
  mv "${TARGET}" "${BACKUP}"
fi
if ! mv "${STAGE}" "${TARGET}"; then
  if test -e "${BACKUP}"; then mv "${BACKUP}" "${TARGET}"; fi
  bashio::log.error "Installation failed; previous version restored"
  exit 1
fi
bashio::log.info "reCamera integration installed. Restart Home Assistant, then add reCamera under Settings > Devices & Services."
