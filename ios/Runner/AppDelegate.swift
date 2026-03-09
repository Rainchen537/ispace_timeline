import Flutter
import Foundation
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let credentialUserDefaultsKeyUser = "ispace.saved_username"
  private let credentialUserDefaultsKeyPass = "ispace.saved_password"

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
        case "saveCredentials":
          guard
            let args = call.arguments as? [String: Any],
            let username = args["username"] as? String,
            let password = args["password"] as? String
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing username/password", details: call.arguments)
            )
            return
          }
          let defaults = UserDefaults.standard
          defaults.set(username, forKey: self.credentialUserDefaultsKeyUser)
          defaults.set(password, forKey: self.credentialUserDefaultsKeyPass)
          result(true)
        case "loadCredentials":
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
        case "clearCredentials":
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
          self.downloadFile(
            from: remoteUrl,
            preferredFileName: preferredName,
            cookieHeader: cookieHeader
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
          if self.shouldShareAsFile(urlString), let remoteUrl = URL(string: urlString) {
            self.downloadFile(
              from: remoteUrl,
              preferredFileName: preferredName,
              cookieHeader: cookieHeader
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
          self.downloadFile(
            from: remoteUrl,
            preferredFileName: preferredName,
            cookieHeader: cookieHeader
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
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
    completion: @escaping (Result<URL, Error>) -> Void
  ) {
    var request = URLRequest(url: remoteUrl)
    let extraCookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
    if !extraCookie.isEmpty {
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

    URLSession.shared.downloadTask(with: request) { [weak self] tempUrl, response, error in
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
    value = value.components(separatedBy: invalid).joined(separator: "_")
    if value.isEmpty {
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

final class IspaceNativeWebView: NSObject, FlutterPlatformView {
  private let webView: WKWebView
  private let container: UIView

  init(frame: CGRect, viewId: Int64, args: Any?) {
    self.webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
    self.container = UIView(frame: frame)
    super.init()
    self.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    self.webView.allowsBackForwardNavigationGestures = true
    self.webView.scrollView.alwaysBounceVertical = true
    self.container.addSubview(self.webView)
    self.loadFromArgs(args)
  }

  func view() -> UIView {
    container
  }

  private func loadFromArgs(_ args: Any?) {
    guard let params = args as? [String: Any] else {
      return
    }
    let initialUrl = (params["initialUrl"] as? String) ?? ""
    guard let initial = URL(string: initialUrl) else {
      return
    }
    let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
    let rawCookies = (params["cookies"] as? [[String: Any]]) ?? []

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
      let cleanedDomain = domain?
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        .trimmingCharacters(in: .whitespacesAndNewlines)

      var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name,
        .value: value,
        .path: (path?.isEmpty == false ? path! : "/"),
      ]
      if let cleanedDomain, !cleanedDomain.isEmpty {
        properties[.domain] = cleanedDomain
      } else {
        properties[.domain] = initial.host ?? "ispace.uic.edu.cn"
      }
      properties[.secure] = "TRUE"

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
      self.webView.load(URLRequest(url: initial))
    }
  }
}
