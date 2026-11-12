package vce1.sakuraview

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.os.Build
import android.util.Log
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity: FlutterActivity() {
    private val MEDIA_SCAN_CHANNEL = "com.sakuraview.dev/media_scan"
    private val PROXY_CHANNEL = "com.sakuraview.dev/proxy"
    private val WEBVIEW_CHANNEL = "com.sakuraview.dev/webview_cookies"

    companion object {
        var activeWebView: WebView? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val webViewChannel = MethodChannel(messenger, WEBVIEW_CHANNEL)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "com.sakuraview.dev/native_webview",
                SakuraWebViewFactory(messenger, webViewChannel)
            )

        MethodChannel(messenger, MEDIA_SCAN_CHANNEL).setMethodCallHandler { call, result ->
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
                            runOnUiThread {
                                result.success(true)
                            }
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

        MethodChannel(messenger, PROXY_CHANNEL).setMethodCallHandler { call, result ->
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

        webViewChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        val cm = CookieManager.getInstance()
                        cm.flush()
                        val cookies = if (url.isNotEmpty()) cm.getCookie(url) ?: "" else ""
                        val ua = activeWebView?.settings?.userAgentString
                            ?: WebSettings.getDefaultUserAgent(applicationContext)
                        result.success(
                            mapOf(
                                "cookies" to cookies,
                                "userAgent" to ua,
                                "currentUrl" to (activeWebView?.url ?: url)
                            )
                        )
                    } catch (e: Exception) {
                        result.error("COOKIE_ERR", e.localizedMessage, null)
                    }
                }
                "clearCookies" -> {
                    try {
                        val cm = CookieManager.getInstance()
                        cm.removeAllCookies { _ ->
                            cm.flush()
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("COOKIE_CLEAR_ERR", e.localizedMessage, null)
                    }
                }
                "reload" -> {
                    activeWebView?.reload()
                    result.success(true)
                }
                "goBack" -> {
                    if (activeWebView?.canGoBack() == true) {
                        activeWebView?.goBack()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "goForward" -> {
                    if (activeWebView?.canGoForward() == true) {
                        activeWebView?.goForward()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "loadUrl" -> {
                    val url = call.argument<String>("url")
                    if (!url.isNullOrEmpty()) {
                        activeWebView?.loadUrl(url)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun resolveAndroidSystemProxy(): Map<String, Any?>? {
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

class SakuraWebViewFactory(
    private val messenger: BinaryMessenger,
    private val channel: MethodChannel
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String?, Any?>
        val initialUrl = creationParams?.get("initialUrl") as? String ?: "https://yande.re/user/login"
        return SakuraNativeWebView(context, initialUrl, channel)
    }
}

@SuppressLint("SetJavaScriptEnabled")
class SakuraNativeWebView(
    context: Context,
    initialUrl: String,
    private val channel: MethodChannel
) : PlatformView {
    private val webView: WebView = WebView(context)

    init {
        MainActivity.activeWebView = webView
        val cm = CookieManager.getInstance()
        cm.setAcceptCookie(true)
        cm.setAcceptThirdPartyCookies(webView, true)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            userAgentString = userAgentString.replace("; wv", "")
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                channel.invokeMethod(
                    "onProgress",
                    mapOf("progress" to newProgress)
                )
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                return false
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                val currentUrl = url ?: ""
                channel.invokeMethod(
                    "onPageStateChanged",
                    mapOf(
                        "url" to currentUrl,
                        "title" to (view?.title ?: ""),
                        "cookies" to (if (currentUrl.isNotEmpty()) cm.getCookie(currentUrl) ?: "" else ""),
                        "userAgent" to (view?.settings?.userAgentString ?: ""),
                        "isLoading" to true
                    )
                )
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                cm.flush()
                val currentUrl = url ?: ""
                val cookies = if (currentUrl.isNotEmpty()) cm.getCookie(currentUrl) ?: "" else ""
                channel.invokeMethod(
                    "onPageStateChanged",
                    mapOf(
                        "url" to currentUrl,
                        "title" to (view?.title ?: ""),
                        "cookies" to cookies,
                        "userAgent" to (view?.settings?.userAgentString ?: ""),
                        "isLoading" to false
                    )
                )
            }
        }

        webView.loadUrl(initialUrl)
    }

    override fun getView(): View = webView

    override fun dispose() {
        if (MainActivity.activeWebView === webView) {
            MainActivity.activeWebView = null
        }
        CookieManager.getInstance().flush()
        webView.destroy()
    }
}
