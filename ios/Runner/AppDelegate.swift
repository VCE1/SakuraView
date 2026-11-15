import CFNetwork
import Flutter
import Photos
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let proxyChannelName = "com.sakuraview.dev/proxy"
  private static let mediaScanChannelName = "com.sakuraview.dev/media_scan"
  private static let webViewChannelName = "com.sakuraview.dev/webview_cookies"
  private static let webViewFactoryId = "com.sakuraview.dev/native_webview"

  static weak var activeWebView: WKWebView?
  private var webViewRelay: SakuraWKWebViewRelay?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let registrar = self.registrar(forPlugin: "SakuraNativeBridge") {
      let messenger = registrar.messenger()

      let proxyChannel = FlutterMethodChannel(
        name: AppDelegate.proxyChannelName,
        binaryMessenger: messenger
      )
      proxyChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(nil)
          return
        }
        if call.method == "getSystemProxy" {
          result(self.resolveSystemProxy())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      let mediaChannel = FlutterMethodChannel(
        name: AppDelegate.mediaScanChannelName,
        binaryMessenger: messenger
      )
      mediaChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(false)
          return
        }
        if call.method == "scanFile",
           let args = call.arguments as? [String: Any],
           let path = args["path"] as? String {
          self.saveMediaToPhotosLibrary(path: path, result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      let webChannel = FlutterMethodChannel(
        name: AppDelegate.webViewChannelName,
        binaryMessenger: messenger
      )
      registrar.register(
        SakuraWKWebViewFactory(messenger: messenger, channel: webChannel),
        withId: AppDelegate.webViewFactoryId
      )

      webChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(nil)
          return
        }
        self.handleWebViewMethod(call: call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func resolveSystemProxy() -> [String: Any]? {
    guard let unmanaged = CFNetworkCopySystemProxySettings(),
          let settings = unmanaged.takeRetainedValue() as? [String: Any] else {
      return nil
    }
    let httpEnabled = (settings[kCFNetworkProxiesHTTPEnable as String] as? Int) == 1
    if httpEnabled,
       let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String,
       let port = settings[kCFNetworkProxiesHTTPPort as String] as? Int,
       !host.isEmpty, port > 0 {
      return [
        "host": host,
        "port": port,
        "nonProxyHosts": "",
        "pacFileUrl": ""
      ]
    }
    return nil
  }

  private func saveMediaToPhotosLibrary(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(false)
      return
    }
    let ext = url.pathExtension.lowercased()
    let isVideo = ext == "mp4" || ext == "mov" || ext == "m4v"

    let performSave: () -> Void = {
      PHPhotoLibrary.shared().performChanges({
        if isVideo {
          PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } else {
          PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }
      }) { success, _ in
        DispatchQueue.main.async {
          result(success)
        }
      }
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        if status == .authorized || status == .limited {
          performSave()
        } else {
          DispatchQueue.main.async {
            result(false)
          }
        }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        if status == .authorized {
          performSave()
        } else {
          DispatchQueue.main.async {
            result(false)
          }
        }
      }
    }
  }

  private func handleWebViewMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "getCookies":
      let targetUrl = args?["url"] as? String ?? ""
      let targetHost = URL(string: targetUrl)?.host?.lowercased() ?? ""
      WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
        let filtered = cookies.filter { cookie in
          guard !targetHost.isEmpty else { return true }
          let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
          return targetHost == domain || targetHost.hasSuffix("." + domain)
        }
        let cookieHeader = filtered.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

        let fallbackResult: [String: Any] = [
          "cookies": cookieHeader,
          "userAgent": "",
          "currentUrl": targetUrl,
          "currentUserName": "",
          "currentUserId": ""
        ]

        guard let wv = AppDelegate.activeWebView else {
          result(fallbackResult)
          return
        }
        let metaScript = "(function(){var u=document.querySelector('meta[name=\"current-user-name\"]');var i=document.querySelector('meta[name=\"current-user-id\"]');return JSON.stringify({u:u?u.content:'',i:i?i.content:'',ua:navigator.userAgent||''});})();"
        wv.evaluateJavaScript(metaScript) { raw, _ in
          var uname = ""
          var uid = ""
          var ua = ""
          if let jsonStr = raw as? String,
             let data = jsonStr.data(using: .utf8),
             let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            uname = (obj["u"] as? String) ?? ""
            uid = (obj["i"] as? String) ?? ""
            ua = (obj["ua"] as? String) ?? ""
          }
          result([
            "cookies": cookieHeader,
            "userAgent": ua,
            "currentUrl": wv.url?.absoluteString ?? targetUrl,
            "currentUserName": uname,
            "currentUserId": uid
          ])
        }
      }

    case "webViewFetch":
      let method = args?["method"] as? String ?? "GET"
      let targetUrl = args?["url"] as? String ?? ""
      let baseUrl = args?["baseUrl"] as? String ?? ""
      let cookieHeader = args?["cookies"] as? String ?? ""
      let uaOverride = args?["userAgent"] as? String ?? ""
      if targetUrl.isEmpty || baseUrl.isEmpty {
        result(FlutterError(code: "INVALID_ARGS", message: "url and baseUrl are required", details: nil))
        return
      }
      let relay = SakuraWKWebViewRelay()
      self.webViewRelay = relay
      relay.execute(
        method: method,
        targetUrl: targetUrl,
        baseUrl: baseUrl,
        cookieHeader: cookieHeader,
        userAgentOverride: uaOverride
      ) { [weak self] payload in
        self?.webViewRelay = nil
        result(payload)
      }

    case "clearCookies":
      let dataTypes: Set<String> = [WKWebsiteDataTypeCookies, WKWebsiteDataTypeSessionStorage, WKWebsiteDataTypeLocalStorage]
      WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
        result(true)
      }

    case "reload":
      AppDelegate.activeWebView?.reload()
      result(true)

    case "goBack":
      if AppDelegate.activeWebView?.canGoBack == true {
        AppDelegate.activeWebView?.goBack()
        result(true)
      } else {
        result(false)
      }

    case "goForward":
      if AppDelegate.activeWebView?.canGoForward == true {
        AppDelegate.activeWebView?.goForward()
        result(true)
      } else {
        result(false)
      }

    case "loadUrl":
      if let urlStr = args?["url"] as? String, let url = URL(string: urlStr) {
        AppDelegate.activeWebView?.load(URLRequest(url: url))
      }
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

final class SakuraWKWebViewRelay: NSObject, WKScriptMessageHandler {
  private var webView: WKWebView?
  private var completion: (([String: Any]) -> Void)?
  private var targetHost: String = ""
  private var finished = false
  private var timeoutTimer: Timer?

  func execute(
    method: String,
    targetUrl: String,
    baseUrl: String,
    cookieHeader: String,
    userAgentOverride: String,
    completion: @escaping ([String: Any]) -> Void
  ) {
    self.completion = completion
    self.targetHost = URL(string: baseUrl)?.host?.lowercased() ?? ""

    let config = WKWebViewConfiguration()
    config.websiteDataStore = WKWebsiteDataStore.default()
    let ucc = WKUserContentController()
    ucc.add(self, name: "SakuraRelayBridge")
    config.userContentController = ucc

    let wv = WKWebView(frame: .zero, configuration: config)
    if !userAgentOverride.isEmpty {
      wv.customUserAgent = userAgentOverride
    }
    self.webView = wv

    timeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
      self?.finish(statusCode: 408, body: "WebView fetch timeout")
    }

    let seedAndRun: () -> Void = { [weak self] in
      guard let self = self, !self.finished else { return }
      let normalizedMethod = ["POST", "DELETE", "PUT"].contains(method.uppercased()) ? method.uppercased() : "GET"
      let quotedMethod = SakuraWKWebViewRelay.jsQuote(normalizedMethod)
      let quotedUrl = SakuraWKWebViewRelay.jsQuote(targetUrl)
      let quotedBase = SakuraWKWebViewRelay.jsQuote(baseUrl)

      let html = """
      <!DOCTYPE html><html><head><meta charset="utf-8"></head><body><script>
      (async function(){
        try {
          const reqMethod = \(quotedMethod);
          const reqHeaders = { 'Accept': 'application/json' };
          if (reqMethod !== 'GET') {
            try {
              const pageResp = await fetch(\(quotedBase), { credentials: 'include' });
              const pageHtml = await pageResp.text();
              const m = pageHtml.match(/<meta[^>]*name=["']csrf-token["'][^>]*content=["']([^"']+)["']/i)
                || pageHtml.match(/<meta[^>]*content=["']([^"']+)["'][^>]*name=["']csrf-token["']/i);
              if (m && m[1]) {
                reqHeaders['X-CSRF-Token'] = m[1];
              }
            } catch (_) {}
            reqHeaders['X-Requested-With'] = 'XMLHttpRequest';
          }
          const resp = await fetch(\(quotedUrl), {
            method: reqMethod,
            credentials: 'include',
            headers: reqHeaders
          });
          const text = await resp.text();
          window.webkit.messageHandlers.SakuraRelayBridge.postMessage({ statusCode: resp.status, body: text });
        } catch (e) {
          window.webkit.messageHandlers.SakuraRelayBridge.postMessage({ statusCode: -1, body: String(e || 'fetch error') });
        }
      })();
      </script></body></html>
      """
      wv.loadHTMLString(html, baseURL: URL(string: baseUrl))
    }

    if !cookieHeader.isEmpty, let urlObj = URL(string: baseUrl), let host = urlObj.host {
      let group = DispatchGroup()
      let store = WKWebsiteDataStore.default().httpCookieStore
      for part in cookieHeader.split(separator: ";") {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard let eq = trimmed.firstIndex(of: "=") else { continue }
        let name = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
        let val = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if name.isEmpty { continue }
        if let cookie = HTTPCookie(properties: [
          .domain: host,
          .path: "/",
          .name: name,
          .value: val
        ]) {
          group.enter()
          store.setCookie(cookie) {
            group.leave()
          }
        }
      }
      group.notify(queue: .main) {
        seedAndRun()
      }
    } else {
      seedAndRun()
    }
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let dict = message.body as? [String: Any] else { return }
    let status = (dict["statusCode"] as? Int) ?? -1
    let body = (dict["body"] as? String) ?? ""
    finish(statusCode: status, body: body)
  }

  private func finish(statusCode: Int, body: String) {
    guard !finished else { return }
    finished = true
    timeoutTimer?.invalidate()
    timeoutTimer = nil

    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
      guard let self = self else { return }
      let host = self.targetHost
      let filtered = cookies.filter { c in
        guard !host.isEmpty else { return true }
        let dom = c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return host == dom || host.hasSuffix("." + dom)
      }
      let cookieStr = filtered.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
      let cb = self.completion
      self.completion = nil
      self.webView?.stopLoading()
      self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "SakuraRelayBridge")
      self.webView = nil
      cb?([
        "statusCode": statusCode,
        "body": body,
        "cookies": cookieStr
      ])
    }
  }

  private static func jsQuote(_ raw: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [raw], options: []),
          let arr = String(data: data, encoding: .utf8),
          arr.count >= 2 else {
      return "\"\""
    }
    return String(arr.dropFirst().dropLast())
  }
}

final class SakuraWKWebViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger, channel: FlutterMethodChannel) {
    self.messenger = messenger
    self.channel = channel
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let params = args as? [String: Any]
    let initialUrl = (params?["initialUrl"] as? String) ?? "https://yande.re/user/login"
    return SakuraWKWebViewPlatformView(frame: frame, initialUrl: initialUrl, channel: channel)
  }
}

final class SakuraWKWebViewPlatformView: NSObject, FlutterPlatformView, WKNavigationDelegate {
  private let webView: WKWebView
  private let channel: FlutterMethodChannel
  private var progressObservation: NSKeyValueObservation?

  init(frame: CGRect, initialUrl: String, channel: FlutterMethodChannel) {
    self.channel = channel
    let config = WKWebViewConfiguration()
    config.websiteDataStore = WKWebsiteDataStore.default()
    config.allowsInlineMediaPlayback = true
    self.webView = WKWebView(frame: frame, configuration: config)
    super.init()

    AppDelegate.activeWebView = webView
    webView.navigationDelegate = self
    webView.allowsBackForwardNavigationGestures = true
    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
      let pct = Int((view.estimatedProgress * 100.0).rounded())
      self?.channel.invokeMethod("onProgress", arguments: ["progress": pct])
    }

    if let url = URL(string: initialUrl) {
      webView.load(URLRequest(url: url))
    }
  }

  func view() -> UIView {
    return webView
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    emitPageState(isLoading: true)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    emitPageState(isLoading: false)
    let metaScript = "(function(){var u=document.querySelector('meta[name=\"current-user-name\"]');var i=document.querySelector('meta[name=\"current-user-id\"]');return JSON.stringify({u:u?u.content:'',i:i?i.content:''});})();"
    webView.evaluateJavaScript(metaScript) { [weak self] raw, _ in
      guard let self = self,
            let jsonStr = raw as? String,
            let data = jsonStr.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
      }
      let uname = (obj["u"] as? String) ?? ""
      let uid = (obj["i"] as? String) ?? ""
      if !uname.isEmpty || !uid.isEmpty {
        self.channel.invokeMethod("onUserMetaDetected", arguments: [
          "currentUserName": uname,
          "currentUserId": uid
        ])
      }
    }
  }

  private func emitPageState(isLoading: Bool) {
    let currentUrl = webView.url?.absoluteString ?? ""
    let host = webView.url?.host?.lowercased() ?? ""
    let title = webView.title ?? ""
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
      guard let self = self else { return }
      let filtered = cookies.filter { c in
        guard !host.isEmpty else { return true }
        let dom = c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return host == dom || host.hasSuffix("." + dom)
      }
      let cookieStr = filtered.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
      self.webView.evaluateJavaScript("navigator.userAgent") { uaRaw, _ in
        self.channel.invokeMethod("onPageStateChanged", arguments: [
          "url": currentUrl,
          "title": title,
          "cookies": cookieStr,
          "userAgent": (uaRaw as? String) ?? "",
          "isLoading": isLoading
        ])
      }
    }
  }

  deinit {
    progressObservation?.invalidate()
    if AppDelegate.activeWebView === webView {
      AppDelegate.activeWebView = nil
    }
  }
}
