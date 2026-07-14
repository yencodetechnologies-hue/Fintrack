package com.yencode.fintrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
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
