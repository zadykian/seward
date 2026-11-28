#!/bin/sh
# Tries words-check.sh with stand-in words, on a throwaway repository, for the text of an issue and
# of a pull request. It needs no secret.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
script=$here/words-check.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

# A word and two phrases, one with a _ in its entry, normalized as the job normalizes the secret.
printf '%s\n' 'acmeword' 'foo bar' 'baz qux' >"$tmp/list"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
repo=$tmp/repo
git init -q "$repo"
cd "$repo"
git config commit.gpgsign false
echo clean >base.txt
git add base.txt
git commit -q -m 'the base'
base=$(git rev-parse HEAD)

# event KEY BASE HEAD BRANCH TITLE BODY writes the event file that the job reads.
event() {
    jq -n --arg k "$1" --arg b "$2" --arg h "$3" --arg r "$4" --arg t "$5" --arg y "$6" \
        '{($k): {base: {sha: $b}, head: {sha: $h, ref: $r}, title: $t, body: $y}}' >"$tmp/event"
}

# An issue has a title and a body alone, and needs no repository.
EXPECT='title'
rc=0
event issue '' '' '' 'baz qux' fine
sh "$script" "$tmp/list" issue "$tmp/event" >"$tmp/out" 2>&1 || rc=$?
if [ "$rc" != 1 ] || ! grep -q "$EXPECT" "$tmp/out"; then
    echo 'FAIL an issue title'
    failed=1
fi
if grep -qiE 'acmeword|foo|bar|baz|qux' "$tmp/out"; then
    echo 'FAIL an issue title: the output holds a stand-in word'
    failed=1
fi
rc=0
event issue '' '' '' fine 'the body
says AcmeWord'
sh "$script" "$tmp/list" issue "$tmp/event" >"$tmp/out" 2>&1 || rc=$?
if [ "$rc" != 1 ] || ! grep -q 'body line 2' "$tmp/out"; then
    echo 'FAIL an issue body'
    failed=1
fi
rc=0
event issue '' '' '' fine fine
sh "$script" "$tmp/list" issue "$tmp/event" >"$tmp/out" 2>&1 || rc=$?
[ "$rc" = 0 ] || {
    echo 'FAIL a clean issue'
    failed=1
}

# A mode that is none of the script's is an error, status 2.
rc=0
sh "$script" "$tmp/list" nothing "$tmp/event" >"$tmp/out" 2>&1 || rc=$?
[ "$rc" = 2 ] || {
    echo "FAIL a wrong mode: status $rc"
    failed=1
}

if [ "$failed" = 0 ]; then echo "words-check-test: ok"; fi
exit "$failed"
