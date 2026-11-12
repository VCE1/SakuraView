package vce1.sakuraview

import android.content.Context
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val MEDIA_SCAN_CHANNEL = "com.sakuraview.dev/media_scan"
    private val PROXY_CHANNEL = "com.sakuraview.dev/proxy"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SCAN_CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    try {
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(path),
                            null
                        ) { scannedPath, uri ->
                            Log.i("MediaScanner", "Scanned $scannedPath -> uri=$uri")
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        Log.e("MediaScanner", "Error scanning file", e)
                        result.error("SCAN_FAILED", "Failed to scan file.", e.localizedMessage)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "File path is null.", null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PROXY_CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "getSystemProxy") {
                try {
                    val proxyMap = resolveAndroidSystemProxy()
                    result.success(proxyMap)
                } catch (e: Exception) {
                    Log.w("ProxyChannel", "Failed to read system proxy", e)
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun resolveAndroidSystemProxy(): Map<String, Any?>? {
        // 1. Official Google Android API (API 23+): ConnectivityManager.getDefaultProxy()
        // Captures Wi-Fi mounted proxy, global HTTP proxy, and VpnService HTTP proxy.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val proxyInfo = cm?.defaultProxy
            if (proxyInfo != null && !proxyInfo.host.isNullOrBlank() && proxyInfo.port > 0) {
                val exclusions = proxyInfo.exclusionList?.joinToString(",") ?: ""
                return mapOf(
                    "host" to proxyInfo.host,
                    "port" to proxyInfo.port,
                    "nonProxyHosts" to exclusions,
                    "pacFileUrl" to (proxyInfo.pacFileUrl?.toString() ?: "")
                )
            }
        }

        // 2. Fallback to JVM system properties (http.proxyHost / https.proxyHost)
        val host = System.getProperty("http.proxyHost")?.takeIf { it.isNotBlank() }
            ?: System.getProperty("https.proxyHost")?.takeIf { it.isNotBlank() }
        val portStr = System.getProperty("http.proxyPort")?.takeIf { it.isNotBlank() }
            ?: System.getProperty("https.proxyPort")?.takeIf { it.isNotBlank() }
        val port = portStr?.toIntOrNull() ?: -1
        if (host != null && port > 0) {
            val nonProxy = System.getProperty("http.nonProxyHosts") ?: ""
            return mapOf(
                "host" to host,
                "port" to port,
                "nonProxyHosts" to nonProxy,
                "pacFileUrl" to ""
            )
        }

        return null
    }
}