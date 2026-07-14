package com.aeologic.adhoc.aiapp

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "adhoc.aiapp/bubble"
        private const val REQUEST_SCREEN_CAPTURE = 19703
        private const val REQUEST_OVERLAY_PERMISSION = 19704
        
        private var channelInstance: MethodChannel? = null
        private var isEngineActive = false
        
        fun isEngineActive(): Boolean = isEngineActive && channelInstance != null
        
        fun invokeScreenshotCallback(jpegBytes: ByteArray): Boolean {
            val channel = channelInstance
            if (channel != null && isEngineActive) {
                try {
                    Handler(Looper.getMainLooper()).post {
                        channel.invokeMethod("onScreenshotCaptured", jpegBytes)
                    }
                    return true
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "Failed to invoke screenshot callback: ${e.message}")
                }
            }
            return false
        }
    }

    private var startServiceResultCallback: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        isEngineActive = true
        channelInstance = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channelInstance?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    result.success(true)
                }
                "checkOverlayPermission" -> {
                    result.success(checkOverlayPermission())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "startBubble" -> {
                    if (!checkOverlayPermission()) {
                        result.error("PERMISSION_DENIED", "Overlay draw permission is required.", null)
                        return@setMethodCallHandler
                    }
                    startServiceResultCallback = result
                    requestScreenCapturePermission()
                }
                "stopBubble" -> {
                    stopBubbleService()
                    result.success(true)
                }
                "updateAnswer" -> {
                    val answerText = call.argument<String>("text") ?: ""
                    FloatingBubbleService.instance?.showAnswer(answerText)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivityForResult(intent, REQUEST_OVERLAY_PERMISSION)
        }
    }

    private fun requestScreenCapturePermission() {
        val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), REQUEST_SCREEN_CAPTURE)
    }

    private fun stopBubbleService() {
        val intent = Intent(this, FloatingBubbleService::class.java)
        stopService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                // Store results for service
                FloatingBubbleService.resultCode = resultCode
                FloatingBubbleService.resultData = data
                
                // Start Foreground Service
                val serviceIntent = Intent(this, FloatingBubbleService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                
                startServiceResultCallback?.success(true)
                startServiceResultCallback = null
            } else {
                startServiceResultCallback?.error("CAPTURE_DENIED", "Screen capture permission denied by user.", null)
                startServiceResultCallback = null
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        isEngineActive = false
        channelInstance = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        isEngineActive = false
        channelInstance = null
        super.onDestroy()
    }
}
