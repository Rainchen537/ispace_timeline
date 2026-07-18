import Flutter
import Foundation
import MobileCoreServices
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentInteractionControllerDelegate {
  private let credentialUserDefaultsKeyUser = "ispace.saved_username"
  private let credentialUserDefaultsKeyPass = "ispace.saved_password"
  private var documentInteractionController: UIDocumentInteractionController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let registrar = self.registrar(forPlugin: "IspaceNativeWebViewPlugin") {
      registrar.register(
        IspaceNativeWebViewFactory(messenger: registrar.messenger()),
        withId: "ispace/native_webview"
      )
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      let credentialStoreChannel = FlutterMethodChannel(
        name: "ispace/credential_store",
        binaryMessenger: controller.binaryMessenger
      )
      credentialStoreChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(
            FlutterError(code: "deallocated", message: "AppDelegate unavailable", details: nil)
          )
          return
        }
        switch call.method {
        case "readLegacyCredentials":
          let defaults = UserDefaults.standard
          let username = defaults.string(forKey: self.credentialUserDefaultsKeyUser) ?? ""
          let password = defaults.string(forKey: self.credentialUserDefaultsKeyPass) ?? ""
          if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty {
            result(nil)
            return
          }
          result([
            "username": username,
            "password": password,
          ])
        case "clearLegacyCredentials":
          let defaults = UserDefaults.standard
          defaults.removeObject(forKey: self.credentialUserDefaultsKeyUser)
          defaults.removeObject(forKey: self.credentialUserDefaultsKeyPass)
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let channel = FlutterMethodChannel(
        name: "ispace/native_actions",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(
            FlutterError(code: "deallocated", message: "AppDelegate unavailable", details: nil)
          )
          return
        }
        switch call.method {
        case "downloadFile":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let remoteUrl = URL(string: urlString)
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing url", details: call.arguments)
            )
            return
          }
          let preferredName = (args["filename"] as? String) ?? ""
          let cookieHeader = (args["cookieHeader"] as? String) ?? ""
          let cookieOrigin = (args["cookieOrigin"] as? String) ?? ""
          self.downloadFile(
            from: remoteUrl,
            preferredFileName: preferredName,
            cookieHeader: cookieHeader,
            cookieOrigin: cookieOrigin
          ) { downloadResult in
            switch downloadResult {
            case .success(let localUrl):
              result(localUrl.path)
            case .failure(let error):
              result(
                FlutterError(
                  code: "download_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        case "openExternalUrl":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let url = URL(string: urlString)
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing url", details: call.arguments)
            )
            return
          }
          DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
              result(success)
            }
          }
        case "shareUrl":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            !urlString.isEmpty
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing url", details: call.arguments)
            )
            return
          }
          let title = (args["title"] as? String) ?? ""
          let preferredName = (args["filename"] as? String) ?? ""
          let cookieHeader = (args["cookieHeader"] as? String) ?? ""
          let cookieOrigin = (args["cookieOrigin"] as? String) ?? ""
          if self.shouldShareAsFile(urlString), let remoteUrl = URL(string: urlString) {
            self.downloadFile(
              from: remoteUrl,
              preferredFileName: preferredName,
              cookieHeader: cookieHeader,
              cookieOrigin: cookieOrigin
            ) { downloadResult in
              switch downloadResult {
              case .success(let localUrl):
                self.presentShareSheet(items: [localUrl], result: result)
              case .failure(let error):
                result(
                  FlutterError(
                    code: "share_failed",
                    message: error.localizedDescription,
                    details: nil
                  )
                )
              }
            }
            return
          }
          let items: [Any] = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [urlString] : [title, urlString]
          self.presentShareSheet(items: items, result: result)
        case "shareFile":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let remoteUrl = URL(string: urlString)
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing url", details: call.arguments)
            )
            return
          }
          let preferredName = (args["filename"] as? String) ?? ""
          let cookieHeader = (args["cookieHeader"] as? String) ?? ""
          let cookieOrigin = (args["cookieOrigin"] as? String) ?? ""
          self.downloadFile(
            from: remoteUrl,
            preferredFileName: preferredName,
            cookieHeader: cookieHeader,
            cookieOrigin: cookieOrigin
          ) { downloadResult in
            switch downloadResult {
            case .success(let localUrl):
              self.presentShareSheet(items: [localUrl], result: result)
            case .failure(let error):
              result(
                FlutterError(
                  code: "share_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        case "clearWebSession":
          let dataStore = WKWebsiteDataStore.default()
          dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
          ) {
            result(true)
          }
        case "getMailAttachmentCacheDir":
          do {
            let directory = try self.mailAttachmentCacheDirectory()
            result(directory.path)
          } catch {
            result(
              FlutterError(
                code: "cache_directory_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        case "openFile":
          guard
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            !path.isEmpty
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing path", details: call.arguments)
            )
            return
          }
          let mimeType = (args["mimeType"] as? String) ?? "application/octet-stream"
          self.openFile(
            at: URL(fileURLWithPath: path),
            mimeType: mimeType,
            result: result
          )
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func mailAttachmentCacheDirectory() throws -> URL {
    let cacheRoot = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first!
    let directory = cacheRoot.appendingPathComponent(
      "mail_attachments",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func openFile(
    at url: URL,
    mimeType: String,
    result: @escaping FlutterResult
  ) {
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(
        FlutterError(code: "file_not_found", message: "文件不存在", details: url.path)
      )
      return
    }

    DispatchQueue.main.async {
      guard self.documentInteractionController == nil else {
        result(
          FlutterError(
            code: "presentation_in_progress",
            message: "已有文件打开菜单，请先关闭后重试。",
            details: nil
          )
        )
        return
      }
      guard let presenter = self.topViewController() else {
        result(
          FlutterError(
            code: "no_presenter",
            message: "No view controller available to open the file",
            details: nil
          )
        )
        return
      }
      let sourceView = presenter.view!

      let controller = UIDocumentInteractionController(url: url)
      controller.delegate = self
      if let typeIdentifier = self.typeIdentifier(
        mimeType: mimeType,
        fileExtension: url.pathExtension
      ) {
        controller.uti = typeIdentifier
      }
      self.documentInteractionController = controller
      let presented = controller.presentOptionsMenu(
        from: sourceView.bounds,
        in: sourceView,
        animated: true
      )
      if presented {
        result(true)
      } else {
        self.documentInteractionController = nil
        result(
          FlutterError(
            code: "no_app",
            message: "没有可以打开此类型文件的应用",
            details: nil
          )
        )
      }
    }
  }

  private func typeIdentifier(mimeType: String, fileExtension: String) -> String? {
    let normalizedMimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedMimeType.isEmpty, normalizedMimeType != "*/*",
      let value = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassMIMEType,
        normalizedMimeType as CFString,
        nil
      )?.takeRetainedValue()
    {
      return value as String
    }

    let normalizedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedExtension.isEmpty,
      let value = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension,
        normalizedExtension as CFString,
        nil
      )?.takeRetainedValue()
    {
      return value as String
    }
    return nil
  }

  private func topViewController(base: UIViewController? = nil) -> UIViewController? {
    let root = base ?? window?.rootViewController
    if let nav = root as? UINavigationController {
      return topViewController(base: nav.visibleViewController)
    }
    if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
      return topViewController(base: selected)
    }
    if let presented = root?.presentedViewController {
      return topViewController(base: presented)
    }
    return root
  }

  private func presentShareSheet(items: [Any], result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let activityVC = UIActivityViewController(
        activityItems: items,
        applicationActivities: nil
      )
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = self.window?.rootViewController?.view
        popover.sourceRect = CGRect(
          x: UIScreen.main.bounds.midX,
          y: UIScreen.main.bounds.midY,
          width: 0,
          height: 0
        )
      }
      guard let presenter = self.topViewController() else {
        result(
          FlutterError(
            code: "no_presenter",
            message: "No view controller to present share sheet",
            details: nil
          )
        )
        return
      }
      presenter.present(activityVC, animated: true)
      result(true)
    }
  }

  private func downloadFile(
    from remoteUrl: URL,
    preferredFileName: String,
    cookieHeader: String,
    cookieOrigin: String,
    completion: @escaping (Result<URL, Error>) -> Void
  ) {
    guard isHttpUrl(remoteUrl) else {
      completion(
        .failure(
          NSError(
            domain: "ispace.native_actions",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "仅支持 HTTP(S) 文件下载"]
          )
        )
      )
      return
    }

    var request = URLRequest(url: remoteUrl)
    let extraCookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
    if !extraCookie.isEmpty, urlsHaveSameOrigin(remoteUrl, cookieOrigin) {
      request.setValue(extraCookie, forHTTPHeaderField: "Cookie")
    } else if
      let cookies = HTTPCookieStorage.shared.cookies(for: remoteUrl),
      !cookies.isEmpty
    {
      let cookieFields = HTTPCookie.requestHeaderFields(with: cookies)
      for (key, value) in cookieFields {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    configuration.httpShouldSetCookies = false
    let session = URLSession(configuration: configuration)
    session.downloadTask(with: request) { [weak self] tempUrl, response, error in
      defer { session.finishTasksAndInvalidate() }
      if let error {
        completion(.failure(error))
        return
      }
      guard let self = self, let tempUrl = tempUrl else {
        completion(
          .failure(
            NSError(
              domain: "ispace.native_actions",
              code: -1,
              userInfo: [NSLocalizedDescriptionKey: "下载失败：临时文件不存在"]
            )
          )
        )
        return
      }

      let suggested = response?.suggestedFilename ?? "download.bin"
      let incomingName = preferredFileName.trimmingCharacters(in: .whitespacesAndNewlines)
      let fileName = self.sanitizedFileName(incomingName.isEmpty ? suggested : incomingName)
      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      let destination = self.uniqueDestinationURL(in: documents, fileName: fileName)

      do {
        try FileManager.default.moveItem(at: tempUrl, to: destination)
        completion(.success(destination))
      } catch {
        completion(.failure(error))
      }
    }.resume()
  }

  private func isHttpUrl(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
  }

  private func urlsHaveSameOrigin(_ target: URL, _ originString: String) -> Bool {
    guard let origin = URL(string: originString), isHttpUrl(target), isHttpUrl(origin) else {
      return false
    }
    return target.scheme?.caseInsensitiveCompare(origin.scheme ?? "") == .orderedSame
      && target.host?.caseInsensitiveCompare(origin.host ?? "") == .orderedSame
      && effectivePort(target) == effectivePort(origin)
  }

  private func effectivePort(_ url: URL) -> Int {
    if let port = url.port {
      return port
    }
    switch url.scheme?.lowercased() {
    case "http":
      return 80
    case "https":
      return 443
    default:
      return -1
    }
  }

  private func uniqueDestinationURL(in directory: URL, fileName: String) -> URL {
    let base = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    var index = 0
    while true {
      let candidateName: String
      if index == 0 {
        candidateName = fileName
      } else if ext.isEmpty {
        candidateName = "\(base)-\(index)"
      } else {
        candidateName = "\(base)-\(index).\(ext)"
      }
      let candidate = directory.appendingPathComponent(candidateName)
      if !FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
      index += 1
    }
  }

  private func sanitizedFileName(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty {
      return "download.bin"
    }
    let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
      .union(.controlCharacters)
    value = value.components(separatedBy: invalid).joined(separator: "_")
    if value.isEmpty || value == "." || value == ".." {
      return "download.bin"
    }
    return value
  }

  private func shouldShareAsFile(_ urlString: String) -> Bool {
    let lower = urlString.lowercased()
    if lower.contains("/pluginfile.php")
      || lower.contains("/webservice/pluginfile.php")
      || lower.contains("/mod/resource/view.php")
      || lower.contains("/mod/folder/download_folder.php")
    {
      return true
    }
    let pattern = #"\.(pdf|ppt|pptx|doc|docx|xls|xlsx|zip|rar|7z|jpg|jpeg|png|gif|webp|mp4|mp3)(\?|$)"#
    return lower.range(of: pattern, options: .regularExpression) != nil
  }

  func documentInteractionControllerDidDismissOptionsMenu(
    _ controller: UIDocumentInteractionController
  ) {
    releaseDocumentInteractionController(controller)
  }

  func documentInteractionControllerDidDismissOpenInMenu(
    _ controller: UIDocumentInteractionController
  ) {
    releaseDocumentInteractionController(controller)
  }

  func documentInteractionControllerDidEndPreview(
    _ controller: UIDocumentInteractionController
  ) {
    releaseDocumentInteractionController(controller)
  }

  private func releaseDocumentInteractionController(
    _ controller: UIDocumentInteractionController
  ) {
    if documentInteractionController === controller {
      documentInteractionController = nil
    }
  }
}

final class IspaceNativeWebViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    IspaceNativeWebView(frame: frame, viewId: viewId, args: args)
  }
}

final class IspaceNativeWebView: NSObject, FlutterPlatformView, WKNavigationDelegate {
  private let webView: WKWebView
  private let container: UIView
  private let isMailContent: Bool

  init(frame: CGRect, viewId: Int64, args: Any?) {
    let params = args as? [String: Any] ?? [:]
    let isMailContent = params["isMailContent"] as? Bool == true
    let configuration = WKWebViewConfiguration()
    if isMailContent {
      configuration.websiteDataStore = .nonPersistent()
      configuration.preferences.javaScriptEnabled = false
      if #available(iOS 14.0, *) {
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
      }
    }

    self.isMailContent = isMailContent
    self.webView = WKWebView(frame: frame, configuration: configuration)
    self.container = UIView(frame: frame)
    super.init()
    self.webView.navigationDelegate = self
    self.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    self.webView.allowsBackForwardNavigationGestures = !isMailContent
    self.webView.scrollView.alwaysBounceVertical = true
    self.container.addSubview(self.webView)
    self.loadFromParams(params)
  }

  func view() -> UIView {
    container
  }

  private func loadFromParams(_ params: [String: Any]) {
    let initialUrl = (params["initialUrl"] as? String) ?? ""
    let htmlContent = (params["htmlContent"] as? String) ?? ""
    let baseUrlString = (params["baseUrl"] as? String) ?? ""
    let initial = URL(string: initialUrl)
    let baseUrl = URL(string: baseUrlString)
    let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
    let rawCookies = isMailContent ? [] : (params["cookies"] as? [[String: Any]]) ?? []

    let group = DispatchGroup()
    for raw in rawCookies {
      guard
        let name = raw["name"] as? String,
        let value = raw["value"] as? String,
        !name.isEmpty
      else {
        continue
      }
      let domain = (raw["domain"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let path = (raw["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let hostOnly = (raw["hostOnly"] as? Bool) == true
      let secure = (raw["secure"] as? Bool) == true
      let expiresAt = (raw["expiresAt"] as? NSNumber)?.doubleValue
      let cleanedDomain = domain?
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let fallbackUrl = baseUrl ?? initial
      let fallbackDomain = fallbackUrl?.host ?? ""

      var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name,
        .value: value,
        .path: (path?.isEmpty == false ? path! : "/"),
      ]
      if hostOnly {
        guard
          let cleanedDomain,
          !cleanedDomain.isEmpty,
          let fallbackUrl,
          cleanedDomain.caseInsensitiveCompare(fallbackDomain) == .orderedSame
        else {
          continue
        }
        properties[.originURL] = fallbackUrl
      } else if
        let cleanedDomain,
        !cleanedDomain.isEmpty,
        cleanedDomain.caseInsensitiveCompare(fallbackDomain) == .orderedSame
      {
        properties[.domain] = cleanedDomain
      } else {
        continue
      }
      if secure {
        properties[.secure] = "TRUE"
      }
      if let expiresAt {
        properties[.expires] = Date(timeIntervalSince1970: expiresAt / 1000)
      }
      properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"

      guard let cookie = HTTPCookie(properties: properties) else {
        continue
      }
      group.enter()
      cookieStore.setCookie(cookie) {
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      if !htmlContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        self.webView.loadHTMLString(htmlContent, baseURL: baseUrl)
        return
      }
      guard let initial else { return }
      self.webView.load(URLRequest(url: initial))
    }
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard isMailContent, navigationAction.navigationType == .linkActivated else {
      decisionHandler(.allow)
      return
    }
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    let scheme = url.scheme?.lowercased()
    if scheme == "http" || scheme == "https" {
      UIApplication.shared.open(url, options: [:])
    }
    decisionHandler(.cancel)
  }
}
