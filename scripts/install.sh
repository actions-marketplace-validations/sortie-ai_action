#!/usr/bin/env bash
# Installs one Sortie release on Linux or macOS. The archive is checked against
# a checksums.txt downloaded in this run, even when the archive itself comes
# from the cache, so a poisoned cache entry never reaches the run step.

set -eu

readonly REPO="sortie-ai/sortie"
readonly RETRIES=3

tag=${SA_TAG:?SA_TAG is not set}
archive=${SA_ARCHIVE:?SA_ARCHIVE is not set}
cache_dir=${SA_CACHE_DIR:?SA_CACHE_DIR is not set}
bin_dir=${SA_BIN_DIR:?SA_BIN_DIR is not set}
verify=${SA_VERIFY:?SA_VERIFY is not set}

path="${cache_dir}/${archive}"
base="https://github.com/${REPO}/releases/download/${tag}"
work=""

cleanup() { if [ -n "$work" ]; then rm -rf "$work"; fi; }
trap cleanup EXIT

fail() {
    _msg=$1
    _msg=${_msg//'%'/'%25'}
    _msg=${_msg//$'\r'/'%0D'}
    _msg=${_msg//$'\n'/'%0A'}
    printf '::error title=Sortie Action::%s\n' "$_msg"
    exit 1
}

# A corrupt or unverifiable archive is removed so the save step can never
# cache it.
reject_archive() {
    rm -f "$path"
    fail "$1"
}

download() {
    _url=$1 _out=$2
    _attempt=0
    until curl -fsSL --connect-timeout 20 --max-time 600 -o "$_out" "$_url"; do
        if [ "$_attempt" -ge "$RETRIES" ]; then
            rm -f "$_out"
            return 1
        fi
        _attempt=$((_attempt + 1))
        sleep $((_attempt * 2))
    done
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

lowercase() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

mkdir -p "$cache_dir"
if [ ! -f "$path" ]; then
    download "${base}/${archive}" "${path}.part" \
        || fail "could not download ${archive} for ${tag}"
    mv "${path}.part" "$path"
fi

work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/sortie-install.XXXXXX")
download "${base}/checksums.txt" "${work}/checksums.txt" \
    || fail "could not download checksums.txt for ${tag}"

want=$(awk -v f="$archive" '$2 == f {print $1; exit}' "${work}/checksums.txt")
[ -n "$want" ] || reject_archive "no checksum entry for ${archive}"
got=$(sha256_of "$path")
[ "$(lowercase "$want")" = "$(lowercase "$got")" ] \
    || reject_archive "checksum mismatch for ${archive}"

if [ "$verify" = "true" ]; then
    gh release verify-asset "$tag" "$path" --repo "$REPO" \
        || reject_archive "attestation check failed for ${archive}; set verify-attestation to false to skip it"
fi

mkdir "${work}/extract"
tar -xzf "$path" -C "${work}/extract" sortie \
    || reject_archive "${archive} does not contain a sortie binary"

mkdir -p "$bin_dir"
mv "${work}/extract/sortie" "${bin_dir}/sortie"
chmod 0755 "${bin_dir}/sortie"

"${bin_dir}/sortie" --version || fail "the installed sortie binary does not run"

printf '%s\n' "$bin_dir" >> "$GITHUB_PATH"
printf 'bin=%s\n' "${bin_dir}/sortie" >> "$GITHUB_OUTPUT"
