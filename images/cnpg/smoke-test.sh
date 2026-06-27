#!/usr/bin/env bash
# Verify both extensions are installed in a built image.
# Usage: ./smoke-test.sh <image-ref>
set -euo pipefail
IMG="${1:?usage: smoke-test.sh <image-ref>}"

docker run --rm --entrypoint bash "$IMG" -lc '
  set -eu
  LIBDIR=$(pg_config --pkglibdir)
  EXTDIR=$(pg_config --sharedir)/extension
  for f in "$LIBDIR/vector.so" "$LIBDIR/age.so" \
           "$EXTDIR/vector.control" "$EXTDIR/age.control"; do
    test -f "$f" || { echo "MISSING: $f"; exit 1; }
  done
  echo "pgvector sql: $(ls "$EXTDIR"/vector--*.sql | head -1)"
  echo "age sql:      $(ls "$EXTDIR"/age--*.sql | head -1)"
  echo "SMOKE OK"
'
