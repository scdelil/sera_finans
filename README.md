# 🌱 Sera Finans — Kişisel CFO & Botanik Birikim Asistanı

**Sera Finans**, günlük bütçe yönetimini, sabit gider takibini ve su tüketimi alışkanlığını oyunlaştırılmış canlı bir botanik sera ekosistemiyle birleştiren Flutter tabanlı kişisel finans uygulamasıdır.

## ✨ Öne Çıkan Özellikler

* **🌿 Dinamik Botanik Sera (`CustomPainter`):** İlerleme barı olmadan birikim havuzuna eklenen **her ₺100**, serada yeni bir bitki, çiçek, biyolüminesans mantar, nilüfer göleti veya yeraltı kök ağı filizlendirir. Günlük limit aşılırsa yapraklar boynunu büker; birikim keyfi harcamayla sıfırlanırsa sera kırağı yer.
* **💼 Kişisel CFO Hesaplama Motoru:** Ödenmemiş sabit ihtiyaçları (yurt, fatura, erzak) kasadan otomatik kilitler; kalan net bakiyeyi kullanıcının belirlediği **para geliş gününe** bölerek kuruşu kuruşuna günlük güvenli harcama limiti çıkarır.
* **🪙 Akıllı Küsurat Yuvarlama:** Harcama girişlerinde tutarı üst onluğa tamamlayıp aradaki farkı tek dokunuşla bahçeye "can suyu" olarak aktarır.
* **⚡ Tek Dokunuşluk Sabit Gelirler:** Burs, harçlık veya maaş gibi düzenli gelirleri şablon olarak kaydedip tek tıkla kasaya işleme imkânı sunar.
* **📸 Wish Albümü (SS Panosu):** Alınmak istenen ürünlerin ekran görüntülerini kalıcı cihaz hafızasında saklar. Ürün alındığında bakiyeden düşer; almaktan vazgeçilip "bahçeye gömüldüğünde" tutarın %25'ini ödül gübresi olarak birikime ekler.
* **💧 CFO Su & Hidrasyon Hatırlatıcısı:** Günlük su tüketimini takip ederek seradaki çiy ve nem oranını artırır; uyku saatlerini koruyan arka plan bildirimleriyle (`flutter_local_notifications`) gün içinde su içmeyi hatırlatır.
* **💾 Tam Kalıcı Yerel Hafıza:** Tüm finansal kayıtlar, ayarlar ve Wish albümü görselleri `shared_preferences` ve `path_provider` ile cihazda güvenle saklanır.

## 🛠️ Teknoloji Yığını

* **Framework:** Flutter & Dart
* **Grafik & Çizim:** Özel `CustomPainter` prosedürel flora motoru
* **Yerel Depolama:** `shared_preferences`, `path_provider`
* **Medya & Bildirim:** `image_picker`, `flutter_local_notifications`, `timezone`

## 📦 Kurulum (Android APK)

Sağ taraftaki **[Releases](../../releases)** bölümünden en güncel `SeraFinans-v6.0.apk` dosyasını indirip Android cihazınıza doğrudan kurabilirsiniz.