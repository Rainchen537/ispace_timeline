package com.rainchen537.handsbnbu

import android.content.ActivityNotFoundException
import android.content.Context
import android.app.DownloadManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.URLUtil
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.net.URLConnection
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    companion object {
        private const val PREF_NAME = "ispace_credentials"
        private const val KEY_USERNAME = "saved_username"
        private const val KEY_PASSWORD = "saved_password"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory("ispace/native_webview", IspaceNativeWebViewFactory())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ispace/credential_store")
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                when (call.method) {
                    "readLegacyCredentials" -> {
                        val username = preferences.getString(KEY_USERNAME, "").orEmpty()
                        val password = preferences.getString(KEY_PASSWORD, "").orEmpty()
                        if (username.isBlank() || password.isBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        result.success(
                            mapOf(
                                "username" to username,
                                "password" to password,
                            )
                        )
                    }
                    "clearLegacyCredentials" -> {
                        preferences.edit().clear().apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ispace/native_actions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "downloadFile" -> {
                        val url = call.argument<String>("url")
                        val preferredFileName = call.argument<String>("filename").orEmpty()
                        val title = call.argument<String>("title").orEmpty()
                        val cookieHeader = call.argument<String>("cookieHeader").orEmpty()
                        val cookieOrigin = call.argument<String>("cookieOrigin").orEmpty()
                        if (url.isNullOrBlank()) {
                            result.error("bad_args", "Missing url", null)
                            return@setMethodCallHandler
                        }
                        if (!isHttpUrl(url)) {
                            result.error("bad_args", "Only HTTP(S) downloads are supported", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val guessedName = sanitizeFileName(
                                if (preferredFileName.isNotBlank()) {
                                    preferredFileName
                                } else {
                                    URLUtil.guessFileName(url, null, null)
                                }
                            )
                            val request = DownloadManager.Request(Uri.parse(url)).apply {
                                setAllowedOverMetered(true)
                                setAllowedOverRoaming(true)
                                setNotificationVisibility(
                                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                                )
                                setTitle(if (title.isBlank()) guessedName else title)
                                setDescription(guessedName)
                                val mime = URLConnection.guessContentTypeFromName(guessedName)
                                if (!mime.isNullOrBlank()) {
                                    setMimeType(mime)
                                }
                                if (
                                    cookieHeader.isNotBlank() &&
                                        urlsHaveSameOrigin(url, cookieOrigin)
                                ) {
                                    addRequestHeader("Cookie", cookieHeader)
                                } else {
                                    val cookie = CookieManager.getInstance().getCookie(url)
                                    if (!cookie.isNullOrBlank()) {
                                        addRequestHeader("Cookie", cookie)
                                    }
                                }
                                addRequestHeader(
                                    "User-Agent",
                                    "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 " +
                                        "(KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"
                                )
                                setDestinationInExternalPublicDir(
                                    Environment.DIRECTORY_DOWNLOADS,
                                    guessedName
                                )
                            }
                            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            val taskId = manager.enqueue(request)
                            result.success(taskId)
                        } catch (error: Exception) {
                            result.error("download_failed", error.message, null)
                        }
                    }
                    "openExternalUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("bad_args", "Missing url", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("open_failed", error.message, null)
                        }
                    }
                    "shareUrl" -> {
                        val url = call.argument<String>("url")
                        val title = call.argument<String>("title").orEmpty()
                        val preferredFileName = call.argument<String>("filename").orEmpty()
                        val cookieHeader = call.argument<String>("cookieHeader").orEmpty()
                        val cookieOrigin = call.argument<String>("cookieOrigin").orEmpty()
                        if (url.isNullOrBlank()) {
                            result.error("bad_args", "Missing url", null)
                            return@setMethodCallHandler
                        }
                        if (shouldShareAsFile(url)) {
                            val guessedName = if (preferredFileName.isNotBlank()) {
                                preferredFileName
                            } else {
                                URLUtil.guessFileName(url, null, null)
                            }
                            shareRemoteFile(
                                remoteUrl = url,
                                preferredFileName = guessedName,
                                title = title,
                                cookieHeader = cookieHeader,
                                cookieOrigin = cookieOrigin,
                                result = result,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                if (title.isNotBlank()) {
                                    putExtra(Intent.EXTRA_SUBJECT, title)
                                }
                                putExtra(Intent.EXTRA_TEXT, url)
                            }
                            startActivity(
                                Intent.createChooser(shareIntent, "分享")
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("share_failed", error.message, null)
                        }
                    }
                    "shareFile" -> {
                        val url = call.argument<String>("url")
                        val preferredFileName = call.argument<String>("filename").orEmpty()
                        val title = call.argument<String>("title").orEmpty()
                        val cookieHeader = call.argument<String>("cookieHeader").orEmpty()
                        val cookieOrigin = call.argument<String>("cookieOrigin").orEmpty()
                        if (url.isNullOrBlank()) {
                            result.error("bad_args", "Missing url", null)
                            return@setMethodCallHandler
                        }
                        val guessedName = if (preferredFileName.isNotBlank()) {
                            preferredFileName
                        } else {
                            URLUtil.guessFileName(url, null, null)
                        }
                        shareRemoteFile(
                            remoteUrl = url,
                            preferredFileName = guessedName,
                            title = title,
                            cookieHeader = cookieHeader,
                            cookieOrigin = cookieOrigin,
                            result = result,
                        )
                    }
                    "clearWebSession" -> {
                        val cookieManager = CookieManager.getInstance()
                        cookieManager.removeAllCookies {
                            cookieManager.flush()
                            result.success(true)
                        }
                    }
                    "getMailAttachmentCacheDir" -> {
                        val dir = File(applicationContext.cacheDir, "mail_attachments")
                        dir.mkdirs()
                        result.success(dir.absolutePath)
                    }
                    "openFile" -> {
                        val filePath = call.argument<String>("path") ?: run {
                            result.error("INVALID_PATH", "path required", null)
                            return@setMethodCallHandler
                        }
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"
                        try {
                            val file = File(filePath)
                            val uri = FileProvider.getUriForFile(
                                applicationContext,
                                "${applicationContext.packageName}.fileprovider",
                                file,
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, mimeType)
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                                )
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            result.error("NO_APP", "没有可以打开此类型文件的应用", null)
                        } catch (e: Exception) {
                            result.error("open_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun shareRemoteFile(
        remoteUrl: String,
        preferredFileName: String,
        title: String,
        cookieHeader: String,
        cookieOrigin: String,
        result: MethodChannel.Result,
    ) {
        if (!isHttpUrl(remoteUrl)) {
            result.error("bad_args", "Only HTTP(S) file sharing is supported", null)
            return
        }
        thread {
            try {
                val fileName = sanitizeFileName(preferredFileName)
                val targetDir = File(cacheDir, "shared_files").apply { mkdirs() }
                val targetFile = uniqueTargetFile(targetDir, fileName)

                val connection = URL(remoteUrl).openConnection().apply {
                    connectTimeout = 15_000
                    readTimeout = 30_000
                    setRequestProperty(
                        "User-Agent",
                        "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 " +
                            "(KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"
                    )
                    val cookie = if (
                        cookieHeader.isNotBlank() &&
                            urlsHaveSameOrigin(remoteUrl, cookieOrigin)
                    ) {
                        cookieHeader
                    } else {
                        CookieManager.getInstance().getCookie(remoteUrl).orEmpty()
                    }
                    if (cookie.isNotBlank()) {
                        setRequestProperty("Cookie", cookie)
                    }
                }

                connection.getInputStream().use { input ->
                    FileOutputStream(targetFile).use { output ->
                        input.copyTo(output)
                    }
                }

                val fileUri = FileProvider.getUriForFile(
                    this,
                    "${packageName}.fileprovider",
                    targetFile,
                )
                val mimeType =
                    URLConnection.guessContentTypeFromName(targetFile.name)
                        ?: "application/octet-stream"

                runOnUiThread {
                    try {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, fileUri)
                            if (title.isNotBlank()) {
                                putExtra(Intent.EXTRA_SUBJECT, title)
                            }
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(
                            Intent.createChooser(shareIntent, "分享")
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("share_failed", error.message, null)
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("share_failed", error.message, null)
                }
            }
        }
    }

    private fun isHttpUrl(value: String): Boolean {
        val uri = Uri.parse(value)
        val scheme = uri.scheme?.lowercase()
        return (scheme == "http" || scheme == "https") && !uri.host.isNullOrBlank()
    }

    private fun urlsHaveSameOrigin(first: String, second: String): Boolean {
        if (!isHttpUrl(first) || !isHttpUrl(second)) {
            return false
        }
        val left = Uri.parse(first)
        val right = Uri.parse(second)
        return left.scheme.equals(right.scheme, ignoreCase = true) &&
            left.host.equals(right.host, ignoreCase = true) &&
            effectivePort(left) == effectivePort(right)
    }

    private fun effectivePort(uri: Uri): Int {
        if (uri.port != -1) {
            return uri.port
        }
        return when (uri.scheme?.lowercase()) {
            "http" -> 80
            "https" -> 443
            else -> -1
        }
    }

    private fun uniqueTargetFile(directory: File, originalName: String): File {
        val safeName = sanitizeFileName(originalName)
        val dotIndex = safeName.lastIndexOf('.')
        val base = if (dotIndex > 0) safeName.substring(0, dotIndex) else safeName
        val ext = if (dotIndex > 0) safeName.substring(dotIndex) else ""
        var index = 0
        while (true) {
            val candidateName = if (index == 0) {
                "$base$ext"
            } else {
                "${base}_$index$ext"
            }
            val candidate = File(directory, candidateName)
            if (!candidate.exists()) {
                return candidate
            }
            index++
        }
    }

    private fun sanitizeFileName(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            return "shared_file.bin"
        }
        val sanitized = trimmed.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1F]"), "_")
        return if (sanitized.isEmpty() || sanitized == "." || sanitized == "..") {
            "shared_file.bin"
        } else {
            sanitized
        }
    }

    private fun shouldShareAsFile(url: String): Boolean {
        val lower = url.lowercase()
        if (
            lower.contains("/pluginfile.php") ||
                lower.contains("/webservice/pluginfile.php") ||
                lower.contains("/mod/resource/view.php") ||
                lower.contains("/mod/folder/download_folder.php")
        ) {
            return true
        }
        return Regex(
            "\\.(pdf|ppt|pptx|doc|docx|xls|xlsx|zip|rar|7z|jpg|jpeg|png|gif|webp|mp4|mp3)(\\?|$)"
        ).containsMatchIn(lower)
    }
}

private class IspaceNativeWebViewFactory :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return IspaceNativeWebView(context, params)
    }
}

private class IspaceNativeWebView(
    context: Context,
    params: Map<String, Any?>,
) : PlatformView {
    private val webView: WebView = WebView(context)

    init {
        val isMailContent = params["isMailContent"] as? Boolean == true
        webView.settings.javaScriptEnabled = !isMailContent
        webView.settings.domStorageEnabled = !isMailContent
        webView.settings.useWideViewPort = true
        webView.settings.loadWithOverviewMode = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            webView.settings.mixedContentMode = if (isMailContent) {
                WebSettings.MIXED_CONTENT_NEVER_ALLOW
            } else {
                WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            }
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean {
                if (!isMailContent || request?.isForMainFrame != true || !request.hasGesture()) {
                    return false
                }
                val target = request.url ?: return true
                if (target.scheme == "http" || target.scheme == "https") {
                    try {
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW, target)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    } catch (_: ActivityNotFoundException) {
                        // Keep the untrusted page inside the blocked mail WebView.
                    }
                }
                return true
            }
        }

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            cookieManager.setAcceptThirdPartyCookies(webView, !isMailContent)
        }

        @Suppress("UNCHECKED_CAST")
        val initialUrl = (params["initialUrl"] as? String).orEmpty()
        val htmlContent = (params["htmlContent"] as? String).orEmpty()
        val baseUrl = (params["baseUrl"] as? String).orEmpty()
        val fallbackCookieUrl = baseUrl.ifBlank { initialUrl }
        val fallbackCookieHost = Uri.parse(fallbackCookieUrl).host.orEmpty()
        val cookies = if (isMailContent) {
            emptyList()
        } else {
            params["cookies"] as? List<Map<String, Any?>> ?: emptyList()
        }
        var didSetCookie = false
        for (cookie in cookies) {
            val name = cookie["name"] as? String ?: continue
            val value = cookie["value"] as? String ?: continue
            if (name.isBlank()) {
                continue
            }
            val domain = (cookie["domain"] as? String)
                ?.trim()
                ?.trimStart('.')
                .orEmpty()
            val path = (cookie["path"] as? String)?.trim().orEmpty().ifEmpty { "/" }
            val hostOnly = cookie["hostOnly"] as? Boolean == true
            val secure = cookie["secure"] as? Boolean == true
            val expiresAt = (cookie["expiresAt"] as? Number)?.toLong()
            if (
                domain.isEmpty() ||
                fallbackCookieHost.isEmpty() ||
                !domain.equals(fallbackCookieHost, ignoreCase = true)
            ) {
                continue
            }
            val domainPart = if (hostOnly) "" else "Domain=$domain; "
            val securePart = if (secure) "Secure; " else ""
            val expiresPart = expiresAt?.let {
                "Expires=${formatCookieExpires(it)}; "
            }.orEmpty()
            val cookieString =
                "$name=$value; ${domainPart}Path=$path; $securePart${expiresPart}HttpOnly"
            cookieManager.setCookie(fallbackCookieUrl, cookieString)
            didSetCookie = true
        }
        if (didSetCookie) {
            cookieManager.flush()
        }

        if (htmlContent.isNotBlank()) {
            webView.loadDataWithBaseURL(
                baseUrl.ifBlank { null },
                htmlContent,
                "text/html",
                "utf-8",
                null,
            )
        } else if (initialUrl.isNotBlank()) {
            webView.loadUrl(initialUrl)
        }
    }

    private fun formatCookieExpires(epochMilliseconds: Long): String {
        val formatter = SimpleDateFormat(
            "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
            Locale.US,
        )
        formatter.timeZone = TimeZone.getTimeZone("GMT")
        return formatter.format(Date(epochMilliseconds))
    }

    override fun getView(): View = webView

    override fun dispose() {
        webView.stopLoading()
        webView.destroy()
    }
}
