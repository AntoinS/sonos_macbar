#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

files="$(
    {
        git ls-files 2>/dev/null || true
        git diff --cached --name-only --diff-filter=ACMRT 2>/dev/null || true
    } | sort -u
)"

if [[ -z "$files" ]]; then
    exit 0
fi

failed=0

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    [[ -f "$file" ]] || continue
    [[ "$file" == "scripts/check_secrets.sh" ]] && continue

    case "$file" in
        *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.xcuserstate|*.DS_Store)
            continue
            ;;
    esac

    while IFS= read -r match; do
        [[ -z "$match" ]] && continue

        if [[ "$match" =~ YOUR_LOCAL_ACCESS_TOKEN|REDACTED|SONOS_ACCESS_TOKEN=$|Authorization:\ Bearer\ \\\(token\\\) ]]; then
            continue
        fi

        printf 'Potential secret in %s: %s\n' "$file" "$match" >&2
        failed=1
    done < <(
        grep -nE \
            'SONOS_ACCESS_TOKEN=.+|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{12,}|client_secret[[:space:]]*[:=][[:space:]]*.+|refresh_token[[:space:]]*[:=][[:space:]]*.+|access_token[[:space:]]*[:=][[:space:]]*.+' \
            "$file" 2>/dev/null || true
    )
done <<< "$files"

if [[ "$failed" -ne 0 ]]; then
    printf 'Secret scan failed. Remove credentials before committing.\n' >&2
    exit 1
fi

printf 'Secret scan passed.\n'
