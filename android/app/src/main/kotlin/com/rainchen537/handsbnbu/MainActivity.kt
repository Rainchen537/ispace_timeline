package com.rainchen537.handsbnbu

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.URLUtil
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLConnection
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    companion object {
        private const val PREF_NAME = "ispace_credentials"
        private const val KEY_USERNAME = "saved_username"
        private const val KEY_PASSWORD = "saved_password"
        private const val CREDENTIAL_STATE_PREF_NAME = "ispace_credential_state"
        private const val LOGOUT_TOMBSTONE_KEY = "logout_tombstone"
        private const val SECURE_PREF_NAME = "FlutterSecureStorage"
        private const val SECURE_CREDENTIAL_KEY =
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_bnbu.credentials.v1"
        private const val LEGACY_SECURE_USERNAME_KEY =
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_bnbu.credentials.username"
        private const val LEGACY_SECURE_PASSWORD_KEY =
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_bnbu.credentials.password"
        private const val LEGACY_DOWNLOAD_PERMISSION_REQUEST = 4107
        private const val SHARE_CACHE_MAX_AGE_MILLIS = 24L * 60L * 60L * 1000L
    }

    private data class PendingLegacyStorageAction(
        val result: MethodChannel.Result,
        val action: () -> Unit,
    )

    private var pendingLegacyStorageAction: PendingLegacyStorageAction? = null

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
                    "readSecureCredentials" -> {
                        runCredentialStoreOperation(result) {
                            secureCredentialPreferences().getString(
                                SECURE_CREDENTIAL_KEY,
                                null,
                            )
                        }
                    }
                    "writeSecureCredentials" -> {
                        val value = call.argument<String>("value")
                        if (value.isNullOrBlank()) {
                            result.error("bad_args", "Missing credential value", null)
                            return@setMethodCallHandler
                        }
                        runCredentialStoreOperation(result) {
                            if (
                                !secureCredentialPreferences()
                                    .edit()
                                    .putString(SECURE_CREDENTIAL_KEY, value)
                                    .commit()
                            ) {
                                throw IllegalStateException(
                                    "Unable to durably write secure credentials"
                                )
                            }
                            true
                        }
                    }
                    "clearSecureCredentials" -> {
                        runCredentialStoreOperation(result) {
                            clearSecureCredentialPreferences(includePrimary = true)
                            true
                        }
                    }
                    "clearLegacySecureCredentials" -> {
                        runCredentialStoreOperation(result) {
                            clearSecureCredentialPreferences(includePrimary = false)
                            true
                        }
                    }
                    "readLogoutTombstone" -> {
                        runCredentialStoreOperation(result) {
                            getSharedPreferences(
                                CREDENTIAL_STATE_PREF_NAME,
                                Context.MODE_PRIVATE,
                            ).getBoolean(LOGOUT_TOMBSTONE_KEY, false)
                        }
                    }
                    "setLogoutTombstone" -> {
                        val blocked = call.argument<Boolean>("blocked")
                        if (blocked == null) {
                            result.error("bad_args", "Missing logout state", null)
                            return@setMethodCallHandler
                        }
                        runCredentialStoreOperation(result) {
                            val state = getSharedPreferences(
                                CREDENTIAL_STATE_PREF_NAME,
                                Context.MODE_PRIVATE,
                            )
                            val editor = state.edit()
                            if (blocked) {
                                editor.putBoolean(LOGOUT_TOMBSTONE_KEY, true)
                            } else {
                                editor.remove(LOGOUT_TOMBSTONE_KEY)
                            }
                            if (!editor.commit()) {
                                throw IllegalStateException(
                                    "Unable to durably update logout state"
                                )
                            }
                            true
                        }
                    }
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
                        if (preferences.edit().clear().commit()) {
                            result.success(true)
                        } else {
                            result.error(
                                "legacy_clear_failed",
                                "Unable to durably clear legacy credentials",
                                null,
                            )
                        }
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
                        runWithLegacyStoragePermission(result) {
                            val canSendCookies =
                                cookieHeader.isNotBlank() &&
                                    urlsHaveSameOrigin(url, cookieOrigin)
                            downloadAuthenticatedFile(
                                remoteUrl = url,
                                preferredFileName = preferredFileName,
                                cookieHeader = if (canSendCookies) cookieHeader else "",
                                cookieOrigin = if (canSendCookies) cookieOrigin else "",
                                result = result,
                            )
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
                            shareRemoteFile(
                                remoteUrl = url,
                                preferredFileName = preferredFileName,
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
                        shareRemoteFile(
                            remoteUrl = url,
                            preferredFileName = preferredFileName,
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

    private fun runCredentialStoreOperation(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        thread {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (_: Exception) {
                runOnUiThread {
                    result.error(
                        "credential_store_failed",
                        "Credential store operation failed",
                        null,
                    )
                }
            }
        }
    }

    private fun secureCredentialPreferences() = EncryptedSharedPreferences.create(
        applicationContext,
        SECURE_PREF_NAME,
        MasterKey.Builder(applicationContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    private fun clearSecureCredentialPreferences(includePrimary: Boolean) {
        val encryptedEditor = secureCredentialPreferences().edit()
            .remove(LEGACY_SECURE_USERNAME_KEY)
            .remove(LEGACY_SECURE_PASSWORD_KEY)
        if (includePrimary) {
            encryptedEditor.remove(SECURE_CREDENTIAL_KEY)
        }
        if (!encryptedEditor.commit()) {
            throw IllegalStateException("Unable to durably clear secure credentials")
        }

        val fallbackEditor = getSharedPreferences(SECURE_PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(SECURE_CREDENTIAL_KEY)
            .remove(LEGACY_SECURE_USERNAME_KEY)
            .remove(LEGACY_SECURE_PASSWORD_KEY)
        if (!fallbackEditor.commit()) {
            throw IllegalStateException("Unable to durably clear fallback credentials")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LEGACY_DOWNLOAD_PERMISSION_REQUEST) {
            return
        }
        val pending = pendingLegacyStorageAction ?: return
        pendingLegacyStorageAction = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            executeLegacyStorageAction(pending)
        } else {
            pending.result.error(
                "storage_permission_denied",
                "Storage permission is required to save files in Downloads on this Android version",
                null,
            )
        }
    }

    private fun runWithLegacyStoragePermission(
        result: MethodChannel.Result,
        action: () -> Unit,
    ) {
        val pending = PendingLegacyStorageAction(result, action)
        if (
            Build.VERSION.SDK_INT > Build.VERSION_CODES.P ||
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ) == PackageManager.PERMISSION_GRANTED
        ) {
            executeLegacyStorageAction(pending)
            return
        }
        if (pendingLegacyStorageAction != null) {
            result.error(
                "storage_permission_in_progress",
                "Another download is waiting for storage permission",
                null,
            )
            return
        }
        pendingLegacyStorageAction = pending
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            LEGACY_DOWNLOAD_PERMISSION_REQUEST,
        )
    }

    private fun executeLegacyStorageAction(pending: PendingLegacyStorageAction) {
        try {
            pending.action()
        } catch (error: Exception) {
            pending.result.error("download_failed", error.message, null)
        }
    }

    private fun downloadAuthenticatedFile(
        remoteUrl: String,
        preferredFileName: String,
        cookieHeader: String,
        cookieOrigin: String,
        result: MethodChannel.Result,
    ) {
        thread {
            try {
                val connection = openDownloadConnection(
                    remoteUrl = remoteUrl,
                    cookieHeader = cookieHeader,
                    cookieOrigin = cookieOrigin,
                )
                val destination = try {
                    val fileName = responseFileName(
                        connection = connection,
                        remoteUrl = remoteUrl,
                        preferredFileName = preferredFileName,
                    )
                    if (isUnexpectedHtmlResponse(connection, fileName)) {
                        throw IllegalStateException(
                            "Download returned a login page instead of the requested file"
                        )
                    }
                    connection.inputStream.use { input ->
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            publishDownloadWithMediaStore(input, fileName)
                        } else {
                            writeLegacyAuthenticatedDownload(input, fileName)
                        }
                    }
                } finally {
                    connection.disconnect()
                }
                runOnUiThread {
                    result.success(destination)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("download_failed", error.message, null)
                }
            }
        }
    }

    private fun responseFileName(
        connection: HttpURLConnection,
        remoteUrl: String,
        preferredFileName: String,
    ): String {
        if (preferredFileName.isNotBlank()) {
            return sanitizeFileName(preferredFileName)
        }
        return sanitizeFileName(
            URLUtil.guessFileName(
                connection.url?.toString() ?: remoteUrl,
                connection.getHeaderField("Content-Disposition"),
                connection.contentType,
            )
        )
    }

    private fun isUnexpectedHtmlResponse(
        connection: HttpURLConnection,
        fileName: String,
    ): Boolean {
        val mimeType = connection.contentType
            ?.substringBefore(';')
            ?.trim()
            ?.lowercase()
            .orEmpty()
        if (mimeType != "text/html" && mimeType != "application/xhtml+xml") {
            return false
        }
        if (connection.url?.path?.lowercase()?.contains("/login") == true) {
            return true
        }
        val extension = fileName.substringAfterLast('.', "").lowercase()
        return extension.isNotEmpty() && extension !in setOf("html", "htm", "xhtml")
    }

    private fun publishDownloadWithMediaStore(
        input: InputStream,
        originalName: String,
    ): String {
        val fileName = sanitizeFileName(originalName)
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(
                MediaStore.Downloads.MIME_TYPE,
                URLConnection.guessContentTypeFromName(fileName)
                    ?: "application/octet-stream",
            )
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS,
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            values,
        ) ?: throw IllegalStateException("Unable to create the download destination")
        try {
            contentResolver.openOutputStream(uri, "w").use { output ->
                if (output == null) {
                    throw IllegalStateException("Unable to open the download destination")
                }
                input.copyTo(output)
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            if (contentResolver.update(uri, values, null, null) != 1) {
                throw IllegalStateException("Unable to publish the downloaded file")
            }
            return uri.toString()
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun writeLegacyAuthenticatedDownload(
        input: InputStream,
        originalName: String,
    ): String {
        val targetDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IllegalStateException("Unable to create the public Downloads directory")
        }
        val targetFile = File(targetDir, uniquePublicDownloadName(originalName))
        val partialFile = File(
            targetDir,
            ".${targetFile.name}.${UUID.randomUUID()}.partial",
        )
        try {
            FileOutputStream(partialFile).use { output -> input.copyTo(output) }
            if (!partialFile.renameTo(targetFile)) {
                throw IllegalStateException("Unable to finalize downloaded file")
            }
            MediaScannerConnection.scanFile(
                this,
                arrayOf(targetFile.absolutePath),
                null,
                null,
            )
            return targetFile.absolutePath
        } finally {
            if (partialFile.exists()) {
                partialFile.delete()
            }
        }
    }

    private fun openDownloadConnection(
        remoteUrl: String,
        cookieHeader: String,
        cookieOrigin: String,
    ): HttpURLConnection {
        var currentUrl = URL(remoteUrl)
        var liveCookieHeader = cookieHeader
        val initialScheme = currentUrl.protocol.lowercase()
        repeat(6) {
            val connection = currentUrl.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.setRequestProperty(
                "User-Agent",
                "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"
            )
            if (
                liveCookieHeader.isNotBlank() &&
                    urlsHaveSameOrigin(currentUrl.toString(), cookieOrigin)
            ) {
                connection.setRequestProperty("Cookie", liveCookieHeader)
            }

            val statusCode = connection.responseCode
            if (urlsHaveSameOrigin(currentUrl.toString(), cookieOrigin)) {
                liveCookieHeader = mergeCookieHeader(
                    liveCookieHeader,
                    connection.headerFields,
                )
            }
            if (statusCode in 200..299) {
                return connection
            }
            if (statusCode !in 300..399) {
                connection.disconnect()
                throw IllegalStateException("Download failed with HTTP $statusCode")
            }

            val location = connection.getHeaderField("Location")
            connection.disconnect()
            if (location.isNullOrBlank()) {
                throw IllegalStateException("Download redirect is missing a target")
            }
            val nextUrl = URL(currentUrl, location)
            val nextScheme = nextUrl.protocol.lowercase()
            if (nextScheme != "http" && nextScheme != "https") {
                throw IllegalStateException("Download redirect uses an unsupported scheme")
            }
            if (initialScheme == "https" && nextScheme != "https") {
                throw IllegalStateException("HTTPS download cannot redirect to HTTP")
            }
            currentUrl = nextUrl
        }
        throw IllegalStateException("Download exceeded the redirect limit")
    }

    private fun mergeCookieHeader(
        currentHeader: String,
        responseHeaders: Map<String?, List<String>>,
    ): String {
        val values = linkedMapOf<String, String>()
        currentHeader.split(';').forEach { part ->
            val separator = part.indexOf('=')
            if (separator > 0) {
                val name = part.substring(0, separator).trim()
                val value = part.substring(separator + 1).trim()
                if (name.isNotEmpty()) {
                    values[name] = value
                }
            }
        }
        responseHeaders.entries
            .filter { it.key.equals("Set-Cookie", ignoreCase = true) }
            .flatMap { it.value }
            .forEach { header ->
                val pair = header.substringBefore(';')
                val separator = pair.indexOf('=')
                if (separator <= 0) {
                    return@forEach
                }
                val name = pair.substring(0, separator).trim()
                val value = pair.substring(separator + 1).trim()
                val removesCookie = value.isEmpty() ||
                    header.contains("Max-Age=0", ignoreCase = true)
                if (removesCookie) {
                    values.remove(name)
                } else if (name.isNotEmpty()) {
                    values[name] = value
                }
            }
        return values.entries.joinToString("; ") { (name, value) -> "$name=$value" }
    }

    private fun uniquePublicDownloadName(originalName: String): String {
        val safeName = sanitizeFileName(originalName)
        val dotIndex = safeName.lastIndexOf('.')
        val base = if (dotIndex > 0) safeName.substring(0, dotIndex) else safeName
        val ext = if (dotIndex > 0) safeName.substring(dotIndex) else ""
        val suffix = UUID.randomUUID().toString().substring(0, 8)
        return "${base}_$suffix$ext"
    }

    private fun pruneStaleShareCache(root: File) {
        val cutoff = System.currentTimeMillis() - SHARE_CACHE_MAX_AGE_MILLIS
        root.listFiles()?.forEach { entry ->
            if (entry.lastModified() < cutoff) {
                entry.deleteRecursively()
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
            var targetDir: File? = null
            try {
                val connection = openDownloadConnection(
                    remoteUrl = remoteUrl,
                    cookieHeader = cookieHeader,
                    cookieOrigin = cookieOrigin,
                )
                val fileName = responseFileName(
                    connection = connection,
                    remoteUrl = remoteUrl,
                    preferredFileName = preferredFileName,
                )
                if (isUnexpectedHtmlResponse(connection, fileName)) {
                    connection.disconnect()
                    throw IllegalStateException(
                        "Download returned a login page instead of the requested file"
                    )
                }
                val shareCacheRoot = File(cacheDir, "shared_files")
                pruneStaleShareCache(shareCacheRoot)
                val destinationDir = File(
                    shareCacheRoot,
                    UUID.randomUUID().toString(),
                )
                if (!destinationDir.mkdirs()) {
                    connection.disconnect()
                    throw IllegalStateException("Unable to create the share cache directory")
                }
                targetDir = destinationDir
                val targetFile = File(destinationDir, fileName)
                val partialFile = File(destinationDir, ".partial")

                try {
                    connection.inputStream.use { input ->
                        FileOutputStream(partialFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                    if (!partialFile.renameTo(targetFile)) {
                        throw IllegalStateException("Unable to finalize shared file")
                    }
                } finally {
                    connection.disconnect()
                    if (partialFile.exists()) {
                        partialFile.delete()
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
                        destinationDir.deleteRecursively()
                        result.error("share_failed", error.message, null)
                    }
                }
            } catch (error: Exception) {
                targetDir?.deleteRecursively()
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

    private fun sanitizeFileName(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            return "shared_file.bin"
        }
        val sanitized = trimmed.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1F]"), "_")
        val safeName = if (sanitized.isEmpty() || sanitized == "." || sanitized == "..") {
            "shared_file.bin"
        } else {
            sanitized
        }
        return truncateFileNameUtf8(safeName, 200)
    }

    private fun truncateFileNameUtf8(fileName: String, maxBytes: Int): String {
        if (fileName.toByteArray(Charsets.UTF_8).size <= maxBytes) {
            return fileName
        }
        val dotIndex = fileName.lastIndexOf('.')
        val hasExtension = dotIndex > 0 && dotIndex < fileName.length - 1
        val extension = if (hasExtension) fileName.substring(dotIndex) else ""
        val extensionBytes = extension.toByteArray(Charsets.UTF_8).size
        if (extensionBytes >= maxBytes) {
            return truncateUtf8(fileName, maxBytes)
        }
        val baseName = if (hasExtension) fileName.substring(0, dotIndex) else fileName
        return truncateUtf8(baseName, maxBytes - extensionBytes) + extension
    }

    private fun truncateUtf8(value: String, maxBytes: Int): String {
        val output = StringBuilder()
        var byteCount = 0
        var index = 0
        while (index < value.length) {
            val codePoint = value.codePointAt(index)
            val character = String(Character.toChars(codePoint))
            val characterBytes = character.toByteArray(Charsets.UTF_8).size
            if (byteCount + characterBytes > maxBytes) {
                break
            }
            output.append(character)
            byteCount += characterBytes
            index += Character.charCount(codePoint)
        }
        return output.toString()
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

        val initialUrl = (params["initialUrl"] as? String).orEmpty()
        val htmlContent = (params["htmlContent"] as? String).orEmpty()
        val baseUrl = (params["baseUrl"] as? String).orEmpty()
        val fallbackCookieUrl = baseUrl.ifBlank { initialUrl }
        val fallbackCookieHost = Uri.parse(fallbackCookieUrl).host.orEmpty()
        val cookies = if (isMailContent) {
            emptyList()
        } else {
            (params["cookies"] as? List<*>)
                ?.filterIsInstance<Map<*, *>>()
                ?: emptyList()
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
