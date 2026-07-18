import Flutter
import Foundation
import MobileCoreServices
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentInteractionControllerDelegate {
  private let credentialUserDefaultsKeyUser = "ispace.saved_username"
  private let credentialUserDefaultsKeyPass = "ispace.saved_password"
  private let credentialLogoutTombstoneKey = "ispace.logout_tombstone"
  private let shareCacheMaxAge: TimeInterval = 24 * 60 * 60
  private var documentInteractionController: UIDocumentInteractionController?
  private var shareActivityController: UIActivityViewController?

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
          if defaults.synchronize() {
            result(true)
          } else {
            result(
              FlutterError(
                code: "legacy_clear_failed",
                message: "Unable to durably clear legacy credentials",
                details: nil
              )
            )
          }
        case "readLogoutTombstone":
          result(UserDefaults.standard.bool(forKey: self.credentialLogoutTombstoneKey))
        case "setLogoutTombstone":
          guard
            let arguments = call.arguments as? [String: Any],
            let blocked = arguments["blocked"] as? Bool
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing logout state", details: nil)
            )
            return
          }
          let defaults = UserDefaults.standard
          if blocked {
            defaults.set(true, forKey: self.credentialLogoutTombstoneKey)
          } else {
            defaults.removeObject(forKey: self.credentialLogoutTombstoneKey)
          }
          if defaults.synchronize() {
            result(true)
          } else {
            result(
              FlutterError(
                code: "logout_tombstone_failed",
                message: "Unable to durably update logout state",
                details: nil
              )
            )
          }
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
            cookieOrigin: cookieOrigin,
            persistent: true
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
              cookieOrigin: cookieOrigin,
              persistent: false
            ) { downloadResult in
              switch downloadResult {
              case .success(let localUrl):
                self.presentShareSheet(
                  items: [localUrl],
                  cleanupUrl: localUrl.deletingLastPathComponent(),
                  result: result
                )
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
            cookieOrigin: cookieOrigin,
            persistent: false
          ) { downloadResult in
            switch downloadResult {
            case .success(let localUrl):
              self.presentShareSheet(
                items: [localUrl],
                cleanupUrl: localUrl.deletingLastPathComponent(),
                result: result
              )
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

  private func presentShareSheet(
    items: [Any],
    cleanupUrl: URL? = nil,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      guard self.shareActivityController == nil else {
        if let cleanupUrl {
          try? FileManager.default.removeItem(at: cleanupUrl)
        }
        result(
          FlutterError(
            code: "presentation_in_progress",
            message: "已有分享菜单，请先关闭后重试。",
            details: nil
          )
        )
        return
      }
      guard let presenter = self.topViewController() else {
        if let cleanupUrl {
          try? FileManager.default.removeItem(at: cleanupUrl)
        }
        result(
          FlutterError(
            code: "no_presenter",
            message: "No view controller to present share sheet",
            details: nil
          )
        )
        return
      }

      let activityVC = UIActivityViewController(
        activityItems: items,
        applicationActivities: nil
      )
      self.shareActivityController = activityVC
      activityVC.completionWithItemsHandler = { _, _, _, _ in
        DispatchQueue.main.async {
          if let cleanupUrl {
            try? FileManager.default.removeItem(at: cleanupUrl)
          }
          if self.shareActivityController === activityVC {
            self.shareActivityController = nil
          }
        }
      }
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = self.window?.rootViewController?.view
        popover.sourceRect = CGRect(
          x: UIScreen.main.bounds.midX,
          y: UIScreen.main.bounds.midY,
          width: 0,
          height: 0
        )
      }
      presenter.present(activityVC, animated: true) {
        guard activityVC.presentingViewController != nil else {
          if let cleanupUrl {
            try? FileManager.default.removeItem(at: cleanupUrl)
          }
          if self.shareActivityController === activityVC {
            self.shareActivityController = nil
          }
          result(
            FlutterError(
              code: "presentation_failed",
              message: "Unable to present share sheet",
              details: nil
            )
          )
          return
        }
        result(true)
      }
    }
  }

  private func downloadFile(
    from remoteUrl: URL,
    preferredFileName: String,
    cookieHeader: String,
    cookieOrigin: String,
    persistent: Bool,
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
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    configuration.httpShouldSetCookies = false
    let redirectDelegate = SameOriginCookieRedirectDelegate(
      cookieHeader: extraCookie,
      cookieOrigin: URL(string: cookieOrigin),
      initialUrl: remoteUrl
    )
    let session = URLSession(
      configuration: configuration,
      delegate: redirectDelegate,
      delegateQueue: nil
    )
    session.downloadTask(with: request) { [weak self] tempUrl, response, error in
      defer { session.finishTasksAndInvalidate() }
      if let error {
        completion(.failure(error))
        return
      }
      if let response = response as? HTTPURLResponse,
        !(200...299).contains(response.statusCode)
      {
        completion(
          .failure(
            NSError(
              domain: "ispace.native_actions",
              code: response.statusCode,
              userInfo: [
                NSLocalizedDescriptionKey: "下载失败（HTTP \(response.statusCode)）"
              ]
            )
          )
        )
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
      if self.isUnexpectedHtmlResponse(response, fileName: fileName) {
        completion(
          .failure(
            NSError(
              domain: "ispace.native_actions",
              code: -3,
              userInfo: [
                NSLocalizedDescriptionKey: "下载返回了登录页面，而不是请求的文件"
              ]
            )
          )
        )
        return
      }

      do {
        let destination: URL
        if persistent {
          let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
          ).first!
          destination = try self.movePersistentDownload(
            at: tempUrl,
            to: documents,
            fileName: fileName
          )
          var resourceValues = URLResourceValues()
          resourceValues.isExcludedFromBackup = true
          var mutableDestination = destination
          try? mutableDestination.setResourceValues(resourceValues)
        } else {
          let cacheRoot = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
          ).first!
          let shareRoot = cacheRoot.appendingPathComponent(
            "shared_files",
            isDirectory: true
          )
          self.pruneStaleShareCache(at: shareRoot)
          let shareDirectory = shareRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
          )
          try FileManager.default.createDirectory(
            at: shareDirectory,
            withIntermediateDirectories: true
          )
          destination = shareDirectory.appendingPathComponent(fileName)
          do {
            try FileManager.default.moveItem(at: tempUrl, to: destination)
          } catch {
            try? FileManager.default.removeItem(at: shareDirectory)
            throw error
          }
        }
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

  private func movePersistentDownload(
    at temporaryUrl: URL,
    to directory: URL,
    fileName: String
  ) throws -> URL {
    let base = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    var destination = directory.appendingPathComponent(fileName)

    for attempt in 0..<10 {
      do {
        try FileManager.default.moveItem(at: temporaryUrl, to: destination)
        return destination
      } catch {
        let cocoaError = error as NSError
        guard cocoaError.domain == NSCocoaErrorDomain,
          cocoaError.code == CocoaError.Code.fileWriteFileExists.rawValue,
          attempt < 9
        else {
          throw error
        }
        let suffix = UUID().uuidString.lowercased()
        let uniqueName = ext.isEmpty
          ? "\(base)-\(suffix)"
          : "\(base)-\(suffix).\(ext)"
        destination = directory.appendingPathComponent(uniqueName)
      }
    }
    throw NSError(
      domain: "ispace.native_actions",
      code: -4,
      userInfo: [NSLocalizedDescriptionKey: "Unable to allocate a download filename"]
    )
  }

  private func pruneStaleShareCache(at root: URL) {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }
    let cutoff = Date().addingTimeInterval(-shareCacheMaxAge)
    for entry in entries {
      let modified = try? entry.resourceValues(
        forKeys: [.contentModificationDateKey]
      ).contentModificationDate
      if modified == nil || modified! < cutoff {
        try? FileManager.default.removeItem(at: entry)
      }
    }
  }

  private func isUnexpectedHtmlResponse(
    _ response: URLResponse?,
    fileName: String
  ) -> Bool {
    let mimeType = response?.mimeType?.lowercased() ?? ""
    guard mimeType == "text/html" || mimeType == "application/xhtml+xml" else {
      return false
    }
    if response?.url?.path.lowercased().contains("/login") == true {
      return true
    }
    let ext = (fileName as NSString).pathExtension.lowercased()
    return !ext.isEmpty && !["html", "htm", "xhtml"].contains(ext)
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
      value = "download.bin"
    }
    return truncateFileNameUtf8(value, maxBytes: 200)
  }

  private func truncateFileNameUtf8(_ fileName: String, maxBytes: Int) -> String {
    if fileName.lengthOfBytes(using: .utf8) <= maxBytes {
      return fileName
    }
    let path = fileName as NSString
    let ext = path.pathExtension
    let base = path.deletingPathExtension
    let suffix = ext.isEmpty ? "" : ".\(ext)"
    if suffix.lengthOfBytes(using: .utf8) >= maxBytes {
      let truncated = truncateUtf8(fileName, maxBytes: maxBytes)
      return truncated.isEmpty ? "download.bin" : truncated
    }
    let truncatedBase = truncateUtf8(
      base,
      maxBytes: maxBytes - suffix.lengthOfBytes(using: .utf8)
    )
    return (truncatedBase.isEmpty ? "download" : truncatedBase) + suffix
  }

  private func truncateUtf8(_ value: String, maxBytes: Int) -> String {
    var output = ""
    var byteCount = 0
    for character in value {
      let characterString = String(character)
      let characterBytes = characterString.lengthOfBytes(using: .utf8)
      if byteCount + characterBytes > maxBytes {
        break
      }
      output.append(character)
      byteCount += characterBytes
    }
    return output
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

private final class SameOriginCookieRedirectDelegate: NSObject, URLSessionTaskDelegate {
  private var cookieValues: [String: String]
  private let cookieOrigin: URL?
  private let initialScheme: String?

  init(cookieHeader: String, cookieOrigin: URL?, initialUrl: URL) {
    var values: [String: String] = [:]
    for part in cookieHeader.split(separator: ";", omittingEmptySubsequences: true) {
      let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if pair.count == 2 {
        let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
          values[name] = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
      }
    }
    self.cookieValues = values
    self.cookieOrigin = cookieOrigin
    self.initialScheme = initialUrl.scheme?.lowercased()
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let target = request.url, isHttpUrl(target) else {
      completionHandler(nil)
      return
    }
    if initialScheme == "https", target.scheme?.lowercased() != "https" {
      completionHandler(nil)
      return
    }

    if let responseUrl = response.url,
      let cookieOrigin,
      urlsHaveSameOrigin(responseUrl, cookieOrigin)
    {
      var headerFields: [String: String] = [:]
      for (rawName, rawValue) in response.allHeaderFields {
        if let name = rawName as? String, let value = rawValue as? String {
          headerFields[name] = value
        }
      }
      for cookie in HTTPCookie.cookies(
        withResponseHeaderFields: headerFields,
        for: responseUrl
      ) {
        if cookie.expiresDate.map({ $0 <= Date() }) == true {
          cookieValues.removeValue(forKey: cookie.name)
        } else {
          cookieValues[cookie.name] = cookie.value
        }
      }
    }

    var redirected = request
    redirected.setValue(nil, forHTTPHeaderField: "Cookie")
    if !cookieValues.isEmpty,
      let cookieOrigin,
      urlsHaveSameOrigin(target, cookieOrigin)
    {
      let header = cookieValues
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "; ")
      redirected.setValue(header, forHTTPHeaderField: "Cookie")
    }
    completionHandler(redirected)
  }

  private func isHttpUrl(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
  }

  private func urlsHaveSameOrigin(_ first: URL, _ second: URL) -> Bool {
    guard isHttpUrl(first), isHttpUrl(second) else {
      return false
    }
    return first.scheme?.caseInsensitiveCompare(second.scheme ?? "") == .orderedSame
      && first.host?.caseInsensitiveCompare(second.host ?? "") == .orderedSame
      && effectivePort(first) == effectivePort(second)
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
    let rawCookies: [[String: Any]]
    if isMailContent {
      rawCookies = []
    } else {
      rawCookies = (params["cookies"] as? [Any])?.compactMap {
        $0 as? [String: Any]
      } ?? []
    }

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
