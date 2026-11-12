# Komando FPS

Commandos tarzı gizlilik oyunu, **birinci şahıs** (oyuncu gözünden). Godot 4.3 + GDScript.
Hedef platformlar: **Android** ve **PC** (Windows / Linux).

Kardeş proje [Komando](https://github.com/malisah61/komando) ile aynı bölüm dosyalarını
(`levels/bolum0–6.json`) ve aynı oyun mantığını kullanır. Mantık 2D'den 3D'ye taşındı.
2D'de 1 piksel, 3D'de 5 cm'ye karşılık gelir.

## Komando'dan taşınanlar
- **Nöbetçi yapay zekâsı** (`scripts/guard3d.gd`) şu durumlardan geçer: devriye → şüphe → araştırma → çok noktalı arama → çatışma → sirene koşma.
  - Fark edilme kademeli artar. Hızı mesafe, çömelme, rütbe ve alarm seviyesine bağlıdır.
  - Asker çevresini sezer, şüphelendikten sonra bir süre tetikte kalır.
  - Yaralanınca siper alır, oyuncuyu kuşatır, yakındakilere seslenir. Subay düdük çalar.
  - Silah sesini, taşı ve ıslığı duyar. Arama yaparken arkadaşlarıyla noktaları paylaşır ve kaçtığın yöne göre tahminli arar.
  - Cesedi fark eder, kaybolan nöbet arkadaşını fark eder. Bayıltılan asker ayılır, bağlanan ayılmaz. Bazı askerler anahtar düşürür.
  - Rütbeler: er, kış, SS (elit), subay, kule nöbetçisi.
- **Görüş artık gerçek 3D.** Askerin göz hizasından ışın atılır. Alçak siperin (kum torbası, sandık) arkasında çömelen oyuncu gerçekten görünmez. Çalılık görüşü keser, ama yakındaki asker çalıyı delip görür.
- **Alarm sistemi** (`scripts/main.gd`): sarı ve kırmızı alarm var. Bir asker sirene koşar; onu yolda durdurursan takviye gelmez. Kırmızı alarmda kışladan takviye çıkar.
- **Görevler** (`scripts/mission3d.gd`) Komando'daki türlerin aynısı: ulaş, al, kurtar, patlat, edin, sabotaj, çıkış.

## FPS'e özel
- Çömelme kamerayı alçaltır. Çalılıkta çömelirsen gizlenirsin.
- **Fark edilme göstergesi:** Seni görmeye başlayan askerin yönünde, dolan bir ok belirir.
- **Taktik harita** (TAB / HARİTA düğmesi): Oyunu durdurur ve haritayı yukarıdan gösterir. Çatılar gizlenir, askerlerin ışınla hesaplanmış görüş alanları çizilir. Commandos'taki planlama anı budur.
- Silahlar:
  - Bıçak: arkadan ya da asker habersizken tek vuruşta öldürür, sessizdir.
  - Yumruk: askeri bayıltır.
  - Tabanca: gürültülüdür, kafaya isabet 2,6 kat hasar verir.
  - Taş: atıldığı yere askerin dikkatini çeker.
- Ceset taşıyabilir, çalılığa bırakıp saklayabilirsin. Bayıltılan askeri bağlayabilirsin. Kilitli kapıyı anahtarla açarsın.

## Kontroller
**PC**
- WASD: yürü, fare: bak
- Sol tık: silahı kullan, E veya sağ tık: etkileşim
- C / Ctrl: çömel, Shift: koş
- 1–4 / Q / tekerlek: silah değiştir
- Z: ıslık, H: ilk yardım, TAB: taktik harita, ESC: duraklat

**Android**
- Sol taraf: sanal joystick, sağ taraf: sürükleyerek bak
- Düğmeler: ATEŞ, E, ÇÖMEL, KOŞ, SİLAH, ISLIK, HARİTA, MENÜ

## Test
```
godot --headless -s res://tests/sim.gd -- --test-level=res://levels/bolum0.json
xvfb-run godot --rendering-driver opengl3 -s res://tests/shot.gd -- --test-level=res://levels/bolum1.json --out=/tmp/k
```
`sim.gd` her bölümü kurar ve şunları denetler: navmesh oluşuyor mu, devriye yürüyor mu, asker önündeki oyuncuyu görüyor mu, arkadan bıçak sessiz mi, görev ve çıkış çalışıyor mu. GitHub Actions bu testi her push'ta yedi bölümün hepsinde çalıştırır. Testler geçerse APK ile Windows ve Linux zip'leri **Releases → son-surum** altına yüklenir.

## Sıradaki adımlar
- CC0 3D asker ve komando modelleri (Quaternius), animasyonlar
- Takım: birden fazla komando arasında geçiş ve taktik haritadan emir verme
- Kayıt ve yükleme (çoklu kayıt yeri, ölünce yeniden yükleme)
- Dikenli tel kesme, projektörler, el bombası, ayak izi takibi (Komando'da var, burada henüz yok)
- Ses efektleri
