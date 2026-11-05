#!/usr/bin/env bash
# Ayı ile Baykuş: durum çubuğunu kapatır, kurulumdan önceki ayarı geri getirir.
set -eu
C="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; H="$C/ayi-baykus"; S="$C/settings.json"
command -v jq >/dev/null 2>&1 || { echo "jq bulunamadı."; exit 1; }
[ -f "$S" ] || { echo "$S yok, yapılacak bir şey yok."; exit 0; }
# Çıkış koduna değil çıktıya bakılır: bazı jq sarmalayıcıları hatada da 0 döndürüyor.
nesne_mi() { [ "$(jq -r 'type' "$1" 2>/dev/null | tr -d '\r')" = object ]; }
nesne_mi "$S" || { echo "$S geçerli bir JSON nesnesi değil, dokunmadım."; exit 1; }
case "$(jq -r '.statusLine.command // ""' "$S" | tr -d '\r')" in
  *ayi-baykus/statusline.sh*) ;;
  *) echo "Etkin durum çubuğu Ayı ile Baykuş değil, ayara dokunmadım."; exit 0;;
esac
cp "$S" "$S.ayi-baykus-yedek-$(date +%Y%m%d-%H%M%S)"
O=null; [ -f "$H/onceki.json" ] && O=$(tr -d '\r' < "$H/onceki.json")
if [ "$O" = "null" ]; then jq 'del(.statusLine)' "$S" > "$S.yeni"
else jq --argjson o "$O" '.statusLine = $o' "$S" > "$S.yeni"; fi
nesne_mi "$S.yeni" || { echo "Yeni ayar üretilemedi, dokunmadım."; exit 1; }
mv "$S.yeni" "$S"
mv "$H/onceki.json" "$H/onceki.json.kullanildi" 2>/dev/null || true
echo "Kaldırıldı, önceki ayar geri geldi. Dosyalar $H klasöründe duruyor, isterseniz silebilirsiniz."
