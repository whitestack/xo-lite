#!/usr/bin/env bash

set -euo pipefail

: "${EXPECTED_FPR:?EXPECTED_FPR is required}"
: "${RPM_RELATIVE:?RPM_RELATIVE is required}"

KEY_HOME='/signing/gnupg'
PRIVATE_KEY='/signing/private-key.asc'
FINGERPRINT_FILE='/signing/key-fingerprint'
PUBLIC_KEY='/signing/RPM-GPG-KEY-xo-lite'
KEY_SOURCE_FILE='/signing/key-source'
RPM_FILE="/output/${RPM_RELATIVE}"

cleanup_private_material() {
    rm -f "${PRIVATE_KEY}"
    rm -rf "${KEY_HOME}"
}

trap cleanup_private_material EXIT

test -s "${PRIVATE_KEY}"
test -s "${RPM_FILE}"

install -d -m 0700 "${KEY_HOME}"

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

EXPECTED_FPR_NORMALIZED="$(
    printf '%s' "${EXPECTED_FPR}" |
    tr -d '[:space:]' |
    tr '[:lower:]' '[:upper:]'
)"

test -n "${KEY_FPR}"

if [ "${KEY_FPR}" != "${EXPECTED_FPR_NORMALIZED}" ]; then
    echo "Signing key fingerprint does not match RPM_GPG_EXPECTED_FINGERPRINT." >&2
    echo "Expected: ${EXPECTED_FPR_NORMALIZED}" >&2
    echo "Actual:   ${KEY_FPR}" >&2
    exit 1
fi

gpg1 \
    --homedir "${KEY_HOME}" \
    --batch \
    --armor \
    --export "${KEY_FPR}" \
    > "${PUBLIC_KEY}"

test -s "${PUBLIC_KEY}"
grep -q \
    '^-----BEGIN PGP PUBLIC KEY BLOCK-----$' \
    "${PUBLIC_KEY}"

printf '%s\n' "${KEY_FPR}" > "${FINGERPRINT_FILE}"
printf '%s\n' 'github-secret' > "${KEY_SOURCE_FILE}"

cat > /root/.rpmmacros <<RPM_MACROS
%_signature gpg
%_gpg_name ${KEY_FPR}
%_gpg_path ${KEY_HOME}
%_gpgbin /usr/bin/gpg1
%__gpg /usr/bin/gpg1
%_gpg_digest_algo sha256
RPM_MACROS

rpmsign --addsign "${RPM_FILE}"

RPM_DB='/tmp/xo-lite-rpmdb'
install -d -m 0755 "${RPM_DB}"

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
    "${FINGERPRINT_FILE}" \
    "${PUBLIC_KEY}" \
    "${KEY_SOURCE_FILE}"

chmod a+r "${RPM_FILE}"

printf 'Signed RPM: %s\n' "${RPM_FILE}"
printf 'Signing key: %s\n' "${KEY_FPR}"