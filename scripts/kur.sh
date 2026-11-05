#!/usr/bin/env bash
# Ayı ile Baykuş: durum çubuğunu kurar. Önceki ayarı yedekler, kaldir.sh geri alır.
set -eu
C="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; H="$C/ayi-baykus"; S="$C/settings.json"
BURADA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 3 ]; }; then
  echo "Bash 4.3 veya üstü gerekli (sizdeki $BASH_VERSION). macOS: brew install bash"; exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "jq bulunamadı. Önce kurun: https://jqlang.github.io/jq/"; exit 1; }

mkdir -p "$H"
[ -f "$S" ] || echo '{}' > "$S"
# Çıkış koduna değil çıktıya bakılır: bazı jq sarmalayıcıları hatada da 0 döndürüyor.
nesne_mi() { [ "$(jq -r 'type' "$1" 2>/dev/null | tr -d '\r')" = object ]; }
nesne_mi "$S" || { echo "$S geçerli bir JSON nesnesi değil, dokunmadım."; exit 1; }

cp "$BURADA/statusline.sh" "$H/statusline.sh.yeni"
bash -n "$H/statusline.sh.yeni"
mv "$H/statusline.sh.yeni" "$H/statusline.sh"
cp "$BURADA/canlandir.sh" "$H/canlandir.sh"

cp "$S" "$S.ayi-baykus-yedek-$(date +%Y%m%d-%H%M%S)"
# İlk kurulumda önceki durum çubuğunu sakla; yeniden kurulumda üstüne yazma.
[ -f "$H/onceki.json" ] || jq -c '.statusLine // null' "$S" > "$H/onceki.json"
if [ "$C" = "$HOME/.claude" ]; then YOL='~/.claude/ayi-baykus/statusline.sh'; else YOL="$H/statusline.sh"; fi
jq --arg k "bash $YOL" '.statusLine = {"type":"command","command":$k,"refreshInterval":1}' "$S" > "$S.yeni"
[ "$(jq -r '.statusLine.command // ""' "$S.yeni" 2>/dev/null | tr -d '\r')" = "bash $YOL" ] || { echo "Yeni ayar üretilemedi, dokunmadım."; exit 1; }
mv "$S.yeni" "$S"

echo "Kuruldu: $H/statusline.sh"
[ "$(cat "$H/onceki.json")" = "null" ] || echo "Önceki durum çubuğu saklandı, kaldırınca geri gelir."
echo "Bir sonraki yenilemede görünür. Görünmezse Claude Code'u yeniden başlatın."
