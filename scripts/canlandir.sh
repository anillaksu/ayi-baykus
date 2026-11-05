#!/usr/bin/env bash
# Durum çubuğu sahnesini saniyede bir kare canlı oynatır. Gerçek durumu değiştirmez.
# Kullanım: bash ~/.claude/ayi-baykus/canlandir.sh [yagmur|firtina|dusunce|ikisi] [saniye]
SAHNE=${1:-ikisi}; SURE=${2:-60}
Y="${TMPDIR:-/tmp}/cc-canlandir-$$"; mkdir -p "$Y"; K="$Y/kayit.jsonl"
yaz() { local z; z=$(date -u -d "@$(( $(date +%s) - $1 ))" +%Y-%m-%dT%H:%M:%S.123Z); printf '%s\n' "$2" | sed "s/ZAMAN/$z/" > "$K"; }
BEKLE='{"type":"assistant","timestamp":"ZAMAN","message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}'
DUSUN='{"type":"user","timestamp":"ZAMAN","message":{"content":[{"type":"tool_result"}]}}'
printf '\033[?25l\033[2J'
trap 'printf "\033[?25h\n"' EXIT
for (( t=1; t<=SURE; t++ )); do
  s=$SAHNE; [ "$s" = ikisi ] && { if (( t <= SURE/2 )); then s=yagmur; else s=firtina; fi; }
  case $s in
    yagmur)  c=80; yaz 40 "$BEKLE"; ad="Yağmur: tek şemsiye";;
    firtina) c=93; yaz 40 "$BEKLE"; ad="Fırtına: ayı baykuşa sarılır";;
    *)       c=30; yaz 2 "$DUSUN"; ad="Düşünme: baykuş ampulü getirir";;
  esac
  J='{"session_id":"canlandir","model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":'$c'},"effort":{"level":"high"},"workspace":{"current_dir":"demo"},"transcript_path":"'"$K"'"}'
  KARE=$(printf '%s' "$J" | TMPDIR="$Y" SL_OKTANT=1 SL_TICK=$t SL_HOUR=23 COLUMNS=${COLUMNS:-112} bash "$(dirname "${BASH_SOURCE[0]}")/statusline.sh" 2>&1)
  printf '\033[H\033[1m  %s\033[0m   %d/%d sn\033[K\n\n%s\033[K\n' "$ad" "$t" "$SURE" "$KARE"
  sleep 0.6
done
