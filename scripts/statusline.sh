#!/usr/bin/env bash
# Ayı ile Baykuş — https://github.com/anillaksu/ayi-baykus
# Oturum durumuna göre yaşayan piksel sahne. avenoxstatusline uyarlamasıdır.
#
#   Satır 1: <ayı + ne yaptığı>  model-yıldızı  düşünme-noktaları  $maliyet
#   Satır 2: terminal genişliğinde sinematik şerit. Her hücrenin kendi 24-bit zemin rengi var
#            (renk geçişi + kenar kararması), üstünde yoğun sahne katmanı, en üstte bilgiler.
#
# Ayı ve sahne o an oturumda ne oluyorsa onu gösterir. Kaynak:
#   - Claude Code'un stdin JSON'u (bağlam %, limitler, maliyet…)
#   - oturum kaydının (transcript_path) son satırları: çalışan araç, düşünme, bekleme ve süresi
# Sahneler: gece=yıldız+ay+şehir silueti, gündüz=bulut+güneş+tepeler, sessizlik=koyu gece+zZ,
#   düşünme=mor bulutsu, Bash=yeşil kod yağmuru, kod=amber terminal, okuma=sayfa çizgileri,
#   web=okyanus dalgası, ajan=akan oklar, soru=altın ışık, bağlam %75+/limit %80+=yağmur,
#   bağlam %90+=fırtına ve şimşek.
#
# Hız: fork yalnız tail + jq (+5 sn'de bir git); şerit tamamen bash içinde çizilir.
# Env: SL_BADGE_CMD, SL_NO_SERAI=1, SL_TICK (testte saati sabitle), SL_NOW, SL_HOUR, COLUMNS
# License: MIT

export LC_ALL=C.UTF-8
for d in /opt/homebrew/bin /usr/local/bin; do
  [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH";; esac
done
export PATH

if ! command -v jq >/dev/null 2>&1; then
  printf 'statusline: jq bulunamadi\n'
  exit 0
fi

[ -z "$input" ] && IFS= read -r -d '' input
[ -z "$input" ] && input='{}'

printf -v now '%(%s)T' -1; now=${SL_NOW:-$now}
printf -v HOUR '%(%H)T' -1; HOUR=$((10#${SL_HOUR:-$HOUR}))

ESC=$'\033'; R="${ESC}[0m"; B="${ESC}[1m"; D="${ESC}[2m"
CY="${ESC}[36m"; GR="${ESC}[32m"; YE="${ESC}[33m"; RD="${ESC}[31m"; MG="${ESC}[35m"

# ---- oturum kaydı yolu (JSON'da kaçışlı ters bölü: C:\\Users\\… -> C:/Users/…) ----
TR=""
if [[ $input =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  TR=${BASH_REMATCH[1]}; TR=${TR//\\\\//}
fi

# ---- oturum yuvası: 64 sabit yuva (dosya sayısı birikmez). Girdi ve kayıt değişmediyse jq/tail çalışmaz ----
SID=""; [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && SID=${BASH_REMATCH[1]}
h2=${SID:0:2}; [[ $h2 =~ ^[0-9a-fA-F]{2}$ ]] || h2=00
SLOT=$(( 16#$h2 % 64 )); TD=${TMPDIR:-/tmp}
FC="$TD/cc-sl-m$SLOT.alan"; IC="$TD/cc-sl-m$SLOT.girdi"; SF="$TD/cc-sl-m$SLOT.durum"
son=""; [ -f "$IC" ] && IFS= read -r -d '' son < "$IC"
if ! [ -f "$FC" ] || [ "$son" != "$input" ] || { [ -n "$TR" ] && [ "$TR" -nt "$FC" ]; }; then
  { [ -n "$TR" ] && [ -f "$TR" ] && tail -n 12 "$TR" 2>/dev/null; } |
  jq -n -R -r --argjson i "$input" '
    ([inputs | fromjson? | select(type=="object" and (.type=="user" or .type=="assistant") and (.isMeta != true))]) as $all
    | ($all | last) as $l
    | ($l.message.content // "") as $c
    | ([ ($c | if type=="array" then .[] else empty end) | select(type=="object" and .type=="tool_use") | .name ] | last) as $tn
    | (if $l == null then "yok"
       elif $l.type == "assistant" then
         (if $tn then "arac" elif ($l.message.stop_reason // "") == "end_turn" then "bekliyor" else "dusunuyor" end)
       elif ($c|type) == "array" and ([$c[] | select(type=="object" and .type=="tool_result")] | length) > 0 then "dusunuyor"
       else "mesaj" end) as $k
    | ((($l.timestamp // "") | tostring | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch 0)) | floor) as $ts
    | ($all | map(select(.type=="user" and ([.message.content | if type=="array" then (.[] | select(type=="object" and .type=="tool_result")) else empty end] | length == 0))) | last) as $u
    | (($u.message.content // "") | if type=="array" then (map(select(type=="object" and .type=="text") | .text) | join(" ")) else tostring end) as $ut
    | (if ($ut | test("teşekkür|sağ ?ol|aferin|harika|süper|mükemmel|bravo|çok güzel|seviyorum"; "i")) then "sevgi"
       elif ($ut | test("bozuk|olmadı|olmamış|berbat|çirkin|kötü|yanlış"; "i")) then "uzgun" else "-" end) as $rk
    | ((($u.timestamp // "") | tostring | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch 0)) | floor) as $rt
    | $i
    | [ (.model.display_name // "?"),
        (.context_window.used_percentage // 0 | floor),
        (.effort.level // ""),
        (.thinking.enabled // false),
        ((.cost.total_cost_usd // 0) * 100 | floor),
        (.rate_limits.five_hour.used_percentage // -1 | floor),
        (.rate_limits.seven_day.used_percentage // -1 | floor),
        (.workspace.git_worktree // ""),
        (.workspace.current_dir // .cwd // "."),
        (.session_id // "nosess"),
        (.rate_limits.five_hour.resets_at // 0 | if type=="string" then (try fromdateiso8601 catch 0) else . end | floor),
        (.rate_limits.seven_day.resets_at // 0 | if type=="string" then (try fromdateiso8601 catch 0) else . end | floor),
        $k, ($tn // ""), $ts, $rk, $rt
      ] | .[] | tostring | gsub("[\r\n\t]"; " ")' > "$FC" 2>/dev/null
  printf '%s' "$input" > "$IC" 2>/dev/null
fi
{
  IFS= read -r MODEL; IFS= read -r CTX;   IFS= read -r EFFORT
  IFS= read -r THINK; IFS= read -r COSTC; IFS= read -r FIVE
  IFS= read -r SEVEN; IFS= read -r WT;    IFS= read -r CWD
  IFS= read -r SID2;  IFS= read -r FIVE_R; IFS= read -r SEVEN_R
  IFS= read -r ACTK;  IFS= read -r ACTN;  IFS= read -r ACTTS
  IFS= read -r RK;    IFS= read -r RKT
} < "$FC"
for v in MODEL CTX EFFORT THINK COSTC FIVE SEVEN WT CWD FIVE_R SEVEN_R ACTK ACTN ACTTS RK RKT; do
  declare -n _r=$v; _r=${_r%$'\r'}; unset -n _r
done

int() { local -n _v=$1; case "$_v" in ''|*[!0-9-]*) _v=$2;; esac; }
MODEL=${MODEL:-?}; int CTX 0; int FIVE -1; int SEVEN -1; int COSTC 0
int FIVE_R 0; int SEVEN_R 0; int ACTTS 0
CWD=${CWD:-.}

# ---- git + rozet (klasör anahtarlı, ~5 sn önbellek; ilk satır = zaman damgası) ----
CACHE="${TMPDIR:-/tmp}/cc-sl-d-${CWD//[^A-Za-z0-9]/_}.cache"
mt=0; BRANCH=""; DIRTY=""; BADGE=""; SYNC=""; APPROV=0
if [ -s "$CACHE" ]; then
  { IFS= read -r mt; IFS= read -r BRANCH; IFS= read -r DIRTY; IFS= read -r BADGE
    IFS= read -r SYNC; IFS= read -r APPROV; } < "$CACHE"
fi
int mt 0
if (( now - mt >= 5 )); then
  BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
  DIRTY=""; [ -n "$(git -C "$CWD" status --porcelain --untracked-files=no 2>/dev/null | head -1)" ] && DIRTY="*"
  ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || ROOT=$CWD
  BADGE=""; SYNC=""; APPROV=0
  if [ -n "$SL_BADGE_CMD" ]; then
    BADGE=$( (cd "$ROOT" 2>/dev/null && eval "$SL_BADGE_CMD") 2>/dev/null | head -1 | tr -d '\t\n' )
  fi
  if [ -z "$BADGE" ] && [ -z "$SL_NO_SERAI" ] && [ -f "$ROOT/.serai/config.json" ]; then
    BADGE="serai:${ROOT##*/}"
    SS="$ROOT/.serai/cache/sync.state.json"
    if [ -f "$SS" ]; then
      hb=$(jq -r '(.lastHeartbeatAt // .heartbeatAt // .lastPullAt // .updatedAt // empty)
                  | if type=="number" then . else (try (fromdateiso8601) catch empty) end' "$SS" 2>/dev/null)
      if [ -n "$hb" ]; then (( now - ${hb%.*} < 180 )) && SYNC="live" || SYNC="stale"; fi
    fi
    SNAP="$ROOT/.serai/cache/snapshot.json"
    if [ -f "$SNAP" ]; then
      APPROV=$(jq -r '[ (.approvalRequests // .approvals // [])[]
                        | select(((.status // "")|ascii_downcase) | test("pending|requested|open")) ] | length' "$SNAP" 2>/dev/null)
    fi
  fi
  int APPROV 0
  printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$now" "$BRANCH" "$DIRTY" "$BADGE" "$SYNC" "$APPROV" > "$CACHE" 2>/dev/null
fi
int APPROV 0
[ ${#BRANCH} -gt 24 ] && BRANCH="${BRANCH:0:23}…"

T=${SL_TICK:-$now}
frame() { local -a a=("${@:2}"); PET="${a[$(( $1 % ${#a[@]} ))]}"; }
dur() { DUR=""; local s=$1
  if (( s >= 3600 )); then printf -v DUR '%d sa %d dk' $((s/3600)) $((s%3600/60))
  elif (( s >= 60 )); then printf -v DUR '%d dk' $((s/60))
  else printf -v DUR '%d sn' "$s"; fi; }

# ---- ayının yüzü: bağlam baskısını taşır ----
if   (( CTX >= 90 )); then F1="ʕ⊙ᴥ⊙ʔ"; F2="ʕ☉ᴥ☉ʔ"; PETC=$RD
elif (( CTX >= 75 )); then F1="ʕ;ᴥ;ʔ"; F2="ʕ°ᴥ°ʔ"; PETC=$YE
else                       F1="ʕ•ᴥ•ʔ"; F2="ʕ◕ᴥ◕ʔ"; PETC=$CY; fi
BK="ʕ-ᴥ-ʔ"

# ---- ayının işi: oturumda o an ne oluyor ----
dt=0; (( ACTTS > 0 )) && dt=$(( now - ACTTS )); (( dt < 0 )) && dt=0
SCN=gok
case "$ACTK" in
  arac)
    case "$ACTN" in
      Bash|PowerShell)
        ACT="komut çalıştırıyor"; SCN=komut
        frame "$T" "${F1}>_" "${F1}ﾉ>_" "${F2}>_" "${F1}ﾉ>";;
      Edit|Write|NotebookEdit|MultiEdit)
        ACT="kod yazıyor"; SCN=kod
        frame "$T" "${F1}✎" "${F1}✎_" "${F2}✎__" "${F1}✎___";;
      Read|Grep|Glob|LSP)
        ACT="dosya okuyor"; SCN=okuma
        frame "$T" "${F1}≡" "${F2}≡" "${BK}≡" "${F1}≡";;
      WebFetch|WebSearch)
        ACT="internette arıyor"; SCN=web
        frame "$T" "${F1}⌕" "${F2}⌕" " ${F1}⌕" "${F2}⌕";;
      *chrome*)
        ACT="tarayıcıda geziniyor"; SCN=web
        frame "$T" "${F1}⌕" "${F2}⌕" " ${F1}⌕" "${F2}⌕";;
      Agent|Task|SendMessage)
        ACT="yardımcı ajana iş verdi"; SCN=ajan
        frame "$T" "${F1}➤" "${F1}ﾉ➤" "${F1}ﾉ ➤" "${F2}";;
      AskUserQuestion)
        ACT="sana soru soruyor"; SCN=soru
        frame "$T" "${F1}?" "${F2}?" "${F1}¿" "${F2}?";;
      TodoWrite|Task*)
        ACT="yapılacakları düzenliyor"; SCN=kod
        frame "$T" "${F1}✎" "${F2}✎";;
      *)
        ACT="araç kullanıyor: ${ACTN##*__}"; SCN=arac
        frame "$T" "${F1}⁂" "${F2}⁂" "${F1}⁂" "${BK}⁂";;
    esac
    (( dt >= 60 )) && { dur "$dt"; ACT+=" ($DUR)"; } ;;
  dusunuyor)
    ACT="düşünüyor"; SCN=dusunce
    frame "$T" "${BK}∘" "${BK}∘°" "${BK}∘°○" "${F2}✧";;
  mesaj)
    ACT="mesajını okuyor"; SCN=dusunce
    frame "$T" "${F1}»" "${F2}»" "${BK}»";;
  bekliyor)
    if (( dt >= 3600 )); then
      ACT="derin uykuda"; SCN=uyku; frame "$T" "${BK}zZ" "${BK} zZ"
    elif (( dt >= 600 )); then
      dur "$dt"; ACT="uyukluyor ($DUR sessiz)"; SCN=uyku
      frame "$T" "${BK} z" "${BK} zz" "${BK} zzz" "${BK} zz"
    else
      ACT="seni bekliyor"; SCN=gok
      frame "$T" "$F1" "$F1" "$BK" "$F2" "$F1" "${F1}ﾉ"
    fi;;
  *)
    ACT="hazır"; SCN=gok; frame "$T" "$F1" "$F1" "$BK" "$F2";;
esac
PET_CAT="$PET"

ACTSC=$SCN
# ---- baskı notları: bağlam ve limitler sahneyi de bozar ----
if   (( CTX >= 90 )); then ACT+=" · bağlam %$CTX"; SCN=firtina
elif (( CTX >= 75 )); then ACT+=" · bağlam %$CTX"; SCN=yagmur; fi
if (( FIVE >= 80 ));  then ACT+=" · 5s %$FIVE"; [ "$SCN" = firtina ] || SCN=yagmur
elif (( SEVEN >= 80 )); then ACT+=" · 7g %$SEVEN"; [ "$SCN" = firtina ] || SCN=yagmur; fi
if [ "$SCN" = gok ] && ! (( HOUR >= 7 && HOUR < 19 )); then SCN=gece; fi

# ---- model yıldızı: ışın sayısı model gücünü gösterir ----
OR="${ESC}[38;5;208m"
case "$MODEL" in
  *[Hh]aiku*)  MT=1;; *[Ss]onnet*) MT=2;; *[Oo]pus*) MT=3;; *[Ff]able*) MT=4;; *) MT=0;;
esac
case "$MT" in
  1) frame "$T" "·" "✢" "✢" "✢";;
  2) frame "$T" "✢" "✱" "✱" "✱";;
  3) frame "$T" "✱" "✶" "✻" "✶";;
  4) frame "$T" "✻" "✽" "✺" "✽";;
  *) frame "$T" "✢" "✢";;
esac
BADGE_M="${OR}${B}${PET}${R}"
MSTAR="$PET"

# ---- düşünme düzeyi: 5 nokta (low..max); düşünme açıksa mor, kapalıysa camgöbeği ----
case "$EFFORT" in low) EN=1;; medium) EN=2;; high) EN=3;; xhigh) EN=4;; max) EN=5;; *) EN=0;; esac
EFF=""
if [ "$EN" -gt 0 ]; then
  EC="$CY"; [ "$THINK" = true ] && EC="$MG"
  for (( i=0; i<5; i++ )); do
    if (( i < EN )); then
      h="●"; (( EN >= 4 && i == EN-1 && T%2 == 1 )) && h="◉"
      EFF+="${EC}${h}"
    else EFF+="${D}○"; fi
  done
  EFF+="$R"
fi

# ---- satır 1: ayı + ne yaptığı · model · düşünme · maliyet ----
L1="${PETC}${PET_CAT}${R} ${D}${ACT}${R}  ${BADGE_M}"
[ -n "$EFF" ] && L1+="  ${EFF}"
if (( COSTC > 0 )); then printf -v cst '$%d.%02d' $((COSTC/100)) $((COSTC%100)); L1+="  ${D}${cst}${R}"; fi

# =====================================================================
#   SİNEMATİK ŞERİT (satır 2)
# =====================================================================
W=$(( ${COLUMNS:-112} - 4 )); (( W < 60 )) && W=60; (( W > 220 )) && W=220
F() { printf -v "$1" '%s[38;2;%d;%d;%dm' "$ESC" "$2" "$3" "$4"; }   # ön renk
G() { printf -v "$1" '%s[48;2;%d;%d;%dm' "$ESC" "$2" "$3" "$4"; }   # zemin

# ---- üst katman: bilgiler hücre hücre yerleşir (OC=karakter, OF=ön renk, OB=zemin; boş zemin=sahne) ----
declare -a OC OF OB
# Katman dizini = satır*1000 + sütun. Satır 0 = ayı satırı, son satır = bilgi bandı.
ROWS=${SL_ROWS:-4}; int ROWS 4; (( ROWS < 2 )) && ROWS=2; (( ROWS > 12 )) && ROWS=12
ROWOFF=0; CUR=2
put() { local t=$3 k n=${#3}; for (( k=0; k<n; k++ )); do OC[ROWOFF+CUR]=${t:k:1}; OF[ROWOFF+CUR]=$1; OB[ROWOFF+CUR]=$2; ((CUR++)); done; }
gap() { CUR=$(( CUR + $1 )); }
F TXT 238 238 244; F DIMT 150 155 170; F DARK 14 14 18
if   (( CTX >= 80 )); then F CCF 255 105 95; elif (( CTX >= 50 )); then F CCF 245 205 85; else F CCF 95 225 140; fi

left() {  # left <resets_at> -> LEFT ("2s13d" / "3g3s" / "")
  LEFT=""; local s=$(( $1 - now ))
  (( $1 <= 0 || s <= 0 )) && return
  if   (( s >= 86400 )); then printf -v LEFT '%dg%ds' $((s/86400)) $(( s%86400/3600 ))
  elif (( s >= 3600 ));  then printf -v LEFT '%ds%dd' $((s/3600)) $(( s%3600/60 ))
  else printf -v LEFT '%dd' $(( s/60 )); fi
}
pill() {  # pill <etiket> <kullanılan%> <resets_at>: içi yazılı, dolu kısmında gezinen ışık
  local u=$2 w=15 txt lf i hl2=-1 bf bh be fe
  (( u > 100 )) && u=100; (( u < 0 )) && u=0
  if   (( u >= 80 )); then G bf 192 57 43;  G bh 255 110 95
  elif (( u >= 50 )); then G bf 201 162 39; G bh 245 215 110
  else                     G bf 46 158 91;  G bh 100 215 140; fi
  G be 44 48 60; F fe 228 230 236
  left "$3"; txt=" $1 ${u}%${LEFT:+ $LEFT}"
  printf -v txt '%-*s' "$w" "$txt"; txt=${txt:0:$w}
  lf=$(( u*w/100 )); (( u > 0 && lf == 0 )) && lf=1
  (( lf >= 2 )) && hl2=$(( T % lf ))
  for (( i=0; i<w; i++ )); do
    OC[ROWOFF+CUR]=${txt:i:1}
    if (( i < lf )); then OF[ROWOFF+CUR]=$DARK; (( i == hl2 )) && OB[ROWOFF+CUR]=$bh || OB[ROWOFF+CUR]=$bf
    else OF[ROWOFF+CUR]=$fe; OB[ROWOFF+CUR]=$be; fi
    ((CUR++))
  done
}

# ---- üst satır (sahnenin içinde): ayı + ne yaptığı · model yıldızı · düşünme · maliyet ----
case "$PETC" in "$RD") F pf 255 232 222;; "$YE") F pf 250 210 90;; *) F pf 120 225 240;; esac
F af 214 218 228; F of 255 140 30
if (( CTX >= 75 )); then put "$pf" "" "$ACT"; else put "$af" "" "$ACT"; fi
gap 3; put "$of" "" "$MSTAR"
if (( EN > 0 )); then
  gap 2
  if [ "$THINK" = true ]; then F ef 205 130 255; else F ef 100 210 230; fi
  F eo 95 100 120
  for (( i=0; i<5; i++ )); do
    if (( i < EN )); then h="●"; (( EN >= 4 && i == EN-1 && T%2 == 1 )) && h="◉"; put "$ef" "" "$h"
    else put "$eo" "" "○"; fi
  done
fi
if (( COSTC > 0 )); then printf -v cst '$%d.%02d' $((COSTC/100)) $((COSTC%100)); gap 3; put "$DIMT" "" "$cst"; fi

TOPEND=$CUR
# ---- alt satır (bilgi bandı) ----
ROWOFF=$(( (ROWS-1)*1000 )); CUR=2

# ---- bağlam: cam hücreler (dolu kısım renkli, gezinen ışık) + yüzde ----
if   (( CTX >= 80 )); then G cbf 192 57 43;  G cbh 255 110 95
elif (( CTX >= 50 )); then G cbf 201 162 39; G cbh 245 215 110
else                       G cbf 46 158 91;  G cbh 100 215 140; fi
G cbe 44 48 60
bw=8; fill=$((CTX*bw/100)); (( fill > bw )) && fill=$bw; (( fill < 0 )) && fill=0
(( CTX > 0 && fill == 0 )) && fill=1
hl=-1; (( fill >= 2 )) && hl=$(( T % fill ))
for (( i=0; i<bw; i++ )); do
  OC[ROWOFF+CUR]=" "; OF[ROWOFF+CUR]=""
  if (( i < fill )); then (( i == hl )) && OB[ROWOFF+CUR]=$cbh || OB[ROWOFF+CUR]=$cbf; else OB[ROWOFF+CUR]=$cbe; fi
  ((CUR++))
done
put "$TXT" "" " ${CTX}%"
(( FIVE  >= 0 )) && { gap 3; pill 5s "$FIVE" "$FIVE_R"; }
(( SEVEN >= 0 )) && { gap 2; pill 7g "$SEVEN" "$SEVEN_R"; }
if [ -n "$BRANCH" ]; then gap 3; put "$DIMT" "" "⎇ "; put "$TXT" "" "$BRANCH"; [ -n "$DIRTY" ] && { F yf 245 205 85; put "$yf" "" "*"; }; fi
[ -n "$WT" ] && { gap 2; put "$DIMT" "" "⑂$WT"; }
if [ -n "$BADGE" ]; then F gf 95 225 140; gap 3; put "$gf" "" "● "; put "$TXT" "" "$BADGE"; fi
(( APPROV > 0 ))    && { F rf 255 105 95; gap 2; put "$rf" "" "⚑$APPROV"; }
[ "$SYNC" = live ]  && { F gf 95 225 140; gap 2; put "$gf" "" "●sync"; }
[ "$SYNC" = stale ] && { gap 2; put "$DIMT" "" "○sync"; }

# =====================================================================
#   PİKSEL PANORAMA
#   Her hücre "▀": üst yarı = ön renk, alt yarı = zemin -> hücre başına 2 kare piksel.
#   ROWS satır = ROWS*2 piksel yükseklik. Satır 0 ayı yazısı, son satır bilgi bandı
#   (yazılar resmin üstüne, altındaki iki pikselin ortalama renginde basılır).
#   Renkler tek tamsayı: 0xRRGGBB. P[y*PW+x] boşsa o satırın gökyüzü rengi (SKYR) kullanılır.
# =====================================================================
HUDEND=$CUR
HY=$(( ROWS - 1 )); PW=$W; PH=$(( ROWS * 2 ))
declare -a P SKYR VG
hsh() { HV=$(( ($1 * 1103515245 + 12345) & 0x7fffffff )); HV=$(( (HV ^ (HV >> 13)) % 1000 )); }
mix() { local a=$1 b=$2 p=$3 q=$(( 100 - $3 ))
  MIX=$(( ( (((a>>16)&255)*q + ((b>>16)&255)*p)/100 << 16 ) | ( (((a>>8)&255)*q + ((b>>8)&255)*p)/100 << 8 ) | ( ((a&255)*q + (b&255)*p)/100 ) )); }
getp() { GP=${P[$2*PW+$1]:-${SKYR[$2]}}; }
tri() { TRI=$(( ($1 % $2 + $2) % $2 )); (( TRI > $2/2 )) && TRI=$(( $2 - TRI )); }

sky() { local y; for (( y=0; y<PH; y++ )); do mix $1 $2 $(( y*100/(PH-1) )); SKYR[y]=$MIX; done; }

disc() {  # disc cx cy yarıçap renk hale_renk hale_genişlik
  local cx=$1 cy=$2 rr=$3 c=$4 gc=$5 gw=$6 x y dx dy d2
  local R1=$(( rr*rr + rr )) R2=$(( (rr+gw)*(rr+gw) ))
  for (( y=cy-rr-gw; y<=cy+rr+gw; y++ )); do (( y < 0 || y >= PH )) && continue
    for (( x=cx-rr-gw; x<=cx+rr+gw; x++ )); do (( x < 0 || x >= PW )) && continue
      dx=$(( x-cx )); dy=$(( y-cy )); d2=$(( dx*dx + dy*dy ))
      if (( d2 <= R1 )); then P[y*PW+x]=$c
      elif (( d2 <= R2 )); then getp $x $y; mix $GP $gc $(( 55*(R2-d2)/(R2-R1) )); P[y*PW+x]=$MIX; fi
    done
  done; }

stars() {  # stars adet en_alt_piksel_satırı
  local k x y c
  for (( k=0; k<$1; k++ )); do
    hsh $(( k*7919 + 11 )); x=$(( HV*PW/1000 )); hsh $(( k*104729 + 3 )); y=$(( HV % $2 ))
    case $(( (k + T) % 4 )) in 0) c=0x4a5080;; 1|3) c=0x9aa2d4;; 2) c=0xf6f6ff;; esac
    [ -z "${P[y*PW+x]}" ] && P[y*PW+x]=$c
  done; }

ridge() {  # ridge taban yükseklik dönem1 dönem2 faz renk_üst renk_alt  (sıradağ katmanı)
  local base=$1 amp=$2 p1=$3 p2=$4 ph=$5 ct=$6 cb=$7 x y h top t1
  for (( x=0; x<PW; x++ )); do
    tri $(( x + ph )) $p1; t1=$TRI; tri $(( x*2 + ph*3 )) $p2
    h=$(( base + amp*(t1*200/p1 + TRI*100/p2)/150 )); (( h < 1 )) && continue
    top=$(( PH - h )); (( top < 0 )) && top=0
    for (( y=top; y<PH; y++ )); do mix $ct $cb $(( (y-top)*100/h )); P[y*PW+x]=$MIX; done
  done; }

pines() {  # pines taban dönem faz renk  (çam ormanı katmanı: üçgen tepeler)
  local base=$1 per=$2 ph=$3 c=$4 x y h
  for (( x=0; x<PW; x++ )); do
    tri $(( x + ph )) $per; hsh $(( (x + ph)/per * 13 + ph )); h=$(( base + TRI*2 + HV % 2 ))
    for (( y=PH-h; y<PH; y++ )); do (( y >= 0 )) && P[y*PW+x]=$c; done
  done; }

city() {  # city başlangıç_x renk pencere_renk  (şehir silüeti + yanan pencereler)
  local x0=$1 c=$2 wc=$3 x y k h top
  for (( x=x0; x<PW; x++ )); do
    k=$(( x/5 )); hsh $(( k*7 + 3 )); h=$(( 3 + HV % (PH-3) ))
    (( x % 5 == 4 && HV % 3 == 0 )) && continue
    top=$(( PH - h ))
    for (( y=top; y<PH; y++ )); do
      P[y*PW+x]=$c
      if (( y > top && x % 2 == 1 && y % 2 == 0 )); then hsh $(( x*31 + y*17 + T/15 )); (( HV < 320 )) && P[y*PW+x]=$wc; fi
    done
  done; }

water() {  # water başlangıç_y renk_üst renk_alt yansıma_x(-1=yok) yansıma_renk
  local y0=$1 x y base c d
  for (( y=y0; y<PH; y++ )); do
    mix $2 $3 $(( (y-y0)*100/(PH-y0) )); base=$MIX
    for (( x=0; x<PW; x++ )); do
      tri $(( x + T*(y-y0+1) + y*7 )) 9
      if (( TRI >= 4 )); then mix $base 0xffffff 14; c=$MIX; else c=$base; fi
      if (( $4 >= 0 )); then
        d=$(( x - $4 )); (( d < 0 )) && d=$(( -d ))
        if (( d < 2 + (y-y0)*2 )); then hsh $(( y*13 + T*3 + x*7 )); (( HV < 450 )) && { mix $c $5 60; c=$MIX; }; fi
      fi
      P[y*PW+x]=$c
    done
  done; }

cloud() {  # cloud cx cy yarı_en yarı_boy renk yoğunluk%
  local cx=$1 cy=$2 rx=$3 ry=$4 c=$5 al=$6 x y dx dy q
  for (( y=cy-ry; y<=cy+ry; y++ )); do (( y < 0 || y >= PH )) && continue
    for (( x=cx-rx; x<=cx+rx; x++ )); do (( x < 0 || x >= PW )) && continue
      dx=$(( x-cx )); dy=$(( y-cy )); q=$(( dx*dx*100/(rx*rx) + dy*dy*100/(ry*ry) ))
      (( q <= 100 )) && { getp $x $y; mix $GP $c $(( al*(130-q)/130 )); P[y*PW+x]=$MIX; }
    done
  done; }

# ---- sahne kurgusu ----
FLASH=0; ZZ=0
case "$SCN" in
  gece)
    sky 0x070a26 0x40286a
    stars 46 $(( PH-2 ))
    disc $(( PW*80/100 )) 1 2 0xf8f2d6 0x8a96c8 4
    ridge 2 3 41 23 5 0x231a48 0x150f30
    city $(( PW*55/100 )) 0x0b0a18 0xffd27a;;
  gok)
    sky 0x2a6cc0 0xa6d6f2
    disc $(( PW*86/100 )) 1 2 0xfff8d8 0xffe08a 5
    for k in 0 1 2 3; do cloud $(( (k*61 + T/2*(1 + k%2)) % (PW+24) - 12 )) $(( 1 + k%2 )) $(( 6 + k%3*2 )) 1 0xffffff 85; done
    ridge 2 3 37 19 3 0x4d9a5c 0x37784a
    ridge 1 2 23 13 11 0x2f6b3c 0x1d4a2a;;
  uyku)
    sky 0x020310 0x0e1534
    stars 18 $(( PH-2 ))
    disc $(( PW*70/100 )) 2 3 0xfaf4dc 0x5a6aa0 5
    ridge 2 2 47 29 9 0x0c1024 0x060812; ZZ=1;;
  dusunce)
    sky 0x04051a 0x101a3a
    stars 30 $(( PH-2 ))
    for (( x=0; x<PW; x++ )); do                       # kutup ışıkları: dalgalanan renk perdesi
      tri $(( x*2 + T*3 )) 40; cyy=$(( 1 + TRI*3/20 ))
      tri $(( x + T )) 60; if (( TRI < 12 )); then ac=0x3cffa0; elif (( TRI < 22 )); then ac=0x3cc8ff; else ac=0xb45cff; fi
      for (( y=0; y<PH-2; y++ )); do
        d=$(( y - cyy )); (( d < 0 )) && d=$(( -d ))
        if (( d <= 2 )); then getp $x $y; mix $GP $ac $(( (3-d)*22 )); P[y*PW+x]=$MIX; fi
      done
    done
    ridge 2 3 43 21 7 0x0a0c1e 0x050610;;
  komut)
    sky 0x010604 0x03140a
    for (( x=0; x<PW; x++ )); do                       # kod yağmuru: dikey akan yeşil izler
      hsh $(( x*17 + 5 )); (( HV >= 720 )) && continue
      sp=$(( 1 + HV % 3 )); L=$(( 3 + HV % 5 )); per=$(( PH + L + 5 )); hd=$(( (T*sp*2 + HV) % per ))
      for (( y=0; y<PH; y++ )); do
        dd=$(( hd - y ))
        if (( dd == 0 )); then P[y*PW+x]=0xd8ffe2
        elif (( dd > 0 && dd < L )); then mix 0x03140a 0x2cff6a $(( (L-dd)*100/L )); P[y*PW+x]=$MIX; fi
      done
    done;;
  kod)                                                 # synthwave gün batımı + perspektif ızgara
    hz=$(( PH/2 )); cx=$(( PW/2 ))
    sky 0x1a0638 0xff4f8a
    for (( y=hz; y<PH; y++ )); do SKYR[y]=0x12052a; done
    for (( y=0; y<hz; y++ )); do
      for (( x=cx-6; x<=cx+6; x++ )); do
        dx=$(( x-cx )); dy=$(( y-hz )); (( dx*dx + dy*dy > 40 )) && continue
        (( y >= hz-2 && (y + T) % 2 == 0 )) && continue
        mix 0xffe45a 0xff3c8c $(( y*100/hz )); P[y*PW+x]=$MIX
      done
    done
    for (( y=hz; y<PH; y++ )); do
      for (( x=0; x<PW; x++ )); do
        t=$(( (x - cx)*4 / (y - hz + 1) ))
        if (( (t % 9 + 9) % 9 == 0 )); then P[y*PW+x]=0xff3cc8
        elif (( (y - hz + T) % 3 == 0 )); then P[y*PW+x]=0x9a2a8a; fi
      done
    done;;
  okuma)                                               # sisli çam ormanı
    sky 0x5a7280 0xb8c8c8
    pines 3 7 2 0x7a9298
    pines 2 5 9 0x4a666a
    for (( x=0; x<PW; x++ )); do tri $(( x + T )) 30; y=$(( PH-3 )); getp $x $y; mix $GP 0xdde6e6 $(( 20 + TRI )); P[y*PW+x]=$MIX; done
    pines 1 4 4 0x1a3028;;
  web)                                                 # ay ışığında dalgalı deniz
    sky 0x08142e 0x24467a
    stars 22 $(( PH/2 ))
    mx=$(( PW*72/100 ))
    disc $mx 1 1 0xfff6d8 0x8aa0d0 3
    water $(( PH/2 )) 0x123a6a 0x041228 $mx 0xfff2c8;;
  ajan)                                                # kuyruklu yıldızlar
    sky 0x0a0624 0x1c1a44
    stars 28 $(( PH-2 ))
    for k in 0 1 2; do
      hx=$(( (T*(3+k) + k*47) % (PW+20) - 10 )); hy=$(( 1 + k*2 ))
      if (( k % 2 )); then cc=0x5ce0d0; else cc=0xb48cff; fi
      for (( j=0; j<10; j++ )); do
        x=$(( hx - j )); y=$(( hy + j/5 )); (( x < 0 || x >= PW || y >= PH )) && continue
        if (( j == 0 )); then P[y*PW+x]=0xffffff; else getp $x $y; mix $GP $cc $(( 100 - j*10 )); P[y*PW+x]=$MIX; fi
      done
    done
    ridge 1 2 39 17 3 0x0c0a1c 0x06050e;;
  soru)                                                # gün batımında deniz
    sky 0x2a1446 0xff8a3c
    disc $(( PW*62/100 )) $(( PH/2 )) 3 0xffd27a 0xff9a4a 4
    water $(( PH/2 + 1 )) 0x6a2a3a 0x1a0a1e $(( PW*62/100 )) 0xffc060;;
  arac)                                                # alacakaranlık dağları
    sky 0x1a1a3c 0x7a5070
    stars 12 2
    ridge 3 3 45 25 1 0x3a2c50 0x2a2040
    ridge 1 3 29 15 13 0x1a1428 0x0e0a18;;
  yagmur|firtina)
    if [ "$SCN" = firtina ]; then sky 0x1a0610 0x44121e; dc=0x0c0408; rc=0xd08a8a; (( T % 5 == 0 )) && FLASH=1
    else sky 0x1a2230 0x3c4a5e; dc=0x10141c; rc=0x8eb0d8; fi
    if (( FLASH )); then for (( y=0; y<PH; y++ )); do mix ${SKYR[y]} 0xffffff 18; SKYR[y]=$MIX; done; fi
    for k in 0 1 2 3 4; do cloud $(( (k*37 + T) % (PW+20) - 10 )) 0 $(( 8 + k%3*3 )) 2 $dc 80; done
    ridge 1 1 31 17 5 0x0e1218 0x080a0e
    for (( x=0; x<PW; x++ )); do                       # yağmur: aşağı inen kısa çizgiler
      for (( y=1; y<PH; y++ )); do
        hsh $(( x*131 + ((y + T*4)/2)*977 )); (( HV < 105 )) && { getp $x $y; mix $GP $rc 70; P[y*PW+x]=$MIX; }
      done
    done
    if (( FLASH )); then                               # şimşek: yukarıdan zikzakla iner
      hsh $(( T*7 )); bx=$(( PW*25/100 + HV % (PW/2) ))
      for (( y=0; y<PH; y++ )); do
        hsh $(( T*13 + y*7 )); bx=$(( bx + HV % 3 - 1 ))
        (( bx >= 0 && bx < PW )) && P[y*PW+bx]=0xfffbe0
        (( bx+1 < PW )) && { getp $(( bx+1 )) $y; mix $GP 0xffe8a0 50; P[y*PW+bx+1]=$MIX; }
      done
    fi;;
esac

# =====================================================================
#   MASKOT KATMANI (oktant): hücre başına 2×4 kare piksel, yani tuvalin iki katı çözünürlük.
#   Ayı ve baykuş burada çizilir; hücrede en fazla 2 renk olur (terminal sınırı), en uzak iki renk seçilir.
#   Konumlar durum dosyasında (SF) saklanır: karakterler ışınlanmaz, hedefe yürür/uçar.
# =====================================================================
QUAD=(' ' '▘' '▝' '▀' '▖' '▌' '▞' '▛' '▗' '▚' '▐' '▜' '▄' '▙' '▟' '█')
OCT=(' ' '𜺨' '𜺫' '🮂' '𜴀' '▘' '𜴁' '𜴂' '𜴃' '𜴄' '▝' '𜴅' '𜴆' '𜴇' '𜴈' '▀' '𜴉' '𜴊' '𜴋' '𜴌' '🯦' '𜴍' '𜴎' '𜴏' '𜴐' '𜴑' '𜴒' '𜴓' '𜴔' '𜴕' '𜴖' '𜴗' '𜴘' '𜴙' '𜴚' '𜴛' '𜴜' '𜴝' '𜴞' '𜴟' '🯧' '𜴠' '𜴡' '𜴢' '𜴣' '𜴤' '𜴥' '𜴦' '𜴧' '𜴨' '𜴩' '𜴪' '𜴫' '𜴬' '𜴭' '𜴮' '𜴯' '𜴰' '𜴱' '𜴲' '𜴳' '𜴴' '𜴵' '🮅' '𜺣' '𜴶' '𜴷' '𜴸' '𜴹' '𜴺' '𜴻' '𜴼' '𜴽' '𜴾' '𜴿' '𜵀' '𜵁' '𜵂' '𜵃' '𜵄' '▖' '𜵅' '𜵆' '𜵇' '𜵈' '▌' '𜵉' '𜵊' '𜵋' '𜵌' '▞' '𜵍' '𜵎' '𜵏' '𜵐' '▛' '𜵑' '𜵒' '𜵓' '𜵔' '𜵕' '𜵖' '𜵗' '𜵘' '𜵙' '𜵚' '𜵛' '𜵜' '𜵝' '𜵞' '𜵟' '𜵠' '𜵡' '𜵢' '𜵣' '𜵤' '𜵥' '𜵦' '𜵧' '𜵨' '𜵩' '𜵪' '𜵫' '𜵬' '𜵭' '𜵮' '𜵯' '𜵰' '𜺠' '𜵱' '𜵲' '𜵳' '𜵴' '𜵵' '𜵶' '𜵷' '𜵸' '𜵹' '𜵺' '𜵻' '𜵼' '𜵽' '𜵾' '𜵿' '𜶀' '𜶁' '𜶂' '𜶃' '𜶄' '𜶅' '𜶆' '𜶇' '𜶈' '𜶉' '𜶊' '𜶋' '𜶌' '𜶍' '𜶎' '𜶏' '▗' '𜶐' '𜶑' '𜶒' '𜶓' '▚' '𜶔' '𜶕' '𜶖' '𜶗' '▐' '𜶘' '𜶙' '𜶚' '𜶛' '▜' '𜶜' '𜶝' '𜶞' '𜶟' '𜶠' '𜶡' '𜶢' '𜶣' '𜶤' '𜶥' '𜶦' '𜶧' '𜶨' '𜶩' '𜶪' '𜶫' '▂' '𜶬' '𜶭' '𜶮' '𜶯' '𜶰' '𜶱' '𜶲' '𜶳' '𜶴' '𜶵' '𜶶' '𜶷' '𜶸' '𜶹' '𜶺' '𜶻' '𜶼' '𜶽' '𜶾' '𜶿' '𜷀' '𜷁' '𜷂' '𜷃' '𜷄' '𜷅' '𜷆' '𜷇' '𜷈' '𜷉' '𜷊' '𜷋' '𜷌' '𜷍' '𜷎' '𜷏' '𜷐' '𜷑' '𜷒' '𜷓' '𜷔' '𜷕' '𜷖' '𜷗' '𜷘' '𜷙' '𜷚' '▄' '𜷛' '𜷜' '𜷝' '𜷞' '▙' '𜷟' '𜷠' '𜷡' '𜷢' '▟' '𜷣' '▆' '𜷤' '𜷥' '█')
SW=$(( PW*2 )); SH=$(( ROWS*4 ))
declare -a SP HD SC
declare -A PAL=( [o]=0x2a1608 [b]=0xa4632e [d]=0x7a4520 [l]=0xd4985c [m]=0xeed2a6 [n]=0x1a0e08 [p]=0xe09a90
  [B]=0x8a6a44 [D]=0x5a3a20 [C]=0xf2e2c0 [c]=0x9a6e3e [W]=0xfffbe8 [E]=0x120c06 [y]=0xf0a830
  [k]=0x101018 [G]=0x38f07a [g]=0xb8ffd0 [K]=0x8a8f9c [r]=0xc23a3a [w]=0xf4efe0
  [u]=0xd8404a [U]=0x9c2a34 [s]=0x3a2a1c [h]=0xff5a7a [z]=0xb8c8ff [q]=0xffe07a [e]=0xf0e6c8 [t]=0x6e4a28 [T]=0xb8814a [Y]=0xf6c21c )

plot() { (( $1 < 0 || $1 >= SW || $2 < 0 || $2 >= SH )) && return; SP[$2*SW+$1]=$3; HD[($2/4)*1000+$1/2]=1; }
blit() { local -n _rows=$1; local sx=$2 sy=$3 fl=$4 yy i w ch dx dy row
  for (( yy=0; yy<${#_rows[@]}; yy++ )); do
    row=${_rows[yy]}; w=${#row}; dy=$(( sy+yy )); (( dy < 0 || dy >= SH )) && continue
    for (( i=0; i<w; i++ )); do
      ch=${row:i:1}; [[ $ch == . ]] && continue
      if (( fl )); then dx=$(( sx+w-1-i )); else dx=$(( sx+i )); fi
      (( dx < 0 || dx >= SW )) && continue
      SP[dy*SW+dx]=${PAL[$ch]}; HD[(dy/4)*1000+dx/2]=1
    done
  done; }
hdisc() {  # hdisc cx cy r renk gölge_renk: yüksek çözünürlüklü ay/güneş
  local xx yy dx dy d2 R=$(( $3*$3 + $3 ))
  for (( yy=$2-$3; yy<=$2+$3; yy++ )); do for (( xx=$1-$3; xx<=$1+$3; xx++ )); do
    dx=$(( xx-$1 )); dy=$(( yy-$2 )); d2=$(( dx*dx + dy*dy ))
    if (( d2 <= R )); then
      if (( dx + dy >= $3 )); then plot $xx $yy $5; else plot $xx $yy $4; fi
    fi
  done; done; }

# ---- çizimler (16 geniş ayı, 12 geniş baykuş) ----
BH=( '.ddd........ddd.' 'dddd........dddd' 'dddd.bbbbbb.dddd' '.ddbbbbbbbbbbdd.'
     '.bbbwwbbbbwwbbb.' 'bbbbwwbbbbwwbbbb' 'bbbbwwbbbbwwbbbb' 'bbbbwwbbbbwwbbbb'
     '.bbbbbmnnmbbbbb.' '.bbbbmmmmmmbbbb.' '..bbbmmmmmmbbb..' '..dbbbmmmmbbbd..' )
BW1=( '.bbbllllllllbbb.' 'bbbbllllllllbbbb' '.bbbllllllllbbb.' '..bb........bb..' )
BW2=( '.bbbllllllllbbb.' 'bbbbllllllllbbbb' '.bbbllllllllbbb.' '....bb....bb....' )
BS=(  '.bbbllllllllbbb.' 'bbbbllllllllbbbb' 'bbbbbbbbbbbbbbbb' 'bbbbbbbbbbbbbbbb' )
OW=( '.TT..........TT.' '.TTT........TTT.' '.TTTTTTTTTTTTTT.' 'TTTTTTTTTTTTTTTT'
     'TTYYYYCCCCYYYYTT' 'TTYYYYCCCCYYYYTT' 'TTYYYYCCCCYYYYTT' 'TTYYYYCyyCYYYYTT'
     'TTTTCCCyyCCCTTTT' 'DTCCcCCCCCCcCCTD' 'DTCCCCCCCCCCCCTD' 'DTCCcCCCCCCcCCTD'
     '.DTTTTTTTTTTTTD.' '.DTTTTTTTTTTTTD.' '..TTTTTTTTTTTT..' '....yy....yy....' )
LAP=( '.oooooooo.' '.oGGGGGGo.' '.oGggGGGo.' '.oGGGGggo.' 'oKKKKKKKKo' 'oooooooooo' )
BOOK=( '.rwwwwwwr.' '.rwwrrwwr.' '.rrrrrrrr.' )
UMB2=( '..........wwuuuuuuwwwwww..........' '.....uwwwwwwuuuuuuwwwwwwuuuuu.....' '.uuuuuwwwwwwuuuuuuwwwwwwuuuuuuwww.' 'uu..uuww..wwuu..uuww..wwuu..uuww..' )
YLD=( '.q.' 'qqq' '.q.' )
HRT=( 'hh.hh' 'hhhhh' '.hhh.' '..h..' )
ENV=( 'ewwwwe' 'wewwew' 'wwKKww' 'wwwwww' )
Q=( 'qqq' '..q' '.qq' '...' '.q.' )
EX=( 'q' 'q' 'q' '.' 'q' )
Z1=( 'zzz' '.z.' 'zzz' )
BULB=( '.qq.' 'qqqq' 'qqqq' '.tt.' )

eyes() {  # eyes x y tür bakış: çukur sabit (2×4 krem), yalnız bebek döner; hücrede 2 renk kalır
  local x0=$1 y0=$2 e=${PAL[E]} b=${PAL[b]} ex yy p sag
  for ex in 4 10; do
    case "$4" in -1) p=0;; 1) p=1;; *) if (( ex == 4 )); then p=1; else p=0; fi;; esac   # öne bakınca içe döner
    sag=0; (( ex == 10 )) && sag=1
    ex=$(( x0 + ex ))
    case "$3" in
      acik|genis|mutlu) ;;
      *) for yy in 4 5 6 7; do plot $ex $(( y0+yy )) $b; plot $(( ex+1 )) $(( y0+yy )) $b; done;;   # kapak iner
    esac
    case "$3" in
      kapali) plot $ex $(( y0+6 )) $e; plot $(( ex+1 )) $(( y0+6 )) $e;;
      mutlu)  for yy in 5 6; do plot $ex $(( y0+yy )) $e; plot $(( ex+1 )) $(( y0+yy )) $e; done;;
      uzgun)  if (( sag )); then plot $ex $(( y0+5 )) $e; plot $(( ex+1 )) $(( y0+6 )) $e
              else plot $ex $(( y0+6 )) $e; plot $(( ex+1 )) $(( y0+5 )) $e; fi;;
      genis)  plot $(( ex+p )) $(( y0+5 )) $e;;
      *)      plot $(( ex+p )) $(( y0+5 )) $e; plot $(( ex+p )) $(( y0+6 )) $e;;
    esac
  done; }

# ---- durum dosyası: konumlar ve son duygu ----
bx=-1; ox=-1; oy=0; rk=-; rkt=0; sid0=""
[ -f "$SF" ] && read -r sid0 bx ox oy rk rkt < "$SF"
if [ "$sid0" != "$SID" ]; then bx=-1; ox=-1; oy=0; rk=-; rkt=0; fi
int bx -1; int ox -1; int oy 0; int rkt 0; int RKT 0
if [ -n "$RK" ] && [ "$RK" != "-" ] && (( RKT > rkt )); then rk=$RK; rkt=$RKT; fi
DUYGU=""; (( now - rkt < 25 )) && [ "$rk" != "-" ] && DUYGU=$rk

# ---- sahne alanı: yazıların sağı ----
WCOL=$(( TOPEND > HUDEND ? TOPEND : HUDEND ))
RL=$(( (WCOL + 2)*2 )); (( RL > SW - 76 )) && RL=$(( SW - 76 )); (( RL < 0 )) && RL=0
HOME_=$(( (SW - 18) & ~1 )); RR=$(( HOME_ - 20 )); BY=$(( SH - 16 )); RNG=$(( RR - RL )); SPOT=$(( RL + 2 ))
hsh $(( (T/11)*31 + 7 )); GEZ=$(( RL + HV*RNG/1000 ))

# ---- ne yapıyorlar: oturum durumuna göre hedef, poz ve birlikte yaptıkları ----
(( bx < 0 )) && bx=$SPOT
pose=walk; eye=acik; btx=$GEZ; step=2; tx=$HOME_; ofly=0; oeye=acik; prop=""; bub=""; env=0; look=""; lk=-1; top=0; yildiz=0; saril=0; sivaz=0
yakin=$(( ox - bx )); (( yakin < 0 )) && yakin=$(( -yakin )); yan=$(( bx + 18 )); FZ=$(( T % 48 ))
case "$ACTSC" in
  uyku)    pose=sit; eye=kapali; btx=$bx; oeye=kapali; tx=$yan; bub=zz;;
  dusunce)
    if [ "$ACTK" = mesaj ]; then btx=$bx; pose=wave; tx=$yan; env=1          # zarfı getirir
    else                                                                    # ayı volta atar, baykuş ampulü getirir
      c0=$(( RL + RNG/2 )); if (( T/9 % 2 )); then btx=$(( c0 - 12 )); else btx=$(( c0 + 12 )); fi
      if (( T % 40 < 10 )); then tx=$HOME_; bub=dusun
      else tx=$yan; btx=$bx; if (( yakin < 22 )); then bub=ampul; eye=mutlu; else bub=tasi; fi; fi
    fi;;
  komut)   btx=$SPOT; prop=laptop; tx=$(( SPOT + 28 )); look=1                # baykuş ekrana bakar, arada tezahürat
           (( T % 14 < 2 )) && { yildiz=1; ofly=1; };;
  kod)     if (( T/7 % 2 )); then btx=$RR; else btx=$RL; fi; step=6; eye=mutlu; tx=$(( bx + 24 )); ofly=1;;   # ayı baykuşu kovalar
  okuma)   btx=$SPOT; prop=kitap; tx=$(( SPOT + 18 )); look=0                 # birlikte okurlar, baykuş soru sorar
           (( T % 12 < 3 )) && { bub=bsoru; look=1; };;
  web)     btx=$GEZ
           if (( T % 24 < 12 )); then tx=$(( SW + 12 ))                        # internete uçar
           else btx=$bx; tx=$yan; env=1; (( yakin < 22 )) && { pose=wave; eye=mutlu; }; fi;;   # zarfı eline verir
  ajan)    btx=$bx; pose=wave; tx=$(( SW + 12 )); env=1;;
  soru)    btx=$bx; pose=wave; tx=$yan; bub=soru; look=0; lk=0;;
  arac)    tx=$(( bx + 26 ));;
  *)                                                                          # bekliyor: 48 sn'lik küçük hikâye
    if   (( FZ < 12 )); then :                                                # ayrı ayrı takılırlar
    elif (( FZ < 20 )); then btx=$bx; tx=$yan; (( yakin < 22 )) && { pose=wave; look=1; }      # selamlaşma
    elif (( FZ < 28 )); then btx=$bx; tx=$yan; eye=mutlu; look=1; ofly=1; pose=wave; (( T % 2 )) && yildiz=1   # çak
    elif (( FZ < 40 )); then btx=$bx; tx=$(( bx + 40 )); eye=mutlu; look=1; top=1    # top atarlar
    fi;;
esac
# hava: tek şemsiyenin altına girerler, fırtınada ayı baykuşa sarılır
SEMS=0; TITR=0
if [ "$SCN" = yagmur ] || [ "$SCN" = firtina ]; then
  SEMS=1; (( step > 2 )) && step=2; top=0; yildiz=0
  case "$ACTSC" in ajan|web|kod|komut|okuma) ;; *) btx=$bx; tx=$yan;; esac
fi
if [ "$SCN" = firtina ]; then TITR=1; saril=1; btx=$bx; tx=$yan; (( FLASH )) && { eye=genis; oeye=genis; }; fi
if (( CTX >= 75 )) && [ "$eye" = acik ]; then eye=uzgun; fi
case "$DUYGU" in
  sevgi) eye=mutlu; bub=kalp; btx=$bx; tx=$yan; lk=0; look=1; top=0;;
  uzgun) eye=uzgun; pose=sit; btx=$bx; tx=$yan; sivaz=1; top=0;;
esac
(( T % 7 == 3 )) && [ "$eye" = acik ] && eye=kapali     # ara sıra göz kırpar
(( T % 9 == 4 )) && [ "$oeye" = acik ] && oeye=kapali

# ---- hareket: çift piksel adım; baykuş ayının içine girmez ----
(( btx < RL )) && btx=$RL; (( btx > RR )) && btx=$RR; btx=$(( btx & ~1 )); bx=$(( bx & ~1 )); dirb=0; yuru=0
if (( bx < btx )); then bx=$(( bx + step )); (( bx > btx )) && bx=$btx; dirb=1; yuru=1
elif (( bx > btx )); then bx=$(( bx - step )); (( bx < btx )) && bx=$btx; dirb=-1; yuru=1; fi
(( tx > HOME_ && tx < SW )) && tx=$HOME_; tx=$(( tx & ~1 )); (( tx < bx + 18 )) && tx=$(( bx + 18 ))
(( ox < 0 )) && ox=$tx; ox=$(( ox & ~1 )); oy=0; ogit=0
if (( ox < tx )); then ox=$(( ox + 8 )); (( ox > tx )) && ox=$tx; ogit=1
elif (( ox > tx )); then ox=$(( ox - 8 )); (( ox < tx )) && ox=$tx; ogit=1; fi
(( ox < bx + 18 )) && ox=$(( bx + 18 ))
(( ogit )) && ofly=1
printf '%s %s %s %s %s %s\n' "$SID" "$bx" "$ox" "$oy" "$rk" "$rkt" > "$SF" 2>/dev/null

# ---- gök cisimleri yüksek çözünürlükte ----
case "$SCN" in
  gece) hdisc $(( PW*160/100 + 1 )) 3 5 0xf8f2d6 0xb8b49c; plot $(( PW*160/100 - 1 )) 2 0xc8c2a6; plot $(( PW*160/100 + 2 )) 1 0xd8d2b6;;
  gok)  hdisc $(( PW*172/100 + 1 )) 3 5 0xfffae0 0xffe48c;;
  uyku) hdisc $(( PW*140/100 + 1 )) 5 7 0xfaf4dc 0xbcb8a4;;
esac

# ---- ayı ----
DY=0; (( SEMS )) && DY=4; BY=$(( BY + DY ))
drawx=$bx; (( TITR && T % 2 )) && drawx=$(( bx + 2 ))
if (( yuru )); then bdy=$(( T % 2 )); else bdy=0; fi
blit BH $drawx $BY 0
if (( yuru )); then look=$dirb; elif [ -z "$look" ]; then look=1; fi
eyes $drawx $BY "$eye" "$look"
if [ "$pose" = sit ] || [ "$prop" = laptop ] || [ "$prop" = kitap ]; then
  blit BS $drawx $(( BY+12 )) 0
  (( bx == btx )) || { blit BW1 $drawx $(( BY+12 )) 0; }
elif (( yuru )) && (( T % 2 )); then blit BW2 $drawx $(( BY+12 )) 0
else blit BW1 $drawx $(( BY+12 )) 0; fi
if [ "$pose" = wave ]; then                              # el sallar
  ay=$(( 8 + DY + ((T+1)%2)*4 )); for (( yy=ay; yy<ay+4; yy++ )); do plot $(( drawx+16 )) $yy ${PAL[b]}; plot $(( drawx+17 )) $yy ${PAL[b]}; done
fi
if [ "$prop" = laptop ] && (( bx == btx )); then
  if (( T % 2 )); then PAL[g]=0xb8ffd0; else PAL[g]=0x38f07a; fi
  blit LAP $(( drawx+16 )) $(( SH-6 )) 0
  plot $(( drawx+14 + T%2 )) $(( SH-4 )) ${PAL[m]}       # patiler klavyede
elif [ "$prop" = kitap ] && (( bx == btx )); then blit BOOK $(( drawx+3 )) $(( BY+12 )) 0; fi
if (( SEMS )); then                                      # şemsiye: üst sıra tamamen onun, sap aralarında
  blit UMB2 $drawx 0 0
  for (( yy=4; yy<SH; yy++ )); do plot $(( drawx+17 )) $yy ${PAL[w]}; done
  plot $(( drawx+16 )) $(( SH-1 )) ${PAL[w]}
fi

# ---- baykuş ----
OY=0; (( SEMS && ox - bx < 24 )) && OY=4
blit OW $ox $OY 0
if (( ofly )); then                                      # kanat çırpar: yukarı / aşağı
  if (( T % 2 )); then wy=$OY; else wy=$(( OY+8 )); fi
  for (( yy=wy; yy<wy+4; yy++ )); do for dx in -2 -1 16 17; do plot $(( ox+dx )) $yy ${PAL[D]}; done; done
fi
# göz: sarı iris üstünde 2×2 göz bebeği; aynı hücrede yalnız 2 renk kalır
case "$oeye" in
  kapali) for yy in 4 5 6 7; do for dx in 2 3 4 5 10 11 12 13; do plot $(( ox+dx )) $(( OY+yy )) ${PAL[T]}; done; done
          for dx in 2 3 4 5 10 11 12 13; do plot $(( ox+dx )) $(( OY+6 )) ${PAL[D]}; done;;
  genis)  for yy in 5 6; do plot $(( ox+4 )) $(( OY+yy )) ${PAL[E]}; plot $(( ox+11 )) $(( OY+yy )) ${PAL[E]}; done;;
  *)      case $lk in -1) p1=2; p2=10;; 1) p1=4; p2=12;; *) p1=4; p2=10;; esac
          for yy in 5 6; do for dx in $p1 $(( p1+1 )) $p2 $(( p2+1 )); do plot $(( ox+dx )) $(( OY+yy )) ${PAL[E]}; done; done;;
esac
(( env )) && blit ENV $(( ox-8 )) 10 0                    # taşıdığı zarf

# ---- birlikte yaptıkları ----
if (( top )); then                                       # top: ayıdan baykuşa yay çizerek gider gelir
  tri $T 6; tx2=$(( bx + 16 + (ox - bx - 18)*TRI/3 )); case $TRI in 0|3) ty2=8;; *) ty2=4;; esac
  for yy in 0 1; do for dx in 0 1; do plot $(( tx2+dx )) $(( ty2+yy )) ${PAL[r]}; done; done
fi
(( yildiz )) && blit YLD $(( bx + 16 )) 0 0               # çak / tezahürat kıvılcımı
if (( saril )); then for yy in 13 14; do for dx in 0 1 2 3 4 5; do plot $(( ox+dx )) $yy ${PAL[b]}; done; done; fi
if (( sivaz )); then wy=$(( 8 + (T%2)*4 )); for (( yy=wy; yy<wy+4; yy++ )); do plot $(( bx+14 )) $yy ${PAL[D]}; plot $(( bx+15 )) $yy ${PAL[D]}; done; fi
# ---- baloncuklar ----
case "$bub" in
  zz)    for k in 0 1; do blit Z1 $(( drawx + 12 + k*5 )) $(( 3 - (T + k*3) % 4 )) 0; done;;
  dusun) plot $(( drawx+16 )) 3 ${PAL[z]}; plot $(( drawx+18 )) 1 ${PAL[z]};;
  tasi)  blit BULB $(( ox-6 )) 1 0;;
  ampul) blit BULB $(( bx+14 )) 0 0;;
  soru)  blit Q $(( ox-4 )) 1 0;;
  bsoru) blit Q $(( ox-4 )) 1 0;;
  kalp)  blit HRT $(( bx+14 )) $(( (T*2) % 6 )) 0;;
esac
[ "$DUYGU" = uzgun ] && blit EX $(( ox-4 )) 2 0

# ---- kenar kararması (sinema vinyeti) ----
half=$(( PW/2 ))
for (( x=0; x<PW; x++ )); do d=$(( x - half )); (( d < 0 )) && d=$(( -d )); VG[x]=$(( 100 - 38*d*d/(half*half) )); done

# ---- çizim: tuval 2 piksel, maskot hücreleri 8 piksel ----
OUT=""
for (( cy=0; cy<ROWS; cy++ )); do
  LN=""; t0=$(( 2*cy*PW )); t1=$(( (2*cy+1)*PW )); s0=${SKYR[2*cy]}; s1=${SKYR[2*cy+1]}; sy0=$(( cy*4 ))
  for (( x=0; x<PW; x++ )); do
    a=${P[t0+x]:-$s0}; c=${P[t1+x]:-$s1}; v=${VG[x]}
    ix=$(( cy*1000 + x ))
    if [ -n "${OC[ix]+set}" ]; then
      ar=$(( ((a>>16)&255)*v/100 )); ag=$(( ((a>>8)&255)*v/100 )); ab=$(( (a&255)*v/100 ))
      cr=$(( ((c>>16)&255)*v/100 )); cg=$(( ((c>>8)&255)*v/100 )); cb=$(( (c&255)*v/100 ))
      if [ -n "${OB[ix]}" ]; then bgs=${OB[ix]}
      else
        k=100; (( cy == HY )) && k=62
        bgs="${ESC}[48;2;$(( (ar+cr)*k/200 ));$(( (ag+cg)*k/200 ));$(( (ab+cb)*k/200 ))m"
      fi
      LN+="${bgs}${OF[ix]}${OC[ix]}"
    elif [ -n "${HD[ix]}" ]; then
      # zemin yalnız bu hücrede tek renge iner ve hafif kararır (en dar sınır)
      a=$(( ( ((((a>>16)&255)+((c>>16)&255))*72/200) << 16 ) | ( ((((a>>8)&255)+((c>>8)&255))*72/200) << 8 ) | ( ((a&255)+(c&255))*72/200 ) )); c=$a
      # 8 alt piksel: maskot rengi ya da altındaki tuval; en uzak iki renge indirgenir
      sx0=$(( x*2 )); A=-1; Bk=-1; cok=0
      for (( s=0; s<8; s++ )); do
        col=${SP[(sy0+(s>>1))*SW+sx0+(s&1)]}
        if [ -z "$col" ]; then if (( s < 4 )); then col=$a; else col=$c; fi; fi
        SC[s]=$col
        if (( A < 0 )); then A=$col
        elif (( col != A )); then if (( Bk < 0 )); then Bk=$col; elif (( col != Bk )); then cok=1; fi; fi
      done
      if (( cok )); then                                  # 3+ renk: A'ya en uzak olanı B seç
        en=-1
        for (( s=0; s<8; s++ )); do col=${SC[s]}
          dr=$(( ((col>>16)&255) - ((A>>16)&255) )); dg=$(( ((col>>8)&255) - ((A>>8)&255) )); db=$(( (col&255) - (A&255) ))
          dst=$(( dr*dr + dg*dg + db*db )); (( dst > en )) && { en=$dst; Bk=$col; }
        done
      fi
      m=0
      if (( Bk >= 0 )); then
        for (( s=0; s<8; s++ )); do col=${SC[s]}
          if (( col == Bk )); then m=$(( m | (1<<s) ))
          elif (( cok && col != A )); then
            dr=$(( ((col>>16)&255) - ((A>>16)&255) )); dg=$(( ((col>>8)&255) - ((A>>8)&255) )); db=$(( (col&255) - (A&255) ))
            d1=$(( dr*dr + dg*dg + db*db ))
            dr=$(( ((col>>16)&255) - ((Bk>>16)&255) )); dg=$(( ((col>>8)&255) - ((Bk>>8)&255) )); db=$(( (col&255) - (Bk&255) ))
            (( dr*dr + dg*dg + db*db < d1 )) && m=$(( m | (1<<s) ))
          fi
        done
      else Bk=$A; fi
      ar=$(( ((A>>16)&255)*v/100 )); ag=$(( ((A>>8)&255)*v/100 )); ab=$(( (A&255)*v/100 ))
      cr=$(( ((Bk>>16)&255)*v/100 )); cg=$(( ((Bk>>8)&255)*v/100 )); cb=$(( (Bk&255)*v/100 ))
      if [ -n "$WT_SESSION" ] || [ -n "$SL_OKTANT" ]; then gl=${OCT[m]}
      else  # oktant desteklemeyen terminal: 2×2 çeyrek blok, her fontta var; göz ve gaga kaybolmaz
        gl=${QUAD[ ((m|m>>2)&1) | (((m>>1|m>>3)&1)<<1) | (((m>>4|m>>6)&1)<<2) | (((m>>5|m>>7)&1)<<3) ]}
      fi
      LN+="${ESC}[38;2;${cr};${cg};${cb};48;2;${ar};${ag};${ab}m${gl}"
    else
      ar=$(( ((a>>16)&255)*v/100 )); ag=$(( ((a>>8)&255)*v/100 )); ab=$(( (a&255)*v/100 ))
      cr=$(( ((c>>16)&255)*v/100 )); cg=$(( ((c>>8)&255)*v/100 )); cb=$(( (c&255)*v/100 ))
      LN+="${ESC}[38;2;${ar};${ag};${ab};48;2;${cr};${cg};${cb}m▀"
    fi
  done
  OUT+="${LN}${R}"$'\n'
done

printf '%s' "$OUT"
exit 0
