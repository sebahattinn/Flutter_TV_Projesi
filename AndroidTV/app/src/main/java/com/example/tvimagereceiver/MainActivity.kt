package com.example.tvimagereceiver

<<<<<<< HEAD
=======
import android.app.Activity
import android.graphics.Bitmap
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
<<<<<<< HEAD
=======
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.FrameLayout
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
import android.widget.ImageView
import android.widget.TextView
<<<<<<< HEAD
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
=======
import com.google.zxing.BarcodeFormat
import com.google.zxing.WriterException
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.*
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.URL
<<<<<<< HEAD
import android.graphics.Color
import android.view.Gravity
import android.widget.FrameLayout
import android.view.View
=======
import java.util.*
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)

class MainActivity : Activity() {

<<<<<<< HEAD
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
=======
    companion object {
        private const val TAG = "TV_RECEIVER"
        private const val BROKER_URI = "tcp://broker.hivemq.com:1883"
        private const val AUTO_HIDE_DELAY = 2000L // 2 seconds
    }

    // MQTT Client
    private var mqttClient: MqttClient? = null
    private lateinit var serial: String
    private var pairingCode: String = ""

    // MQTT Topics
    private lateinit var pairTopic: String
    private lateinit var imagesTopic: String
    private lateinit var imageTopic: String
    private lateinit var pairResponseTopic: String

    // UI Components
    private lateinit var statusText: TextView
    private lateinit var messageText: TextView
    private lateinit var imageView: ImageView
    private lateinit var qrImageView: ImageView
    private lateinit var containerLayout: FrameLayout
    private lateinit var infoLayout: LinearLayout
    private lateinit var serialText: TextView
    private lateinit var instructionText: TextView
    private lateinit var titleText: TextView
    private lateinit var imageCountText: TextView
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)

    // State
    private var isPaired = false
<<<<<<< HEAD
    private var downloadedImages = mutableListOf<String>()

    // Handler for auto-hiding status messages
    private val hideHandler = Handler(Looper.getMainLooper())
=======
    private val downloadedImages = mutableListOf<String>()
    private var currentImageIndex = 0
    private val scope = CoroutineScope(Dispatchers.Main + Job())
    private val handler = Handler(Looper.getMainLooper())
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
    private var hideRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
<<<<<<< HEAD
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
=======

        try {
            // Initialize serial and topics
            serial = getOrCreateSerial()
            pairTopic = "tv/$serial/pair"
            imagesTopic = "tv/$serial/images"
            imageTopic = "tv/$serial/image"
            pairResponseTopic = "tv/$serial/pair_response"

            // Generate pairing code
            pairingCode = generatePairingCode()

            // Setup UI
            createUI()

            // Generate QR code
            generateQRCode()

            // Connect to MQTT
            connectToMqtt()

            // Start auto-hide timer for initial display
            startAutoHideTimer()

        } catch (e: Exception) {
            Log.e(TAG, "onCreate error: ${e.message}", e)
        }
    }

    private fun generatePairingCode(): String {
        return UUID.randomUUID().toString().take(6).uppercase()
    }

    private fun getOrCreateSerial(): String {
        val prefs = getSharedPreferences("tv_prefs", MODE_PRIVATE)
        return prefs.getString("serial", null) ?: run {
            val newSerial = "TV_${UUID.randomUUID().toString().take(8).uppercase()}"
            prefs.edit().putString("serial", newSerial).apply()
            Log.d(TAG, "Generated new serial: $newSerial")
            newSerial
        }
    }

    private fun createUI() {
        // Main container - FrameLayout for layering
        containerLayout = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.BLACK)
        }

        // Image view (fullscreen, behind everything)
        imageView = ImageView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            scaleType = ImageView.ScaleType.CENTER_CROP // This will fill the screen
            setBackgroundColor(Color.BLACK)
            visibility = View.GONE
        }

        // Info layout (contains all text and QR code)
        infoLayout = LinearLayout(this).apply {
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
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
<<<<<<< HEAD
            setPadding(48, 48, 48, 48)
            visibility = View.VISIBLE
        }

        val titleText = TextView(this).apply {
            text = "\uD83D\uDCFA Android TV MQTT Alıcısı"
            textSize = 28f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 16)
=======
            setPadding(40, 40, 40, 40)
            gravity = Gravity.CENTER
        }

        // Title
        titleText = TextView(this).apply {
            text = "📺 Android TV Image Receiver"
            textSize = 32f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 20)
        }

        // Serial text
        serialText = TextView(this).apply {
            text = "Serial: $serial"
            textSize = 16f
            setTextColor(Color.GRAY)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 10)
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
        }

        // Status text
        statusText = TextView(this).apply {
<<<<<<< HEAD
            text = "\uD83D\uDD0C MQTT Bağlantısı kuruluyor..."
=======
            text = "Connecting..."
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
            textSize = 20f
            setTextColor(Color.YELLOW)
            gravity = Gravity.CENTER
<<<<<<< HEAD
            setPadding(0, 0, 0, 12)
        }

        messageText = TextView(this).apply {
            text = "\u23F3 Pair mesajı bekleniyor..."
=======
            setPadding(0, 0, 0, 20)
        }

        // Instructions
        instructionText = TextView(this).apply {
            text = "Scan QR code with mobile app"
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
            textSize = 18f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
<<<<<<< HEAD
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

=======
            setPadding(0, 20, 0, 20)
        }

        // QR Code
        qrImageView = ImageView(this).apply {
            layoutParams = LinearLayout.LayoutParams(400, 400).apply {
                gravity = Gravity.CENTER
            }
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.WHITE)
            setPadding(20, 20, 20, 20)
        }

        // Message text
        messageText = TextView(this).apply {
            text = "Waiting for pairing..."
            textSize = 16f
            setTextColor(Color.GRAY)
            gravity = Gravity.CENTER
            setPadding(0, 20, 0, 20)
        }

        // Image count text (shows which image is displayed)
        imageCountText = TextView(this).apply {
            text = ""
            textSize = 14f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 10, 0, 10)
            visibility = View.GONE
        }

        // Add views to info layout
        infoLayout.addView(titleText)
        infoLayout.addView(serialText)
        infoLayout.addView(statusText)
        infoLayout.addView(instructionText)
        infoLayout.addView(qrImageView)
        infoLayout.addView(messageText)
        infoLayout.addView(imageCountText)

        // Add to main container (order matters - image behind, info on top)
        containerLayout.addView(imageView)
        containerLayout.addView(infoLayout)

        setContentView(containerLayout)
    }

    // Handle keyboard input for image switching
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // Only handle keys when paired and images are available
        if (isPaired && downloadedImages.isNotEmpty()) {
            when (keyCode) {
                KeyEvent.KEYCODE_1, KeyEvent.KEYCODE_NUMPAD_1 -> {
                    showImageByNumber(0)
                    return true
                }
                KeyEvent.KEYCODE_2, KeyEvent.KEYCODE_NUMPAD_2 -> {
                    showImageByNumber(1)
                    return true
                }
                KeyEvent.KEYCODE_3, KeyEvent.KEYCODE_NUMPAD_3 -> {
                    showImageByNumber(2)
                    return true
                }
                KeyEvent.KEYCODE_4, KeyEvent.KEYCODE_NUMPAD_4 -> {
                    showImageByNumber(3)
                    return true
                }
                KeyEvent.KEYCODE_5, KeyEvent.KEYCODE_NUMPAD_5 -> {
                    showImageByNumber(4)
                    return true
                }
                KeyEvent.KEYCODE_6, KeyEvent.KEYCODE_NUMPAD_6 -> {
                    showImageByNumber(5)
                    return true
                }
                KeyEvent.KEYCODE_7, KeyEvent.KEYCODE_NUMPAD_7 -> {
                    showImageByNumber(6)
                    return true
                }
                KeyEvent.KEYCODE_8, KeyEvent.KEYCODE_NUMPAD_8 -> {
                    showImageByNumber(7)
                    return true
                }
                KeyEvent.KEYCODE_9, KeyEvent.KEYCODE_NUMPAD_9 -> {
                    showImageByNumber(8)
                    return true
                }
                KeyEvent.KEYCODE_0, KeyEvent.KEYCODE_NUMPAD_0 -> {
                    showImageByNumber(9)
                    return true
                }
                // Arrow keys for navigation
                KeyEvent.KEYCODE_DPAD_LEFT -> {
                    showPreviousImage()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_RIGHT -> {
                    showNextImage()
                    return true
                }
                // Space bar to toggle info display
                KeyEvent.KEYCODE_SPACE -> {
                    toggleInfoDisplay()
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun showImageByNumber(index: Int) {
        if (index < downloadedImages.size) {
            currentImageIndex = index
            showImage(currentImageIndex)
            Log.d(TAG, "Switched to image ${index + 1} via keyboard")
        } else {
            Log.d(TAG, "Image ${index + 1} not available (only ${downloadedImages.size} images)")
            runOnUiThread {
                messageText.text = "Image ${index + 1} not available"
                showInfoTemporarily()
            }
        }
    }

    private fun showNextImage() {
        if (downloadedImages.isNotEmpty()) {
            currentImageIndex = (currentImageIndex + 1) % downloadedImages.size
            showImage(currentImageIndex)
            Log.d(TAG, "Showing next image: ${currentImageIndex + 1}")
        }
    }

    private fun showPreviousImage() {
        if (downloadedImages.isNotEmpty()) {
            currentImageIndex = if (currentImageIndex > 0) {
                currentImageIndex - 1
            } else {
                downloadedImages.size - 1
            }
            showImage(currentImageIndex)
            Log.d(TAG, "Showing previous image: ${currentImageIndex + 1}")
        }
    }

    private fun toggleInfoDisplay() {
        runOnUiThread {
            if (infoLayout.visibility == View.VISIBLE) {
                infoLayout.visibility = View.GONE
            } else {
                showInfoTemporarily()
            }
        }
    }

    private fun startAutoHideTimer() {
        // Cancel any existing timer
        hideRunnable?.let { handler.removeCallbacks(it) }

        // Create new timer
        hideRunnable = Runnable {
            if (isPaired) {
                // Hide info layout when paired and showing images
                infoLayout.visibility = View.GONE
            }
        }

        // Start timer
        handler.postDelayed(hideRunnable!!, AUTO_HIDE_DELAY)
    }

    private fun showInfoTemporarily() {
        runOnUiThread {
            infoLayout.visibility = View.VISIBLE
            startAutoHideTimer()
        }
    }

    private fun generateQRCode() {
        try {
            val qrData = JSONObject().apply {
                put("tvSerial", serial)
                put("pairingCode", pairingCode)
                put("timestamp", System.currentTimeMillis())
            }.toString()

            Log.d(TAG, "QR Data: $qrData")

            val writer = QRCodeWriter()
            val bitMatrix = writer.encode(qrData, BarcodeFormat.QR_CODE, 400, 400)

            val width = bitMatrix.width
            val height = bitMatrix.height
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)

            for (x in 0 until width) {
                for (y in 0 until height) {
                    bitmap.setPixel(x, y, if (bitMatrix[x, y]) Color.BLACK else Color.WHITE)
                }
            }

            runOnUiThread {
                qrImageView.setImageBitmap(bitmap)
            }

        } catch (e: Exception) {
            Log.e(TAG, "QR generation failed: ${e.message}", e)
        }
    }

>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
    private fun connectToMqtt() {
        scope.launch(Dispatchers.IO) {
            try {
                val clientId = "TV_${serial}_${System.currentTimeMillis()}"
                mqttClient = MqttClient(BROKER_URI, clientId, MemoryPersistence())

                val options = MqttConnectOptions().apply {
                    isCleanSession = true
<<<<<<< HEAD
                    connectionTimeout = 10
                    keepAliveInterval = 20
=======
                    connectionTimeout = 30
                    keepAliveInterval = 60
                    isAutomaticReconnect = true
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
                }

                mqttClient?.setCallback(object : MqttCallback {
                    override fun connectionLost(cause: Throwable?) {
<<<<<<< HEAD
                        Log.e("MQTT", "❌ Bağlantı koptu: ${cause?.message}")
                        showTemporaryMessage("❌ MQTT Bağlantısı Kesildi", Color.RED, true)
=======
                        Log.e(TAG, "Connection lost: ${cause?.message}")
                        runOnUiThread {
                            statusText.text = "Disconnected"
                            statusText.setTextColor(Color.RED)
                            showInfoTemporarily() // Show info and auto-hide
                        }
                        // Reconnect after delay
                        scope.launch {
                            delay(5000)
                            connectToMqtt()
                        }
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
                    }

                    override fun messageArrived(topic: String?, message: MqttMessage?) {
                        val payload = message?.toString() ?: return
<<<<<<< HEAD
                        Log.d("MQTT", "📩 Mesaj geldi: $topic -> $payload")
=======
                        Log.d(TAG, "Message on $topic")
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)

                        when (topic) {
                            pairTopic -> handlePairRequest()
                            imagesTopic -> handleImagesMessage(payload)
<<<<<<< HEAD
                            imageTopic -> {
                                val index = payload.toIntOrNull()
                                if (index != null) showImageByIndex(index)
                                else Log.e("MQTT", "⚠️ Geçersiz index: $payload")
                            }
=======
                            imageTopic -> handleImageIndex(payload)
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
                        }
                    }

                    override fun deliveryComplete(token: IMqttDeliveryToken?) {
<<<<<<< HEAD
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
=======
                        Log.d(TAG, "Delivery complete")
                    }
                })

                mqttClient?.connect(options)

                // Subscribe to topics
                mqttClient?.subscribe(pairTopic, 1)
                mqttClient?.subscribe(imagesTopic, 1)
                mqttClient?.subscribe(imageTopic, 1)

                withContext(Dispatchers.Main) {
                    statusText.text = "Connected"
                    statusText.setTextColor(Color.GREEN)
                    showInfoTemporarily() // Show info and auto-hide
                }

                Log.i(TAG, "MQTT Connected")

            } catch (e: Exception) {
                Log.e(TAG, "MQTT Error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    statusText.text = "Connection Error"
                    statusText.setTextColor(Color.RED)
                    showInfoTemporarily() // Show info and auto-hide
                }
                delay(5000)
                connectToMqtt()
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
            }
        }
    }

    private fun handlePairRequest() {
        isPaired = true
        showTemporaryMessage("✅ Pair işlemi başarılı!", Color.GREEN)

        try {
<<<<<<< HEAD
            val responseMessage = "paired_ok"
            mqttClient.publish(pairResponseTopic, responseMessage.toByteArray(), 1, false)
            Log.d("MQTT", "📤 Pair yanıtı gönderildi -> $pairResponseTopic")
        } catch (e: MqttException) {
            Log.e("MQTT", "❌ Pair yanıtı gönderilemedi: ${e.message}")
=======
            val json = JSONObject(payload)
            val action = json.optString("action")
            val code = json.optString("pairingCode")

            if (action == "pair" && code == pairingCode) {
                isPaired = true

                runOnUiThread {
                    qrImageView.visibility = View.GONE
                    imageView.visibility = View.VISIBLE
                    messageText.text = "Paired Successfully!"
                    messageText.setTextColor(Color.GREEN)
                    instructionText.text = "Use number keys 1-9 to switch images\nArrow keys: Navigate | Space: Toggle info"
                    imageCountText.visibility = View.VISIBLE

                    // Auto-hide after showing pairing success
                    startAutoHideTimer()
                }

                // Send success response
                val response = JSONObject().apply {
                    put("status", "success")
                    put("pairingCode", pairingCode)
                    put("tvSerial", serial)
                }.toString()

                mqttClient?.publish(pairResponseTopic, MqttMessage(response.toByteArray()))

                Log.d(TAG, "Pairing successful")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Pair error: ${e.message}", e)
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
        }
    }

    private fun handleImagesMessage(payload: String) {
<<<<<<< HEAD
        try {
            val jsonObject = JSONObject(payload)
            val imagesArray = jsonObject.getJSONArray("images")
            val totalImages = jsonObject.optInt("total_images", imagesArray.length())

            showTemporaryMessage("📥 $totalImages görsel indiriliyor...", Color.parseColor("#ffaa00"))
=======
        if (!isPaired) return

        try {
            val json = JSONObject(payload)
            val images = json.getJSONArray("images")

            runOnUiThread {
                messageText.text = "Downloading ${images.length()} images..."
                showInfoTemporarily() // Show info and auto-hide
            }
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)

            scope.launch(Dispatchers.IO) {
                downloadedImages.clear()
                currentImageIndex = 0

                for (i in 0 until images.length()) {
                    val imageObj = images.getJSONObject(i)
                    val url = imageObj.getString("url")
                    downloadImage(url, i)
                }

                withContext(Dispatchers.Main) {
                    if (downloadedImages.isNotEmpty()) {
                        showImage(0)
                        messageText.text = "${downloadedImages.size} images ready"
                        instructionText.text = "Press 1-${minOf(downloadedImages.size, 9)} to switch images"
                        // Info will auto-hide after 2 seconds
                    }
                }
            }
<<<<<<< HEAD

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
=======
        } catch (e: Exception) {
            Log.e(TAG, "Images error: ${e.message}", e)
        }
    }

    private fun downloadImage(url: String, index: Int) {
        try {
            val dir = File(filesDir, "images")
            if (!dir.exists()) dir.mkdirs()

            val file = File(dir, "image_$index.jpg")
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)

            URL(url).openStream().use { input ->
                FileOutputStream(file).use { output ->
                    input.copyTo(output)
<<<<<<< HEAD
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
=======
                }
            }

            downloadedImages.add(file.absolutePath)
            Log.d(TAG, "Downloaded image $index from $url")

        } catch (e: Exception) {
            Log.e(TAG, "Download failed for image $index: ${e.message}")
        }
    }

    private fun handleImageIndex(payload: String) {
        val index = payload.toIntOrNull() ?: 0
        currentImageIndex = index
        showImage(index)
    }

    private fun showImage(index: Int) {
        if (downloadedImages.isEmpty()) return

        val actualIndex = index.coerceIn(0, downloadedImages.size - 1)
        currentImageIndex = actualIndex
        val path = downloadedImages[actualIndex]
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)

        runOnUiThread {
            try {
                val bitmap = BitmapFactory.decodeFile(path)
                imageView.setImageBitmap(bitmap)

<<<<<<< HEAD
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
=======
                // Update image counter
                imageCountText.text = "Image ${actualIndex + 1} of ${downloadedImages.size}"
                messageText.text = "Showing image ${actualIndex + 1}/${downloadedImages.size}"

                // Briefly show info when changing images, then hide
                showInfoTemporarily()

            } catch (e: Exception) {
                Log.e(TAG, "Display error: ${e.message}")
            }
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        hideRunnable?.let { handler.removeCallbacks(it) }
        try {
<<<<<<< HEAD
            // Cancel any pending hide operations
            hideRunnable?.let { hideHandler.removeCallbacks(it) }

            if (::mqttClient.isInitialized && mqttClient.isConnected) {
                mqttClient.disconnect()
                Log.d("MQTT", "🔌 MQTT bağlantısı kapatıldı")
            }
        } catch (e: Exception) {
            Log.e("MQTT", "❌ MQTT kapatma hatası: ${e.message}")
=======
            mqttClient?.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Disconnect error: ${e.message}")
>>>>>>> ce41075 (AndroidTV'de qr kodlu güvenlik sistemi sağlandı akabinde çoklu görsel iletimi ve 1,2,3,4 gibi kumanda tuşları ile aralarında geçiş sağlandı gereksiz buton widget'ları kaldırıldı proje daha sağlıklı hale getirildi.)
        }
    }
}