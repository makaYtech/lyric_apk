#!/usr/bin/env bash
# release.sh — публикация APK в GitHub Releases репозитория lyric_apk.
#
# Использование:
#   ./scripts/release.sh             # релиз в канал release
#   ./scripts/release.sh beta        # релиз в канал beta
#   ./scripts/release.sh alpha       # релиз в канал alpha
#
# Требования:
#   - gh (GitHub CLI), авторизованный: gh auth login
#   - flutter в PATH
#   - jq для редактирования JSON
#
# Что делает:
#   1. Читает version из pubspec.yaml основного проекта.
#   2. Собирает prod-release APK.
#   3. Считает SHA-256 и размер.
#   4. Обновляет docs/update.json в этом репозитории.
#   5. Коммитит и пушит update.json.
#   6. Создаёт GitHub Release с тегом v<version> и загружает APK.

set -euo pipefail

# ── Настройки (при необходимости поменяй пути) ───────────────────────
FLUTTER_PROJECT="${FLUTTER_PROJECT:-$HOME/AndroidS/epos_clien}"
UPDATE_REPO="${UPDATE_REPO:-$HOME/AndroidS/lyric_apk}"
CHANNEL="${1:-release}"
FLAVOR="prod"

if [[ "$CHANNEL" != "release" && "$CHANNEL" != "beta" && "$CHANNEL" != "alpha" ]]; then
  echo "Ошибка: неверный канал '$CHANNEL'. Ожидается release|beta|alpha." >&2
  exit 1
fi

# ── 1. Версия из pubspec.yaml ────────────────────────────────────────
cd "$FLUTTER_PROJECT"
if [[ ! -f pubspec.yaml ]]; then
  echo "Ошибка: pubspec.yaml не найден в $FLUTTER_PROJECT" >&2
  exit 1
fi

VERSION=$(grep -E '^version:' pubspec.yaml \
  | sed -E 's/version: *([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
BUILD=$(grep -E '^version:' pubspec.yaml \
  | sed -E 's/version: *[0-9]+\.[0-9]+\.[0-9]+\+?([0-9]+)?.*/\1/')

if [[ -z "$VERSION" ]]; then
  echo "Ошибка: не удалось прочитать version из pubspec.yaml" >&2
  exit 1
fi

echo "Публикуем: v${VERSION} (build ${BUILD:-?}), канал: ${CHANNEL}"

# ── 2. Сборка APK ────────────────────────────────────────────────────
echo "Собираем APK (flavor=${FLAVOR})..."
flutter clean >/dev/null
flutter pub get >/dev/null
flutter build apk --release --flavor "$FLAVOR"

APK_PATH="build/app/outputs/flutter-apk/app-${FLAVOR}-release.apk"
if [[ ! -f "$APK_PATH" ]]; then
  echo "Ошибка: APK не найден: $APK_PATH" >&2
  exit 1
fi

# ── 3. SHA-256 и размер ──────────────────────────────────────────────
SHA=$(sha256sum "$APK_PATH" | awk '{print $1}')
SIZE=$(stat -c '%s' "$APK_PATH" 2>/dev/null || stat -f '%z' "$APK_PATH")
APK_NAME="lyric-${VERSION}-${CHANNEL}.apk"

echo "  Имя:     ${APK_NAME}"
echo "  Размер:  ${SIZE} байт"
echo "  SHA-256: ${SHA}"

# ── 4. Changelog ─────────────────────────────────────────────────────
CHANGELOG_FILE="/tmp/lyric_changelog.txt"
if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "Внимание: $CHANGELOG_FILE не найден." >&2
  echo "Создай файл с описанием изменений и запусти снова." >&2
  echo "(Будет создан пустой — для теста)" >&2
  echo "Релиз v${VERSION}" > "$CHANGELOG_FILE"
fi
CHANGELOG=$(cat "$CHANGELOG_FILE")

# ── 5. Обновляем docs/update.json ────────────────────────────────────
cd "$UPDATE_REPO"
if [[ ! -f docs/update.json ]]; then
  echo '{"release":null,"beta":null,"alpha":null}' > docs/update.json
fi

jq --arg ch "$CHANNEL" \
   --arg ver "$VERSION" \
   --arg log "$CHANGELOG" \
   --argjson size "$SIZE" \
   --arg sha "$SHA" \
   --arg apk "$APK_NAME" \
   '.[$ch] = {
      version: $ver,
      changelog: $log,
      size_bytes: $size,
      sha256: $sha,
      apk_name: $apk
    }' \
   docs/update.json > docs/update.json.tmp
mv docs/update.json.tmp docs/update.json

echo "docs/update.json обновлён."

# ── 6. Commit & push ─────────────────────────────────────────────────
git add docs/update.json
if git diff --cached --quiet; then
  echo "Никаких изменений в update.json — нечего коммитить."
else
  git commit -m "release: v${VERSION} (${CHANNEL})"
  git push origin main
fi

# ── 7. GitHub Release ────────────────────────────────────────────────
TAG="v${VERSION}"
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Релиз ${TAG} уже существует. Загружаю APK в него..."
  gh release upload "$TAG" "${FLUTTER_PROJECT}/${APK_PATH}#${APK_NAME}" --clobber
else
  gh release create "$TAG" \
    --title "v${VERSION} (${CHANNEL})" \
    --notes "$CHANGELOG" \
    "${FLUTTER_PROJECT}/${APK_PATH}#${APK_NAME}"
fi

echo ""
echo "Готово."
echo "Release:  https://github.com/${REPO_SLUG}/releases/tag/${TAG}"
echo "APK URL:  https://github.com/${REPO_SLUG}/releases/download/${TAG}/${APK_NAME}"
echo "Manifest: https://raw.githubusercontent.com/${REPO_SLUG}/main/docs/update.json"
