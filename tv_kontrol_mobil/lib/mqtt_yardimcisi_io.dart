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

  // ✅ FIXED: Match Android TV topic structure
  String get topicPrefix => dotenv.env['MQTT_TOPIC_PREFIX'] ?? 'ht/demo/tv/';
  String get tvSerial => dotenv.env['TV_SERIAL'] ?? 'androidtv_001';
  String get username => dotenv.env['MQTT_USERNAME'] ?? '';
  String get password => dotenv.env['MQTT_PASSWORD'] ?? '';
  bool get baglantiDurumu => _baglantiDurumu;

  // ✅ FIXED: Topic names now match Android TV exactly
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
      debugPrint("🎯 Pair topic: $pairTopic");
      debugPrint("🎯 Pair response topic: $pairResponseTopic");
      debugPrint(
        "🔑 Kullanıcı adı: ${username.isNotEmpty} | Parola: ${password.isNotEmpty}",
      );

      if (broker.isEmpty) {
        throw Exception("MQTT broker adresi boş! .env dosyasını kontrol edin.");
      }

      // ✅ FIX 1: Simpler client ID
      final clientId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint("📛 Client ID: $clientId");

      client = MqttServerClient.withPort(broker, clientId, port);

      // ✅ FIX 2: More compatible settings
      client!.setProtocolV311();
      client!.secure = false;
      client!.useWebSocket = false;
      client!.logging(on: kDebugMode);

      // ✅ FIX 3: Increased timeouts
      client!.connectTimeoutPeriod = 10000; // 10 seconds instead of 5
      client!.keepAlivePeriod = 60; // 60 seconds instead of 30

      // ✅ FIX 4: Disable auto-reconnect initially
      client!.autoReconnect = false;
      client!.resubscribeOnAutoReconnect = false;

      client!.onConnected = _onConnected;
      client!.onDisconnected = _onDisconnected;

      // ✅ FIX 5: Simplified connection message
      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean(); // Remove .withWillQos() for now

      // Only add auth if both username and password exist
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

        // ✅ FIXED: Subscribe to pair response topic immediately
        await pairResponseTopicDinle();

        // ✅ FIX 6: Re-enable auto-reconnect after successful connection
        client!.autoReconnect = true;
        client!.resubscribeOnAutoReconnect = true;
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

  // ✅ NEW: Subscribe to pair response topic
  Future<void> pairResponseTopicDinle() async {
    if (!_baglantiDurumu || client == null) {
      debugPrint("❌ MQTT bağlantısı yok, pair response dinlenemiyor.");
      return;
    }

    try {
      client!.subscribe(pairResponseTopic, MqttQos.atLeastOnce);
      debugPrint("👂 Pair response topic dinleniyor: $pairResponseTopic");

      client!.updates!.listen((
        List<MqttReceivedMessage<MqttMessage>> messages,
      ) {
        final message = messages[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          message.payload.message,
        );
        final topic = messages[0].topic;

        debugPrint("📨 Mesaj alındı -> Topic: $topic");
        debugPrint("📄 Payload: $payload");

        if (topic == pairResponseTopic) {
          debugPrint("🎉 [PAIR] Pair response alındı: $payload");
          // Handle pair response here
          _handlePairResponse(payload);
        }
      });
    } catch (e) {
      debugPrint("🚨 [PAIR] Pair response dinleme hatası: $e");
    }
  }

  void _handlePairResponse(String payload) {
    if (payload.toLowerCase().contains('paired_ok') ||
        payload.toLowerCase().contains('success')) {
      debugPrint("✅ [PAIR] TV ile eşleşme başarılı!");
      // You can add callback here to notify UI
    } else {
      debugPrint("❌ [PAIR] TV eşleşme başarısız: $payload");
    }
  }

  Future<void> pairGonder() async {
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
      final builder = MqttClientPayloadBuilder();
      builder.addString('pair');

      final payload = builder.payload;
      debugPrint(
        "📦 [PAIR] Payload oluşturuldu: ${utf8.decode(payload ?? [])}",
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

  Future<void> jsonGonder(List<String> urlListesi) async {
    if (!_baglantiDurumu || client == null) {
      throw Exception('MQTT bağlantısı yok, json gönderilemez.');
    }

    if (urlListesi.isEmpty) {
      debugPrint("⚠️ Gönderilecek URL listesi boş.");
      return;
    }

    try {
      final now = DateTime.now();
      final payload = {
        "timestamp": now.toIso8601String(),
        "total_images": urlListesi.length,
        "tv_serial": tvSerial,
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
      debugPrint(
        "📨 Images Topic: $imagesTopic",
      ); // ✅ FIXED: Now uses correct topic

      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(jsonString);

      final messageId = client!.publishMessage(
        imagesTopic, // ✅ FIXED: Now uses the correct topic
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

  // ✅ NEW: Send image index to show specific image on TV
  Future<void> imageIndexGonder(int index) async {
    if (!_baglantiDurumu || client == null) {
      debugPrint("❌ MQTT bağlantısı yok, image index gönderilemez.");
      return;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(index.toString());

      final messageId = client!.publishMessage(
        imageTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      if (messageId > 0) {
        debugPrint("✅ Image index gönderildi: $index (Message ID: $messageId)");
      } else {
        debugPrint("❌ Image index gönderilemedi. Message ID: $messageId");
      }
    } catch (e) {
      debugPrint("🚨 Image index gönderim hatası: $e");
    }
  }

  Future<void> tekUrlGonder(String url) async {
    await jsonGonder([url]);
  }

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

  bool baglantiKontrol() {
    final connected =
        client?.connectionStatus?.state == MqttConnectionState.connected;
    _baglantiDurumu = connected;
    return connected;
  }

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

      debugPrint("📨 Mesaj alındı -> Topic: ${messages[0].topic}");
      debugPrint("📄 Payload: $payload");
      onMessage(payload);
    });
  }

  void _onConnected() {
    debugPrint("🎉 MQTT bağlantısı başarılı! (onConnected)");
    _baglantiDurumu = true;
  }

  void _onDisconnected() {
    debugPrint("⚠️ MQTT bağlantısı kesildi! (onDisconnected)");
    _baglantiDurumu = false;
  }

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
  }
}
