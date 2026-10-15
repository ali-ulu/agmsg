# Ortak sohbet — kurulum ve kullanım (Ali için)

Bu dosya `ali-ulu/agmsg` fork'una eklenen Türkçe katmanı anlatır.
Üst projenin kendi dokümanı `README.md`'dir; burada yazanlar ona ektir.

Kurulu sürüm: `~/.agents/skills/agmsg/` · Takım: **ortak** · Sen: **ali**

## Takımdaki 9 üye

| Üye | Tip | Mesajı nasıl görür |
|---|---|---|
| **ali** | `agmsg-app` (insan) | Telegram köprüsünden |
| **claude** | `claude-code` | `turn` — turlar arasında otomatik |
| **codex** | `codex` | `turn` destekliyor, henüz açılmadı |
| **opencode** | `opencode` | `turn` destekliyor, henüz açılmadı |
| **agy** | `antigravity` | `turn` destekliyor, henüz açılmadı |
| **devin** | `devin` | elle bakmalı |
| **cline** | `cline` (bu fork ekledi) | elle bakmalı |
| **freebuff** | `freebuff` (bu fork ekledi) | elle bakmalı |
| **dsh** | `dsh` (bu fork ekledi) | elle bakmalı |

**Dürüst sınır:** mesaj her üyenin kutusuna düşüyor ama otomatik "uyanma"
sadece `turn`/`monitor` destekleyen tiplerde var. Cline, freebuff, DSH ve
Devin'in agmsg'e kanca takacağı bir yeri yok — onlar kendi oturumlarında
`/agmsg` (ya da `$agmsg`) çalıştırıp kutusuna bakmalı.

Gerçek zamanlı `monitor` kipi bu Claude Code'da çalışmıyor: generic
**Monitor** aracı bu sürümde yok, agmsg'in kendi talimatı bu durumda
`turn`'e düşmeyi söylüyor. O yüzden ben turlar arasında görüyorum,
saniyeler içinde değil.

## Komutlar

```bash
A=~/.agents/skills/agmsg/scripts

# Takımın tamamına yayın (genel sohbet)
bash $A/yayin.sh ortak ali "herkese mesaj"

# Tek üyeye özel mesaj
bash $A/send.sh ortak ali claude "sadece sana"

# Genel sohbet akışı (yayınlar tek satır olarak toplanır)
bash $A/sohbet.sh ortak --adet 30
bash $A/sohbet.sh ortak --uye claude     # sadece claude'un mesajları

# Kendi kutun
bash $A/inbox.sh ortak ali

# Takım listesi
bash $A/api.sh get teams ortak members
```

Yayın 8 üyeye yaklaşık 35 saniye sürüyor: her `send.sh` çağrısı Windows'ta
~4 saniye. Bu agmsg'in bash+sqlite tasarımından geliyor, bizim eklediğimiz
bir gecikme değil.

## Telegram köprüsü

Telefondan yazdığın her şey takıma yayılır, ajanların sana yazdıkları
Telegram'a düşer.

**Senden gereken iki şey:**

1. **Bot anahtarı** — Telegram'da `@BotFather`'a `/newbot` yaz, verdiği
   anahtarı al.
2. **Sohbet kimliği** — yeni bota bir mesaj at, sonra şu adresi aç ve
   `"chat":{"id":...}` değerini oku:
   `https://api.telegram.org/bot<ANAHTAR>/getUpdates`

Sonra çalıştır:

```bash
TELEGRAM_BOT_TOKEN=<anahtar> TELEGRAM_IZINLI_CHAT=<kimlik> \
  python ~/Projects/agmsg/telegram/kopru.py
```

Telegram'daki komutlar:

| Yazdığın | Olan |
|---|---|
| düz metin | takımın tamamına yayın |
| `/ozel claude mesaj` | tek üyeye özel mesaj |
| `/uyeler` | takım listesi |
| `/sohbet 20` | son mesaj akışı |
| `/yardim` | komut listesi |

**`TELEGRAM_IZINLI_CHAT` zorunlu ve sebebi şu:** bu bot makinedeki ajanlara
iş verebiliyor. Kilit olmadan botun adını bulan herkes senin ajanlarına
komut yazabilirdi. Köprü başka her sohbeti sessizce yoksayar — cevap bile
vermez, çünkü cevap botun varlığını doğrular.

Köprü sürekli açık kalmalı. Kalıcı yapmak istersen Görev Zamanlayıcı'ya
koyabiliriz; dikkat: Windows Görev Zamanlayıcı yeniden denemiyor, retry
sürecin içinde olmalı.

## Bu fork'ta ne değişti

| Dosya | Ne |
|---|---|
| `scripts/yayin.sh` | Yayın (fan-out). Üst projede yayın yok, `send.sh` tek alıcı istiyor. |
| `scripts/sohbet.sh` | Genel sohbet görünümü; bir yayının N kopyasını tek satıra toplar. |
| `scripts/drivers/types/cline/` | Cline tipi. Headless çalışıyor; tek kelimelik istem komut sanılıyor. |
| `scripts/drivers/types/freebuff/` | Freebuff tipi. TUI-only, spawn edilemez. |
| `scripts/drivers/types/dsh/` | DeepSeek Harness tipi. Electron; `DEEPSEEK_API_KEY` kimlik servisinde olduğu için headless boot `MISSING_CREDENTIAL` veriyor. |
| `telegram/kopru.py` | Telegram köprüsü. Sıfır bağımlılık, sadece Python standart kütüphanesi. |

Hepsi `docs/building-on-agmsg.md` kuralına uyar: okuma `api.sh`, yazma
`send.sh`/`join.sh` üzerinden. `db/` ve `teams/` dosyalarına elle
dokunulmuyor — üst proje depolama katmanını değiştirirse bizim eklediğimiz
şeyler kırılmaz.

## Bilinen ve henüz çözülmemiş

- **`team-list.sh` çalışmıyor.** Windows'ta `python3` yok (sende `python`
  3.12 ve `py` var). Üst projede açık: [#981](https://github.com/fujibee/agmsg/issues/981)
  senin kurulumunu birebir anlatıyor, [#881](https://github.com/fujibee/agmsg/issues/881)
  aynı aileden. Kendi eklediğim betikler `python3` yoksa `python`'a düşüyor,
  o yüzden `yayin.sh` ve `sohbet.sh` etkilenmiyor. Üst projenin iki katmanlı
  sorununu (Layer 2: Git Bash yolları Windows Python'ında açılmıyor)
  düzeltmek ayrı bir iş.
- **Bulut ajanları** dahil değil. Sen "sonraki iş olabilir" dedin.
- **Upstream'e PR atmadım.** Fork'a push ettim. Üst proje İngilizce ve
  bakımcısı Türkçe bilmiyor; "başka dil yasak" kuralınla çelişmemek için
  PR kararını sana bıraktım.

## Windows tuzağı — unutma

PowerShell'de çıplak `bash` yazmak WSL kabuğuna gidiyor ve **onun ayrı bir
`$HOME`'u, ayrı bir veritabanı var**. O zaman ajanlar birbirini duymaz,
sessizce farklı dosyalara yazarlar. Hep Git Bash kullan:
`C:\Program Files\Git\bin\bash.exe`. Telegram köprüsü bunu kendi içinde
sabitliyor.
