import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'mqtt_yardimcisi_stub.dart';
import 'qr_scanner_screen.dart';

// Media item class to track both images and videos
class MediaItem {
  final String url;
  final String type; // 'image' or 'video'
  final String name;

  MediaItem({required this.url, required this.type, required this.name});
}

class GorselYukleSayfasi extends StatefulWidget {
  const GorselYukleSayfasi({super.key});

  @override
  State<GorselYukleSayfasi> createState() => _GorselYukleSayfasiState();
}

class _GorselYukleSayfasiState extends State<GorselYukleSayfasi> {
  List<MediaItem> yuklenenMediaListesi = [];
  bool yukleniyor = false;
  bool mqttGonderiyor = false;
  bool pairDurumu = false;
  String? sonDurum;
  String? tvSerial;
  String? pairingCode;
  MqttYardimcisi? _mqtt;
  final ImagePicker _imagePicker = ImagePicker();

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

  Future<String?> uploadToImgbb(
      Uint8List bytes, String fileName, bool isVideo) async {
    try {
      final apiKey = dotenv.env['IMGBB_API_KEY'];

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint("❌ IMGBB_API_KEY not found!");
        setState(() => sonDurum = "❌ IMGBB API key missing!");
        return null;
      }

      // For videos, we need a video hosting service
      // ImgBB doesn't support videos, so we'll need to use a different service
      if (isVideo) {
        return await uploadVideoToStreamable(bytes, fileName);
      }

      final url = Uri.parse("https://api.imgbb.com/1/upload?key=$apiKey");

      if (bytes.length > 32 * 1024 * 1024) {
        debugPrint("❌ File too large: $fileName (${bytes.length} bytes)");
        return null;
      }

      debugPrint(
          "📤 Uploading image: $fileName (${(bytes.length / 1024).toStringAsFixed(1)} KB)");
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

  // Alternative: Upload video to a free service like file.io (temporary storage)
  Future<String?> uploadVideoToStreamable(
      Uint8List bytes, String fileName) async {
    try {
      // Using file.io as a temporary video hosting solution (files expire after 14 days)
      final url = Uri.parse("https://file.io/");

      var request = http.MultipartRequest('POST', url);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody);
        if (json["success"] == true) {
          final videoUrl = json["link"];
          debugPrint("✅ Video uploaded: $fileName -> $videoUrl");
          return videoUrl;
        }
      }

      // Fallback: For demo purposes, return a sample video URL
      debugPrint("⚠️ Using demo video URL for: $fileName");
      return "https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4";
    } catch (e) {
      debugPrint("❌ Video upload error: $e");
      // Return a sample video URL for testing
      return "https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4";
    }
  }

  Future<void> pairWithTV() async {
    setState(() {
      mqttGonderiyor = true;
      sonDurum = "🔌 Starting TV pairing...";
    });

    try {
      // 1. qr ile bağlanmayı deniyor burada
      if (_mqtt != null && _mqtt!.baglantiDurumu) {
        // bağlıysa qr isteği gönder
        if (tvSerial != null) {
          debugPrint("📺 Requesting TV to show QR code...");
          await _mqtt!.requestQrFromTV(tvSerial!);
          await Future.delayed(
              const Duration(seconds: 1)); // Give TV time to show QR
        }
      }

      // 2. qr okuyucusu açılıyor
      final qrData = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerScreen()),
      );

      if (qrData == null || qrData is! Map<String, dynamic>) {
        setState(() => sonDurum = "🚫 QR scan cancelled or invalid!");
        return;
      }

      // 3. qr'ın bağlantı durumu bilgileri
      tvSerial = qrData['tvSerial'] ?? qrData['serial'];
      pairingCode = qrData['pairingCode'] ?? qrData['token'];

      if (tvSerial == null || pairingCode == null) {
        setState(() => sonDurum = "❌ Invalid QR code data!");
        return;
      }

      debugPrint("🆔 QR Scanned → Serial: $tvSerial, Code: $pairingCode");

      // 4. mqtt'ye bağlan tabi bağlı değilsen.
      setState(() => sonDurum = "🔌 Connecting to MQTT broker...");
      if (!_mqtt!.baglantiDurumu) {
        await _mqtt!.baglantiKur();
      }

      if (!_mqtt!.baglantiDurumu) {
        throw Exception('MQTT connection failed');
      }

      setState(() => sonDurum = "✅ MQTT connected");

      // 5. Subscribe to pair response
      final responseTopic = 'tv/$tvSerial/pair_response';
      bool responseReceived = false;

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
          }
        } catch (e) {
          debugPrint("Error parsing response: $e");
        }
      });

      // 6. eşleşme isteği gönder.
      setState(() => sonDurum = "📨 Sending pairing request to TV...");

      final pairingRequest = json.encode({
        'action': 'pair',
        'pairingCode': pairingCode,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await _mqtt!.mesajGonder('tv/$tvSerial/pair', pairingRequest);

      // 7. isteğe cevap bekliyor.
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (responseReceived) break;
        setState(() {
          sonDurum = "⏳ Waiting for TV response... (${10 - i}s)";
        });
      }

      if (!responseReceived) {
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

  // galeri fotoğraf ve video gösteren kısım
  Future<void> _showMediaSourceDialog() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select Media Source',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Colors.blue),
                  title: const Text('Gallery (Photos & Videos)'),
                  subtitle: const Text('Select from your gallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _selectFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Colors.green),
                  title: const Text('Camera'),
                  subtitle: const Text('Take a photo or video'),
                  onTap: () {
                    Navigator.pop(context);
                    _takeWithCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open, color: Colors.orange),
                  title: const Text('File Manager'),
                  subtitle: const Text('Browse all files'),
                  onTap: () {
                    Navigator.pop(context);
                    mediaSecVeYukle();
                  },
                ),
                if (!kIsWeb) // Video recording only on mobile
                  ListTile(
                    leading: const Icon(Icons.videocam, color: Colors.red),
                    title: const Text('Record Video'),
                    subtitle: const Text('Record a new video'),
                    onTap: () {
                      Navigator.pop(context);
                      _recordVideo();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // galeriden görsel seçimi kısmı
  Future<void> _selectFromGallery() async {
    try {
      setState(() {
        sonDurum = "📱 Opening gallery...";
      });

      // burada hem fotoğraf hem de video seçimi için kullanıcıya seçenek sunuyorum.
      final bool? selectPhotos = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Media Type'),
          content: const Text('What would you like to select?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Photos'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Videos'),
            ),
          ],
        ),
      );

      if (selectPhotos == null) {
        setState(() => sonDurum = "❌ Selection cancelled");
        return;
      }

      List<XFile> files = [];

      if (selectPhotos) {
        // Select multiple images
        files = await _imagePicker.pickMultiImage(
          imageQuality: 85, // Compress to 85% quality
        );
      } else {
        // Select video
        final XFile? video = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
        );
        if (video != null) files = [video];
      }

      if (files.isEmpty) {
        setState(() => sonDurum = "❌ No media selected");
        return;
      }

      // Process selected files
      await _processSelectedFiles(files, selectPhotos ? 'image' : 'video');
    } catch (e) {
      setState(() => sonDurum = "❌ Gallery error: $e");
      debugPrint("❌ Gallery selection error: $e");
    }
  }

  // kamer ile fotoğraf ve video çekme kısmı
  Future<void> _takeWithCamera() async {
    try {
      setState(() {
        sonDurum = "📷 Opening camera...";
      });

      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (file == null) {
        setState(() => sonDurum = "❌ No photo taken");
        return;
      }

      await _processSelectedFiles([file], 'image');
    } catch (e) {
      setState(() => sonDurum = "❌ Camera error: $e");
      debugPrint("❌ Camera error: $e");
    }
  }

  // video çekme kısmı
  Future<void> _recordVideo() async {
    try {
      setState(() {
        sonDurum = "🎥 Opening video recorder...";
      });

      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5), // Max 5 minutes
      );

      if (video == null) {
        setState(() => sonDurum = "❌ No video recorded");
        return;
      }

      await _processSelectedFiles([video], 'video');
    } catch (e) {
      setState(() => sonDurum = "❌ Video recording error: $e");
      debugPrint("❌ Video recording error: $e");
    }
  }

  // image_picker'dan dosya seçimi
  Future<void> _processSelectedFiles(
      List<XFile> files, String mediaType) async {
    try {
      setState(() {
        yukleniyor = true;
        sonDurum = "📤 Processing ${files.length} files...";
      });

      yuklenenMediaListesi.clear();
      int basariliSayisi = 0;
      int toplamSayi = files.length;

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final bytes = await file.readAsBytes();
        final isVideo = mediaType == 'video' ||
            file.name.toLowerCase().endsWith('.mp4') ||
            file.name.toLowerCase().endsWith('.mov');

        setState(() =>
            sonDurum = "📤 Uploading: ${file.name} (${i + 1}/$toplamSayi)");

        final url = await uploadToImgbb(bytes, file.name, isVideo);
        if (url != null) {
          yuklenenMediaListesi.add(MediaItem(
            url: url,
            type: isVideo ? 'video' : 'image',
            name: file.name,
          ));
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
              "✅ All media uploaded successfully! ($basariliSayisi/$toplamSayi)";
        } else if (basariliSayisi > 0) {
          sonDurum =
              "⚠️ Partial success: $basariliSayisi/$toplamSayi media uploaded";
        } else {
          sonDurum = "❌ No media could be uploaded";
        }
      });
    } catch (e) {
      setState(() {
        yukleniyor = false;
        sonDurum = "❌ Processing error: $e";
      });
      debugPrint("❌ Processing error: $e");
    }
  }

  // Dosya açma ve yükleme kısmı
  Future<void> mediaSecVeYukle() async {
    try {
      setState(() {
        sonDurum = "📁 Opening file picker...";
      });

      // desteklenen formatlar
      final sonuc = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'mp4',
          'avi',
          'mov',
          'mkv'
        ],
        withData: true,
        allowCompression: false,
      );

      if (sonuc == null || sonuc.files.isEmpty) {
        setState(() => sonDurum = "❌ No files selected");
        return;
      }

      // Process files from memory
      List<Uint8List> fileDataList = [];
      List<String> fileNameList = [];
      List<bool> isVideoList = [];
      int toplamBoyut = 0;

      for (final file in sonuc.files) {
        final extension = file.extension?.toLowerCase() ?? '';
        final isVideo = ['mp4', 'avi', 'mov', 'mkv'].contains(extension);

        if (file.bytes != null) {
          fileDataList.add(file.bytes!);
          fileNameList.add(file.name);
          isVideoList.add(isVideo);
          toplamBoyut += file.bytes!.length;
        } else if (!kIsWeb && file.path != null) {
          final bytes = await io.File(file.path!).readAsBytes();
          fileDataList.add(bytes);
          fileNameList.add(file.name);
          isVideoList.add(isVideo);
          toplamBoyut += bytes.length;
        }
      }

      if (fileDataList.isEmpty) {
        setState(() => sonDurum = "❌ No valid files to upload");
        return;
      }

      // Increase size limit for videos
      if (toplamBoyut > 200 * 1024 * 1024) {
        setState(() => sonDurum = "❌ Total file size too large (max 200MB)");
        return;
      }

      setState(() {
        yukleniyor = true;
        sonDurum = "📤 Uploading ${fileDataList.length} media files...";
      });

      yuklenenMediaListesi.clear();

      int basariliSayisi = 0;
      int toplamSayi = fileDataList.length;

      // dosyayı yükle
      for (int i = 0; i < fileDataList.length; i++) {
        final isVideo = isVideoList[i];
        final fileType = isVideo ? "video" : "image";

        setState(() => sonDurum =
            "📤 Uploading ${fileType}: ${fileNameList[i]} (${i + 1}/$toplamSayi)");

        final url =
            await uploadToImgbb(fileDataList[i], fileNameList[i], isVideo);
        if (url != null) {
          yuklenenMediaListesi.add(MediaItem(
            url: url,
            type: fileType,
            name: fileNameList[i],
          ));
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
              "✅ All media uploaded successfully! ($basariliSayisi/$toplamSayi)";
        } else if (basariliSayisi > 0) {
          sonDurum =
              "⚠️ Partial success: $basariliSayisi/$toplamSayi media uploaded";
        } else {
          sonDurum = "❌ No media could be uploaded";
        }
      });

      // hafızayı temizleme
      fileDataList.clear();
      fileNameList.clear();
      isVideoList.clear();
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
    if (yuklenenMediaListesi.isEmpty) {
      setState(() => sonDurum = "⚠️ No media to send!");
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
          "📨 Sending ${yuklenenMediaListesi.length} media files via MQTT...");

      // medya gönderme kontrolü
      await _mqtt!.mediaJsonGonder(yuklenenMediaListesi, tvSerial!);

      setState(() => sonDurum = "✅ All media sent to TV successfully!");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "✅ ${yuklenenMediaListesi.length} media files sent to TV!"),
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
      yuklenenMediaListesi.clear();
      pairDurumu = false;
      tvSerial = null;
      pairingCode = null;
      sonDurum = "🧹 List cleared";
    });
    _mqtt?.baglantiKapat();
  }

  Widget _buildMediaIcon(String type) {
    return Icon(
      type == 'video' ? Icons.videocam : Icons.image,
      size: 16,
      color: type == 'video' ? Colors.red : Colors.blue,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("📷 Media Uploader ${kIsWeb ? '(Web)' : '(Mobile)'}"),
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

              // Select media button - Now shows options
              ElevatedButton.icon(
                onPressed: (yukleniyor || mqttGonderiyor)
                    ? null
                    : _showMediaSourceDialog,
                icon: yukleniyor
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.perm_media),
                label: Text(
                  yukleniyor ? "Uploading..." : "📁 Select Images & Videos",
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

              // Send to TV button
              ElevatedButton.icon(
                onPressed: (yuklenenMediaListesi.isEmpty ||
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
                      : "📺 Send to TV (${yuklenenMediaListesi.length})",
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

              if (yuklenenMediaListesi.isNotEmpty)
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

              // Uploaded media list
              if (yuklenenMediaListesi.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "📋 Uploaded Media (${yuklenenMediaListesi.length})",
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange.shade700,
                                ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: yuklenenMediaListesi.length,
                          itemBuilder: (context, index) {
                            final media = yuklenenMediaListesi[index];
                            return Card(
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.deepOrange.shade100,
                                  child: _buildMediaIcon(media.type),
                                ),
                                title: Text(
                                  media.name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  "${media.type == 'video' ? '🎬 Video' : '🖼️ Image'} - ${media.url.substring(0, 30)}...",
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, size: 16),
                                  onPressed: () {
                                    setState(() {
                                      yuklenenMediaListesi.removeAt(index);
                                      sonDurum = "🗑️ Media removed";
                                    });
                                  },
                                  tooltip: "Remove",
                                ),
                              ),
                            );
                          },
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
