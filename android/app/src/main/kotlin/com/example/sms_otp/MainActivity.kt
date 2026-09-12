package com.example.sms_otp

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "sms_otp/usage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "trafficStats" -> result.success(trafficStats())
                    "networkType" -> result.success(networkType())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Bu uygulamanın UID'si için cihaz açıldığından bu yana taşınan bayt
     * sayısı. Cihaz yeniden başlatıldığında sayaçlar sıfırlanır; toplamı
     * biriktirmek Dart tarafının işi.
     *
     * Desteklenmeyen cihazlarda TrafficStats.UNSUPPORTED (-1) döner; bunu
     * null'a çevirip Dart tarafında "okunamadı" olarak ele alıyoruz.
     */
    private fun trafficStats(): Map<String, Any?> {
        val uid = Process.myUid()
        val rx = TrafficStats.getUidRxBytes(uid)
        val tx = TrafficStats.getUidTxBytes(uid)
        return mapOf(
            "rx" to if (rx == TrafficStats.UNSUPPORTED.toLong()) null else rx,
            "tx" to if (tx == TrafficStats.UNSUPPORTED.toLong()) null else tx
        )
    }

    /**
     * Aktif bağlantının türü. TrafficStats UID başına mobil/Wi-Fi ayrımı
     * vermediği için, tüketimi hangi kovaya yazacağımızı örnekleme anındaki
     * bağlantı türüne bakarak belirliyoruz.
     */
    private fun networkType(): String {
        val manager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return "none"
        val network = manager.activeNetwork ?: return "none"
        val capabilities = manager.getNetworkCapabilities(network) ?: return "none"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            else -> "other"
        }
    }
}
