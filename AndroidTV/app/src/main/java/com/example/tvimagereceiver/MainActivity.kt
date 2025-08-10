package com.example.tvimagereceiver

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
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
        private const val KEY_SAVED_MEDIA = "saved_media"
        private const val KEY_CURRENT_INDEX = "current_media_index"
    }

    // Media item class to store both images and videos
    data class MediaItem(
        val path: String,
        val type: MediaType,
        val index: Int,
        val originalUrl: String = "" // Store original URL for debugging
    )

    enum class MediaType {
        IMAGE, VIDEO
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
    private lateinit var requestQrTopic: String // New topic for QR requests

    // UI Components
    private lateinit var statusText: TextView
    private lateinit var messageText: TextView
    private lateinit var imageView: ImageView
    private lateinit var videoView: SurfaceView
    private lateinit var qrImageView: ImageView
    private lateinit var containerLayout: FrameLayout
    private lateinit var infoLayout: LinearLayout
    private lateinit var serialText: TextView
    private lateinit var instructionText: TextView
    private lateinit var titleText: TextView
    private lateinit var mediaCountText: TextView

    // Media Player for videos
    private var mediaPlayer: MediaPlayer? = null
    private var surfaceHolder: SurfaceHolder? = null
    private var surfaceReady = false
    private var pendingVideoPath: String? = null

    // State
    private var isPaired = false
    private val downloadedMedia = mutableListOf<MediaItem>()
    private var currentMediaIndex = 0
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
            requestQrTopic = "tv/$serial/request_qr" // New topic

            // Setup UI
            createUI()

            // Load saved media from SharedPreferences
            loadSavedMedia()

            // Check if we have saved media
            if (downloadedMedia.isNotEmpty()) {
                // Show saved media directly
                showSavedMediaMode()
                // Show the last viewed media
                showMedia(currentMediaIndex)
            } else {
                // No saved media, show QR code for first time setup
                showQRCodeMode()
            }

            // Connect to MQTT (always connect for receiving new media)
            connectToMqtt()

            // Show a hint toast on startup
            showHintToast()

        } catch (e: Exception) {
            Log.e(TAG, "onCreate error: ${e.message}", e)
        }
    }

    private fun showHintToast() {
        handler.postDelayed({
            if (!isShowingQRCode && downloadedMedia.isNotEmpty()) {
                Toast.makeText(
                    this,
                    "Press 0 key to show QR code for new uploads",
                    Toast.LENGTH_LONG
                ).show()
            }
        }, 3000)
    }

    private fun loadSavedMedia() {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val savedMediaStr = prefs.getString(KEY_SAVED_MEDIA, null)
        currentMediaIndex = prefs.getInt(KEY_CURRENT_INDEX, 0)

        if (!savedMediaStr.isNullOrEmpty()) {
            val mediaEntries = savedMediaStr.split("|")
            downloadedMedia.clear()

            // Parse each media entry (format: "path,type,index,url")
            mediaEntries.forEach { entry ->
                val parts = entry.split(",")
                if (parts.size >= 3) {
                    val path = parts[0]
                    val type = if (parts[1] == "VIDEO") MediaType.VIDEO else MediaType.IMAGE
                    val index = parts[2].toIntOrNull() ?: 0
                    val url = if (parts.size > 3) parts[3] else ""

                    if (File(path).exists()) {
                        downloadedMedia.add(MediaItem(path, type, index, url))
                        Log.d(TAG, "Loaded saved media: $path (${type.name})")
                    }
                }
            }

            // Adjust current index if needed
            if (currentMediaIndex >= downloadedMedia.size) {
                currentMediaIndex = 0
            }

            Log.d(TAG, "Loaded ${downloadedMedia.size} saved media items")
        }
    }

    private fun saveMediaToPreferences() {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val editor = prefs.edit()

        if (downloadedMedia.isNotEmpty()) {
            // Format: "path,type,index,url|path,type,index,url|..."
            val mediaStr = downloadedMedia.joinToString("|") {
                "${it.path},${it.type.name},${it.index},${it.originalUrl}"
            }
            editor.putString(KEY_SAVED_MEDIA, mediaStr)
            editor.putInt(KEY_CURRENT_INDEX, currentMediaIndex)
            Log.d(TAG, "Saved ${downloadedMedia.size} media items to preferences")
        } else {
            editor.remove(KEY_SAVED_MEDIA)
            editor.remove(KEY_CURRENT_INDEX)
        }

        editor.apply()
    }

    private fun showQRCodeMode() {
        isShowingQRCode = true

        // Stop any playing video
        stopVideo()

        // Generate new pairing code
        pairingCode = generatePairingCode()

        // Cancel any hide timer
        hideRunnable?.let { handler.removeCallbacks(it) }

        runOnUiThread {
            // Show QR code elements
            qrImageView.visibility = View.VISIBLE
            imageView.visibility = View.GONE
            videoView.visibility = View.GONE
            infoLayout.visibility = View.VISIBLE

            // Update texts for QR mode
            titleText.text = "📺 Android TV Media Receiver"
            statusText.text = if (mqttClient?.isConnected == true) "Connected" else "Connecting..."
            statusText.setTextColor(if (mqttClient?.isConnected == true) Color.GREEN else Color.YELLOW)
            instructionText.text = "Scan QR code with mobile app"
            messageText.text = "Waiting for pairing..."
            messageText.setTextColor(Color.GRAY)
            mediaCountText.visibility = View.GONE

            // Generate QR code
            generateQRCode()

            // Show toast
            Toast.makeText(this, "QR Code Mode - Ready for pairing", Toast.LENGTH_SHORT).show()
        }

        Log.d(TAG, "QR Code mode activated - Pairing code: $pairingCode")
    }

    private fun showSavedMediaMode() {
        isShowingQRCode = false
        isPaired = true // Consider as paired if we have saved media

        runOnUiThread {
            // Hide QR code
            qrImageView.visibility = View.GONE

            // Update instructions
            instructionText.text = "Press 0 to upload new media\nUse 1-9 or arrows to navigate"
            messageText.text = "Showing saved media (${downloadedMedia.size} items)"
            messageText.setTextColor(Color.GREEN)
            mediaCountText.visibility = View.VISIBLE

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

        // Video view (fullscreen)
        videoView = SurfaceView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            visibility = View.GONE
        }

        // Setup video surface holder
        surfaceHolder = videoView.holder
        surfaceHolder?.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                // Surface is ready
                surfaceReady = true
                Log.d(TAG, "Surface created and ready")

                // If there's a pending video, play it now
                pendingVideoPath?.let { path ->
                    playVideo(path)
                    pendingVideoPath = null
                }
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                // Surface changed
                Log.d(TAG, "Surface changed: ${width}x${height}")
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                surfaceReady = false
                stopVideo()
                Log.d(TAG, "Surface destroyed")
            }
        })

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
            text = "📺 Android TV Media Receiver"
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

        // Media count text
        mediaCountText = TextView(this).apply {
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
        infoLayout.addView(mediaCountText)

        // Add to main container (order matters)
        containerLayout.addView(imageView)
        containerLayout.addView(videoView)
        containerLayout.addView(infoLayout)

        setContentView(containerLayout)
    }

    // Handle keyboard input for media switching and menu
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        Log.d(TAG, "Key pressed: $keyCode, isShowingQR: $isShowingQRCode")

        // Handle 0 key to show QR code for new upload
        when (keyCode) {
            KeyEvent.KEYCODE_0, KeyEvent.KEYCODE_NUMPAD_0 -> {
                // Only handle 0 for QR mode if we have saved media
                // Otherwise, 0 can be used for media navigation
                if (downloadedMedia.isNotEmpty()) {
                    Log.d(TAG, "0 key pressed - toggling QR mode")
                    if (!isShowingQRCode) {
                        showQRCodeMode()
                    } else {
                        // If already showing QR, go back to media
                        showSavedMediaMode()
                        showMedia(currentMediaIndex)
                    }
                    return true
                }
            }
            // ESC or BACK to exit QR mode and return to media
            KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BACK -> {
                if (isShowingQRCode && downloadedMedia.isNotEmpty()) {
                    Log.d(TAG, "ESC/BACK pressed - exiting QR mode")
                    showSavedMediaMode()
                    showMedia(currentMediaIndex)
                    return true
                }
            }
        }

        // Only handle media navigation keys when we have media and not showing QR
        if (!isShowingQRCode && downloadedMedia.isNotEmpty()) {
            when (keyCode) {
                KeyEvent.KEYCODE_1, KeyEvent.KEYCODE_NUMPAD_1 -> {
                    showMediaByNumber(0)
                    return true
                }
                KeyEvent.KEYCODE_2, KeyEvent.KEYCODE_NUMPAD_2 -> {
                    showMediaByNumber(1)
                    return true
                }
                KeyEvent.KEYCODE_3, KeyEvent.KEYCODE_NUMPAD_3 -> {
                    showMediaByNumber(2)
                    return true
                }
                KeyEvent.KEYCODE_4, KeyEvent.KEYCODE_NUMPAD_4 -> {
                    showMediaByNumber(3)
                    return true
                }
                KeyEvent.KEYCODE_5, KeyEvent.KEYCODE_NUMPAD_5 -> {
                    showMediaByNumber(4)
                    return true
                }
                KeyEvent.KEYCODE_6, KeyEvent.KEYCODE_NUMPAD_6 -> {
                    showMediaByNumber(5)
                    return true
                }
                KeyEvent.KEYCODE_7, KeyEvent.KEYCODE_NUMPAD_7 -> {
                    showMediaByNumber(6)
                    return true
                }
                KeyEvent.KEYCODE_8, KeyEvent.KEYCODE_NUMPAD_8 -> {
                    showMediaByNumber(7)
                    return true
                }
                KeyEvent.KEYCODE_9, KeyEvent.KEYCODE_NUMPAD_9 -> {
                    showMediaByNumber(8)
                    return true
                }
                // Arrow keys for navigation
                KeyEvent.KEYCODE_DPAD_LEFT -> {
                    showPreviousMedia()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_RIGHT -> {
                    showNextMedia()
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

    private fun showMediaByNumber(index: Int) {
        if (index < downloadedMedia.size) {
            currentMediaIndex = index
            showMedia(currentMediaIndex)
            saveMediaToPreferences()
            Log.d(TAG, "Switched to media ${index + 1} via keyboard")
        } else {
            Log.d(TAG, "Media ${index + 1} not available (only ${downloadedMedia.size} items)")
            runOnUiThread {
                messageText.text = "Media ${index + 1} not available"
                showInfoTemporarily()
            }
        }
    }

    private fun showNextMedia() {
        if (downloadedMedia.isNotEmpty()) {
            currentMediaIndex = (currentMediaIndex + 1) % downloadedMedia.size
            showMedia(currentMediaIndex)
            saveMediaToPreferences()
            Log.d(TAG, "Showing next media: ${currentMediaIndex + 1}")
        }
    }

    private fun showPreviousMedia() {
        if (downloadedMedia.isNotEmpty()) {
            currentMediaIndex = if (currentMediaIndex > 0) {
                currentMediaIndex - 1
            } else {
                downloadedMedia.size - 1
            }
            showMedia(currentMediaIndex)
            saveMediaToPreferences()
            Log.d(TAG, "Showing previous media: ${currentMediaIndex + 1}")
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
                // Hide info layout when paired and showing media
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
                            imagesTopic -> handleMediaMessage(payload)
                            imageTopic -> handleMediaIndex(payload)
                            requestQrTopic -> handleQrRequest() // Handle QR request
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
                mqttClient?.subscribe(requestQrTopic, 1) // Subscribe to QR request topic

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

    private fun handleQrRequest() {
        // When mobile app requests QR, show it
        Log.d(TAG, "QR request received from mobile app")
        runOnUiThread {
            showQRCodeMode()
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
                    messageText.text = "Paired Successfully! Waiting for media..."
                    messageText.setTextColor(Color.GREEN)
                    instructionText.text = "Media will be received shortly..."
                    mediaCountText.visibility = View.VISIBLE

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

    private fun handleMediaMessage(payload: String) {
        if (!isPaired) return

        try {
            val json = JSONObject(payload)
            val mediaArray = json.getJSONArray("media")

            runOnUiThread {
                messageText.text = "Downloading ${mediaArray.length()} media files..."
                showInfoTemporarily()
            }

            scope.launch(Dispatchers.IO) {
                downloadedMedia.clear()
                currentMediaIndex = 0

                for (i in 0 until mediaArray.length()) {
                    val mediaObj = mediaArray.getJSONObject(i)
                    val url = mediaObj.getString("url")
                    val type = mediaObj.optString("type", "image")
                    val name = mediaObj.optString("name", "media_$i")

                    Log.d(TAG, "Processing media $i: type=$type, url=$url, name=$name")

                    if (type.equals("video", ignoreCase = true)) {
                        downloadVideo(url, i, name)
                    } else {
                        downloadImage(url, i)
                    }
                }

                withContext(Dispatchers.Main) {
                    if (downloadedMedia.isNotEmpty()) {
                        // Save media to preferences
                        saveMediaToPreferences()

                        // Show media mode
                        showSavedMediaMode()
                        showMedia(0)

                        messageText.text = "${downloadedMedia.size} media files received"
                        instructionText.text = "Press 1-${minOf(downloadedMedia.size, 9)} to switch media\nPress 0 to upload new media"
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Media error: ${e.message}", e)
        }
    }

    private fun downloadImage(url: String, index: Int) {
        try {
            val dir = File(filesDir, "media")
            if (!dir.exists()) dir.mkdirs()

            val file = File(dir, "image_$index.jpg")

            Log.d(TAG, "Downloading image $index from: $url")

            URL(url).openStream().use { input ->
                FileOutputStream(file).use { output ->
                    input.copyTo(output)
                }
            }

            downloadedMedia.add(MediaItem(file.absolutePath, MediaType.IMAGE, index, url))
            Log.d(TAG, "Downloaded image $index successfully to: ${file.absolutePath}")

        } catch (e: Exception) {
            Log.e(TAG, "Download failed for image $index: ${e.message}", e)
        }
    }

    private fun downloadVideo(url: String, index: Int, name: String) {
        try {
            val dir = File(filesDir, "media")
            if (!dir.exists()) dir.mkdirs()

            // Determine file extension from name or default to mp4
            val extension = when {
                name.lowercase().endsWith(".mp4") -> "mp4"
                name.lowercase().endsWith(".mov") -> "mov"
                name.lowercase().endsWith(".avi") -> "avi"
                name.lowercase().endsWith(".mkv") -> "mkv"
                else -> "mp4"
            }

            val file = File(dir, "video_$index.$extension")

            Log.d(TAG, "Downloading video $index from: $url")
            Log.d(TAG, "Video will be saved as: ${file.absolutePath}")

            // Download the video file
            val connection = URL(url).openConnection()
            connection.connectTimeout = 30000 // 30 seconds
            connection.readTimeout = 30000    // 30 seconds

            connection.getInputStream().use { input ->
                FileOutputStream(file).use { output ->
                    val buffer = ByteArray(4096)
                    var bytesRead: Int
                    var totalBytes = 0L

                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalBytes += bytesRead

                        // Log progress every MB
                        if (totalBytes % (1024 * 1024) == 0L) {
                            Log.d(TAG, "Downloaded ${totalBytes / (1024 * 1024)} MB...")
                        }
                    }

                    Log.d(TAG, "Video download complete: ${totalBytes / 1024} KB")
                }
            }

            // Verify file exists and has content
            if (file.exists() && file.length() > 0) {
                downloadedMedia.add(MediaItem(file.absolutePath, MediaType.VIDEO, index, url))
                Log.d(TAG, "Downloaded video $index successfully: ${file.absolutePath} (${file.length() / 1024} KB)")
            } else {
                Log.e(TAG, "Video file is empty or doesn't exist: ${file.absolutePath}")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Download failed for video $index: ${e.message}", e)
            // If video download fails, try to use the URL directly (for testing)
            Log.w(TAG, "Attempting to use fallback for video playback")
        }
    }

    private fun handleMediaIndex(payload: String) {
        val index = payload.toIntOrNull() ?: 0
        currentMediaIndex = index
        showMedia(index)
        saveMediaToPreferences()
    }

    private fun showMedia(index: Int) {
        if (downloadedMedia.isEmpty()) return

        val actualIndex = index.coerceIn(0, downloadedMedia.size - 1)
        currentMediaIndex = actualIndex
        val mediaItem = downloadedMedia[actualIndex]

        runOnUiThread {
            try {
                // Stop any playing video first
                stopVideo()

                when (mediaItem.type) {
                    MediaType.IMAGE -> {
                        // Show image
                        imageView.visibility = View.VISIBLE
                        videoView.visibility = View.GONE

                        val bitmap = BitmapFactory.decodeFile(mediaItem.path)
                        if (bitmap != null) {
                            imageView.setImageBitmap(bitmap)
                            Log.d(TAG, "Showing image: ${mediaItem.path}")
                        } else {
                            Log.e(TAG, "Failed to decode image: ${mediaItem.path}")
                        }

                        mediaCountText.text = "Image ${actualIndex + 1} of ${downloadedMedia.size}"
                        messageText.text = "Showing image ${actualIndex + 1}/${downloadedMedia.size}"
                    }
                    MediaType.VIDEO -> {
                        // Show video
                        imageView.visibility = View.GONE
                        videoView.visibility = View.VISIBLE

                        Log.d(TAG, "Preparing to show video: ${mediaItem.path}")
                        Log.d(TAG, "Video file exists: ${File(mediaItem.path).exists()}")
                        Log.d(TAG, "Video file size: ${File(mediaItem.path).length() / 1024} KB")

                        // Give surface time to be ready if needed
                        if (surfaceReady) {
                            playVideo(mediaItem.path)
                        } else {
                            Log.d(TAG, "Waiting for surface to be ready...")
                            pendingVideoPath = mediaItem.path
                            // Force surface creation if needed
                            videoView.holder.setType(SurfaceHolder.SURFACE_TYPE_PUSH_BUFFERS)
                        }

                        mediaCountText.text = "Video ${actualIndex + 1} of ${downloadedMedia.size}"
                        messageText.text = "Playing video ${actualIndex + 1}/${downloadedMedia.size}"
                    }
                }

                // Briefly show info when changing media, then hide
                showInfoTemporarily()

            } catch (e: Exception) {
                Log.e(TAG, "Display error: ${e.message}", e)
                runOnUiThread {
                    messageText.text = "Error displaying media: ${e.message}"
                    messageText.setTextColor(Color.RED)
                    showInfoTemporarily()
                }
            }
        }
    }

    private fun playVideo(path: String) {
        try {
            // If surface is not ready, save the path to play later
            if (!surfaceReady) {
                Log.d(TAG, "Surface not ready, saving video path for later")
                pendingVideoPath = path
                return
            }

            // Stop and release any existing player
            stopVideo()

            Log.d(TAG, "Starting video playback: $path")

            // Check if file exists
            val videoFile = File(path)
            if (!videoFile.exists()) {
                Log.e(TAG, "Video file does not exist: $path")
                runOnUiThread {
                    messageText.text = "Video file not found"
                    messageText.setTextColor(Color.RED)
                    showInfoTemporarily()
                }
                return
            }

            if (videoFile.length() == 0L) {
                Log.e(TAG, "Video file is empty: $path")
                runOnUiThread {
                    messageText.text = "Video file is empty"
                    messageText.setTextColor(Color.RED)
                    showInfoTemporarily()
                }
                return
            }

            Log.d(TAG, "Video file confirmed: ${videoFile.absolutePath} (${videoFile.length() / 1024} KB)")

            mediaPlayer = MediaPlayer().apply {
                try {
                    // Use file descriptor for better compatibility
                    setDataSource(this@MainActivity, Uri.fromFile(videoFile))
                    setDisplay(surfaceHolder)

                    setOnPreparedListener { mp ->
                        Log.d(TAG, "Video prepared successfully")
                        Log.d(TAG, "Video duration: ${mp.duration} ms")
                        Log.d(TAG, "Video size: ${mp.videoWidth}x${mp.videoHeight}")

                        mp.start()
                        mp.isLooping = true // Enable looping

                        runOnUiThread {
                            messageText.text = "Playing video"
                            messageText.setTextColor(Color.GREEN)
                        }
                    }

                    setOnErrorListener { mp, what, extra ->
                        Log.e(TAG, "MediaPlayer error: what=$what, extra=$extra")

                        val errorMsg = when (what) {
                            MediaPlayer.MEDIA_ERROR_UNKNOWN -> "Unknown error"
                            MediaPlayer.MEDIA_ERROR_SERVER_DIED -> "Server died"
                            else -> "Error code: $what"
                        }

                        val extraMsg = when (extra) {
                            MediaPlayer.MEDIA_ERROR_IO -> "IO error"
                            MediaPlayer.MEDIA_ERROR_MALFORMED -> "Malformed media"
                            MediaPlayer.MEDIA_ERROR_UNSUPPORTED -> "Unsupported format"
                            MediaPlayer.MEDIA_ERROR_TIMED_OUT -> "Timed out"
                            else -> "Extra code: $extra"
                        }

                        Log.e(TAG, "MediaPlayer error details: $errorMsg, $extraMsg")

                        runOnUiThread {
                            messageText.text = "Video error: $errorMsg"
                            messageText.setTextColor(Color.RED)
                            showInfoTemporarily()
                        }

                        // Try to recover
                        mp.reset()
                        false
                    }

                    setOnCompletionListener { mp ->
                        Log.d(TAG, "Video completed, looping...")
                    }

                    setOnInfoListener { mp, what, extra ->
                        Log.d(TAG, "MediaPlayer info: what=$what, extra=$extra")
                        false
                    }

                    // Prepare asynchronously to avoid blocking
                    prepareAsync()

                } catch (e: Exception) {
                    Log.e(TAG, "Error setting data source: ${e.message}", e)
                    release()

                    runOnUiThread {
                        messageText.text = "Cannot play video: ${e.message}"
                        messageText.setTextColor(Color.RED)
                        showInfoTemporarily()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Video playback error: ${e.message}", e)
            runOnUiThread {
                messageText.text = "Video playback failed: ${e.message}"
                messageText.setTextColor(Color.RED)
                showInfoTemporarily()
            }
        }
    }

    private fun stopVideo() {
        try {
            mediaPlayer?.let { player ->
                if (player.isPlaying) {
                    player.stop()
                }
                player.release()
            }
            mediaPlayer = null
            Log.d(TAG, "Video stopped and released")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping video: ${e.message}")
        }
    }

    override fun onPause() {
        super.onPause()
        stopVideo()
    }

    override fun onResume() {
        super.onResume()
        // Resume video if it was playing
        if (!isShowingQRCode &&
            downloadedMedia.isNotEmpty() &&
            currentMediaIndex < downloadedMedia.size &&
            downloadedMedia[currentMediaIndex].type == MediaType.VIDEO) {
            // Wait a bit for surface to be ready
            handler.postDelayed({
                if (surfaceReady) {
                    playVideo(downloadedMedia[currentMediaIndex].path)
                }
            }, 100)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Save current state before destroying
        saveMediaToPreferences()
        stopVideo()
        scope.cancel()
        hideRunnable?.let { handler.removeCallbacks(it) }
        try {
            mqttClient?.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Disconnect error: ${e.message}")
        }
    }
}