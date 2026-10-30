package com.yencode.fintrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val DOWNLOADER_CHANNEL = "com.yencode.fintrack/downloader"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOADER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "export.csv"
                    val content = call.argument<String>("content") ?: ""
                    val mimeType = call.argument<String>("mimeType") ?: "text/csv"
                    val res = saveToDownloads(fileName, content, mimeType)
                    if (res != null) {
                        result.success(res)
                    } else {
                        result.error("SAVE_FAILED", "Could not save file to Downloads", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(fileName: String, content: String, mimeType: String): Map<String, String>? {
        return try {
            val bytes = content.toByteArray(Charsets.UTF_8)
            val resolver = contentResolver

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val contentValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { os ->
                        os.write(bytes)
                        os.flush()
                    }
                    var actualName = fileName
                    resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                            if (nameIdx >= 0) {
                                actualName = cursor.getString(nameIdx)
                            }
                        }
                    }
                    mapOf(
                        "uri" to uri.toString(),
                        "fileName" to actualName,
                        "path" to "Downloads/$actualName"
                    )
                } else null
            } else {
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!dir.exists()) {
                    dir.mkdirs()
                }
                val file = File(dir, fileName)
                FileOutputStream(file).use { fos ->
                    fos.write(bytes)
                    fos.flush()
                }
                mapOf(
                    "uri" to Uri.fromFile(file).toString(),
                    "fileName" to fileName,
                    "path" to file.absolutePath
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)

        val paymentChannel = NotificationChannel(
            "payment_reminder",
            "Payment Reminders",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Credit card payment reminder notifications"
            enableVibration(true)
        }
        manager.createNotificationChannel(paymentChannel)

        val defaultChannel = NotificationChannel(
            "high_importance_channel",
            "General Notifications",
            NotificationManager.IMPORTANCE_HIGH,
        )
        manager.createNotificationChannel(defaultChannel)
    }
}
