package com.example.tvimagereceiver

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.google.zxing.BarcodeFormat
import com.google.zxing.WriterException
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.*
import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.util.*

class MainActivity : Activity() {

    companion object {
        private const val TAG = "TV_RECEIVER"
        private const val BROKER_URI = "tcp://broker.hivemq.com:1883"
        private const val AUTO_HIDE_DELAY = 2000L // 2 seconds
        private const val PREFS_NAME = "tv_prefs"
        private const val KEY_SAVED_IMAGES = "saved_images"
        private const val KEY_CURRENT_INDEX = "current_image_index"
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

    // State
    private var isPaired = false
    private val downloadedImages = mutableListOf<String>()
    private var currentImageIndex = 0
    private val scope = CoroutineScope(Dispatchers.Main + Job())
    private val handler = Handler(Looper.getMainLooper())
    private var hideRunnable: Runnable? = null
    private var isShowingQRCode = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            // Initialize serial and topics
            serial = getOrCreateSerial()
            pairTopic = "tv/$serial/pair"
            imagesTopic = "tv/$serial/images"
            imageTopic = "tv/$serial/image"
            pairResponseTopic = "tv/$serial/pair_response"

            // Setup UI
            createUI()

            // Load saved images from SharedPreferences
            loadSavedImages()

            // Check if we have saved images
            if (downloadedImages.isNotEmpty()) {
                // Show saved images directly
                showSavedImagesMode()
                // Show the last viewed image
                showImage(currentImageIndex)
            } else {
                // No saved images, show QR code for first time setup
                showQRCodeMode()
            }

            // Connect to MQTT (always connect for receiving new images)
            connectToMqtt()

        } catch (e: Exception) {
            Log.e(TAG, "onCreate error: ${e.message}", e)
        }
    }

    private fun loadSavedImages() {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val savedImagesStr = prefs.getString(KEY_SAVED_IMAGES, null)
        currentImageIndex = prefs.getInt(KEY_CURRENT_INDEX, 0)

        if (!savedImagesStr.isNullOrEmpty()) {
            val paths = savedImagesStr.split(",")
            downloadedImages.clear()

            // Verify each file still exists
            paths.forEach { path ->
                if (File(path).exists()) {
                    downloadedImages.add(path)
                    Log.d(TAG, "Loaded saved image: $path")
                }
            }

            // Adjust current index if needed
            if (currentImageIndex >= downloadedImages.size) {
                currentImageIndex = 0
            }

            Log.d(TAG, "Loaded ${downloadedImages.size} saved images")
        }
    }

    private fun saveImagesToPreferences() {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val editor = prefs.edit()

        if (downloadedImages.isNotEmpty()) {
            val imagesStr = downloadedImages.joinToString(",")
            editor.putString(KEY_SAVED_IMAGES, imagesStr)
            editor.putInt(KEY_CURRENT_INDEX, currentImageIndex)
            Log.d(TAG, "Saved ${downloadedImages.size} images to preferences")
        } else {
            editor.remove(KEY_SAVED_IMAGES)
            editor.remove(KEY_CURRENT_INDEX)
        }

        editor.apply()
    }

    private fun showQRCodeMode() {
        isShowingQRCode = true

        // Generate new pairing code
        pairingCode = generatePairingCode()

        runOnUiThread {
            // Show QR code elements
            qrImageView.visibility = View.VISIBLE
            imageView.visibility = View.GONE
            infoLayout.visibility = View.VISIBLE

            // Update texts for QR mode
            titleText.text = "📺 Android TV Image Receiver"
            statusText.text = if (mqttClient?.isConnected == true) "Connected" else "Connecting..."
            statusText.setTextColor(if (mqttClient?.isConnected == true) Color.GREEN else Color.YELLOW)
            instructionText.text = "Scan QR code with mobile app"
            messageText.text = "Waiting for pairing..."
            messageText.setTextColor(Color.GRAY)
            imageCountText.visibility = View.GONE

            // Generate QR code
            generateQRCode()
        }
    }

    private fun showSavedImagesMode() {
        isShowingQRCode = false
        isPaired = true // Consider as paired if we have saved images

        runOnUiThread {
            // Hide QR code, show images
            qrImageView.visibility = View.GONE
            imageView.visibility = View.VISIBLE

            // Update instructions
            instructionText.text = "Press MENU or M to upload new images\nUse 1-9 or arrows to navigate"
            messageText.text = "Showing saved images (${downloadedImages.size} total)"
            messageText.setTextColor(Color.GREEN)
            imageCountText.visibility = View.VISIBLE

            // Auto-hide info after showing
            startAutoHideTimer()
        }
    }

    private fun generatePairingCode(): String {
        return UUID.randomUUID().toString().take(6).uppercase()
    }

    private fun getOrCreateSerial(): String {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
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
            scaleType = ImageView.ScaleType.CENTER_CROP
            setBackgroundColor(Color.BLACK)
            visibility = View.GONE
        }

        // Info layout (contains all text and QR code)
        infoLayout = LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#CC000000"))
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
        }

        // Status text
        statusText = TextView(this).apply {
            text = "Connecting..."
            textSize = 20f
            setTextColor(Color.YELLOW)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 20)
        }

        // Instructions
        instructionText = TextView(this).apply {
            text = "Scan QR code with mobile app"
            textSize = 18f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
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

        // Image count text
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

    // Handle keyboard input for image switching and menu
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // Handle MENU key or M key to show QR code for new upload
        when (keyCode) {
            KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_M -> {
                if (!isShowingQRCode) {
                    showQRCodeMode()
                    return true
                }
            }
            // ESC or BACK to exit QR mode and return to images
            KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BACK -> {
                if (isShowingQRCode && downloadedImages.isNotEmpty()) {
                    showSavedImagesMode()
                    showImage(currentImageIndex)
                    return true
                }
            }
        }

        // Only handle image navigation keys when we have images and not showing QR
        if (!isShowingQRCode && downloadedImages.isNotEmpty()) {
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
            saveImagesToPreferences() // Save current index
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
            saveImagesToPreferences() // Save current index
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
            saveImagesToPreferences() // Save current index
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
            if (isPaired && !isShowingQRCode) {
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

    private fun connectToMqtt() {
        scope.launch(Dispatchers.IO) {
            try {
                val clientId = "TV_${serial}_${System.currentTimeMillis()}"
                mqttClient = MqttClient(BROKER_URI, clientId, MemoryPersistence())

                val options = MqttConnectOptions().apply {
                    isCleanSession = true
                    connectionTimeout = 30
                    keepAliveInterval = 60
                    isAutomaticReconnect = true
                }

                mqttClient?.setCallback(object : MqttCallback {
                    override fun connectionLost(cause: Throwable?) {
                        Log.e(TAG, "Connection lost: ${cause?.message}")
                        runOnUiThread {
                            statusText.text = "Disconnected"
                            statusText.setTextColor(Color.RED)
                            if (!isShowingQRCode) {
                                showInfoTemporarily()
                            }
                        }
                        // Reconnect after delay
                        scope.launch {
                            delay(5000)
                            connectToMqtt()
                        }
                    }

                    override fun messageArrived(topic: String?, message: MqttMessage?) {
                        val payload = message?.toString() ?: return
                        Log.d(TAG, "Message on $topic")

                        when (topic) {
                            pairTopic -> handlePairRequest(payload)
                            imagesTopic -> handleImagesMessage(payload)
                            imageTopic -> handleImageIndex(payload)
                        }
                    }

                    override fun deliveryComplete(token: IMqttDeliveryToken?) {
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
                    if (!isShowingQRCode) {
                        showInfoTemporarily()
                    }
                }

                Log.i(TAG, "MQTT Connected")

            } catch (e: Exception) {
                Log.e(TAG, "MQTT Error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    statusText.text = "Connection Error"
                    statusText.setTextColor(Color.RED)
                    if (!isShowingQRCode) {
                        showInfoTemporarily()
                    }
                }
                delay(5000)
                connectToMqtt()
            }
        }
    }

    private fun handlePairRequest(payload: String) {
        try {
            val json = JSONObject(payload)
            val action = json.optString("action")
            val code = json.optString("pairingCode")

            if (action == "pair" && code == pairingCode) {
                isPaired = true
                isShowingQRCode = false

                runOnUiThread {
                    qrImageView.visibility = View.GONE
                    imageView.visibility = View.VISIBLE
                    messageText.text = "Paired Successfully! Waiting for images..."
                    messageText.setTextColor(Color.GREEN)
                    instructionText.text = "Images will be received shortly..."
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
        }
    }

    private fun handleImagesMessage(payload: String) {
        if (!isPaired) return

        try {
            val json = JSONObject(payload)
            val images = json.getJSONArray("images")

            runOnUiThread {
                messageText.text = "Downloading ${images.length()} images..."
                showInfoTemporarily()
            }

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
                        // Save images to preferences
                        saveImagesToPreferences()

                        // Show images mode
                        showSavedImagesMode()
                        showImage(0)

                        messageText.text = "${downloadedImages.size} new images received"
                        instructionText.text = "Press 1-${minOf(downloadedImages.size, 9)} to switch images\nPress MENU or M to upload new images"
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Images error: ${e.message}", e)
        }
    }

    private fun downloadImage(url: String, index: Int) {
        try {
            val dir = File(filesDir, "images")
            if (!dir.exists()) dir.mkdirs()

            val file = File(dir, "image_$index.jpg")

            URL(url).openStream().use { input ->
                FileOutputStream(file).use { output ->
                    input.copyTo(output)
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
        saveImagesToPreferences() // Save current index
    }

    private fun showImage(index: Int) {
        if (downloadedImages.isEmpty()) return

        val actualIndex = index.coerceIn(0, downloadedImages.size - 1)
        currentImageIndex = actualIndex
        val path = downloadedImages[actualIndex]

        runOnUiThread {
            try {
                val bitmap = BitmapFactory.decodeFile(path)
                imageView.setImageBitmap(bitmap)

                // Update image counter
                imageCountText.text = "Image ${actualIndex + 1} of ${downloadedImages.size}"
                messageText.text = "Showing image ${actualIndex + 1}/${downloadedImages.size}"

                // Briefly show info when changing images, then hide
                showInfoTemporarily()

            } catch (e: Exception) {
                Log.e(TAG, "Display error: ${e.message}")
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Save current state before destroying
        saveImagesToPreferences()
        scope.cancel()
        hideRunnable?.let { handler.removeCallbacks(it) }
        try {
            mqttClient?.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Disconnect error: ${e.message}")
        }
    }
}