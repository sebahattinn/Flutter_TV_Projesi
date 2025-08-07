package com.example.tvimagereceiver

import android.graphics.BitmapFactory
import android.os.Bundle
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

class MainActivity : AppCompatActivity() {

    private lateinit var mqttClient: MqttClient
    private val serial = "androidtv_001"
    private val brokerUri = "tcp://broker.hivemq.com:1883"

    private val pairTopic = "tv/$serial/pair"
    private val imagesTopic = "tv/$serial/images"
    private val imageTopic = "tv/$serial/image"
    private val pairResponseTopic = "tv/$serial/pair_response"

    private lateinit var statusText: TextView
    private lateinit var messageText: TextView
    private lateinit var imageView: ImageView
    private lateinit var containerLayout: LinearLayout

    private var isPaired = false
    private var downloadedImages = mutableListOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createUI()

        // ✅ Kayıtlı görseli yükle
        val prefs = getSharedPreferences("tv_prefs", MODE_PRIVATE)
        val lastImagePath = prefs.getString("last_image_path", null)
        if (lastImagePath != null) {
            val file = File(lastImagePath)
            if (file.exists()) {
                val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                imageView.setImageBitmap(bitmap)
                messageText.text = "📂 Kayıtlı görsel yüklendi"
                messageText.setTextColor(Color.GREEN)
            }
        }

        connectToMqtt()
    }

    private fun createUI() {
        containerLayout = LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1a1a1a"))
            setPadding(48, 48, 48, 48)
        }

        val titleText = TextView(this).apply {
            text = "\uD83D\uDCFA Android TV MQTT Alıcısı"
            textSize = 28f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 32)
        }

        statusText = TextView(this).apply {
            text = "\uD83D\uDD0C MQTT Bağlantısı kuruluyor..."
            textSize = 20f
            setTextColor(Color.parseColor("#ffaa00"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 24)
        }

        messageText = TextView(this).apply {
            text = "\u23F3 Pair mesajı bekleniyor..."
            textSize = 18f
            setTextColor(Color.parseColor("#cccccc"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 32)
        }

        imageView = ImageView(this).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setBackgroundColor(Color.parseColor("#333333"))
        }

        containerLayout.addView(titleText)
        containerLayout.addView(statusText)
        containerLayout.addView(messageText)
        containerLayout.addView(imageView)
        setContentView(containerLayout)
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
                        runOnUiThread {
                            statusText.text = "❌ MQTT Bağlantısı Kesildi"
                            statusText.setTextColor(Color.RED)
                        }
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

                runOnUiThread {
                    statusText.text = "✅ MQTT Bağlantısı Aktif"
                    statusText.setTextColor(Color.GREEN)
                }

                mqttClient.subscribe(pairTopic, 1)
                mqttClient.subscribe(imagesTopic, 1)
                mqttClient.subscribe(imageTopic, 1)

                Log.d("MQTT", "🔔 Subscribed to topics: \n- $pairTopic\n- $imagesTopic\n- $imageTopic")

                runOnUiThread {
                    messageText.text = "📲 Pair mesajı bekleniyor..."
                }

            } catch (e: MqttException) {
                Log.e("MQTT", "❌ Bağlantı hatası: ${e.message}")
                runOnUiThread {
                    statusText.text = "❌ MQTT Hatası: ${e.message}"
                    statusText.setTextColor(Color.RED)
                }
            }
        }.start()
    }

    private fun handlePairRequest() {
        isPaired = true
        runOnUiThread {
            messageText.text = "✅ Pair işlemi başarılı!"
            messageText.setTextColor(Color.GREEN)
        }
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

            runOnUiThread {
                messageText.text = "📥 $totalImages görsel indiriliyor..."
            }

            val urls = mutableListOf<String>()
            for (i in 0 until imagesArray.length()) {
                val url = imagesArray.getJSONObject(i).getString("url")
                urls.add(url)
            }

            downloadAndSaveImages(urls)

        } catch (e: Exception) {
            Log.e("MQTT", "❌ JSON parse hatası: ${e.message}")
            runOnUiThread {
                messageText.text = "❌ Görsel verisi işlenemedi"
                messageText.setTextColor(Color.RED)
            }
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
                        imageFile.delete() // ✅ Önceki dosyayı sil
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
                    messageText.text = "✅ Tüm görseller indirildi!"
                    messageText.setTextColor(Color.GREEN)
                    showFirstImage()
                } else {
                    messageText.text = "⚠️ $successCount/${urls.size} görsel indirildi"
                    messageText.setTextColor(Color.YELLOW)
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
                        messageText.text = "🖼️ Görsel gösteriliyor: ${index + 1}"
                        messageText.setTextColor(Color.WHITE)

                        getSharedPreferences("tv_prefs", MODE_PRIVATE)
                            .edit()
                            .putString("last_image_path", file.absolutePath)
                            .apply()
                    } else {
                        messageText.text = "❌ Bitmap decode hatası"
                        messageText.setTextColor(Color.RED)
                    }
                } catch (e: Exception) {
                    Log.e("IMG", "❌ Gösterim hatası: ${e.message}")
                    messageText.text = "❌ Gösterim hatası"
                    messageText.setTextColor(Color.RED)
                }
            }
        } else {
            Log.w("IMG", "⚠️ Dosya bulunamadı: image_$index.jpg")
            runOnUiThread {
                messageText.text = "⚠️ Görsel dosyası bulunamadı"
                messageText.setTextColor(Color.YELLOW)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            if (::mqttClient.isInitialized && mqttClient.isConnected) {
                mqttClient.disconnect()
                Log.d("MQTT", "🔌 MQTT bağlantısı kapatıldı")
            }
        } catch (e: Exception) {
            Log.e("MQTT", "❌ MQTT kapatma hatası: ${e.message}")
        }
    }
}
