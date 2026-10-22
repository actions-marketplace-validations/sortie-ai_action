#!/usr/bin/env bash
# Validates the action inputs before anything is downloaded, so a bad input
# fails in seconds and never costs a download.

set -eu

readonly REPO="sortie-ai/sortie"
# Earlier releases reject --once and --once-result as unknown flags, and that
# exit status would read as a failed task.
readonly MIN_SORTIE_VERSION="v1.30.0"

fail() {
    # Inputs are echoed in messages; escaping stops one from starting a new
    # workflow command.
    _msg=$1
    _msg=${_msg//'%'/'%25'}
    _msg=${_msg//$'\r'/'%0D'}
    _msg=${_msg//$'\n'/'%0A'}
    printf '::error title=Sortie Action::%s\n' "$_msg"
    exit 1
}

is_windows() { [ "${RUNNER_OS-}" = "Windows" ]; }

trim() {
    _t=$1
    _t=${_t#"${_t%%[![:space:]]*}"}
    _t=${_t%"${_t##*[![:space:]]}"}
    printf '%s' "$_t"
}

# Output of a native Windows program can end in a carriage return, which would
# become part of the path.
posix_path() {
    if is_windows; then
        _p=$(cygpath -u "$1")
        printf '%s' "${_p%$'\r'}"
    else
        printf '%s' "$1"
    fi
}

native_path() {
    if is_windows; then
        _p=$(cygpath -w "$1")
        printf '%s' "${_p%$'\r'}"
    else
        printf '%s' "$1"
    fi
}

absolute_path() {
    _p=$(posix_path "$1")
    case $_p in
        /*) printf '%s' "$_p" ;;
        *)  printf '%s/%s' "$(posix_path "$GITHUB_WORKSPACE")" "$_p" ;;
    esac
}

# The releases/latest page redirects to the tagged release and, unlike the
# API, is not rate-limited per IP, which is what breaks on shared runners.
latest_tag_via_redirect() {
    _loc=$(curl -fsSI --connect-timeout 20 --max-time 60 -o /dev/null \
        -w '%{redirect_url}' "https://github.com/${REPO}/releases/latest") || return 1
    _loc=${_loc%$'\r'}
    case $_loc in
        */releases/tag/?*) printf '%s' "${_loc##*/}" ;;
        *)                 return 1 ;;
    esac
}

# The token goes through a curl config on stdin so it never appears in a
# command line.
latest_tag_via_api() {
    _json=$({
        printf 'header = "Accept: application/vnd.github+json"\n'
        if [ -n "${GH_TOKEN-}" ]; then
            printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN"
        fi
    } | curl -fsSL --connect-timeout 20 --max-time 60 -K - \
        "https://api.github.com/repos/${REPO}/releases/latest") || return 1
    _tag=$(printf '%s' "$_json" | jq -r '.tag_name // empty') || return 1
    printf '%s' "${_tag%$'\r'}"
}

meets_minimum() {
    IFS=. read -r -a _have <<<"${1#v}"
    IFS=. read -r -a _want <<<"${MIN_SORTIE_VERSION#v}"
    for _i in 0 1 2; do
        if (( 10#${_have[_i]} > 10#${_want[_i]} )); then return 0; fi
        if (( 10#${_have[_i]} < 10#${_want[_i]} )); then return 1; fi
    done
    return 0
}

require_tools() {
    _missing=""
    for _cmd in "$@"; do
        command -v "$_cmd" >/dev/null 2>&1 \
            || _missing="${_missing:+$_missing, }$_cmd"
    done
    if ! is_windows; then
        command -v tar >/dev/null 2>&1 || _missing="${_missing:+$_missing, }tar"
        command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
            || _missing="${_missing:+$_missing, }sha256sum or shasum"
    fi
    [ -z "$_missing" ] || fail "required tools not found on PATH: ${_missing}"
}

verify=$(trim "${SA_VERIFY_ATTESTATION-}")
verify=$(printf '%s' "$verify" | tr '[:upper:]' '[:lower:]')
case $verify in
    true|false) ;;
    *) fail "verify-attestation must be true or false" ;;
esac

tools="bash curl jq"
if is_windows; then tools="$tools cygpath"; fi
if [ "$verify" = "true" ]; then tools="$tools gh"; fi
# shellcheck disable=SC2086 # the list is split on purpose
require_tools $tools

[ -n "${SA_WORKFLOW-}" ] || fail "workflow is required"
workflow=$(absolute_path "$SA_WORKFLOW")
[ -f "$workflow" ] || fail "workflow is not a file: ${SA_WORKFLOW}"

if [ -n "${SA_TASK-}" ] && [ -n "${SA_TASK_FILE-}" ]; then
    fail "set only one of task and task-file"
fi
if [ -z "${SA_TASK-}" ] && [ -z "${SA_TASK_FILE-}" ]; then
    fail "one of task and task-file is required"
fi
task_file=""
if [ -n "${SA_TASK_FILE-}" ]; then
    task_file=$(absolute_path "$SA_TASK_FILE")
    { [ -f "$task_file" ] && [ -r "$task_file" ]; } \
        || fail "task-file is not a readable file: ${SA_TASK_FILE}"
fi

version=$(trim "${SA_VERSION-}")
if [ "$version" != "latest" ]; then
    version_re='^[vV]?[0-9]+\.[0-9]+\.[0-9]+$'
    [[ $version =~ $version_re ]] \
        || fail "version must be latest or a release such as v1.30.0: ${version}"
    version="v${version#[vV]}"
fi

case ${RUNNER_ARCH-} in
    X64)   arch=amd64 ;;
    ARM64) arch=arm64 ;;
    *)     fail "unsupported runner architecture: ${RUNNER_ARCH-}" ;;
esac
case ${RUNNER_OS-} in
    Linux)   os=linux ;;
    macOS)   os=darwin ;;
    Windows) os=windows ;;
    *)       fail "unsupported runner OS: ${RUNNER_OS-}" ;;
esac

if [ "$version" = "latest" ]; then
    tag=$(latest_tag_via_redirect) || tag=$(latest_tag_via_api) \
        || fail "could not resolve the latest Sortie release"
else
    tag=$version
fi

tag_re='^v[0-9]+\.[0-9]+\.[0-9]+$'
[[ $tag =~ $tag_re ]] || fail "not a release tag: ${tag}"
meets_minimum "$tag" \
    || fail "Sortie ${tag} is older than ${MIN_SORTIE_VERSION}, the first release with --once-result"

if [ "$os" = "windows" ]; then
    archive="sortie_${tag#v}_${os}_${arch}.zip"
else
    archive="sortie_${tag#v}_${os}_${arch}.tar.gz"
fi
root="$(posix_path "$RUNNER_TEMP")/sortie-action"
cache_dir="${root}/cache/${tag}-${os}-${arch}"
bin_dir="${root}/bin/${tag}-${os}-${arch}"

task_file_out=""
if [ -n "$task_file" ]; then task_file_out=$(native_path "$task_file"); fi

{
    printf 'tag=%s\n' "$tag"
    printf 'archive=%s\n' "$archive"
    printf 'cache-dir=%s\n' "$(native_path "$cache_dir")"
    printf 'bin-dir=%s\n' "$(native_path "$bin_dir")"
    printf 'workflow=%s\n' "$(native_path "$workflow")"
    printf 'task-file=%s\n' "$task_file_out"
    printf 'verify=%s\n' "$verify"
} >> "$(posix_path "$GITHUB_OUTPUT")"
