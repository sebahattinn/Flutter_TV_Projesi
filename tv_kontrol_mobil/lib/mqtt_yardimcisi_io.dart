import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttYardimcisi {
  MqttServerClient? client;
  bool _baglantiDurumu = false;

  String get broker =>
      dotenv.env['MQTT_BROKER'] ??
      dotenv.env['MQTT_HOST'] ??
      'broker.hivemq.com';

  int get port => int.tryParse(dotenv.env['MQTT_PORT'] ?? '') ?? 1883;

  // Topic configuration
  String get topicPrefix => dotenv.env['MQTT_TOPIC_PREFIX'] ?? 'tv/';
  String get tvSerial => dotenv.env['TV_SERIAL'] ?? 'androidtv_001';
  String get username => dotenv.env['MQTT_USERNAME'] ?? '';
  String get password => dotenv.env['MQTT_PASSWORD'] ?? '';
  bool get baglantiDurumu => _baglantiDurumu;

  // Topic getters
  String get pairTopic => '${topicPrefix}$tvSerial/pair';
  String get pairResponseTopic => '${topicPrefix}$tvSerial/pair_response';
  String get imagesTopic => '${topicPrefix}$tvSerial/images';
  String get imageTopic => '${topicPrefix}$tvSerial/image';

  Future<void> baglantiKur() async {
    try {
      debugPrint("🔧 MQTT yapılandırması başlatılıyor...");
      debugPrint("📡 Broker: $broker:$port");
      debugPrint("📍 Topic prefix: $topicPrefix");
      debugPrint("📱 TV Serial: $tvSerial");

      if (broker.isEmpty) {
        throw Exception("MQTT broker adresi boş! .env dosyasını kontrol edin.");
      }

      final clientId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint("📛 Client ID: $clientId");

      client = MqttServerClient.withPort(broker, clientId, port);

      client!.setProtocolV311();
      client!.secure = false;
      client!.useWebSocket = false;
      client!.logging(on: kDebugMode);

      client!.connectTimeoutPeriod = 10000; // 10 seconds
      client!.keepAlivePeriod = 60; // 60 seconds

      client!.autoReconnect = true;
      client!.resubscribeOnAutoReconnect = true;

      client!.onConnected = _onConnected;
      client!.onDisconnected = _onDisconnected;

      final connMessage =
          MqttConnectMessage().withClientIdentifier(clientId).startClean();

      if (username.isNotEmpty && password.isNotEmpty) {
        connMessage.authenticateAs(username, password);
        debugPrint("🔐 Kimlik doğrulama bilgileri eklendi.");
      }

      client!.connectionMessage = connMessage;

      debugPrint("🔌 MQTT broker'a bağlanılıyor...");
      final status = await client!.connect();

      debugPrint("📊 Connection status: ${status?.state}");
      debugPrint("📊 Return code: ${status?.returnCode}");

      if (status?.state == MqttConnectionState.connected) {
        _baglantiDurumu = true;
        debugPrint("✅ MQTT bağlantısı başarılı!");
      } else {
        _baglantiDurumu = false;
        final state = status?.state ?? 'unknown';
        final code = status?.returnCode ?? 'unknown';
        debugPrint("❌ MQTT bağlantısı başarısız! Durum: $state | Kod: $code");
        throw Exception('Bağlantı kurulamadı: $state - $code');
      }
    } catch (e, stack) {
      debugPrint("🚨 HATA: MQTT bağlantı kurulamadı -> $e");
      debugPrint("📌 Stack Trace: $stack");
      _baglantiDurumu = false;
      client?.disconnect();
      rethrow;
    }
  }

  // Generic message sending method
  Future<void> mesajGonder(String topic, String message) async {
    if (!_baglantiDurumu || client == null) {
      debugPrint("❌ MQTT bağlantısı yok, mesaj gönderilemez.");
      return;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);

      final messageId = client!.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      if (messageId > 0) {
        debugPrint(
          "✅ Mesaj gönderildi -> Topic: $topic | Message ID: $messageId",
        );
        debugPrint("📄 Mesaj içeriği: $message");
      } else {
        debugPrint("❌ Mesaj gönderilemedi. Message ID: $messageId");
      }
    } catch (e) {
      debugPrint("🚨 Mesaj gönderim hatası: $e");
    }
  }

  // NEW: Request TV to show QR code
  Future<void> requestQrFromTV(String tvSerial) async {
    if (!_baglantiDurumu || client == null) {
      debugPrint("❌ MQTT bağlantısı yok, QR isteği gönderilemez.");
      // Try to connect first
      await baglantiKur();
    }

    try {
      final requestQrTopic = '${topicPrefix}$tvSerial/request_qr';
      final payload = jsonEncode({
        "action": "show_qr",
        "timestamp": DateTime.now().millisecondsSinceEpoch,
      });

      debugPrint("📺 Sending QR request to TV on topic: $requestQrTopic");

      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);

      final messageId = client!.publishMessage(
        requestQrTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      if (messageId > 0) {
        debugPrint(
            "✅ QR request sent to TV successfully. Message ID: $messageId");
      } else {
        debugPrint("❌ Failed to send QR request. Message ID: $messageId");
      }
    } catch (e) {
      debugPrint("🚨 QR request error: $e");
    }
  }

  // Send media (images and videos) with type information
  Future<void> mediaJsonGonder(
    List<dynamic> mediaListesi, [
    String? customTvSerial,
  ]) async {
    if (!_baglantiDurumu || client == null) {
      throw Exception('MQTT bağlantısı yok, media gönderilemez.');
    }

    if (mediaListesi.isEmpty) {
      debugPrint("⚠️ Gönderilecek media listesi boş.");
      return;
    }

    try {
      final targetSerial = customTvSerial ?? tvSerial;
      final targetTopic = '${topicPrefix}$targetSerial/images';

      final now = DateTime.now();
      final payload = {
        "timestamp": now.toIso8601String(),
        "total_media": mediaListesi.length,
        "tv_serial": targetSerial,
        "device_info": {
          "platform": Platform.operatingSystem,
          "version": Platform.operatingSystemVersion,
          "client_type": "flutter_mobile",
        },
        "media": List.generate(
          mediaListesi.length,
          (i) {
            final media = mediaListesi[i];
            return {
              "id": i + 1,
              "url": media.url,
              "type": media.type, // 'image' or 'video'
              "name": media.name,
              "uploaded_at": now.toIso8601String(),
              "index": i,
            };
          },
        ),
      };

      final jsonString = jsonEncode(payload);
      debugPrint(
          "📦 Media JSON oluşturuldu, karakter sayısı: ${jsonString.length}");
      debugPrint("📨 Media Topic: $targetTopic");

      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonString);

      final messageId = client!.publishMessage(
        targetTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      if (messageId > 0) {
        debugPrint("✅ Media JSON başarıyla gönderildi. Message ID: $messageId");
      } else {
        debugPrint("❌ Media JSON gönderilemedi. Message ID: $messageId");
        throw Exception('MQTT gönderim başarısız.');
      }
    } catch (e, stack) {
      debugPrint("🚨 Media JSON gönderim hatası: $e");
      debugPrint("📌 Stack: $stack");
      rethrow;
    }
  }

  // Legacy method for backward compatibility - sends images only
  Future<void> jsonGonder(
    List<String> urlListesi, [
    String? customTvSerial,
  ]) async {
    // Convert to media format for backward compatibility
    final mediaList = urlListesi
        .map((url) => MediaItem(
              url: url,
              type: 'image',
              name: 'image_${urlListesi.indexOf(url)}.jpg',
            ))
        .toList();

    await mediaJsonGonder(mediaList, customTvSerial);
  }

  // Pair gönderme - QR kod tarandıktan sonra kullanılır
  Future<void> pairGonder({
    required String token,
    required String folderName,
    String deviceInfo = "Flutter Mobile",
  }) async {
    debugPrint("📢 [PAIR] pairGonder() fonksiyonu çağrıldı");
    debugPrint("📍 [PAIR] Pair topic: $pairTopic");
    debugPrint("📍 [PAIR] MQTT bağlantı durumu: $_baglantiDurumu");
    debugPrint("📍 [PAIR] MQTT client null mu: ${client == null}");

    if (!_baglantiDurumu || client == null) {
      debugPrint(
        "❌ [PAIR] MQTT bağlantısı yok veya client null, mesaj gönderilemez.",
      );
      return;
    }

    try {
      final payloadMap = {
        "action": "pair",
        "token": token,
        "folder_name": folderName,
        "device_info": deviceInfo,
        "timestamp": DateTime.now().millisecondsSinceEpoch,
      };

      final jsonString = jsonEncode(payloadMap);
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonString);

      debugPrint("📦 [PAIR] JSON payload: $jsonString");
      debugPrint("📨 [PAIR] Topic: $pairTopic");

      final messageId = client!.publishMessage(
        pairTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      if (messageId <= 0) {
        debugPrint("❌ [PAIR] Mesaj gönderilemedi. messageId: $messageId");
      } else {
        debugPrint("✅ [PAIR] Pair mesajı gönderildi. messageId: $messageId");
        debugPrint("📍 [PAIR] Gönderilen topic: $pairTopic");
      }

      await Future.delayed(const Duration(milliseconds: 300));
      debugPrint(
        "🔁 [PAIR] MQTT bağlantı durumu: ${client!.connectionStatus?.state}",
      );
    } catch (e, stack) {
      debugPrint("🚨 [PAIR] Hata oluştu: $e");
      debugPrint("📌 [PAIR] Stack Trace: $stack");
    }
  }

  // Belirli bir media index'ini gönder (TV'de gösterilecek media)
  Future<void> mediaIndexGonder(int index, [String? customTvSerial]) async {
    if (!_baglantiDurumu || client == null) {
      debugPrint("❌ MQTT bağlantısı yok, media index gönderilemez.");
      return;
    }

    try {
      final targetSerial = customTvSerial ?? tvSerial;
      final targetTopic = '${topicPrefix}$targetSerial/image';

      final builder = MqttClientPayloadBuilder();
      builder.addString(index.toString());

      final messageId = client!.publishMessage(
        targetTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      if (messageId > 0) {
        debugPrint(
          "✅ Media index gönderildi: $index -> Topic: $targetTopic (Message ID: $messageId)",
        );
      } else {
        debugPrint("❌ Media index gönderilemedi. Message ID: $messageId");
      }
    } catch (e) {
      debugPrint("🚨 Media index gönderim hatası: $e");
    }
  }

  // Tek URL gönder
  Future<void> tekUrlGonder(String url, [String? customTvSerial]) async {
    await jsonGonder([url], customTvSerial);
  }

  // Topic dinleme (pair response vs. için)
  void topicDinle(String topic, Function(String) onMessage) {
    if (!_baglantiDurumu || client == null) {
      debugPrint("❌ MQTT bağlantısı yok, $topic dinlenemiyor.");
      return;
    }

    client!.subscribe(topic, MqttQos.atLeastOnce);
    debugPrint("👂 Topic dinleniyor: $topic");

    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      final message = messages[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );
      final receivedTopic = messages[0].topic;

      debugPrint("📨 Mesaj alındı -> Topic: $receivedTopic");
      debugPrint("📄 Payload: $payload");

      if (receivedTopic == topic) {
        onMessage(payload);
      }
    });
  }

  // Bağlantıyı kapat
  void baglantiKapat() {
    try {
      if (client != null) {
        debugPrint("🔌 MQTT bağlantısı kapatılıyor...");
        client!.disconnect();
        _baglantiDurumu = false;
        debugPrint("✅ MQTT bağlantısı kapatıldı.");
      }
    } catch (e) {
      debugPrint("⚠️ MQTT bağlantı kapatma hatası: $e");
    }
  }

  // Bağlantı durumunu kontrol et
  bool baglantiKontrol() {
    final connected =
        client?.connectionStatus?.state == MqttConnectionState.connected;
    _baglantiDurumu = connected;
    return connected;
  }

  // Callback fonksiyonları
  void _onConnected() {
    debugPrint("🎉 MQTT bağlantısı başarılı! (onConnected)");
    _baglantiDurumu = true;
  }

  void _onDisconnected() {
    debugPrint("⚠️ MQTT bağlantısı kesildi! (onDisconnected)");
    _baglantiDurumu = false;
  }

  // Debug bilgilerini yazdır
  void debugBilgileri() {
    debugPrint("📋 MQTT Yapılandırma Detayları:");
    debugPrint("  Broker: $broker:$port");
    debugPrint("  Topic Prefix: $topicPrefix");
    debugPrint("  TV Serial: $tvSerial");
    debugPrint("  Pair Topic: $pairTopic");
    debugPrint("  Pair Response Topic: $pairResponseTopic");
    debugPrint("  Images Topic: $imagesTopic");
    debugPrint("  Image Topic: $imageTopic");
    debugPrint("  Kullanıcı adı: ${username.isEmpty ? 'Yok' : 'Var'}");
    debugPrint("  Parola: ${password.isEmpty ? 'Yok' : 'Var'}");
    debugPrint(
      "  Bağlantı durumu: ${_baglantiDurumu ? 'Bağlı' : 'Bağlı değil'}",
    );

    if (client != null) {
      debugPrint("  Client ID: ${client!.clientIdentifier}");
      debugPrint("  Connection Status: ${client!.connectionStatus?.state}");
    }
  }
}

// Helper class for media items
class MediaItem {
  final String url;
  final String type;
  final String name;

  MediaItem({
    required this.url,
    required this.type,
    required this.name,
  });
}
