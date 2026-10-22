#!/usr/bin/env bash
# Runs scripts/install.sh against a real release, so it needs network access.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tag=v1.29.0
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
archive="sortie_${tag#v}_linux_${arch}.tar.gz"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/stub" "$work/fake"
printf '#!/bin/sh\necho "$*" >> "%s/gh.calls"\nexit 1\n' "$work" > "$work/stub/gh"
chmod +x "$work/stub/gh"

run_install() {
  env SA_TAG="$tag" SA_ARCHIVE="$archive" SA_CACHE_DIR="$work/cache" \
    SA_BIN_DIR="$work/bin" SA_VERIFY="$1" RUNNER_OS=Linux RUNNER_TEMP="$work" \
    GITHUB_PATH="$work/path" GITHUB_OUTPUT="$work/output" PATH="$work/stub:$PATH" \
    bash "$root/scripts/install.sh" > "$work/log" 2>&1
}

fail() {
  echo "FAIL: $*" >&2
  sed 's/^/  | /' "$work/log" >&2
  exit 1
}

# A well-formed archive with the wrong content installs fine unless the
# checksum is compared, which is what makes this case able to fail.
mkdir "$work/cache"
printf '#!/bin/sh\necho tampered\n' > "$work/fake/sortie"
chmod +x "$work/fake/sortie"
tar -czf "$work/cache/$archive" -C "$work/fake" sortie

if run_install false; then fail "P1: an archive that differs from checksums.txt was installed"; fi
[ ! -e "$work/cache/$archive" ] || fail "P1: the mismatched archive stayed in the cache"
[ ! -e "$work/bin/sortie" ] || fail "P1: a binary was left in bin-dir"

run_install false || fail "P2: install with verify false failed"
[ -x "$work/bin/sortie" ] || fail "P2: install with verify false left no binary"
[ ! -e "$work/gh.calls" ] || fail "P2: verify false still called gh"

rm -rf "${work:?}/bin"
if run_install true; then fail "P2: install with verify true ignored the failing gh"; fi
grep -q verify-asset "$work/gh.calls" || fail "P2: verify true never called gh release verify-asset"

echo "install tests passed"
