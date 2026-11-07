#!/bin/sh
# Run every addon simulation test. From the repo root: sh tests/run.sh
cd "$(dirname "$0")/.." || exit 1
command -v lua5.1 >/dev/null 2>&1 || apt-get install -y -q lua5.1 >/dev/null 2>&1 \
    || { apt-get update -qq >/dev/null 2>&1 && apt-get install -y -q lua5.1 >/dev/null 2>&1; }
status=0
for f in */*.lua; do
    case "$f" in tests/*|*/libs/*) continue ;; esac
    # WoW accepts a UTF-8 byte-order mark at the start of a file; plain Lua doesn't.
    sed '1s/^\xEF\xBB\xBF//' "$f" | luac5.1 -p - 2>&1 | sed "s#^luac5.1: stdin#$f#" | grep . && status=1
done
for t in tests/*_test.lua; do
    echo "== $t"
    lua5.1 "$t" || status=1
done
exit $status
