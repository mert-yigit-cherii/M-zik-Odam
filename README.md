# Müzik Odam v1.1.0

macOS 14 veya daha yenisi için yerel müzik oynatıcısı.

## Öne çıkanlar

- Türkçe ve English arayüzü; yalnızca ilk açılışta gösterilen kurulum akışı
- Sistem, açık ve koyu tema; vurgu rengi seçimi
- Varsayılan Müzik, Downloads ve Desktop klasörlerini veya seçtiğiniz özel klasörü tarama
- Liste ve responsive ızgara görünümü; şarkı, sanatçı ve albüm araması
- Albüm ve sanatçı detay sayfaları
- Kalıcı playlist oluşturma, yeniden adlandırma, silme ve şarkı yönetimi
- Play/Pause, seek, ses, Shuffle ve Repeat kontrolleri
- macOS Now Playing, medya tuşları ve menu bar mini player
- Gerçek 9 bantlı Equalizer (60 Hz–16 kHz) ve presetler
- Albüm kapağından türetilen Ambient Effect

MP3, AAC/M4A, WAV, AIFF, ALAC, FLAC ve macOS tarafından çözülebilen diğer yerel ses biçimleri desteklenir. Çok kanallı parçalarda EQ, kanal yapısını zorla stereo'ya çevirmemek için güvenli biçimde devre dışı kalır; parça macOS oynatıcısında oynatılır. Dolby Atmos desteği iddia edilmez.

Visualizer v1.1.0 sürümüne dahil değildir.

## Gizlilik

Müzik dosyalarınız cihazınızdan dışarı yüklenmez. Şarkı bilgilerini ve kapak görsellerini zenginleştirmek için yalnızca şarkı adı ve sanatçı bilgileri Apple iTunes Search API’sine gönderilebilir.

## Kurulum

Müzik Odam.dmg dosyasını açın ve **Müzik Odam.app** uygulamasını **Applications** klasörüne sürükleyin.

Bu sürüm Apple Developer ID ile imzalanmış veya notarize edilmiş değildir; ad-hoc imzalıdır. macOS Gatekeeper uygulamayı engellerse **System Settings → Privacy & Security → Open Anyway** yolundan açılmasına izin verin. Uygulama Apple tarafından notarize edilmiş gibi tanıtılmaz.

## Geliştirme

    swift run MuzikOdam
