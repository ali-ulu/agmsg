#!/usr/bin/env bash
set -euo pipefail

# yayin.sh — bir mesajı takımdaki herkese gönderir (genel sohbet).
#
# Kullanım:
#   yayin.sh <takim> <kimden> <mesaj>              # gövde TEK argüman olarak
#   yayin.sh <takim> <kimden> --govde-dosya <yol>  # gövde dosyadan
#   yayin.sh <takim> <kimden> --govde -            # gövde stdin'den
#
# agmsg'in send.sh'ı tek bir kayıtlı alıcı istiyor; yayın diye bir şey yok.
# Bu betik üye listesini api.sh'tan okuyup gönderenin dışındaki herkese
# send.sh ile ayrı ayrı yazar (fan-out). Böylece mevcut okuma yüzeylerinin
# (inbox.sh, check-inbox.sh, watch.sh ve teslim kancaları) hiçbiri
# değişmeden çalışmaya devam eder.
#
# docs/building-on-agmsg.md kuralına uyar: okuma api.sh üzerinden, yazma
# mevcut send.sh üzerinden. db/ ve teams/ dosyalarına elle dokunulmaz.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 3 ]; then
  echo "Kullanım: yayin.sh <takim> <kimden> <mesaj>" >&2
  echo "          yayin.sh <takim> <kimden> --govde-dosya <yol>" >&2
  echo "          yayin.sh <takim> <kimden> --govde -" >&2
  exit 2
fi

TAKIM="$1"
KIMDEN="$2"
shift 2

# Gövdeyi topla. Dosya/stdin biçimleri tercih edilir: konumsal metin
# çağıranın kabuğundan geçer ve içindeki ` ya da $( ) çalışıp sessizce
# kaybolur (agmsg'in send.sh'ında #507/#1101 olarak kayıtlı aynı tuzak).
case "${1:-}" in
  --govde-dosya)
    [ $# -ge 2 ] || { echo "yayin.sh: --govde-dosya bir yol bekliyor" >&2; exit 2; }
    [ -r "$2" ] || { echo "yayin.sh: dosya okunamıyor: $2" >&2; exit 2; }
    GOVDE="$(cat -- "$2")"
    ;;
  --govde)
    [ "${2:-}" = "-" ] || { echo "yayin.sh: --govde yalnızca - (stdin) kabul eder" >&2; exit 2; }
    GOVDE="$(cat)"
    ;;
  *)
    GOVDE="$1"
    ;;
esac

[ -n "${GOVDE//[[:space:]]/}" ] || { echo "yayin.sh: mesaj boş" >&2; exit 2; }

PY="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
[ -n "$PY" ] || { echo "yayin.sh: python bulunamadı (üye listesini ayrıştırmak için gerekiyor)" >&2; exit 1; }

# Üye listesi: api.sh JSONL döndürür, her satır bir üye.
#
# `tr -d '\r'` şart: Windows'ta Python stdout'u metin kipinde açar ve her
# satır sonunu \r\n yapar. O \r üye adının sonuna yapışır, send.sh "codex\r"
# diye bir üye arar ve "kayıtlı değil" der — üstelik hata metninde \r
# görünmediği için mesaj "codex kayıtlı değil (kayıtlı: ... codex ...)"
# gibi kendisiyle çelişen bir şeye dönüşür.
UYELER="$(bash "$SCRIPT_DIR/api.sh" get teams "$TAKIM" members 2>/dev/null \
  | "$PY" -c '
import sys, json
for satir in sys.stdin:
    satir = satir.strip()
    if not satir:
        continue
    try:
        print(json.loads(satir)["name"])
    except Exception:
        pass
' | tr -d '\r')" || true

[ -n "$UYELER" ] || { echo "yayin.sh: '$TAKIM' takımında üye bulunamadı" >&2; exit 1; }

# Gövdeyi geçici dosyadan geçir: --body-file kabuk genişletmesini tamamen
# devre dışı bırakır, çok satırlı ve Türkçe karakterli gövdeyi bozmaz.
GECICI="$(mktemp)"
trap 'rm -f "$GECICI"' EXIT
printf '%s' "$GOVDE" > "$GECICI"

GIDEN=0
ATLANAN=0
BASARISIZ=0
HATALAR=""

while IFS= read -r UYE; do
  [ -n "$UYE" ] || continue
  if [ "$UYE" = "$KIMDEN" ]; then
    ATLANAN=$((ATLANAN + 1))
    continue
  fi
  if CIKTI="$(bash "$SCRIPT_DIR/send.sh" "$TAKIM" "$KIMDEN" "$UYE" --body-file "$GECICI" 2>&1)"; then
    GIDEN=$((GIDEN + 1))
  else
    BASARISIZ=$((BASARISIZ + 1))
    HATALAR="${HATALAR}  $UYE: $(printf '%s' "$CIKTI" | head -1)
"
  fi
done <<< "$UYELER"

echo "Yayın gönderildi: $GIDEN üye (gönderen atlandı: $ATLANAN)"
if [ "$BASARISIZ" -gt 0 ]; then
  echo "Ulaşılamayan: $BASARISIZ" >&2
  printf '%s' "$HATALAR" >&2
  exit 1
fi
