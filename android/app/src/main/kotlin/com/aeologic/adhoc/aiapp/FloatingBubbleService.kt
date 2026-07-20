package com.aeologic.adhoc.aiapp

import android.app.*
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.text.InputType
import android.util.DisplayMetrics
import android.util.Log
import android.view.*
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.*
import androidx.core.app.NotificationCompat
import java.io.ByteArrayOutputStream

class FloatingBubbleService : Service() {

    companion object {
        private const val TAG = "FloatingBubbleService"
        private const val CHANNEL_ID = "floating_bubble_channel"
        private const val NOTIFICATION_ID = 8868
        const val ACTION_STOP_BUBBLE = "com.aeologic.adhoc.aiapp.ACTION_STOP_BUBBLE"
        
        var isRunning = false
        var instance: FloatingBubbleService? = null
        
        // Reference to projection data
        var resultCode: Int = 0
        var resultData: Intent? = null

        // Persistent card dimensions across captures within the session
        private var sessionCardWidthPx = 0
        private var sessionCardHeightPx = 0
    }

    private lateinit var windowManager: WindowManager
    private var containerView: ViewGroup? = null
    private var bubbleFrame: FrameLayout? = null
    private var cardView: View? = null
    private var windowParams: WindowManager.LayoutParams? = null
    
    private var muteBtn: ImageView? = null
    private var contentTextView: TextView? = null
    private var questionEditText: EditText? = null
    private var closeBadge: TextView? = null
    
    var isMuted = false
        set(value) {
            field = value
            Handler(Looper.getMainLooper()).post {
                updateMuteIcon()
            }
        }

    private var lastCapturedJpegBytes: ByteArray? = null
    private var mediaProjection: MediaProjection? = null
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, getNotification(), 
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            } else {
                0
            }
        )
        
        setupViews()
        initMediaProjection()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_BUBBLE) {
            Log.d(TAG, "onStartCommand: ACTION_STOP_BUBBLE received. Cleaning up service.")
            MainActivity.invokeServiceStoppedCallback()
            stopSelfAndCleanUp()
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        stopSelfAndCleanUp()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Floating Bubble Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun getNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val stopIntent = Intent(this, FloatingBubbleService::class.java).apply {
            action = ACTION_STOP_BUBBLE
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Floating Answer Bubble")
            .setContentText("Tap overlay bubble to answer screen content")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            .build()
    }

    private fun initMediaProjection() {
        val mpManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        try {
            mediaProjection = mpManager.getMediaProjection(resultCode, resultData!!)
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing MediaProjection: ${e.message}")
        }
    }

    private fun stopMediaProjection() {
        mediaProjection?.stop()
        mediaProjection = null
    }

    private fun setupViews() {
        val context = this
        
        // Parent Container holding BOTH Bubble and Expanded Card as ONE Compound Unit View
        val parentContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.START
        }
        
        // 1. Bubble Frame (56dp circle icon + optional close badge)
        val bubbleFrameView = FrameLayout(context)
        val bubbleInner = ImageView(context).apply {
            setImageResource(android.R.drawable.ic_menu_compass)
            val circleShape = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF6C63FF.toInt())
            }
            background = circleShape
            setPadding(16, 16, 16, 16)
        }
        
        val bubbleSize = dpToPx(56)
        val bubbleLayoutParams = FrameLayout.LayoutParams(bubbleSize, bubbleSize)
        bubbleFrameView.addView(bubbleInner, bubbleLayoutParams)
        
        // Close Badge on Bubble (Revealed on Long-Press to fully stop service)
        val badgeView = TextView(context).apply {
            text = "✕"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 11f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
            val badgeBg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFFFF3B30.toInt())
            }
            background = badgeBg
            visibility = View.GONE
            setOnClickListener {
                stopSelfAndCleanUp()
            }
        }
        closeBadge = badgeView
        val badgeSize = dpToPx(20)
        val badgeParams = FrameLayout.LayoutParams(badgeSize, badgeSize).apply {
            gravity = Gravity.TOP or Gravity.END
        }
        bubbleFrameView.addView(badgeView, badgeParams)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            bubbleFrameView.outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: android.graphics.Outline) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
            bubbleFrameView.clipToOutline = false
        }
        
        bubbleFrame = bubbleFrameView
        parentContainer.addView(bubbleFrameView, LinearLayout.LayoutParams(bubbleSize, bubbleSize))
        
        // 2. Expanded Card View
        val cardLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpToPx(16), dpToPx(12), dpToPx(16), dpToPx(12))
            
            // Glassmorphism dark aesthetic
            val shape = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(16).toFloat()
                setColor(0xE61A1A2E.toInt())
                setStroke(dpToPx(1), 0x33FFFFFF.toInt())
            }
            background = shape
        }
        
        // Header Row: Title + Copy Button + Mute Button + Collapse Card Button
        val headerRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        
        val titleText = TextView(context).apply {
            text = "SCREEN ANSWER"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 12f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        headerRow.addView(titleText, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        
        // FEATURE: Copy Button
        val copyIcon = TextView(context).apply {
            text = "📋"
            textSize = 14f
            setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
            contentDescription = "Copy Answer"
            setOnClickListener {
                copyAnswerToClipboard()
            }
        }
        headerRow.addView(copyIcon, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        // Mute Toggle Button
        val muteIcon = ImageView(context).apply {
            setPadding(dpToPx(6), dpToPx(6), dpToPx(6), dpToPx(6))
            contentDescription = "Mute TTS"
            setOnClickListener {
                toggleMute()
            }
        }
        muteBtn = muteIcon
        updateMuteIcon()
        headerRow.addView(muteIcon, LinearLayout.LayoutParams(dpToPx(32), dpToPx(32)))
        
        // Collapse Card Button (X) — ONLY collapses the card, does NOT stop the service!
        val closeIcon = TextView(context).apply {
            text = "✕"
            setTextColor(0xFFFF5252.toInt())
            textSize = 16f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(dpToPx(8), dpToPx(4), dpToPx(8), dpToPx(4))
            setOnClickListener {
                cardView?.visibility = View.GONE
                enableOverlayFocus(false)
            }
        }
        headerRow.addView(closeIcon, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        
        cardLayout.addView(headerRow)
        
        // Separator
        val separator = View(context).apply {
            setBackgroundColor(0x33FFFFFF.toInt())
        }
        val sepParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpToPx(1)).apply {
            topMargin = dpToPx(6)
            bottomMargin = dpToPx(8)
        }
        cardLayout.addView(separator, sepParams)
        
        // Scrollable Answer Content
        val scrollView = ScrollView(context)
        val contentText = TextView(context).apply {
            text = "Tap the bubble to analyze what is currently shown on your screen."
            setTextColor(0xCCFFFFFF.toInt())
            textSize = 13f
            setTextIsSelectable(true)
        }
        contentTextView = contentText
        scrollView.addView(contentText)
        
        val initialScrollHeight = if (sessionCardHeightPx > 0) (sessionCardHeightPx - dpToPx(110)).coerceAtLeast(dpToPx(60)) else dpToPx(130)
        val scrollParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, initialScrollHeight)
        cardLayout.addView(scrollView, scrollParams)
        
        // Question Input Row
        val inputRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val marginParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            marginParams.topMargin = dpToPx(8)
            layoutParams = marginParams
        }
        
        val inputEdit = EditText(context).apply {
            hint = "Ask a question..."
            setHintTextColor(0x77FFFFFF.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 12f
            setSingleLine(true)
            imeOptions = EditorInfo.IME_ACTION_SEND
            inputType = InputType.TYPE_CLASS_TEXT
            
            val editBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(0x33FFFFFF.toInt())
                setStroke(dpToPx(1), 0x22FFFFFF.toInt())
            }
            background = editBg
            setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8))
            
            setOnFocusChangeListener { _, hasFocus ->
                enableOverlayFocus(hasFocus)
            }
            
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_SEND || actionId == EditorInfo.IME_ACTION_DONE) {
                    submitCustomQuestion()
                    true
                } else {
                    false
                }
            }
        }
        questionEditText = inputEdit
        inputRow.addView(inputEdit, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        
        val askButton = TextView(context).apply {
            text = "Ask"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 12f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            val btnBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(8).toFloat()
                setColor(0xFF6C63FF.toInt())
            }
            background = btnBg
            setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))
            val askParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            askParams.marginStart = dpToPx(6)
            layoutParams = askParams
            
            setOnClickListener {
                submitCustomQuestion()
            }
        }
        inputRow.addView(askButton)
        
        cardLayout.addView(inputRow)
        
        // FEATURE: Bottom Footer Row with Resize Handle Grip ("◢")
        val footerRow = FrameLayout(context).apply {
            val footerLp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            footerLp.topMargin = dpToPx(4)
            layoutParams = footerLp
        }
        val resizeGrip = TextView(context).apply {
            text = "◢"
            setTextColor(0x88FFFFFF.toInt())
            textSize = 14f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            gravity = Gravity.BOTTOM or Gravity.END
            setPadding(dpToPx(4), dpToPx(2), dpToPx(4), dpToPx(2))
        }
        val gripLp = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.BOTTOM or Gravity.END
        }
        footerRow.addView(resizeGrip, gripLp)
        cardLayout.addView(footerRow)
        
        // Drag Resize Listener on Grip Handle
        var initialResizeW = 0
        var initialResizeH = 0
        var initialResizeX = 0f
        var initialResizeY = 0f

        resizeGrip.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialResizeW = cardLayout.width
                    initialResizeH = cardLayout.height
                    initialResizeX = event.rawX
                    initialResizeY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = (event.rawX - initialResizeX).toInt()
                    val deltaY = (event.rawY - initialResizeY).toInt()

                    val metrics = resources.displayMetrics
                    val minWidth = dpToPx(200)
                    val maxWidth = (metrics.widthPixels * 0.9).toInt()
                    val minHeight = dpToPx(160)
                    val maxHeight = (metrics.heightPixels * 0.85).toInt()

                    val newWidth = (initialResizeW + deltaX).coerceIn(minWidth, maxWidth)
                    val newHeight = (initialResizeH + deltaY).coerceIn(minHeight, maxHeight)

                    sessionCardWidthPx = newWidth
                    sessionCardHeightPx = newHeight

                    val cardLp = cardLayout.layoutParams
                    cardLp.width = newWidth
                    cardLp.height = newHeight
                    cardLayout.layoutParams = cardLp
                    cardLayout.requestLayout()

                    // Adjust ScrollView height dynamically to fit container
                    val currentScrollLp = scrollView.layoutParams
                    currentScrollLp.height = (newHeight - dpToPx(110)).coerceAtLeast(dpToPx(60))
                    scrollView.layoutParams = currentScrollLp
                    scrollView.requestLayout()

                    true
                }
                else -> false
            }
        }
        
        cardView = cardLayout
        cardView?.visibility = View.GONE
        
        val initialCardW = if (sessionCardWidthPx > 0) sessionCardWidthPx else dpToPx(280)
        val initialCardH = if (sessionCardHeightPx > 0) sessionCardHeightPx else LinearLayout.LayoutParams.WRAP_CONTENT
        val cardLayoutParams = LinearLayout.LayoutParams(initialCardW, initialCardH)
        cardLayoutParams.topMargin = dpToPx(8)
        parentContainer.addView(cardLayout, cardLayoutParams)
        
        // WindowManager LayoutParams for Parent Container View
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) 
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY 
            else 
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 300
        }
        
        windowParams = params
        containerView = parentContainer
        
        windowManager.addView(containerView, windowParams)
        
        // Drag, Tap, and Long-Press Listener attached to Bubble Frame
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isLongPress = false
        
        val longPressHandler = Handler(Looper.getMainLooper())
        val longPressRunnable = Runnable {
            isLongPress = true
            closeBadge?.visibility = if (closeBadge?.visibility == View.VISIBLE) View.GONE else View.VISIBLE
        }
        
        bubbleFrameView.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    val currentParams = windowParams ?: return@setOnTouchListener false
                    initialX = currentParams.x
                    initialY = currentParams.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isLongPress = false
                    longPressHandler.postDelayed(longPressRunnable, 600)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val diffX = Math.abs(event.rawX - initialTouchX)
                    val diffY = Math.abs(event.rawY - initialTouchY)
                    if (diffX > 10 || diffY > 10) {
                        longPressHandler.removeCallbacks(longPressRunnable)
                        if (!isLongPress) {
                            val currentParams = windowParams ?: return@setOnTouchListener false
                            currentParams.x = initialX + (event.rawX - initialTouchX).toInt()
                            currentParams.y = initialY + (event.rawY - initialTouchY).toInt()
                            windowManager.updateViewLayout(containerView, currentParams)
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    longPressHandler.removeCallbacks(longPressRunnable)
                    if (!isLongPress) {
                        val diffX = Math.abs(event.rawX - initialTouchX)
                        val diffY = Math.abs(event.rawY - initialTouchY)
                        if (diffX < 10 && diffY < 10) {
                            if (closeBadge?.visibility == View.VISIBLE) {
                                closeBadge?.visibility = View.GONE
                            } else {
                                onBubbleTapped()
                            }
                        }
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    longPressHandler.removeCallbacks(longPressRunnable)
                    true
                }
                else -> false
            }
        }
    }

    private fun copyAnswerToClipboard() {
        val text = contentTextView?.text?.toString() ?: ""
        if (text.isEmpty() || text.startsWith("Tap to analyze") || text.startsWith("Capturing") || text.startsWith("Thinking")) {
            Toast.makeText(this, "No answer to copy yet", Toast.LENGTH_SHORT).show()
            return
        }
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("Screen Answer", text)
            clipboard.setPrimaryClip(clip)
            Toast.makeText(this, "Answer copied to clipboard", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy to clipboard: ${e.message}")
        }
    }

    private fun updateMuteIcon() {
        muteBtn?.setImageResource(
            if (isMuted) android.R.drawable.ic_lock_silent_mode
            else android.R.drawable.ic_lock_silent_mode_off
        )
        muteBtn?.alpha = if (isMuted) 0.5f else 1.0f
    }

    private fun toggleMute() {
        isMuted = !isMuted
        if (isMuted) {
            MainActivity.stopSpeaking()
        }
    }

    private fun enableOverlayFocus(enable: Boolean) {
        val params = windowParams ?: return
        val container = containerView ?: return
        
        if (enable) {
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            @Suppress("DEPRECATION")
            params.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        } else {
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        }
        try {
            windowManager.updateViewLayout(container, params)
        } catch (e: Exception) {
            Log.e(TAG, "Error updating window focus flags: ${e.message}")
        }
    }

    private fun submitCustomQuestion() {
        val edit = questionEditText ?: return
        val question = edit.text.toString().trim()
        if (question.isEmpty()) return
        
        edit.clearFocus()
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(edit.windowToken, 0)
        enableOverlayFocus(false)
        edit.setText("")
        
        if (!MainActivity.isEngineActive()) {
            contentTextView?.text = "Please open the app once to initialize this feature."
            cardView?.visibility = View.VISIBLE
            return
        }
        
        contentTextView?.text = "Thinking..."
        cardView?.visibility = View.VISIBLE
        
        val bytes = lastCapturedJpegBytes
        if (bytes != null) {
            MainActivity.invokeCustomQuestionCallback(question, bytes)
        } else {
            captureScreen { capturedBytes ->
                if (capturedBytes != null) {
                    lastCapturedJpegBytes = capturedBytes
                    MainActivity.invokeCustomQuestionCallback(question, capturedBytes)
                } else {
                    contentTextView?.text = "Error capturing screen context."
                }
            }
        }
    }

    private fun onBubbleTapped() {
        if (cardView?.visibility == View.VISIBLE) {
            triggerScreenCaptureAndAnalysis()
        } else {
            cardView?.visibility = View.VISIBLE
            triggerScreenCaptureAndAnalysis()
        }
    }

    private fun triggerScreenCaptureAndAnalysis() {
        if (!MainActivity.isEngineActive()) {
            contentTextView?.text = "Please open the app once to initialize this feature."
            cardView?.visibility = View.VISIBLE
            return
        }

        contentTextView?.text = "Capturing screen..."
        cardView?.visibility = View.VISIBLE

        captureScreen { jpegBytes ->
            if (jpegBytes != null) {
                lastCapturedJpegBytes = jpegBytes
                contentTextView?.text = "Analyzing screen context..."
                val sent = MainActivity.invokeScreenshotCallback(jpegBytes)
                if (!sent) {
                    contentTextView?.text = "Please open the app once to initialize this feature."
                }
            } else {
                contentTextView?.text = "Error capturing screen. Please restart service."
            }
        }
    }

    fun showAnswer(text: String) {
        Handler(Looper.getMainLooper()).post {
            cardView?.visibility = View.VISIBLE
            contentTextView?.text = text
        }
    }

    private fun captureScreen(callback: (ByteArray?) -> Unit) {
        val displayManager = getSystemService(DISPLAY_SERVICE) as DisplayManager
        val display = displayManager.getDisplay(Display.DEFAULT_DISPLAY)
        
        if (display == null || mediaProjection == null) {
            Handler(Looper.getMainLooper()).post {
                callback(null)
            }
            return
        }
        
        val metrics = DisplayMetrics()
        display.getRealMetrics(metrics)
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi

        Thread {
            val imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            var virtualDisplay: VirtualDisplay? = null
            
            try {
                virtualDisplay = mediaProjection?.createVirtualDisplay(
                    "ScreenCapture",
                    width, height, density,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    imageReader.surface, null, null
                )

                Thread.sleep(600)

                val image = imageReader.acquireLatestImage()
                if (image != null) {
                    val planes = image.planes
                    val buffer = planes[0].buffer
                    val pixelStride = planes[0].pixelStride
                    val rowStride = planes[0].rowStride
                    val rowPadding = rowStride - pixelStride * width

                    val bitmap = Bitmap.createBitmap(
                        width + rowPadding / pixelStride,
                        height, Bitmap.Config.ARGB_8888
                    )
                    bitmap.copyPixelsFromBuffer(buffer)
                    image.close()

                    val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                    bitmap.recycle()

                    val targetWidth = 1280
                    val scale = targetWidth.toFloat() / width
                    val targetHeight = (height * scale).toInt()
                    val scaledBitmap = Bitmap.createScaledBitmap(croppedBitmap, targetWidth, targetHeight, true)
                    croppedBitmap.recycle()

                    val outStream = ByteArrayOutputStream()
                    scaledBitmap.compress(Bitmap.CompressFormat.JPEG, 80, outStream)
                    scaledBitmap.recycle()

                    val jpegBytes = outStream.toByteArray()
                    Handler(Looper.getMainLooper()).post {
                        callback(jpegBytes)
                    }
                } else {
                    Handler(Looper.getMainLooper()).post {
                        callback(null)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Screen capture failed: ${e.message}")
                Handler(Looper.getMainLooper()).post {
                    callback(null)
                }
            } finally {
                virtualDisplay?.release()
                imageReader.close()
            }
        }.start()
    }

    fun stopSelfAndCleanUp() {
        isRunning = false
        instance = null
        
        MainActivity.stopSpeaking()
        removeViews()
        stopMediaProjection()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun removeViews() {
        containerView?.let {
            try {
                windowManager.removeView(it)
            } catch (e: Exception) {
                Log.e(TAG, "Error removing container view: ${e.message}")
            }
        }
        containerView = null
        bubbleFrame = null
        cardView = null
    }

    private fun dpToPx(dp: Int): Int {
        val density = resources.displayMetrics.density
        return Math.round(dp.toFloat() * density)
    }
}
