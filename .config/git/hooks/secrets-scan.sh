#!/bin/sh
# Strict secrets guard for git (works under git-bash on Windows).
# Usage: secrets-scan.sh <commit|push>
# Exits 1 and prints offending lines when a change contains secrets
# (passwords, logins, tokens, private keys, credentials files).
#
# Emergency bypass (audited in the log): GIT_ALLOW_SECRETS=1
# Logs every event to ~/.config/git/secret-scan.log.

MODE="$1"

FILENAME_PATTERN='\.env([A-Za-z0-9_ .-]*)?$|\.pem$|\.key$|\.p12$|\.pfx$|\.ppk$|\.jks$|\.keystore$|^id_rsa(\.pub)?$|^id_ed25519(\.pub)?$|^id_dsa(\.pub)?$|\.htpasswd$|\.netrc$|\.npmrc$|\.password$|\.secret$|\.credentials$|(^|/)credentials[^/]*\.(json|ya?ml|txt)$|(^|/)secrets[^/]*\.(json|ya?ml|txt)$|(^|/)tokens?[^/]*\.(json|ya?ml|txt)$|(^|/)[^/]*\.token(\.|$)'

# Credential key (optionally quoted, optionally with a prefix like EWS_) whose
# value is a real-looking literal: a quoted string >=4 chars, or a bare token
# >=6 chars that is NOT followed by ( [ { (i.e. not a code expression) and is
# followed by a delimiter. Placeholders are filtered out afterwards.
CONTENT_PATTERN='(^|[^A-Za-z0-9_])["'"'"']?[A-Za-z0-9_]*?(PASSWORD|PASSWD|USERNAME|LOGIN|CLIENT[_-]SECRET|SECRET[_-]KEY|PRIVATE[_-]KEY|API[_-]KEY|APITOKEN|API[_-]TOKEN|AUTH[_-]TOKEN|ACCESS[_-]KEY|OAUTH[_-]?TOKEN|REFRESH[_-]TOKEN|DBA[_-]PASSWORD|AUTH[_-]KEY|ACCESS[_-]TOKEN|ID[_-]TOKEN|SESSION[_-]?TOKEN)[[:space:]]*["'"'"']?[:=][[:space:]]*("([^"]{4,})"|'"'"'([^'"'"']{4,})'"'"'|[A-Za-z0-9+/=_-]{6,})([[:space:]]|,|}|]|;|$|"|'"'"')'

# Catch-all for long tokens (JWT, API keys, etc.) on any key ending in
# _TOKEN/_KEY/_SECRET (with a non-word char before them to avoid "Monkey").
LONG_TOKEN_PATTERN='(^|[^A-Za-z0-9_])(TOKEN|KEY|SECRET)[[:space:]]*["'"'"']?[:=][[:space:]]*["'"'"']?[A-Za-z0-9+/=._-]{20,}'

PRIVATE_KEY_PATTERN='BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY'

PLACEHOLDER_PATTERN='(your[-_]?(password|secret|email|token|key|login|pass|user|pwd|credentials?)|changeme|CHANGEME|example|EXAMPLE|placeholder|PLACEHOLDER|xxxx|XXXX|<[^>]*>|xxx|\.\.\.|yourpassword|youruser|your[-_]client[-_]?secret|your[-_]?pwd|foobar|put.*your.*here|sample[-_]?(secret|token|key)|test[-_]?(secret|password|token|key)|demo[-_]?(secret|password|token|key)|not.?a.?real|TBD|TODO|replace.*with|fill.*in|insert.*here|YOUR[-_])'

FAIL=0
LOG_DIR="${USERPROFILE:-$HOME}/.config/git"
LOG="$(printf '%s' "$LOG_DIR" | sed 's|\\|/|g')/secret-scan.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

warn() {
  echo "SECRET-SCAN: $*" >&2
  FAIL=1
}

note() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null || true
}

check_path() {
  echo "$1" | grep -qiE "$FILENAME_PATTERN" && warn "suspicious filename: $1"
}

# Reads content on stdin, scans lines for credential-looking assignments.
scan_content() {
  label="$1"
  tmp=$(mktemp 2>/dev/null) || tmp="/tmp/gitsecret-$$"
  grep -niE "$CONTENT_PATTERN" | grep -ivE "$PLACEHOLDER_PATTERN" > "$tmp"
  if [ -s "$tmp" ]; then
    warn "potential credential assignment in $label:"
    cat "$tmp" >&2
  fi
  grep -niE "$LONG_TOKEN_PATTERN" | grep -ivE "$PLACEHOLDER_PATTERN" > "$tmp"
  if [ -s "$tmp" ]; then
    warn "potential token value in $label:"
    cat "$tmp" >&2
  fi
  grep -nE "$PRIVATE_KEY_PATTERN" > "$tmp"
  if [ -s "$tmp" ]; then
    warn "private key material in $label:"
    cat "$tmp" >&2
  fi
  rm -f "$tmp"
}

scan_index_file() {
  f="$1"
  tmp=$(mktemp 2>/dev/null) || tmp="/tmp/gitindex-$$"
  git show ":$f" 2>/dev/null > "$tmp"
  scan_content "staged file '$f'" < "$tmp"
  rm -f "$tmp"
}

if [ "$MODE" = "commit" ]; then
  names=$(mktemp 2>/dev/null) || names="/tmp/gitnames-$$"
  git diff --cached --name-only -z > "$names"
  while IFS= read -r -d '' f; do
    [ -n "$f" ] || continue
    check_path "$f"
    case "$f" in
      */docs/*|docs/*|*/examples/*|examples/*) ;;  # doc/example dirs: skip content scan
      *) scan_index_file "$f" ;;
    esac
  done < "$names"
  rm -f "$names"

elif [ "$MODE" = "push" ]; then
  # stdin: <local-ref> <local-sha> <remote-ref> <remote-sha>
  refs=$(mktemp 2>/dev/null) || refs="/tmp/gitrefs-$$"
  cat > "$refs"
  while read -r local_ref local_sha remote_ref remote_sha; do
    [ -n "$local_sha" ] || continue
    case "$local_sha" in
      *[!0]*)
        if [ "$remote_sha" = "0000000000000000000000000000000000000000" ]; then
          range="$local_sha"
        else
          base=$(git merge-base "$remote_sha" "$local_sha" 2>/dev/null) || continue
          [ -n "$base" ] || continue
          range="$base..$local_sha"
        fi
        names=$(mktemp 2>/dev/null) || names="/tmp/gitnames-$$"
        git diff --name-only --no-renames "$range" 2>/dev/null > "$names"
        while IFS= read -r f; do
          check_path "$f"
        done < "$names"
        rm -f "$names"

        patch=$(mktemp 2>/dev/null) || patch="/tmp/gitpatch-$$"
        git log --format= --no-renames -p "$range" 2>/dev/null \
          | grep -E '^\+' | grep -v '^\+\+\+' > "$patch"
        scan_content "push range $range" < "$patch"
        rm -f "$patch"
        ;;
    esac
  done < "$refs"
  rm -f "$refs"

else
  echo "SECRET-SCAN: unknown mode '$MODE'" >&2
  exit 2
fi

if [ "$FAIL" -ne 0 ]; then
  if [ "${GIT_ALLOW_SECRETS:-0}" = "1" ]; then
    note "ALLOWED-BY-FORCE mode=$MODE secrets-founds=yes"
    echo "SECRET-SCAN: GIT_ALLOW_SECRETS=1 set - allowing despite secrets (logged)." >&2
    exit 0
  fi
  note "BLOCKED mode=$MODE"
  echo "" >&2
  echo "SECRET-SCAN: commit/push BLOCKED - potential secret detected." >&2
  echo "SECRET-SCAN: If this is a false positive, review the lines above." >&2
  echo "SECRET-SCAN: Emergency override: GIT_ALLOW_SECRETS=1 (logged to ~/.config/git/secret-scan.log)." >&2
  exit 1
fi
exit 0
