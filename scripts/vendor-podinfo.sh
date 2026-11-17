#!/usr/bin/env bash
# Lấy mã nguồn podinfo tại tag đã ghim vào app/ (kế hoạch mục 7.1). Ghi nguồn gốc ở docs/upstream.md.
# Dùng `git archive` để chỉ lấy file được theo dõi, không kéo theo .git. Chạy lại = thay toàn bộ app/.
set -euo pipefail

PODINFO_REPO=https://github.com/stefanprodan/podinfo
PODINFO_TAG=6.17.0
PODINFO_COMMIT=fd3a834ed8d14b80ea334cf8a2fddd4597924da6

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

git clone -q --branch "$PODINFO_TAG" --depth 1 "$PODINFO_REPO" "$TMP/podinfo"
ACTUAL=$(git -C "$TMP/podinfo" rev-parse HEAD)
[ "$ACTUAL" = "$PODINFO_COMMIT" ] || { echo "Tag $PODINFO_TAG trỏ $ACTUAL, khác commit ghim $PODINFO_COMMIT — dừng." >&2; exit 1; }

rm -rf "$ROOT/app"; mkdir -p "$ROOT/app"
git -C "$TMP/podinfo" archive --format=tar HEAD | tar -x -C "$ROOT/app"
echo "podinfo $PODINFO_TAG ($PODINFO_COMMIT) → app/  ($(find "$ROOT/app" -type f | wc -l) file)"
