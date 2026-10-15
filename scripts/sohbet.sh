#!/usr/bin/env bash
set -euo pipefail

# sohbet.sh — takımın mesaj akışını tek bir sohbet olarak gösterir.
#
# Kullanım:
#   sohbet.sh <takim> [--adet N] [--uye <ad>]
#
#   --adet N    Kaç mesaj gösterilsin (varsayılan 40, en yenilerden).
#   --uye <ad>  Yalnızca bu üyenin gönderdiği/aldığı mesajlar.
#
# agmsg mesajları ikili (kimden→kime) tutar; ortak bir oda yok. yayin.sh bir
# mesajı her üyeye ayrı satır olarak yazdığı için aynı yayın akışta N kez
# görünür. Bu betik aynı gönderen + aynı gövdeli satırları tek bir "yayın"
# olarak toplar, böylece akış insanın okuyabileceği bir sohbete dönüşür.
#
# Toplama penceresi 120 saniye: Windows'ta her send.sh çağrısı ~4 saniye
# sürüyor, yani 8 üyeye yapılan bir yayının damgaları 30+ saniyeye yayılıyor.
# "Aynı saniye" ölçütü bu yüzden hiçbir şeyi gruplamaz. Pencere, aynı metnin
# günler sonra yapılan ikinci bir yayınını ayrı tutacak kadar da dar.
#
# docs/building-on-agmsg.md kuralına uyar: okuma yalnızca api.sh üzerinden.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ $# -ge 1 ] || { echo "Kullanım: sohbet.sh <takim> [--adet N] [--uye <ad>]" >&2; exit 2; }

TAKIM="$1"; shift
ADET=40
UYE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --adet)
      [ $# -ge 2 ] || { echo "sohbet.sh: --adet bir sayı bekliyor" >&2; exit 2; }
      case "$2" in (*[!0-9]*|'') echo "sohbet.sh: --adet sayı olmalı: $2" >&2; exit 2 ;; esac
      ADET="$2"; shift 2 ;;
    --uye)
      [ $# -ge 2 ] || { echo "sohbet.sh: --uye bir ad bekliyor" >&2; exit 2; }
      UYE="$2"; shift 2 ;;
    *) echo "sohbet.sh: bilinmeyen seçenek: $1" >&2; exit 2 ;;
  esac
done

PY="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
[ -n "$PY" ] || { echo "sohbet.sh: python bulunamadı (akışı biçimlendirmek için gerekiyor)" >&2; exit 1; }

if [ -n "$UYE" ]; then
  HAM="$(bash "$SCRIPT_DIR/api.sh" get teams "$TAKIM" messages --agent "$UYE" --limit "$ADET" 2>/dev/null)" || true
else
  HAM="$(bash "$SCRIPT_DIR/api.sh" get teams "$TAKIM" messages --limit "$ADET" 2>/dev/null)" || true
fi

printf '%s' "$HAM" | "$PY" -c '
import sys, json

kayitlar = []
for satir in sys.stdin:
    satir = satir.strip()
    if not satir:
        continue
    try:
        kayitlar.append(json.loads(satir))
    except Exception:
        pass

if not kayitlar:
    print("Henüz mesaj yok.")
    raise SystemExit(0)

from datetime import datetime, timezone

PENCERE_SN = 120

def saniye(damga):
    try:
        return datetime.strptime(damga, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc).timestamp()
    except Exception:
        return None

# Aynı gönderen + aynı gövde + PENCERE_SN içinde = tek yayının kopyaları.
gruplar = []
for k in kayitlar:
    kimden, govde, zaman = k.get("from"), k.get("body"), k.get("at")
    birlestir = False
    if gruplar:
        (g_kimden, g_govde, g_zaman), alicilar, g_son = gruplar[-1]
        if g_kimden == kimden and g_govde == govde:
            yeni, eski = saniye(zaman), saniye(g_son)
            birlestir = (yeni is None or eski is None or abs(yeni - eski) <= PENCERE_SN)
    if birlestir:
        gruplar[-1][1].append(k.get("to"))
        gruplar[-1][2] = zaman
    else:
        gruplar.append([(kimden, govde, zaman), [k.get("to")], zaman])

for (kimden, govde, zaman), alicilar, _son in gruplar:
    saat = (zaman or "")[11:19]
    alicilar = [a for a in alicilar if a]
    if len(alicilar) > 1:
        hedef = "herkese (%d)" % len(alicilar)
    elif alicilar:
        hedef = "-> %s" % alicilar[0]
    else:
        hedef = ""
    print("[%s] %s %s" % (saat, kimden, hedef))
    for parca in (govde or "").splitlines() or [""]:
        print("    %s" % parca)
    print()
'
