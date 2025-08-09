import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'mqtt_yardimcisi_stub.dart';

class GorselYukleSayfasi extends StatefulWidget {
  const GorselYukleSayfasi({super.key});

  @override
  State<GorselYukleSayfasi> createState() => _GorselYukleSayfasiState();
}

class _GorselYukleSayfasiState extends State<GorselYukleSayfasi> {
  List<String> yuklenenUrlListesi = [];
  bool yukleniyor = false;
  bool mqttGonderiyor = false;
  bool pairDurumu = false;
  String? sonDurum;
  String? tvSerial;
  String? pairingCode;
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
      setState(() => sonDurum = "⚠️ IMGBB_API_KEY missing! Check .env file.");
    } else {
      setState(
          () => sonDurum = "✅ Configuration complete. Ready to pair with TV.");
    }
  }

  Future<String?> uploadToImgbb(Uint8List bytes, String fileName) async {
    try {
      final apiKey = dotenv.env['IMGBB_API_KEY'];

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint("❌ IMGBB_API_KEY not found!");
        setState(() => sonDurum = "❌ IMGBB API key missing!");
        return null;
      }

      final url = Uri.parse("https://api.imgbb.com/1/upload?key=$apiKey");

      if (bytes.length > 32 * 1024 * 1024) {
        debugPrint("❌ File too large: $fileName (${bytes.length} bytes)");
        return null;
      }

      debugPrint(
          "📤 Uploading: $fileName (${(bytes.length / 1024).toStringAsFixed(1)} KB)");
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        url,
        body: {"image": base64Image},
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json["success"] == true) {
          final imageUrl = json["data"]["url"];
          debugPrint("✅ Image uploaded: $fileName -> $imageUrl");
          return imageUrl;
        } else {
          final errorMsg = json["error"]?["message"] ?? "Unknown ImgBB error";
          debugPrint("❌ ImgBB API error: $errorMsg");
          return null;
        }
      } else {
        debugPrint("❌ HTTP Error ${response.statusCode}: ${response.body}");
        return null;
      }
    } catch (e, stack) {
      debugPrint("❌ Upload error: $e");
      debugPrint("📌 Stack: $stack");
      return null;
    }
  }

<<<<<<< HEAD
  // YENİ: Pair işlemi
  Future<void> pairIslemi() async {
=======
  Future<void> pairWithTV() async {
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
    setState(() {
      mqttGonderiyor = true;
      sonDurum = "🔌 Starting TV pairing...";
    });

    try {
<<<<<<< HEAD
      debugPrint("📡 Pair işlemi başlatılıyor...");

      // MQTT bağlantısını kur
      setState(() => sonDurum = "🔌 MQTT broker'a bağlanılıyor...");
=======
      // 1. Open QR scanner
      final qrData = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerScreen()),
      );

      if (qrData == null || qrData is! Map<String, dynamic>) {
        setState(() => sonDurum = "🚫 QR scan cancelled or invalid!");
        return;
      }

      // 2. Extract pairing info from QR
      tvSerial = qrData['tvSerial'] ?? qrData['serial'];
      pairingCode = qrData['pairingCode'] ?? qrData['token'];

      if (tvSerial == null || pairingCode == null) {
        setState(() => sonDurum = "❌ Invalid QR code data!");
        return;
      }

      debugPrint("🆔 QR Scanned → Serial: $tvSerial, Code: $pairingCode");

      // 3. Connect to MQTT
      setState(() => sonDurum = "🔌 Connecting to MQTT broker...");
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
      await _mqtt!.baglantiKur();

      if (!_mqtt!.baglantiDurumu) {
        throw Exception('MQTT connection failed');
      }

      setState(() => sonDurum = "✅ MQTT connected");

      // 4. Subscribe to pair response
      final responseTopic = 'tv/$tvSerial/pair_response';
      bool responseReceived = false;

<<<<<<< HEAD
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
=======
      _mqtt!.topicDinle(responseTopic, (message) {
        debugPrint("📨 Pair response received: $message");

        try {
          final response = json.decode(message);
          if (response['status'] == 'success' &&
              response['pairingCode'] == pairingCode) {
            responseReceived = true;
            setState(() {
              pairDurumu = true;
              sonDurum = "✅ Paired with TV successfully!";
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("✅ TV pairing successful!"),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
          }
        } catch (e) {
          debugPrint("Error parsing response: $e");
        }
      });

<<<<<<< HEAD
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
=======
      // 5. Send pairing request
      setState(() => sonDurum = "📨 Sending pairing request to TV...");

      final pairingRequest = json.encode({
        'action': 'pair',
        'pairingCode': pairingCode,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await _mqtt!.mesajGonder('tv/$tvSerial/pair', pairingRequest);

      // 6. Wait for response
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (responseReceived) break;
        setState(() {
          sonDurum = "⏳ Waiting for TV response... (${10 - i}s)";
        });
      }

      if (!responseReceived) {
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
        setState(() {
          sonDurum = "⚠️ No response from TV. Is the TV app running?";
          pairDurumu = false;
        });
      }
    } catch (e, stack) {
      setState(() {
        sonDurum = "❌ Pairing error: $e";
        pairDurumu = false;
      });
      debugPrint("❌ Pairing error: $e");
      debugPrint("📌 Stack: $stack");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Pairing error: $e"),
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
        sonDurum = "📁 Opening file picker...";
      });

      // Pick files - The key is to NOT save copies
      // On mobile: withData=true reads file into memory without creating copies
      // allowedExtensions helps prevent system from creating cached copies
      final sonuc = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true, // This ensures we get bytes directly in memory
        allowCompression:
            false, // Prevent any compression/processing that might save copies
      );

      if (sonuc == null || sonuc.files.isEmpty) {
        setState(() => sonDurum = "❌ No files selected");
        return;
      }

      // Process files from memory without touching the file system
      List<Uint8List> fileDataList = [];
      List<String> fileNameList = [];
      int toplamBoyut = 0;

      for (final file in sonuc.files) {
        // Use bytes that are already in memory - no file system access
        if (file.bytes != null) {
          fileDataList.add(file.bytes!);
          fileNameList.add(file.name);
          toplamBoyut += file.bytes!.length;
        } else if (!kIsWeb && file.path != null) {
          // For mobile: Read file ONCE directly into memory without creating copies
          // We use readAsBytes which doesn't create any copies
          final bytes = await io.File(file.path!).readAsBytes();
          fileDataList.add(bytes);
          fileNameList.add(file.name);
          toplamBoyut += bytes.length;
        }
      }

      if (fileDataList.isEmpty) {
        setState(() => sonDurum = "❌ No valid files to upload");
        return;
      }

      if (toplamBoyut > 100 * 1024 * 1024) {
        setState(() => sonDurum = "❌ Total file size too large (max 100MB)");
        return;
      }

      setState(() {
        yukleniyor = true;
        sonDurum = "📤 Uploading ${fileDataList.length} files...";
      });

      yuklenenUrlListesi.clear();

      int basariliSayisi = 0;
      int toplamSayi = fileDataList.length;

      // Upload directly from memory - no file system operations
      for (int i = 0; i < fileDataList.length; i++) {
        setState(() => sonDurum =
            "📤 Uploading: ${fileNameList[i]} (${i + 1}/$toplamSayi)");

        final url = await uploadToImgbb(fileDataList[i], fileNameList[i]);
        if (url != null) {
          yuklenenUrlListesi.add(url);
          basariliSayisi++;
        }

        final progress = ((i + 1) / toplamSayi * 100).round();
        setState(() => sonDurum =
            "📤 Progress: %$progress ($basariliSayisi/$toplamSayi successful)");
      }

      setState(() {
        yukleniyor = false;
        if (basariliSayisi == toplamSayi) {
          sonDurum =
              "✅ All images uploaded successfully! ($basariliSayisi/$toplamSayi)";
        } else if (basariliSayisi > 0) {
          sonDurum =
              "⚠️ Partial success: $basariliSayisi/$toplamSayi images uploaded";
        } else {
          sonDurum = "❌ No images could be uploaded";
        }
      });

      // Clear memory references to free up RAM
      fileDataList.clear();
      fileNameList.clear();
    } catch (e, stack) {
      setState(() {
        yukleniyor = false;
        sonDurum = "❌ Upload error: $e";
      });
      debugPrint("❌ Upload error: $e");
      debugPrint("📌 Stack: $stack");
    }
  }

  Future<void> mqttIleGonder() async {
    if (yuklenenUrlListesi.isEmpty) {
      setState(() => sonDurum = "⚠️ No images to send!");
      return;
    }

    if (!pairDurumu) {
      setState(() => sonDurum = "⚠️ Please pair with TV first!");
      return;
    }

    setState(() {
      mqttGonderiyor = true;
      sonDurum = "📨 Sending to TV...";
    });

    try {
      if (!_mqtt!.baglantiKontrol()) {
        setState(() => sonDurum = "🔌 Reconnecting MQTT...");
        await _mqtt!.baglantiKur();
      }

      if (!_mqtt!.baglantiDurumu) {
        throw Exception('MQTT connection failed');
      }

      setState(() => sonDurum =
          "📨 Sending ${yuklenenUrlListesi.length} images via MQTT...");

      // Send images to TV
      await _mqtt!.jsonGonder(yuklenenUrlListesi, tvSerial!);

      setState(() => sonDurum = "✅ All images sent to TV successfully!");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ ${yuklenenUrlListesi.length} images sent to TV!"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stack) {
      setState(() => sonDurum = "❌ MQTT error: $e");
      debugPrint("❌ MQTT send error: $e");
      debugPrint("📌 Stack: $stack");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Send error: $e"),
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
      pairDurumu = false;
      tvSerial = null;
      pairingCode = null;
      sonDurum = "🧹 List cleared";
    });
    _mqtt?.baglantiKapat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("📷 Image Uploader ${kIsWeb ? '(Web)' : '(Mobile)'}"),
        backgroundColor: Colors.deepOrange.shade600,
        foregroundColor: Colors.white,
        actions: [
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
                  pairDurumu ? "TV Connected" : "Not Connected",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
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
              // Status card
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

              // Pair button
              ElevatedButton.icon(
                onPressed: (yukleniyor || mqttGonderiyor) ? null : pairWithTV,
                icon: pairDurumu
                    ? const Icon(Icons.cast_connected)
                    : const Icon(Icons.qr_code_scanner),
                label: Text(
                  pairDurumu
                      ? "✅ TV Paired${tvSerial != null ? ' ($tvSerial)' : ''}"
                      : "📺 Scan TV QR Code",
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      pairDurumu ? Colors.green.shade600 : Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Select images button
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
                  yukleniyor ? "Uploading..." : "📁 Select & Upload Images",
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

              // Send to TV button - Only active when paired
              ElevatedButton.icon(
                onPressed: (yuklenenUrlListesi.isEmpty ||
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
                      ? "Sending to TV..."
                      : "📺 Send to TV (${yuklenenUrlListesi.length})",
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      pairDurumu ? Colors.green.shade600 : Colors.grey,
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
                  label: const Text("🧹 Clear List"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade600,
                    side: BorderSide(color: Colors.orange.shade600),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),

              const SizedBox(height: 20),

              // Uploaded URLs list
              if (yuklenenUrlListesi.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "📋 Uploaded Images (${yuklenenUrlListesi.length})",
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
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
                              subtitle: const Text("✅ Upload complete"),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, size: 16),
                                onPressed: () {
                                  setState(() {
                                    yuklenenUrlListesi.removeAt(index);
                                    sonDurum = "🗑️ URL removed";
                                  });
                                },
                                tooltip: "Remove",
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
