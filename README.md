# Müzik Odam

Mac’inizdeki müzik dosyalarını çalmak için kişisel, yerel bir mini oynatıcı.
Dosyalarınız uygulamanın dışına yüklenmez veya paylaşılmaz.

## Çalıştırma

Terminal’i bu klasörde açıp aşağıdaki komutu çalıştırın:

```sh
swift run MuzikOdam
```

İlk çalıştırmada derleme birkaç saniye sürebilir; sonraki çalıştırmalar daha hızlıdır.

## Özellikler

- Başlangıçta Mac'inizdeki `Müzik` klasörünü tarama; seçilen klasörü 12 saniyede bir yeniden tarama
- Yeni bulunan parçalarda gömülü etiketleri okuma ve MusicBrainz üzerinden başlık, sanatçı, albüm, yıl ve kapak bilgisi arama
- MP3, M4A, AAC, WAV, AIFF, FLAC, OGG/OGA, Opus, ALAC, CAF, WMA ve diğer yaygın uzantıları kütüphaneye ekleme
- Kütüphane listesi ve parça silme
- Oynat/duraklat, ileri/geri parça
- İlerleme çubuğu üzerinden sarma
- Ses seviyesi denetimi
- Sistem, açık veya koyu görünüm; pembe, mor, mavi veya turuncu vurgu rengi

> Not: Kütüphane tüm listelenen uzantıları tarar. Bir dosyanın çalınabilirliği macOS'un yerleşik medya çözücüsüne bağlıdır; desteklenmeyen bir kodek için uygulama hata mesajı gösterir.

Bu proje macOS 14 veya daha yeni bir sürüm hedefler.
