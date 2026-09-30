#!/usr/bin/env bash

set -euo pipefail

: "${EXPECTED_FPR:?EXPECTED_FPR is required}"
: "${RPM_RELATIVE:?RPM_RELATIVE is required}"

KEY_HOME='/signing/gnupg'
PRIVATE_KEY='/signing/private-key.asc'
PUBLIC_KEY='/signing/RPM-GPG-KEY-xo-lite'
RPM_FILE="/output/${RPM_RELATIVE}"

cleanup_private_material() {
    rm -f "${PRIVATE_KEY}"
    rm -rf "${KEY_HOME}"
}

trap cleanup_private_material EXIT

[ -s "${PRIVATE_KEY}" ] || {
    echo "Missing private signing key" >&2
    exit 1
}

[ -s "${RPM_FILE}" ] || {
    echo "Missing RPM: ${RPM_FILE}" >&2
    exit 1
}

mkdir -p "${KEY_HOME}"
chmod 0700 "${KEY_HOME}"

gpg1 \
    --homedir "${KEY_HOME}" \
    --batch \
    --import "${PRIVATE_KEY}"

KEY_FPR="$(
    gpg1 \
        --homedir "${KEY_HOME}" \
        --with-colons \
        --fingerprint \
        --list-secret-keys |
    awk -F: '$1 == "fpr" { print toupper($10); exit }'
)"

NORMALIZED_EXPECTED_FPR="$(
    printf '%s' "${EXPECTED_FPR}" |
        tr -d '[:space:]' |
        tr '[:lower:]' '[:upper:]'
)"

if [ "${KEY_FPR}" != "${NORMALIZED_EXPECTED_FPR}" ]; then
    echo "Signing-key fingerprint mismatch." >&2
    echo "Expected: ${NORMALIZED_EXPECTED_FPR}" >&2
    echo "Actual:   ${KEY_FPR}" >&2
    exit 1
fi

printf '%s\n' "${KEY_FPR}" \
    > /signing/key-fingerprint

printf '%s\n' 'github-secret' \
    > /signing/key-source

gpg1 \
    --homedir "${KEY_HOME}" \
    --batch \
    --armor \
    --export "${KEY_FPR}" \
    > "${PUBLIC_KEY}"

sed \
    -e "s|@@KEY_FINGERPRINT@@|${KEY_FPR}|g" \
    -e "s|@@KEY_HOME@@|${KEY_HOME}|g" \
    /ci/rpmmacros.tmpl \
    > /root/.rpmmacros

rpmsign \
    --addsign \
    "${RPM_FILE}"

RPM_DB='/tmp/xo-lite-rpmdb'

mkdir -p "${RPM_DB}"

rpm \
    --dbpath "${RPM_DB}" \
    --initdb

rpm \
    --dbpath "${RPM_DB}" \
    --import "${PUBLIC_KEY}"

rpmkeys \
    --dbpath "${RPM_DB}" \
    --checksig \
    --verbose \
    "${RPM_FILE}"

chmod 0644 \
    /signing/key-fingerprint \
    /signing/key-source \
    "${PUBLIC_KEY}"

chmod a+r "${RPM_FILE}"

printf 'Signed RPM: %s\n' "${RPM_FILE}"
printf 'Signing key: %s\n' "${KEY_FPR}"