package com.example.sms_reader

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

private const val CHANNEL = "com.example.momoapp/sms"
private const val TAG = "SmsReaderPlugin"

/**
 * Reads the device SMS inbox via a `ContentResolver` query against
 * application context, not an `Activity`.
 *
 * Registered as a genuine [FlutterPlugin] (declared in this package's
 * pubspec `flutter.plugin` section) rather than wired up by hand in
 * `MainActivity.configureFlutterEngine`, so it attaches to every
 * `FlutterEngine` the app creates automatically — including the headless
 * engines `workmanager` and `flutter_foreground_task` spin up for
 * background work, where there is no Activity to bind to.
 */
class SmsReaderPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getSmsMessages" -> {
                try {
                    result.success(readSms())
                } catch (e: Exception) {
                    Log.e(TAG, "Error reading SMS", e)
                    result.error("SMS_READ_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun readSms(): List<Map<String, Any>> {
        val messages = mutableListOf<Map<String, Any>>()

        val cursor: Cursor? = appContext.contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("body", "date", "address"),
            null,
            null,
            "date DESC",
        )

        cursor?.use {
            while (it.moveToNext()) {
                val body = it.getString(0) ?: continue
                val date = it.getLong(1)
                val address = it.getString(2) ?: "unknown"

                messages.add(mapOf(
                    "body" to body,
                    "date" to date,
                    "address" to address,
                ))
            }
        }

        Log.d(TAG, "Read ${messages.size} SMS messages")
        return messages
    }
}
