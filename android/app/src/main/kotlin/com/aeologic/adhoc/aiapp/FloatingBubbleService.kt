package com.aeologic.adhoc.aiapp

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.*
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class FloatingBubbleService : Service() {

    companion object {
        private const val TAG = "FloatingBubbleService"
        private const val CHANNEL_ID = "floating_bubble_channel"
        private const val NOTIFICATION_ID = 8868
        
        var isRunning = false
        var instance: FloatingBubbleService? = null
        
        // Reference to projection data
        var resultCode: Int = 0
        var resultData: Intent? = null
    }

    private lateinit var windowManager: WindowManager
    private var bubbleView: View? = null
    private var cardView: View? = null
    
    private var mediaProjection: MediaProjection? = null
    private var displayMetrics = DisplayMetrics()
    
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
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        instance = null
        
        removeViews()
        stopMediaProjection()
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

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Floating Answer Bubble")
            .setContentText("Tap overlay bubble to answer screen content")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(pendingIntent)
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
        // Create Bubble View programmatically
        val context = this
        val bubbleFrame = FrameLayout(context)
        
        // Simple circle bubble
        val bubbleInner = ImageView(context)
        bubbleInner.setImageResource(android.R.drawable.ic_menu_compass)
        
        // Create circular background drawable
        val circleShape = android.graphics.drawable.GradientDrawable()
        circleShape.shape = android.graphics.drawable.GradientDrawable.OVAL
        circleShape.setColor(0xFF6C63FF.toInt())
        bubbleInner.background = circleShape
        bubbleInner.setPadding(16, 16, 16, 16)
        
        // Set layout params for bubble icon
        val size = dpToPx(56)
        val layoutParams = FrameLayout.LayoutParams(size, size)
        bubbleFrame.addView(bubbleInner, layoutParams)
        
        // Clip bubble frame to outline
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            bubbleFrame.outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: android.graphics.Outline) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
            bubbleFrame.clipToOutline = true
        }
        
        // Draggable bubble layout params in window
        val windowParams = WindowManager.LayoutParams(
            size, size,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) 
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY 
            else 
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        windowParams.gravity = Gravity.TOP or Gravity.START
        windowParams.x = 100
        windowParams.y = 300
        
        bubbleView = bubbleFrame
        Log.d(TAG, "setupViews: Creating circular bubble view. Class: ${bubbleView?.javaClass?.name}, Background: GradientDrawable (OVAL)")
        windowManager.addView(bubbleView, windowParams)
        
        // Expanded Card View programmatically
        val cardLayout = LinearLayout(context)
        cardLayout.orientation = LinearLayout.VERTICAL
        cardLayout.setBackgroundColor(0xE61A1A2E.toInt()) // Sleek dark glass aesthetic
        cardLayout.setPadding(32, 24, 32, 24)
        
        val titleText = TextView(context)
        titleText.text = "SCREEN ANSWER"
        titleText.setTextColor(0xFFFFFFFF.toInt())
        titleText.textSize = 12f
        titleText.setTypeface(titleText.typeface, android.graphics.Typeface.BOLD)
        cardLayout.addView(titleText)
        
        // Separator
        val separator = View(context)
        separator.setBackgroundColor(0x33FFFFFF.toInt())
        val sepParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpToPx(1))
        sepParams.topMargin = dpToPx(6)
        sepParams.bottomMargin = dpToPx(12)
        cardLayout.addView(separator, sepParams)
        
        // Scrollable content
        val scrollView = ScrollView(context)
        val contentText = TextView(context)
        contentText.text = "Tap the bubble to analyze what is currently shown on your screen."
        contentText.setTextColor(0xCCFFFFFF.toInt())
        contentText.textSize = 14f
        scrollView.addView(contentText)
        
        val scrollParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 
            dpToPx(180)
        )
        cardLayout.addView(scrollView, scrollParams)
        
        // Buttons
        val buttonRow = LinearLayout(context)
        buttonRow.orientation = LinearLayout.HORIZONTAL
        buttonRow.gravity = Gravity.END
        
        val dismissBtn = TextView(context)
        dismissBtn.text = "Close"
        dismissBtn.setTextColor(0xFFFF5252.toInt())
        dismissBtn.setPadding(24, 16, 24, 16)
        dismissBtn.setOnClickListener {
            cardView?.visibility = View.GONE
        }
        buttonRow.addView(dismissBtn)
        
        cardLayout.addView(buttonRow)
        
        val cardWindowParams = WindowManager.LayoutParams(
            dpToPx(280), WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) 
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY 
            else 
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        cardWindowParams.gravity = Gravity.TOP or Gravity.START
        cardWindowParams.x = 100
        cardWindowParams.y = 400
        
        cardView = cardLayout
        cardView?.visibility = View.GONE
        windowManager.addView(cardView, cardWindowParams)
        
        // Implement touch listener for dragging
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        
        bubbleFrame.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = windowParams.x
                    initialY = windowParams.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    windowParams.x = initialX + (event.rawX - initialTouchX).toInt()
                    windowParams.y = initialY + (event.rawY - initialTouchY).toInt()
                    windowManager.updateViewLayout(bubbleView, windowParams)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    // Check if it's a tap vs a drag
                    val diffX = Math.abs(event.rawX - initialTouchX)
                    val diffY = Math.abs(event.rawY - initialTouchY)
                    if (diffX < 10 && diffY < 10) {
                        onBubbleTapped(contentText)
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun onBubbleTapped(textView: TextView) {
        if (!MainActivity.isEngineActive()) {
            textView.text = "Please open the app once to initialize this feature."
            cardView?.visibility = View.VISIBLE
            
            // Position card under the bubble
            val bubbleParams = bubbleView?.layoutParams as WindowManager.LayoutParams
            val cardParams = cardView?.layoutParams as WindowManager.LayoutParams
            cardParams.x = bubbleParams.x
            cardParams.y = bubbleParams.y + dpToPx(64)
            windowManager.updateViewLayout(cardView, cardParams)
            return
        }

        textView.text = "Capturing screen..."
        cardView?.visibility = View.VISIBLE
        
        // Position card under the bubble
        val bubbleParams = bubbleView?.layoutParams as WindowManager.LayoutParams
        val cardParams = cardView?.layoutParams as WindowManager.LayoutParams
        cardParams.x = bubbleParams.x
        cardParams.y = bubbleParams.y + dpToPx(64)
        windowManager.updateViewLayout(cardView, cardParams)

        // Capture screen content
        captureScreen { jpegBytes ->
            if (jpegBytes != null) {
                textView.text = "Analyzing screen context..."
                // Send back to Flutter
                val sent = MainActivity.invokeScreenshotCallback(jpegBytes)
                if (!sent) {
                    textView.text = "Please open the app once to initialize this feature."
                }
            } else {
                textView.text = "Error capturing screen. Please restart service."
            }
        }
    }

    fun showAnswer(text: String) {
        Handler(Looper.getMainLooper()).post {
            cardView?.visibility = View.VISIBLE
            val textScroll = cardView?.findViewById<TextView>(android.R.id.text1) 
                ?: (cardView as? LinearLayout)?.let { layout ->
                    // Find the scrollview text
                    for (i in 0 until layout.childCount) {
                        val v = layout.getChildAt(i)
                        if (v is ScrollView) {
                            val innerText = v.getChildAt(0) as? TextView
                            if (innerText != null) return@let innerText
                        }
                    }
                    null
                }
            if (textScroll != null) {
                textScroll.text = text
            }
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

        // Run on a separate thread to avoid UI blocking
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

                // Sleep briefly for frame to render
                Thread.sleep(600)

                val image = imageReader.acquireLatestImage()
                if (image != null) {
                    val planes = image.planes
                    val buffer = planes[0].buffer
                    val pixelStride = planes[0].pixelStride
                    val rowStride = planes[0].rowStride
                    val rowPadding = rowStride - pixelStride * width

                    // Copy pixels into a Bitmap
                    val bitmap = Bitmap.createBitmap(
                        width + rowPadding / pixelStride,
                        height, Bitmap.Config.ARGB_8888
                    )
                    bitmap.copyPixelsFromBuffer(buffer)
                    image.close()

                    // Crop to standard display dimensions
                    val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                    bitmap.recycle()

                    // Resize to 1280px width max for Gemini / network upload efficiency
                    val targetWidth = 1280
                    val scale = targetWidth.toFloat() / width
                    val targetHeight = (height * scale).toInt()
                    val scaledBitmap = Bitmap.createScaledBitmap(croppedBitmap, targetWidth, targetHeight, true)
                    croppedBitmap.recycle()

                    // Compress to JPEG
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

    private fun removeViews() {
        bubbleView?.let { windowManager.removeView(it) }
        bubbleView = null
        cardView?.let { windowManager.removeView(it) }
        cardView = null
    }

    private fun dpToPx(dp: Int): Int {
        val density = resources.displayMetrics.density
        return Math.round(dp.toFloat() * density)
    }
}
