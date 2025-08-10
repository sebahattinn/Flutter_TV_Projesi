import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'gorsel_yukle_sayfasi.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  // Widget binding'i başlat
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // .env dosyasını yükle
    debugPrint("📁 .env dosyası yükleniyor...");
    await dotenv.load(fileName: ".env");
    debugPrint("✅ .env dosyası başarıyla yüklendi");

    // Önemli env değişkenlerini kontrol et
    final imgbbKey = dotenv.env['IMGBB_API_KEY'];
    final mqttBroker = dotenv.env['MQTT_BROKER'] ?? dotenv.env['MQTT_HOST'];

    if (imgbbKey == null || imgbbKey.isEmpty) {
      debugPrint("⚠️ IMGBB_API_KEY bulunamadı!");
    } else {
      debugPrint("✅ IMGBB_API_KEY mevcut");
    }

    if (mqttBroker == null || mqttBroker.isEmpty) {
      debugPrint("⚠️ MQTT_BROKER/MQTT_HOST bulunamadı!");
    } else {
      debugPrint("✅ MQTT Broker: $mqttBroker");
    }

    // Firebase zaten başlatılmış mı kontrol et
    if (Firebase.apps.isEmpty) {
      debugPrint("🔥 Firebase başlatılıyor...");
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint("✅ Firebase başarıyla başlatıldı");
    } else {
      debugPrint("ℹ️ Firebase zaten başlatılmış");
    }
  } catch (e, stack) {
    debugPrint("❌ Başlatma hatası: $e");
    debugPrint("📌 Stack: $stack");
  }

  runApp(const TvKontrolUygulamasi());
}

class TvKontrolUygulamasi extends StatelessWidget {
  const TvKontrolUygulamasi({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "📺 TV Kontrol",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 2,
          backgroundColor: Colors.deepOrange.shade600,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const AnaSayfa(),
      // Hata sayfası
      onUnknownRoute: (settings) =>
          MaterialPageRoute(builder: (context) => const HataSayfasi()),
    );
  }
}

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _firebaseReady = false;
  String _durumMesaji = "Kontrol ediliyor...";

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _firebaseKontrol();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  void _firebaseKontrol() {
    final firebaseReady = Firebase.apps.isNotEmpty;
    setState(() {
      _firebaseReady = firebaseReady;
      _updateDurumMesaji();
    });
    debugPrint(
      firebaseReady ? "✅ Firebase hazır" : "⚠️ Firebase bulunamadı",
    );
  }

  void _updateDurumMesaji() {
    if (_firebaseReady) {
      _durumMesaji = "✅ Sistem hazır";
    } else {
      _durumMesaji = "❌ Firebase başlatılamadı!";
    }
  }

  void _envKontrol() {
    final imgbbKey = dotenv.env['IMGBB_API_KEY'];
    final mqttBroker = dotenv.env['MQTT_BROKER'] ?? dotenv.env['MQTT_HOST'];
    final mqttPort = dotenv.env['MQTT_PORT'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("🔧 Yapılandırma Durumu"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ayarSatiri("IMGBB API Key", imgbbKey),
              _ayarSatiri("MQTT Broker", mqttBroker),
              _ayarSatiri("MQTT Port", mqttPort),
              const Divider(),
              _ayarSatiri("Firebase", _firebaseReady ? "Aktif" : "Hatalı"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Tamam"),
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
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("📺 TV Kontrol Uygulaması"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _envKontrol,
            tooltip: "Yapılandırmayı Kontrol Et",
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
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Logo/Icon
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.8, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade100,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.deepOrange.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.tv,
                            size: 64,
                            color: Colors.deepOrange.shade600,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Başlık
                  Text(
                    "TV Kontrol Sistemi",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange.shade700,
                        ),
                  ),

                  const SizedBox(height: 16),

                  // Durum mesajı kartı
                  Card(
                    color: _firebaseReady
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _firebaseReady ? Icons.check_circle : Icons.warning,
                            color:
                                _firebaseReady ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _durumMesaji,
                              style: TextStyle(
                                color: _firebaseReady
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Ana butonlar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Görsel Yükleme Butonu - This is the only main button now
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const GorselYukleSayfasi()),
                          );
                        },
                        icon: const Icon(Icons.photo_library),
                        label: const Text('📷 Görsel Yükleme Sayfası'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Yapılandırma butonu
                      OutlinedButton.icon(
                        onPressed: _envKontrol,
                        icon: const Icon(Icons.settings),
                        label: const Text('⚙️ Yapılandırmayı Kontrol Et'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange.shade600,
                          side: BorderSide(color: Colors.deepOrange.shade600),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Hata sayfası
class HataSayfasi extends StatelessWidget {
  const HataSayfasi({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("❌ Hata")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              "Sayfa bulunamadı!",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushReplacementNamed(context, '/'),
              icon: const Icon(Icons.home),
              label: const Text("Ana Sayfaya Dön"),
            ),
          ],
        ),
      ),
    );
  }
}
