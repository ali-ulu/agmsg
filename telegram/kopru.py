#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""agmsg <-> Telegram koprusu.

Ali telefonundan Telegram'a yazar, mesaj takimdaki butun ajanlara yayilir;
ajanlarin Ali'ye yazdiklari Telegram'a duser. Tek sohbet, her yerden.

Calistirma:
    TELEGRAM_BOT_TOKEN=... TELEGRAM_IZINLI_CHAT=... python telegram/kopru.py

Zorunlu ortam degiskenleri:
    TELEGRAM_BOT_TOKEN   @BotFather'dan alinan bot anahtari.
    TELEGRAM_IZINLI_CHAT Komut kabul edilecek TEK sohbet kimligi (Ali'nin
                         sohbeti). Bu kilit olmadan botu bulan herkes
                         makinedeki ajanlara is verebilir, o yuzden
                         zorunludur ve baska her sohbet sessizce yoksayilir.

Secimli:
    AGMSG_TAKIM          Takim adi (varsayilan: ortak).
    AGMSG_BEN            Ali'nin takimdaki uye adi (varsayilan: ali).
    AGMSG_SKILL_DIR      agmsg kurulum dizini
                         (varsayilan: ~/.agents/skills/agmsg).
    KOPRU_ARALIK         Gelen kutusu kac saniyede bir okunsun (varsayilan 5).

Telegram komutlari:
    (duz metin)          Takimin tamamina yayin.
    /ozel <uye> <mesaj>  Tek bir uyeye ozel mesaj.
    /uyeler              Takim listesi.
    /sohbet [adet]       Son mesaj akisi.
    /yardim              Komut listesi.

Disa bagimliligi yoktur: yalnizca Python standart kutuphanesi kullanilir,
Telegram'a uzun yoklama (long polling) ile baglanilir. agmsg tarafina
docs/building-on-agmsg.md kuralina uyarak dokunur - okuma api.sh, yazma
send.sh/yayin.sh uzerinden; db/ ve teams/ dosyalarina elle dokunulmaz.
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.telegram.org/bot%s/%s"

TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
IZINLI = os.environ.get("TELEGRAM_IZINLI_CHAT", "").strip()
TAKIM = os.environ.get("AGMSG_TAKIM", "ortak").strip()
BEN = os.environ.get("AGMSG_BEN", "ali").strip()
SKILL_DIR = os.path.expanduser(
    os.environ.get("AGMSG_SKILL_DIR", "~/.agents/skills/agmsg"))
try:
    ARALIK = max(2, int(os.environ.get("KOPRU_ARALIK", "5")))
except ValueError:
    ARALIK = 5

# Git Bash'i sabitle. PowerShell'den ya da PATH'i farkli bir surecten
# cagrildiginda ciplak `bash` WSL kabuguna dusuyor; onun $HOME'u ve
# veritabani ayri oldugu icin ajanlar baska bir DB'ye konusur.
BASH = os.environ.get("AGMSG_BASH", r"C:\Program Files\Git\bin\bash.exe")
if not os.path.exists(BASH):
    BASH = "bash"


def cik(mesaj):
    sys.stderr.write("kopru: %s\n" % mesaj)
    raise SystemExit(1)


def kabuk(betik, *argumanlar, govde=None):
    """agmsg betigini calistirir, (basarili, cikti) doner."""
    yol = os.path.join(SKILL_DIR, "scripts", betik)
    if not os.path.exists(yol):
        return False, "betik bulunamadi: %s" % yol
    komut = [BASH, yol] + list(argumanlar)
    gecici = None
    try:
        if govde is not None:
            # Govdeyi dosyadan gecir: konumsal metin kabuktan gecerken
            # icindeki ` ya da $( ) calisir ve sessizce kaybolur.
            import tempfile
            tut = tempfile.NamedTemporaryFile(
                "w", suffix=".txt", delete=False, encoding="utf-8")
            tut.write(govde)
            tut.close()
            gecici = tut.name
            komut += ["--govde-dosya" if betik == "yayin.sh" else "--body-file",
                      gecici]
        sonuc = subprocess.run(
            komut, capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=300)
        cikti = (sonuc.stdout or "") + (sonuc.stderr or "")
        return sonuc.returncode == 0, cikti.strip()
    except subprocess.TimeoutExpired:
        return False, "zaman asimi (300 sn)"
    except Exception as hata:  # noqa: BLE001 - kullaniciya tasinacak
        return False, "%s" % hata
    finally:
        if gecici:
            try:
                os.unlink(gecici)
            except OSError:
                pass


def tg(yontem, **veri):
    """Telegram API cagrisi; hata durumunda None doner."""
    gonder = urllib.parse.urlencode(
        {k: v for k, v in veri.items() if v is not None}).encode("utf-8")
    istek = urllib.request.Request(API % (TOKEN, yontem), data=gonder)
    try:
        with urllib.request.urlopen(istek, timeout=70) as yanit:
            return json.loads(yanit.read().decode("utf-8"))
    except urllib.error.HTTPError as hata:
        govde = hata.read().decode("utf-8", "replace")[:200]
        sys.stderr.write("kopru: Telegram %s -> %s %s\n"
                         % (yontem, hata.code, govde))
    except Exception as hata:  # noqa: BLE001 - ag hatasi, dongu surmeli
        sys.stderr.write("kopru: Telegram %s -> %s\n" % (yontem, hata))
    return None


def yaz(metin):
    """Telegram'a mesaj yazar; uzun metni parcalar (4096 siniri).

    True/False doner: her parca gitmediyse False. Cagiran bunu kontrol
    ETMEK ZORUNDA - gonderim basarisizken imleci ilerletmek mesaji kalici
    olarak kaybeder (bir sonraki dongude "zaten gorulmus" sayilir).
    """
    tamam = True
    for bas in range(0, max(len(metin), 1), 3500):
        yanit = tg("sendMessage", chat_id=IZINLI,
                   text=metin[bas:bas + 3500] or " ")
        if not (yanit and yanit.get("ok")):
            tamam = False
    return tamam


def uyeler():
    tamam, cikti = kabuk("api.sh", "get", "teams", TAKIM, "members")
    if not tamam:
        return []
    adlar = []
    for satir in cikti.splitlines():
        satir = satir.strip()
        if not satir.startswith("{"):
            continue
        try:
            adlar.append(json.loads(satir)["name"])
        except Exception:
            pass
    return adlar


IMLEC_DOSYA = os.path.expanduser("~/.agmsg-telegram-imlec")


# Gorulen mesaj kimliklerinin son GECMIS_SINIR tanesi. Imlec tek bir sayi
# OLAMAZ: api.sh'in dondurdugu `id` artan bir tamsayi degil, UUID string
# (docs/building-on-agmsg.md ornegi "id":1234 gosteriyor ama gerceklesen
# deger 01a14201-1e60-784c-... bicimli). Siralanabilir bir imlec olmadigi
# icin gorulenler listesi tutuluyor.
GECMIS_SINIR = 2000

# Her okumada api.sh'tan istenen mesaj sayisi. GECMIS_SINIR bundan belirgin
# olcude buyuk olmali, yoksa pencerede duran bir mesaj imlecten dusup
# Telegram'a ikinci kez gonderilir.
PENCERE = 300


def imlec_oku():
    """Gorulen kimlik listesi; dosya yoksa None (ilk kosum)."""
    try:
        with open(IMLEC_DOSYA, encoding="utf-8") as dosya:
            return [s.strip() for s in dosya if s.strip()]
    except Exception:
        return None


def imlec_yaz(liste):
    try:
        with open(IMLEC_DOSYA, "w", encoding="utf-8") as dosya:
            dosya.write("\n".join(liste[-GECMIS_SINIR:]))
    except OSError as hata:
        sys.stderr.write("kopru: imlec yazilamadi: %s\n" % hata)


def gelen_kutusu():
    """Ali'ye gelen yeni mesajlari Telegram'a tasir.

    inbox.sh degil api.sh kullanilir: olculen surelerde inbox.sh 11.4 sn,
    api.sh ayni veriyi 1.3 sn'de veriyor. inbox.sh ayrica mesajlari
    "okundu" isaretliyor, yani ajanin kendi gelen kutusunu tuketirdi.
    Burada salt okuma yapilip hangi mesaja kadar gelindigi kendi imlec
    dosyasinda tutulur.
    """
    # Pencere 50 degil 300: bir yayin her alici icin ayri satir yazdigi
    # icin 9 uyelik bir takimda tek yayin ~8 satir demek. 50'lik pencere
    # ~6 yayinda dolar ve henuz iletilmemis bir mesaj penceresinin
    # disinda kalip sessizce atlanir.
    tamam, cikti = kabuk("api.sh", "get", "teams", TAKIM, "messages",
                         "--agent", BEN, "--limit", str(PENCERE))
    if not tamam:
        return

    gorulen = imlec_oku()
    ilk_kosum = gorulen is None
    if gorulen is None:
        gorulen = []
    gorulen_kume = set(gorulen)

    yeni = []
    iletilecek = []  # yalnizca Telegram'a GIDECEK olanlarin kimlikleri
    for satir in cikti.splitlines():
        satir = satir.strip()
        if not satir.startswith("{"):
            continue
        try:
            kayit = json.loads(satir)
        except Exception:
            continue
        kimlik = kayit.get("id")
        if not kimlik or kimlik in gorulen_kume:
            continue
        gorulen_kume.add(kimlik)
        # Yalnizca bana GELEN mesajlar; kendi gonderdiklerim Telegram'a
        # geri dusmesin. Iletilmesi gerekmeyenler dogrudan gorulmus sayilir.
        if kayit.get("to") != BEN or kayit.get("from") == BEN:
            gorulen.append(kimlik)
            continue
        yeni.append(kayit)
        iletilecek.append(kimlik)

    # Ilk kosumda gecmisi Telegram'a bosaltma: her seyi gorulmus say.
    if ilk_kosum:
        imlec_yaz(gorulen + iletilecek)
        return

    if yeni:
        parcalar = []
        for kayit in yeni:
            parcalar.append("%s (%s):\n%s" % (kayit.get("from"),
                                              (kayit.get("at") or "")[11:19],
                                              kayit.get("body") or ""))
        if yaz("\n\n".join(parcalar)):
            gorulen.extend(iletilecek)
        else:
            # Gonderim basarisiz: bu kimlikleri GORULMUS SAYMA. Imleci
            # ilerletmek mesaji kalici olarak kaybederdi; boylece bir
            # sonraki dongude tekrar denenir.
            sys.stderr.write("kopru: %d mesaj Telegram'a gonderilemedi, "
                             "imlec ilerletilmedi\n" % len(yeni))

    imlec_yaz(gorulen)


def ozel_gonder(hedef, govde):
    """Tek bir uyeye ozel mesaj."""
    if hedef not in uyeler():
        yaz("'%s' takimda yok. uyeler yazarak listeye bak." % hedef)
        return
    tamam, cikti = kabuk("send.sh", TAKIM, BEN, hedef, govde=govde)
    yaz("%s uyesine gonderildi." % hedef if tamam
        else "Gonderilemedi: %s" % cikti)


def komut_isle(metin):
    metin = metin.strip()
    if not metin:
        return

    # Slash'siz tek kelimelik komutlar: telefonda / yazmak zahmetli.
    # Yalnizca TAM eslesmede komut sayilir, boylece "uyeler" diye baslayan
    # normal bir yayin mesaji komuta donusmez.
    kisayol = {"yardim": "/yardim", "uyeler": "/uyeler", "sohbet": "/sohbet"}
    if metin.lower() in kisayol:
        metin = kisayol[metin.lower()]

    if metin.startswith("/yardim") or metin.startswith("/start"):
        yaz("agmsg koprusu - takim: %s, sen: %s\n\n"
            "Slash ZORUNLU DEGIL.\n\n"
            "Ne yazarsan ne olur:\n"
            "  duz metin         herkese yayin\n"
            "  @claude mesaj     sadece claude'a\n"
            "  claude: mesaj     sadece claude'a\n"
            "  uyeler            takim listesi\n"
            "  sohbet            son mesaj akisi\n"
            "  yardim            bu liste\n\n"
            "Slash'li uzun bicimler de calisir: /ozel <uye> <mesaj>, "
            "/uyeler, /sohbet [adet]." % (TAKIM, BEN))
        return

    if metin.startswith("/uyeler"):
        liste = uyeler()
        if liste:
            yaz("Takim %s (%d uye):\n%s"
                % (TAKIM, len(liste), "\n".join("  " + a for a in liste)))
        else:
            yaz("Uye listesi okunamadi.")
        return

    if metin.startswith("/sohbet"):
        parcalar = metin.split()
        adet = "20"
        if len(parcalar) > 1 and parcalar[1].isdigit():
            adet = parcalar[1]
        tamam, cikti = kabuk("sohbet.sh", TAKIM, "--adet", adet)
        yaz(cikti if cikti else "Akis bos.")
        return

    if metin.startswith("/ozel"):
        parcalar = metin.split(None, 2)
        if len(parcalar) < 3:
            yaz("Kullanim: /ozel <uye> <mesaj>  (ya da kisayol: "
                "@claude mesaj / claude: mesaj)")
            return
        ozel_gonder(parcalar[1], parcalar[2])
        return

    # Slash'siz kisayollar. Telefonda / yazmak zahmetli, o yuzden ozel
    # mesajin iki dogal bicimi de kabul edilir:
    #   @claude mesaj
    #   claude: mesaj
    # "claude:" bicimi yalnizca iki noktadan onceki kelime GERCEKTEN bir
    # uye adiysa ozel sayilir; "dikkat: sunu yapin" gibi normal bir yayin
    # mesaji boylece yanlislikla ozel mesaja donusmez.
    if metin.startswith("@"):
        parcalar = metin[1:].split(None, 1)
        if len(parcalar) == 2 and parcalar[0] in uyeler():
            ozel_gonder(parcalar[0], parcalar[1])
            return

    if ":" in metin.split("\n")[0]:
        bas, _, kalan = metin.partition(":")
        bas = bas.strip()
        kalan = kalan.strip()
        if bas and kalan and " " not in bas and bas in uyeler():
            ozel_gonder(bas, kalan)
            return

    # Duz metin: takimin tamamina yayin.
    tamam, cikti = kabuk("yayin.sh", TAKIM, BEN, govde=metin)
    yaz(cikti if cikti else ("Yayinlandi." if tamam else "Yayinlanamadi."))


def main():
    if not TOKEN:
        cik("TELEGRAM_BOT_TOKEN tanimli degil. @BotFather'dan bir bot acip "
            "anahtarini bu degiskene koy.")
    if not IZINLI:
        cik("TELEGRAM_IZINLI_CHAT tanimli degil. Bu kilit olmadan botu bulan "
            "herkes ajanlara is verebilir. Kendi sohbet kimligini ogrenmek "
            "icin bota bir mesaj yaz ve sunu cagir: "
            "https://api.telegram.org/bot<TOKEN>/getUpdates")
    if not os.path.isdir(SKILL_DIR):
        cik("agmsg kurulumu bulunamadi: %s" % SKILL_DIR)

    sys.stderr.write("kopru: takim=%s ben=%s aralik=%ss bash=%s\n"
                     % (TAKIM, BEN, ARALIK, BASH))
    yaz("Kopru ayakta. Takim: %s. Yazdigin her sey ajanlara yayilir. "
        "/yardim ile komutlar." % TAKIM)

    offset = None
    son_okuma = 0.0
    while True:
        yanit = tg("getUpdates", offset=offset, timeout=30,
                   allowed_updates=json.dumps(["message"]))
        if yanit and yanit.get("ok"):
            for guncelleme in yanit.get("result", []):
                offset = guncelleme["update_id"] + 1
                mesaj = guncelleme.get("message") or {}
                sohbet = str((mesaj.get("chat") or {}).get("id", ""))
                metin = mesaj.get("text")
                if not metin:
                    continue
                if sohbet != IZINLI:
                    # Izinsiz sohbet: sessizce yoksay, cevap da verme -
                    # cevap botun varligini dogrular.
                    sys.stderr.write("kopru: izinsiz sohbet yoksayildi: %s\n"
                                     % sohbet)
                    continue
                try:
                    komut_isle(metin)
                except Exception as hata:  # noqa: BLE001 - dongu surmeli
                    sys.stderr.write("kopru: komut hatasi: %s\n" % hata)
                    yaz("Komut islenemedi: %s" % hata)

        if time.time() - son_okuma >= ARALIK:
            son_okuma = time.time()
            try:
                gelen_kutusu()
            except Exception as hata:  # noqa: BLE001 - dongu surmeli
                sys.stderr.write("kopru: gelen kutusu hatasi: %s\n" % hata)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.stderr.write("\nkopru: kapatildi\n")
