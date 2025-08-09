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

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean();

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

<<<<<<< HEAD
  Future<void> pairGonder() async {
=======
  // Pair gönderme - QR kod tarandıktan sonra kullanılır
  Future<void> pairGonder({
    required String token,
    required String folderName,
    String deviceInfo = "Flutter Mobile",
  }) async {
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
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
<<<<<<< HEAD
      final builder = MqttClientPayloadBuilder();
      builder.addString('pair');

      final payload = builder.payload;
      debugPrint(
        "📦 [PAIR] Payload oluşturuldu: ${utf8.decode(payload ?? [])}",
=======
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
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
      );

      final messageId = client!.publishMessage(
        pairTopic, // ✅ FIXED: Now uses the correct topic
        MqttQos.atLeastOnce,
        payload!,
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

  // Image URL'lerini JSON olarak gönder
  Future<void> jsonGonder(
    List<String> urlListesi, [
    String? customTvSerial,
  ]) async {
    if (!_baglantiDurumu || client == null) {
      throw Exception('MQTT bağlantısı yok, json gönderilemez.');
    }

    if (urlListesi.isEmpty) {
      debugPrint("⚠️ Gönderilecek URL listesi boş.");
      return;
    }

    try {
      final targetSerial = customTvSerial ?? tvSerial;
      final targetTopic = '${topicPrefix}$targetSerial/images';

      final now = DateTime.now();
      final payload = {
        "timestamp": now.toIso8601String(),
        "total_images": urlListesi.length,
        "tv_serial": targetSerial,
        "device_info": {
          "platform": Platform.operatingSystem,
          "version": Platform.operatingSystemVersion,
          "client_type": "flutter_mobile",
        },
        "images": List.generate(
          urlListesi.length,
          (i) => {
            "id": i + 1,
            "url": urlListesi[i],
            "uploaded_at": now.toIso8601String(),
            "index": i,
          },
        ),
      };

      final jsonString = jsonEncode(payload);
      debugPrint("📦 JSON oluşturuldu, karakter sayısı: ${jsonString.length}");
      debugPrint("📨 Images Topic: $targetTopic");

      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonString);

      final messageId = client!.publishMessage(
        targetTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      if (messageId > 0) {
        debugPrint("✅ JSON başarıyla gönderildi. Message ID: $messageId");
      } else {
        debugPrint("❌ JSON gönderilemedi. Message ID: $messageId");
        throw Exception('MQTT gönderim başarısız.');
      }
    } catch (e, stack) {
      debugPrint("🚨 JSON gönderim hatası: $e");
      debugPrint("📌 Stack: $stack");
      rethrow;
    }
  }

  // Belirli bir görsel index'ini gönder (TV'de gösterilecek görsel)
  Future<void> imageIndexGonder(int index, [String? customTvSerial]) async {
    if (!_baglantiDurumu || client == null) {
      debugPrint("❌ MQTT bağlantısı yok, image index gönderilemez.");
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
          "✅ Image index gönderildi: $index -> Topic: $targetTopic (Message ID: $messageId)",
        );
      } else {
        debugPrint("❌ Image index gönderilemedi. Message ID: $messageId");
      }
    } catch (e) {
      debugPrint("🚨 Image index gönderim hatası: $e");
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
