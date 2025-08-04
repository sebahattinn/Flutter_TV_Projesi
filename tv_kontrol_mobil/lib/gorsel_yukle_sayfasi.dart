// Bu kodlar mevcut kodlarınızın üzerine eklenecek güncellemeler

// mqtt_yardimcisi.dart - Bu dosyayı zaten doğru yazmışsınız, değişiklik gerekmiyor

// gorsel_yukle_sayfasi.dart - Güncellenmiş versiyon
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'mqtt_yardimcisi_stub.dart'; // Stub import - platform'a göre otomatik seçilecek

class GorselYukleSayfasi extends StatefulWidget {
  const GorselYukleSayfasi({super.key});

  @override
  State<GorselYukleSayfasi> createState() => _GorselYukleSayfasiState();
}

class _GorselYukleSayfasiState extends State<GorselYukleSayfasi> {
  List<String> yuklenenUrlListesi = [];
  bool yukleniyor = false;
  bool mqttGonderiyor = false;
  bool pairDurumu = false; // Pair durumu takibi
  String? sonDurum;
  MqttYardimcisi? _mqtt;

  @override
  void initState() {
    super.initState();
    _mqtt = MqttYardimcisi();
    _yapilandirmaKontrol();
  }

  @override
  void dispose() {
    _mqtt?.baglantiKapat();
    super.dispose();
  }

  void _yapilandirmaKontrol() {
    final imgbbKey = dotenv.env['IMGBB_API_KEY'];
    if (imgbbKey == null || imgbbKey.isEmpty) {
      setState(
        () => sonDurum = "⚠️ IMGBB_API_KEY eksik! .env dosyasını kontrol edin.",
      );
    } else {
      setState(
        () => sonDurum =
            "✅ Yapılandırma tamamlandı. Pair işlemi için Android TV'yi hazırlayın.",
      );
    }
  }

  Future<String?> uploadToImgbb(PlatformFile file) async {
    try {
      final apiKey = dotenv.env['IMGBB_API_KEY'];

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint("❌ IMGBB_API_KEY bulunamadı!");
        setState(() => sonDurum = "❌ IMGBB API key eksik!");
        return null;
      }

      final url = Uri.parse("https://api.imgbb.com/1/upload?key=$apiKey");

      // Dosya verilerini al
      final Uint8List? bytes =
          file.bytes ??
          (file.path != null ? await io.File(file.path!).readAsBytes() : null);

      if (bytes == null) {
        debugPrint("❌ Dosya verisi alınamadı: ${file.name}");
        return null;
      }

      // Dosya boyutu kontrolü (ImgBB max 32MB)
      if (bytes.length > 32 * 1024 * 1024) {
        debugPrint("❌ Dosya çok büyük: ${file.name} (${bytes.length} bytes)");
        return null;
      }

      debugPrint(
        "📤 Yükleniyor: ${file.name} (${(bytes.length / 1024).toStringAsFixed(1)} KB)",
      );
      final base64Image = base64Encode(bytes);

      final response = await http
          .post(
            url,
            body: {"image": base64Image},
            headers: {"Content-Type": "application/x-www-form-urlencoded"},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json["success"] == true) {
          final imageUrl = json["data"]["url"];
          debugPrint("✅ Görsel yüklendi: ${file.name} -> $imageUrl");
          return imageUrl;
        } else {
          final errorMsg =
              json["error"]?["message"] ?? "Bilinmeyen ImgBB hatası";
          debugPrint("❌ ImgBB API hatası: $errorMsg");
          return null;
        }
      } else {
        debugPrint("❌ HTTP Hatası ${response.statusCode}: ${response.body}");
        return null;
      }
    } catch (e, stack) {
      debugPrint("❌ uploadToImgbb Hata: $e");
      debugPrint("📌 Stack: $stack");
      return null;
    }
  }

  // YENİ: Pair işlemi
  Future<void> pairIslemi() async {
    setState(() {
      mqttGonderiyor = true;
      sonDurum = "🔌 Android TV ile eşleşme başlatılıyor...";
    });

    try {
      debugPrint("📡 Pair işlemi başlatılıyor...");

      // MQTT bağlantısını kur
      setState(() => sonDurum = "🔌 MQTT broker'a bağlanılıyor...");
      await _mqtt!.baglantiKur();

      if (!_mqtt!.baglantiDurumu) {
        throw Exception('MQTT bağlantısı kurulamadı');
      }

      setState(() => sonDurum = "✅ MQTT bağlantısı kuruldu");

      // Kısa bir bekleme
      await Future.delayed(const Duration(milliseconds: 500));

      // Pair response dinleme topic'ini ayarla
      final responseTopic =
          '${_mqtt!.topicPrefix}${_mqtt!.tvSerial}/pair_response';

      // Pair response dinlemeye başla
      _mqtt!.topicDinle(responseTopic, (message) {
        debugPrint("📨 Pair response alındı: $message");
        if (message.toLowerCase().contains('paired') ||
            message.toLowerCase().contains('ok')) {
          setState(() {
            pairDurumu = true;
            sonDurum = "✅ Android TV ile eşleşme tamamlandı!";
          });

          // Başarılı pair bildirim
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("✅ Android TV ile eşleşme başarılı!"),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      });

      // Pair mesajını gönder
      setState(
        () => sonDurum = "📨 Android TV'ye eşleşme isteği gönderiliyor...",
      );
      await _mqtt!.pairGonder();

      // 10 saniye bekle pair response için
      bool responseAlindi = false;
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (pairDurumu) {
          responseAlindi = true;
          break;
        }
        setState(
          () => sonDurum = "⏳ Android TV response bekleniyor... (${10 - i}s)",
        );
      }

      if (!responseAlindi && !pairDurumu) {
        setState(() {
          sonDurum =
              "⚠️ Android TV'den yanıt alınamadı. TV uygulaması açık mı?";
          pairDurumu = false;
        });
      }
    } catch (e, stack) {
      setState(() {
        sonDurum = "❌ Pair hatası: $e";
        pairDurumu = false;
      });
      debugPrint("❌ Pair işlemi hatası: $e");
      debugPrint("📌 Stack: $stack");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Eşleşme hatası: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() => mqttGonderiyor = false);
    }
  }

  Future<void> gorselleriSecVeYukle() async {
    try {
      setState(() {
        sonDurum = "📁 Dosya seçici açılıyor...";
      });

      final sonuc = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true,
        allowedExtensions: null,
      );

      if (sonuc == null || sonuc.files.isEmpty) {
        setState(() => sonDurum = "❌ Hiç dosya seçilmedi");
        return;
      }

      // Dosya boyutu kontrolü
      final toplamBoyut = sonuc.files.fold<int>(
        0,
        (sum, file) => sum + (file.bytes?.length ?? 0),
      );

      if (toplamBoyut > 100 * 1024 * 1024) {
        // 100MB limit
        setState(
          () => sonDurum = "❌ Toplam dosya boyutu çok büyük (max 100MB)",
        );
        return;
      }

      setState(() {
        yukleniyor = true;
        sonDurum = "📤 ${sonuc.files.length} dosya yükleniyor...";
      });

      yuklenenUrlListesi.clear();

      debugPrint(
        "📂 ${sonuc.files.length} adet görsel seçildi. Yükleme başlıyor...",
      );

      int basariliSayisi = 0;
      int toplamSayi = sonuc.files.length;

      for (int i = 0; i < sonuc.files.length; i++) {
        final file = sonuc.files[i];
        setState(
          () => sonDurum = "📤 Yükleniyor: ${file.name} (${i + 1}/$toplamSayi)",
        );

        final url = await uploadToImgbb(file);
        if (url != null) {
          yuklenenUrlListesi.add(url);
          basariliSayisi++;
        }

        // Progress göster
        final progress = ((i + 1) / toplamSayi * 100).round();
        setState(
          () => sonDurum =
              "📤 İlerleme: %$progress ($basariliSayisi/$toplamSayi başarılı)",
        );
      }

      setState(() {
        yukleniyor = false;
        if (basariliSayisi == toplamSayi) {
          sonDurum =
              "✅ Tüm görseller başarıyla yüklendi! ($basariliSayisi/$toplamSayi)";
        } else if (basariliSayisi > 0) {
          sonDurum =
              "⚠️ Kısmi başarı: $basariliSayisi/$toplamSayi görsel yüklendi";
        } else {
          sonDurum = "❌ Hiçbir görsel yüklenemedi";
        }
      });

      debugPrint("📊 Yükleme tamamlandı: $basariliSayisi/$toplamSayi başarılı");
    } catch (e, stack) {
      setState(() {
        yukleniyor = false;
        sonDurum = "❌ Yükleme hatası: $e";
      });
      debugPrint("❌ gorselleriSecVeYükle Hata: $e");
      debugPrint("📌 Stack: $stack");
    }
  }

  Future<void> mqttIleGonder() async {
    if (yuklenenUrlListesi.isEmpty) {
      setState(() => sonDurum = "⚠️ Gönderilecek görsel yok!");
      return;
    }

    if (!pairDurumu) {
      setState(() => sonDurum = "⚠️ Önce Android TV ile eşleşme yapın!");
      return;
    }

    setState(() {
      mqttGonderiyor = true;
      sonDurum = "📨 Android TV'ye gönderiliyor...";
    });

    try {
      debugPrint("📡 MQTT ile gönderim başlatılıyor...");

      // MQTT bağlantısını kontrol et
      if (!_mqtt!.baglantiKontrol()) {
        setState(() => sonDurum = "🔌 MQTT yeniden bağlanıyor...");
        await _mqtt!.baglantiKur();
      }

      if (!_mqtt!.baglantiDurumu) {
        throw Exception('MQTT bağlantısı kurulamadı');
      }

      setState(
        () => sonDurum =
            "📨 ${yuklenenUrlListesi.length} görsel MQTT ile gönderiliyor...",
      );

      debugPrint("📨 Gönderilecek URL'ler:");
      for (int i = 0; i < yuklenenUrlListesi.length; i++) {
        debugPrint("👉 [${i + 1}] ${yuklenenUrlListesi[i]}");
      }

      // JSON formatında gönder
      await _mqtt!.jsonGonder(yuklenenUrlListesi);

      setState(
        () => sonDurum = "✅ Tüm görseller MQTT ile başarıyla gönderildi!",
      );
      debugPrint("✅ MQTT gönderimi tamamlandı.");

      // Başarılı gönderim sonrası bilgilendirme
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ ${yuklenenUrlListesi.length} görsel Android TV'ye gönderildi!",
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stack) {
      setState(() => sonDurum = "❌ MQTT hatası: $e");
      debugPrint("❌ MQTT gönderim hatası: $e");
      debugPrint("📌 Stack: $stack");

      // Hata durumunda kullanıcıya bilgi ver
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ MQTT gönderim hatası: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() => mqttGonderiyor = false);
    }
  }

  Future<void> temizle() async {
    setState(() {
      yuklenenUrlListesi.clear();
      pairDurumu = false; // Pair durumunu da resetle
      sonDurum = "🧹 Liste temizlendi";
    });
  }

  void _yapilandirmaGoster() {
    final imgbbKey = dotenv.env['IMGBB_API_KEY'];
    final mqttBroker = kIsWeb
        ? (dotenv.env['MQTT_WEB_BROKER'] ?? dotenv.env['MQTT_BROKER'])
        : (dotenv.env['MQTT_BROKER'] ?? dotenv.env['MQTT_HOST']);
    final mqttPort = dotenv.env['MQTT_PORT'];
    final tvSerial = dotenv.env['TV_SERIAL'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("🔧 Yapılandırma Bilgileri"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ayarSatiri("IMGBB API Key", imgbbKey),
              _ayarSatiri("MQTT Broker", mqttBroker),
              _ayarSatiri("MQTT Port", mqttPort),
              _ayarSatiri("TV Serial", tvSerial),
              _ayarSatiri("Platform", kIsWeb ? "Web" : "Mobile"),
              _ayarSatiri(
                "MQTT Durumu",
                _mqtt?.baglantiDurumu == true ? "Bağlı" : "Bağlı değil",
              ),
              _ayarSatiri(
                "Pair Durumu",
                pairDurumu ? "Eşleşmiş" : "Eşleşmemiş",
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Tamam"),
          ),
          if (_mqtt != null)
            TextButton(
              onPressed: () {
                _mqtt!.debugBilgileri();
                Navigator.pop(context);
              },
              child: const Text("Debug Bilgileri"),
            ),
        ],
      ),
    );
  }

  Widget _ayarSatiri(String baslik, String? deger) {
    final mevcut = deger != null && deger.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            mevcut ? Icons.check_circle : Icons.error,
            color: mevcut ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "$baslik: ${mevcut ? (deger.length > 20 ? '${deger.substring(0, 20)}...' : deger) : '❌ Eksik'}",
              style: TextStyle(
                color: mevcut ? Colors.green.shade700 : Colors.red.shade700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("📷 Görsel Yükleyici ${kIsWeb ? '(Web)' : '(Mobile)'}"),
        backgroundColor: Colors.deepOrange.shade600,
        foregroundColor: Colors.white,
        actions: [
          // Pair durumu göstergesi
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: pairDurumu ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  pairDurumu ? Icons.cast_connected : Icons.cast,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  pairDurumu ? "TV Bağlı" : "TV Yok",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _yapilandirmaGoster,
            tooltip: "Yapılandırma Bilgileri",
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepOrange.shade50, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Durum kartı
              if (sonDurum != null)
                Card(
                  elevation: 2,
                  color: sonDurum!.startsWith('❌')
                      ? Colors.red.shade50
                      : sonDurum!.startsWith('✅')
                      ? Colors.green.shade50
                      : sonDurum!.startsWith('⚠️')
                      ? Colors.orange.shade50
                      : Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (yukleniyor || mqttGonderiyor)
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            sonDurum!,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: sonDurum!.startsWith('❌')
                                  ? Colors.red.shade700
                                  : sonDurum!.startsWith('✅')
                                  ? Colors.green.shade700
                                  : sonDurum!.startsWith('⚠️')
                                  ? Colors.orange.shade700
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // YENİ: Pair butonu
              ElevatedButton.icon(
                onPressed: (yukleniyor || mqttGonderiyor) ? null : pairIslemi,
                icon: pairDurumu
                    ? const Icon(Icons.cast_connected)
                    : const Icon(Icons.cast),
                label: Text(
                  pairDurumu
                      ? "✅ Android TV Eşleşmiş"
                      : "📺 Android TV ile Eşleş",
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: pairDurumu
                      ? Colors.green.shade600
                      : Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Görsel seçme butonu
              ElevatedButton.icon(
                onPressed: (yukleniyor || mqttGonderiyor)
                    ? null
                    : gorselleriSecVeYukle,
                icon: yukleniyor
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.folder_open),
                label: Text(
                  yukleniyor ? "Yükleniyor..." : "📁 Görselleri Seç ve Yükle",
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // MQTT gönderim butonu - Sadece pair yapıldıysa aktif
              ElevatedButton.icon(
                onPressed:
                    (yuklenenUrlListesi.isEmpty ||
                        mqttGonderiyor ||
                        yukleniyor ||
                        !pairDurumu)
                    ? null
                    : mqttIleGonder,
                icon: mqttGonderiyor
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  mqttGonderiyor
                      ? "Android TV'ye Gönderiliyor..."
                      : "📺 Android TV'ye Gönder (${yuklenenUrlListesi.length})",
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: pairDurumu
                      ? Colors.green.shade600
                      : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              if (yuklenenUrlListesi.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: (yukleniyor || mqttGonderiyor) ? null : temizle,
                  icon: const Icon(Icons.clear_all),
                  label: const Text("🧹 Listeyi Temizle"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade600,
                    side: BorderSide(color: Colors.orange.shade600),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),

              const SizedBox(height: 20),

              // Yüklenen URL'ler listesi
              if (yuklenenUrlListesi.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "📋 Yüklenen Görseller (${yuklenenUrlListesi.length})",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange.shade700,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: yuklenenUrlListesi.length,
                          itemBuilder: (context, index) => Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.deepOrange.shade100,
                                child: Text(
                                  "${index + 1}",
                                  style: TextStyle(
                                    color: Colors.deepOrange.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                yuklenenUrlListesi[index],
                                style: const TextStyle(fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: const Text("✅ Yükleme tamamlandı"),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      debugPrint(
                                        "URL açılıyor: ${yuklenenUrlListesi[index]}",
                                      );
                                    },
                                    tooltip: "URL'yi Aç",
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 16),
                                    onPressed: () {
                                      setState(() {
                                        yuklenenUrlListesi.removeAt(index);
                                        sonDurum = "🗑️ URL kaldırıldı";
                                      });
                                    },
                                    tooltip: "Kaldır",
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
