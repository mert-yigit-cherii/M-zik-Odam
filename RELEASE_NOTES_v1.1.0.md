# Müzik Odam v1.1.0

## Öne çıkanlar

- Daha stabil oynatma ve çalınamayan dosyalar için güvenli fallback
- İlk açılış kurulum akışı, Türkçe / English desteği ve tema seçimi
- Varsayılan veya özel müzik klasörü seçimi
- Liste / ızgara görünümü, arama, albüm ve sanatçı detayları
- Geliştirilmiş playlist oluşturma, düzenleme ve oynatma akışı
- macOS Now Playing, medya tuşları ve menu bar mini player
- Gerçek 9 bant Equalizer ve presetler
- Albüm kapağından renk alan Ambient Effect
- Büyük kütüphaneler için arka plan tarama, sınırlı kapak önizlemeleri ve modern AVFoundation API'leri

## Teknik notlar

- Çok kanallı parçalarda EQ, kanal yapısını korumak için devre dışı kalır ve macOS oynatıcı fallback'i kullanılır.
- Visualizer v1.1.0'a dahil değildir.
- Müzik dosyaları cihaz dışına yüklenmez; metadata ve kapak zenginleştirmesi için şarkı adı ile sanatçı bilgisi Apple iTunes Search API'sine gönderilebilir.
