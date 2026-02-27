package com.example.sms_otp

import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.sms_otp/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val phone = call.argument<String>("phone") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        val simSlot = call.argument<Int>("simSlot") ?: 0
                        try {
                            sendSmsNative(phone, message, simSlot)
                            result.success("sent")
                        } catch (e: Exception) {
                            result.error("SMS_ERROR", e.message, null)
                        }
                    }
                    "checkSmsPermission" -> {
                        val hasPermission = ActivityCompat.checkSelfPermission(
                            this,
                            android.Manifest.permission.SEND_SMS
                        ) == PackageManager.PERMISSION_GRANTED
                        result.success(hasPermission)
                    }
                    "getSimCards" -> {
                        try {
                            result.success(getSimCardsList())
                        } catch (e: Exception) {
                            result.error("SIM_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getSmsManager(simSlot: Int): SmsManager {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val subscriptionManager =
                getSystemService(TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            if (subscriptionManager != null &&
                ActivityCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.READ_PHONE_STATE
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                val subs = subscriptionManager.activeSubscriptionInfoList
                if (subs != null && subs.size > simSlot) {
                    val subId = subs[simSlot].subscriptionId
                    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        applicationContext.getSystemService(SmsManager::class.java)
                            .let { SmsManager.getSmsManagerForSubscriptionId(subId) }
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getSmsManagerForSubscriptionId(subId)
                    }
                }
            }
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applicationContext.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
    }

    private fun sendSmsNative(phoneNumber: String, message: String, simSlot: Int) {
        val smsManager = getSmsManager(simSlot)
        val parts = smsManager.divideMessage(message)
        if (parts.size == 1) {
            smsManager.sendTextMessage(phoneNumber, null, message, null, null)
        } else {
            smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
        }
    }

    private fun getSimCardsList(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val subscriptionManager =
                getSystemService(TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            if (subscriptionManager != null &&
                ActivityCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.READ_PHONE_STATE
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                subscriptionManager.activeSubscriptionInfoList?.forEachIndexed { index, info ->
                    list.add(
                        mapOf(
                            "slot" to index,
                            "subscriptionId" to info.subscriptionId,
                            "displayName" to (info.displayName?.toString() ?: "SIM ${index + 1}"),
                            "carrierName" to (info.carrierName?.toString() ?: "")
                        )
                    )
                }
            }
        }
        if (list.isEmpty()) {
            list.add(
                mapOf(
                    "slot" to 0,
                    "subscriptionId" to -1,
                    "displayName" to "Default SIM",
                    "carrierName" to ""
                )
            )
        }
        return list
    }
}