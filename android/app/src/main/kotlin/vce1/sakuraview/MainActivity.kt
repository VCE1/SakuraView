package vce1.sakuraview

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
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
import org.json.JSONObject
import org.json.JSONTokener
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity: FlutterActivity() {
    private val MEDIA_SCAN_CHANNEL = "com.sakuraview.dev/media_scan"
    private val PROXY_CHANNEL = "com.sakuraview.dev/proxy"
    private val WEBVIEW_CHANNEL = "com.sakuraview.dev/webview_cookies"
    private val DOWNLOAD_NOTIF_CHANNEL = "com.sakuraview.dev/download_notifications"

    companion object {
        var activeWebView: WebView? = null
        private const val DOWNLOAD_CHANNEL_ID = "sakuraview_downloads"
        private const val PROGRESS_NOTIF_ID = 20261
        private const val COMPLETE_NOTIF_ID = 20262
        private const val REQ_POST_NOTIFICATIONS = 1001
    }

    override fun onPause() {
        activeWebView?.onPause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        activeWebView?.onResume()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_MODERATE) {
            activeWebView?.freeMemory()
        }
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
                    val completed = AtomicBoolean(false)
                    val mainHandler = Handler(Looper.getMainLooper())
                    val timeoutRunnable = Runnable {
                        if (completed.compareAndSet(false, true)) {
                            Log.w("MediaScanner", "MediaScanner callback timed out for $path")
                            result.success(false)
                        }
                    }
                    mainHandler.postDelayed(timeoutRunnable, 3500L)
                    try {
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(path),
                            null
                        ) { scannedPath, uri ->
                            mainHandler.removeCallbacks(timeoutRunnable)
                            Log.i("MediaScanner", "Scanned $scannedPath -> uri=$uri")
                            mainHandler.post {
                                if (completed.compareAndSet(false, true)) {
                                    result.success(true)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        mainHandler.removeCallbacks(timeoutRunnable)
                        Log.e("MediaScanner", "Error scanning file", e)
                        if (completed.compareAndSet(false, true)) {
                            result.error("SCAN_FAILED", "Failed to scan file.", e.localizedMessage)
                        }
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "File path is null.", null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, DOWNLOAD_NOTIF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensurePermission" -> {
                    result.success(ensureNotificationPermission())
                }
                "updateProgress" -> {
                    val title = call.argument<String>("title") ?: "正在下载"
                    val body = call.argument<String>("body") ?: ""
                    val progress = call.argument<Int>("progress") ?: 0
                    val max = call.argument<Int>("max") ?: 100
                    val indeterminate = call.argument<Boolean>("indeterminate") ?: false
                    showDownloadProgressNotification(title, body, progress, max, indeterminate)
                    result.success(true)
                }
                "showComplete" -> {
                    val title = call.argument<String>("title") ?: "下载完成"
                    val body = call.argument<String>("body") ?: ""
                    val isError = call.argument<Boolean>("isError") ?: false
                    showDownloadCompleteNotification(title, body, isError)
                    result.success(true)
                }
                "cancelProgress" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    nm?.cancel(PROGRESS_NOTIF_ID)
                    result.success(true)
                }
                else -> result.notImplemented()
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
                        val wv = activeWebView
                        if (wv != null) {
                            wv.evaluateJavascript(
                                "(function(){var u=document.querySelector('meta[name=\"current-user-name\"]');var i=document.querySelector('meta[name=\"current-user-id\"]');return JSON.stringify({u:u?u.content:'',i:i?i.content:''});})();"
                            ) { raw ->
                                var uname = ""
                                var uid = ""
                                try {
                                    val unquoted = JSONTokener(raw ?: "{}").nextValue()?.toString() ?: "{}"
                                    val obj = JSONObject(unquoted)
                                    uname = obj.optString("u", "")
                                    uid = obj.optString("i", "")
                                } catch (_: Exception) {}
                                result.success(
                                    mapOf(
                                        "cookies" to cookies,
                                        "userAgent" to ua,
                                        "currentUrl" to (wv.url ?: url),
                                        "currentUserName" to uname,
                                        "currentUserId" to uid
                                    )
                                )
                            }
                        } else {
                            result.success(
                                mapOf(
                                    "cookies" to cookies,
                                    "userAgent" to ua,
                                    "currentUrl" to url,
                                    "currentUserName" to "",
                                    "currentUserId" to ""
                                )
                            )
                        }
                    } catch (e: Exception) {
                        result.error("COOKIE_ERR", e.localizedMessage, null)
                    }
                }
                "webViewFetch" -> {
                    val method = call.argument<String>("method") ?: "GET"
                    val targetUrl = call.argument<String>("url")
                    val baseUrl = call.argument<String>("baseUrl")
                    val cookieHeader = call.argument<String>("cookies") ?: ""
                    val userAgentOverride = call.argument<String>("userAgent") ?: ""
                    if (targetUrl.isNullOrBlank() || baseUrl.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "url and baseUrl are required", null)
                    } else {
                        performWebViewFetch(
                            method,
                            targetUrl,
                            baseUrl,
                            cookieHeader,
                            userAgentOverride,
                            result
                        )
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

    private fun ensureDownloadNotificationChannel(): NotificationManager? {
        val nm = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(DOWNLOAD_CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    DOWNLOAD_CHANNEL_ID,
                    "下载进度通知",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "显示图片与图组的下载进度与完成提醒"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(channel)
            }
        }
        return nm
    }

    private fun ensureNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= 33) {
            val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) {
                try {
                    requestPermissions(
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        REQ_POST_NOTIFICATIONS
                    )
                } catch (_: Exception) {}
                return false
            }
        }
        return true
    }

    private fun createLaunchPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(this, 0, intent, flags)
    }

    @Suppress("DEPRECATION")
    private fun showDownloadProgressNotification(
        title: String,
        body: String,
        progress: Int,
        max: Int,
        indeterminate: Boolean
    ) {
        val nm = ensureDownloadNotificationChannel() ?: return
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(applicationContext, DOWNLOAD_CHANNEL_ID)
        } else {
            Notification.Builder(applicationContext)
        }
        builder
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(body)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(max.coerceAtLeast(1), progress.coerceIn(0, max.coerceAtLeast(1)), indeterminate)
            .setContentIntent(createLaunchPendingIntent())
        nm.notify(PROGRESS_NOTIF_ID, builder.build())
    }

    @Suppress("DEPRECATION")
    private fun showDownloadCompleteNotification(
        title: String,
        body: String,
        isError: Boolean
    ) {
        val nm = ensureDownloadNotificationChannel() ?: return
        nm.cancel(PROGRESS_NOTIF_ID)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(applicationContext, DOWNLOAD_CHANNEL_ID)
        } else {
            Notification.Builder(applicationContext)
        }
        builder
            .setSmallIcon(
                if (isError) android.R.drawable.stat_notify_error
                else android.R.drawable.stat_sys_download_done
            )
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(false)
            .setAutoCancel(true)
            .setProgress(0, 0, false)
            .setContentIntent(createLaunchPendingIntent())
        nm.notify(COMPLETE_NOTIF_ID, builder.build())
    }

    @SuppressLint("SetJavaScriptEnabled", "AddJavascriptInterface")
    private fun performWebViewFetch(
        method: String,
        targetUrl: String,
        baseUrl: String,
        cookieHeader: String,
        userAgentOverride: String,
        result: MethodChannel.Result
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        mainHandler.post {
            val completed = AtomicBoolean(false)
            val webView = WebView(applicationContext)
            val cm = CookieManager.getInstance()
            cm.setAcceptCookie(true)
            cm.setAcceptThirdPartyCookies(webView, true)

            if (cookieHeader.isNotBlank() && cm.getCookie(baseUrl).isNullOrBlank()) {
                for (pair in cookieHeader.split(";")) {
                    val trimmed = pair.trim()
                    if (trimmed.contains("=")) {
                        cm.setCookie(baseUrl, trimmed)
                    }
                }
                cm.flush()
            }

            webView.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                val defaultUa = WebSettings.getDefaultUserAgent(applicationContext).replace("; wv", "")
                userAgentString = if (userAgentOverride.isNotBlank()) userAgentOverride else defaultUa
            }

            fun finish(statusCode: Int, body: String) {
                if (!completed.compareAndSet(false, true)) return
                mainHandler.post {
                    try {
                        cm.flush()
                        val updatedCookies = cm.getCookie(baseUrl) ?: ""
                        result.success(
                            mapOf(
                                "statusCode" to statusCode,
                                "body" to body,
                                "cookies" to updatedCookies
                            )
                        )
                    } catch (_: Exception) {
                    } finally {
                        try {
                            webView.stopLoading()
                            webView.removeJavascriptInterface("SakuraRelayBridge")
                            webView.destroy()
                        } catch (_: Exception) {}
                    }
                }
            }

            val timeoutRunnable = Runnable {
                finish(408, "WebView fetch timeout")
            }
            mainHandler.postDelayed(timeoutRunnable, 15000L)

            webView.addJavascriptInterface(
                object {
                    @JavascriptInterface
                    fun onDone(statusCode: Int, body: String?) {
                        mainHandler.removeCallbacks(timeoutRunnable)
                        finish(statusCode, body ?: "")
                    }
                },
                "SakuraRelayBridge"
            )

            val normalizedMethod = method.trim().uppercase().let {
                if (it == "POST" || it == "DELETE" || it == "PUT") it else "GET"
            }
            val quotedMethod = JSONObject.quote(normalizedMethod)
            val quotedUrl = JSONObject.quote(targetUrl)
            val quotedBaseUrl = JSONObject.quote(baseUrl)
            val html = """
                <!DOCTYPE html><html><head><meta charset="utf-8"></head><body><script>
                (async function(){
                  try {
                    const reqMethod = $quotedMethod;
                    const reqHeaders = { 'Accept': 'application/json' };
                    if (reqMethod !== 'GET') {
                      try {
                        const pageResp = await fetch($quotedBaseUrl, { credentials: 'include' });
                        const pageHtml = await pageResp.text();
                        const m = pageHtml.match(/<meta[^>]*name=["']csrf-token["'][^>]*content=["']([^"']+)["']/i)
                          || pageHtml.match(/<meta[^>]*content=["']([^"']+)["'][^>]*name=["']csrf-token["']/i);
                        if (m && m[1]) {
                          reqHeaders['X-CSRF-Token'] = m[1];
                        }
                      } catch (_) {}
                      reqHeaders['X-Requested-With'] = 'XMLHttpRequest';
                    }
                    const resp = await fetch($quotedUrl, {
                      method: reqMethod,
                      credentials: 'include',
                      headers: reqHeaders
                    });
                    const text = await resp.text();
                    SakuraRelayBridge.onDone(resp.status, text);
                  } catch (e) {
                    SakuraRelayBridge.onDone(-1, String(e || 'fetch error'));
                  }
                })();
                </script></body></html>
            """.trimIndent()
            webView.loadDataWithBaseURL(baseUrl, html, "text/html", "utf-8", null)
        }
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
                view?.evaluateJavascript(
                    "(function(){var u=document.querySelector('meta[name=\"current-user-name\"]');var i=document.querySelector('meta[name=\"current-user-id\"]');return JSON.stringify({u:u?u.content:'',i:i?i.content:''});})();"
                ) { raw ->
                    try {
                        val unquoted = JSONTokener(raw ?: "{}").nextValue()?.toString() ?: "{}"
                        val obj = JSONObject(unquoted)
                        val uname = obj.optString("u", "")
                        val uid = obj.optString("i", "")
                        if (uname.isNotEmpty() || uid.isNotEmpty()) {
                            channel.invokeMethod(
                                "onUserMetaDetected",
                                mapOf(
                                    "currentUserName" to uname,
                                    "currentUserId" to uid
                                )
                            )
                        }
                    } catch (_: Exception) {}
                }
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
