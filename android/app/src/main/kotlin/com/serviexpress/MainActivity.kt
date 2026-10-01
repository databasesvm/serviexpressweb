package com.serviexpress

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val SHARE_CHANNEL = "com.serviexpress.app/shareintent"
    private var shareChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Canal de share intent
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedText" -> {
                    val text = pendingSharedText ?: extractSharedText(intent)
                    pendingSharedText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractSharedText(intent)
        if (text != null) {
            pendingSharedText = text
            shareChannel?.invokeMethod("onSharedText", text)
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action == Intent.ACTION_SEND &&
            intent.type?.startsWith("text/") == true) {
            return intent.getStringExtra(Intent.EXTRA_TEXT)
        }
        return null
    }
}
