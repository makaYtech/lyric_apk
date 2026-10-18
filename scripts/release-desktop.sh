#!/usr/bin/env bash
# scripts/publish-desktop.sh — переносит desktop-сборки из staging-релиза
# makaYtech/lyric в makaYtech/lyric_apk и обновляет JSON-манифесты.
#
# Использование:
#   ./scripts/publish-desktop.sh v1.2.1
#
# Требования: gh (авторизован), jq, sha256sum, git.

set -euo pipefail

TAG="${1:?Usage: $0 <tag>   например: $0 v1.2.1}"
SOURCE_REPO="makaYtech/lyric"
TARGET_REPO="makaYtech/lyric_apk"
APP_NAME="lyric"
VERSION="${TAG#v}"

CHANGELOG_FILE="${CHANGELOG_FILE:-/tmp/lyric_changelog.txt}"
if [[ -f "$CHANGELOG_FILE" ]]; then
  CHANGELOG="$(cat "$CHANGELOG_FILE")"
else
  CHANGELOG="Релиз $TAG"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

echo "▶ Скачиваем staging-релиз $TAG из $SOURCE_REPO…"
gh release download "$TAG" --repo "$SOURCE_REPO" --dir . --clobber

WIN_SRC=$(ls *windows*.zip 2>/dev/null | head -n1 || true)
LINUX_SRC=$(ls *linux*.tar.gz 2>/dev/null | head -n1 || true)

[[ -z "$WIN_SRC"   ]] && { echo "Windows ZIP не найден в релизе $TAG." >&2; exit 1; }
[[ -z "$LINUX_SRC" ]] && { echo "Linux tar.gz не найден в релизе $TAG." >&2; exit 1; }

WIN_FINAL="${APP_NAME}-${VERSION}-windows.zip"
LINUX_FINAL="${APP_NAME}-${VERSION}-linux.tar.gz"
mv "$WIN_SRC"   "$WIN_FINAL"
mv "$LINUX_SRC" "$LINUX_FINAL"

WIN_SHA=$(sha256sum "$WIN_FINAL"   | awk '{print $1}')
WIN_SIZE=$(stat -c '%s' "$WIN_FINAL")
LINUX_SHA=$(sha256sum "$LINUX_FINAL" | awk '{print $1}')
LINUX_SIZE=$(stat -c '%s' "$LINUX_FINAL")

WIN_URL="https://github.com/${TARGET_REPO}/releases/download/${TAG}/${WIN_FINAL}"
LINUX_URL="https://github.com/${TARGET_REPO}/releases/download/${TAG}/${LINUX_FINAL}"

echo "▶ Заливаем в $TARGET_REPO…"
if gh release view "$TAG" --repo "$TARGET_REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$WIN_FINAL" "$LINUX_FINAL" --repo "$TARGET_REPO" --clobber
else
  gh release create "$TAG" --repo "$TARGET_REPO" \
    --title "$TAG" \
    --notes "$CHANGELOG" \
    "$WIN_FINAL" "$LINUX_FINAL"
fi

echo "▶ Клонируем $TARGET_REPO для обновления манифестов…"
gh repo clone "$TARGET_REPO" target -- --depth=1
cd target
mkdir -p docs

jq -n \
  --arg ver "$VERSION" \
  --arg url "$WIN_URL" \
  --argjson size "$WIN_SIZE" \
  --arg sha "$WIN_SHA" \
  --arg log "$CHANGELOG" \
  '{
    version: $ver,
    download_url: $url,
    file_size: $size,
    sha256: $sha,
    release_notes: $log
  }' > docs/windows_update.json

jq -n \
  --arg ver "$VERSION" \
  --arg url "$LINUX_URL" \
  --argjson size "$LINUX_SIZE" \
  --arg sha "$LINUX_SHA" \
  --arg log "$CHANGELOG" \
  '{
    version: $ver,
    download_url: $url,
    file_size: $size,
    sha256: $sha,
    release_notes: $log
  }' > docs/linux_update.json

git add docs/windows_update.json docs/linux_update.json
if git diff --cached --quiet; then
  echo "Манифесты не изменились — коммит пропущен."
else
  git commit -m "release: desktop $TAG"
  git push origin main
fi

echo ""
echo "✅ Готово."
echo "   Release:  https://github.com/${TARGET_REPO}/releases/tag/${TAG}"
echo "   Windows:  ${WIN_URL}"
echo "   Linux:    ${LINUX_URL}"
echo "   Windows manifest: https://raw.githubusercontent.com/${TARGET_REPO}/main/docs/windows_update.json"
echo "   Linux manifest:   https://raw.githubusercontent.com/${TARGET_REPO}/main/docs/linux_update.json"