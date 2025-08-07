package com.example.tvimagereceiver

import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.ImageView
import android.widget.TextView
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.URL
import android.graphics.Color
import android.view.Gravity
import android.widget.FrameLayout
import android.view.View

class MainActivity : AppCompatActivity() {

    private lateinit var mqttClient: MqttClient
    private val serial = "androidtv_001"
    private val brokerUri = "tcp://broker.hivemq.com:1883"

    private val pairTopic = "tv/$serial/pair"
    private val imagesTopic = "tv/$serial/images"
    private val imageTopic = "tv/$serial/image"
    private val pairResponseTopic = "tv/$serial/pair_response"

    private lateinit var statusOverlay: LinearLayout
    private lateinit var statusText: TextView
    private lateinit var messageText: TextView
    private lateinit var imageView: ImageView
    private lateinit var mainContainer: FrameLayout

    private var isPaired = false
    private var downloadedImages = mutableListOf<String>()

    // Handler for auto-hiding status messages
    private val hideHandler = Handler(Looper.getMainLooper())
    private var hideRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createUI()

        // ✅ Load saved image
        val prefs = getSharedPreferences("tv_prefs", MODE_PRIVATE)
        val lastImagePath = prefs.getString("last_image_path", null)
        if (lastImagePath != null) {
            val file = File(lastImagePath)
            if (file.exists()) {
                val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                imageView.setImageBitmap(bitmap)
                showTemporaryMessage("📂 Kayıtlı görsel yüklendi", Color.GREEN)
            }
        }

        connectToMqtt()
    }

    private fun createUI() {
        // Main container that fills entire screen
        mainContainer = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.BLACK)
        }

        // Image view that fills entire screen
        imageView = ImageView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            scaleType = ImageView.ScaleType.CENTER_CROP
            setBackgroundColor(Color.BLACK)
        }

        // Status overlay that appears on top
        statusOverlay = LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#CC000000")) // Semi-transparent black
            setPadding(48, 48, 48, 48)
            visibility = View.VISIBLE
        }

        val titleText = TextView(this).apply {
            text = "\uD83D\uDCFA Android TV MQTT Alıcısı"
            textSize = 28f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 16)
        }

        statusText = TextView(this).apply {
            text = "\uD83D\uDD0C MQTT Bağlantısı kuruluyor..."
            textSize = 20f
            setTextColor(Color.parseColor("#ffaa00"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 12)
        }

        messageText = TextView(this).apply {
            text = "\u23F3 Pair mesajı bekleniyor..."
            textSize = 18f
            setTextColor(Color.parseColor("#cccccc"))
            gravity = Gravity.CENTER
        }

        statusOverlay.addView(titleText)
        statusOverlay.addView(statusText)
        statusOverlay.addView(messageText)

        mainContainer.addView(imageView)
        mainContainer.addView(statusOverlay)

        setContentView(mainContainer)
    }

    private fun showTemporaryMessage(message: String, color: Int, isStatus: Boolean = false) {
        runOnUiThread {
            // Cancel any existing hide timer
            hideRunnable?.let { hideHandler.removeCallbacks(it) }

            // Show the overlay
            statusOverlay.visibility = View.VISIBLE

            if (isStatus) {
                statusText.text = message
                statusText.setTextColor(color)
            } else {
                messageText.text = message
                messageText.setTextColor(color)
            }

            // Set up auto-hide after 2 seconds
            hideRunnable = Runnable {
                statusOverlay.visibility = View.GONE
            }
            hideHandler.postDelayed(hideRunnable!!, 2000)
        }
    }

    private fun showPermanentStatus(statusMessage: String, statusColor: Int, message: String, messageColor: Int) {
        runOnUiThread {
            // Cancel any existing hide timer for permanent messages
            hideRunnable?.let { hideHandler.removeCallbacks(it) }

            statusOverlay.visibility = View.VISIBLE
            statusText.text = statusMessage
            statusText.setTextColor(statusColor)
            messageText.text = message
            messageText.setTextColor(messageColor)
        }
    }

    private fun connectToMqtt() {
        Thread {
            try {
                val clientId = "tvClient_$serial"
                mqttClient = MqttClient(brokerUri, clientId, MemoryPersistence())

                val options = MqttConnectOptions().apply {
                    isCleanSession = true
                    connectionTimeout = 10
                    keepAliveInterval = 20
                }

                mqttClient.setCallback(object : MqttCallback {
                    override fun connectionLost(cause: Throwable?) {
                        Log.e("MQTT", "❌ Bağlantı koptu: ${cause?.message}")
                        showTemporaryMessage("❌ MQTT Bağlantısı Kesildi", Color.RED, true)
                    }

                    override fun messageArrived(topic: String?, message: MqttMessage?) {
                        val payload = message?.toString() ?: return
                        Log.d("MQTT", "📩 Mesaj geldi: $topic -> $payload")

                        when (topic) {
                            pairTopic -> handlePairRequest()
                            imagesTopic -> handleImagesMessage(payload)
                            imageTopic -> {
                                val index = payload.toIntOrNull()
                                if (index != null) showImageByIndex(index)
                                else Log.e("MQTT", "⚠️ Geçersiz index: $payload")
                            }
                        }
                    }

                    override fun deliveryComplete(token: IMqttDeliveryToken?) {
                        Log.d("MQTT", "📦 Mesaj teslim edildi.")
                    }
                })

                mqttClient.connect(options)
                Log.i("MQTT", "✅ MQTT bağlantısı kuruldu: $brokerUri")

                showTemporaryMessage("✅ MQTT Bağlantısı Aktif", Color.GREEN, true)

                mqttClient.subscribe(pairTopic, 1)
                mqttClient.subscribe(imagesTopic, 1)
                mqttClient.subscribe(imageTopic, 1)

                Log.d("MQTT", "🔔 Subscribed to topics: \n- $pairTopic\n- $imagesTopic\n- $imageTopic")

                showTemporaryMessage("📲 Pair mesajı bekleniyor...", Color.parseColor("#cccccc"))

            } catch (e: MqttException) {
                Log.e("MQTT", "❌ Bağlantı hatası: ${e.message}")
                showTemporaryMessage("❌ MQTT Hatası: ${e.message}", Color.RED, true)
            }
        }.start()
    }

    private fun handlePairRequest() {
        isPaired = true
        showTemporaryMessage("✅ Pair işlemi başarılı!", Color.GREEN)

        try {
            val responseMessage = "paired_ok"
            mqttClient.publish(pairResponseTopic, responseMessage.toByteArray(), 1, false)
            Log.d("MQTT", "📤 Pair yanıtı gönderildi -> $pairResponseTopic")
        } catch (e: MqttException) {
            Log.e("MQTT", "❌ Pair yanıtı gönderilemedi: ${e.message}")
        }
    }

    private fun handleImagesMessage(payload: String) {
        try {
            val jsonObject = JSONObject(payload)
            val imagesArray = jsonObject.getJSONArray("images")
            val totalImages = jsonObject.optInt("total_images", imagesArray.length())

            showTemporaryMessage("📥 $totalImages görsel indiriliyor...", Color.parseColor("#ffaa00"))

            val urls = mutableListOf<String>()
            for (i in 0 until imagesArray.length()) {
                val url = imagesArray.getJSONObject(i).getString("url")
                urls.add(url)
            }

            downloadAndSaveImages(urls)

        } catch (e: Exception) {
            Log.e("MQTT", "❌ JSON parse hatası: ${e.message}")
            showTemporaryMessage("❌ Görsel verisi işlenemedi", Color.RED)
        }
    }

    private fun downloadAndSaveImages(urls: List<String>) {
        Thread {
            val dir = File(filesDir, "tv_images")
            if (!dir.exists()) dir.mkdirs()

            var successCount = 0
            urls.forEachIndexed { index, url ->
                try {
                    val imageFile = File(dir, "image_$index.jpg")
                    if (imageFile.exists()) {
                        imageFile.delete() // ✅ Delete previous file
                    }

                    val connection = URL(url).openConnection()
                    val input = connection.getInputStream()
                    val output = FileOutputStream(imageFile)

                    input.copyTo(output)
                    input.close()
                    output.close()

                    successCount++
                    downloadedImages.add(imageFile.absolutePath)

                } catch (e: Exception) {
                    Log.e("IMG", "❌ İndirme hatası [$index]: ${e.message}")
                }
            }

            runOnUiThread {
                if (successCount == urls.size) {
                    showTemporaryMessage("✅ Tüm görseller indirildi!", Color.GREEN)
                    // Show first image after a short delay
                    Handler(Looper.getMainLooper()).postDelayed({
                        showFirstImage()
                    }, 500)
                } else {
                    showTemporaryMessage("⚠️ $successCount/${urls.size} görsel indirildi", Color.YELLOW)
                }
            }
        }.start()
    }

    private fun showFirstImage() {
        showImageByIndex(0)
    }

    private fun showImageByIndex(index: Int) {
        val file = File(filesDir, "tv_images/image_$index.jpg")
        if (file.exists()) {
            runOnUiThread {
                try {
                    val options = BitmapFactory.Options().apply {
                        inMutable = true
                        inJustDecodeBounds = false
                    }

                    val fis = FileInputStream(file)
                    val bitmap = BitmapFactory.decodeStream(fis, null, options)
                    fis.close()

                    if (bitmap != null) {
                        imageView.setImageBitmap(bitmap)
                        showTemporaryMessage("🖼️ Görsel gösteriliyor: ${index + 1}", Color.WHITE)

                        getSharedPreferences("tv_prefs", MODE_PRIVATE)
                            .edit()
                            .putString("last_image_path", file.absolutePath)
                            .apply()
                    } else {
                        showTemporaryMessage("❌ Bitmap decode hatası", Color.RED)
                    }
                } catch (e: Exception) {
                    Log.e("IMG", "❌ Gösterim hatası: ${e.message}")
                    showTemporaryMessage("❌ Gösterim hatası", Color.RED)
                }
            }
        } else {
            Log.w("IMG", "⚠️ Dosya bulunamadı: image_$index.jpg")
            showTemporaryMessage("⚠️ Görsel dosyası bulunamadı", Color.YELLOW)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            // Cancel any pending hide operations
            hideRunnable?.let { hideHandler.removeCallbacks(it) }

            if (::mqttClient.isInitialized && mqttClient.isConnected) {
                mqttClient.disconnect()
                Log.d("MQTT", "🔌 MQTT bağlantısı kapatıldı")
            }
        } catch (e: Exception) {
            Log.e("MQTT", "❌ MQTT kapatma hatası: ${e.message}")
        }
    }
}