package com.tripnest.luji

import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 原生 EXIF 读取。
 *
 * Dart 的 `exif` 包只解析 JPEG 的 APP1 段，**不认 HEIC/HEIF 容器**
 * （HEIC 的 EXIF 存在 MP4 box 里），所以 OPPO/iPhone 拍的 .heic 照片
 * 在 Dart 侧读不到 GPS，地图上就没有标点。
 *
 * Android 的 `ExifInterface`（API 24+）原生支持 HEIC，这里通过 MethodChannel
 * 把它暴露给 Flutter，Dart 侧只做兜底。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "luji/exif"

    /// 请求「读取照片原始位置」权限。permission_handler 的 mediaLibrary
    /// 在 Android 上没有映射（永远返回 granted），必须原生请求。
    private val reqMediaLocation = 4101

    /// 「保存备份到指定文件夹」的挂起回调：系统文件选择器是异步的，
    /// MethodChannel 的 result 要等用户选完再回。
    /// FlutterActivity 不是 ComponentActivity，取不到 registerForActivityResult，
    /// 只能用 startActivityForResult + onActivityResult。
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSavePath: String? = null
    private val reqSaveDoc = 4202
    private var pendingOpenResult: MethodChannel.Result? = null
    private val reqOpenDoc = 4203

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        // 选择备份文件（ACTION_OPEN_DOCUMENT），读成字节回给 Dart
        if (requestCode == reqOpenDoc) {
            val res = pendingOpenResult
            pendingOpenResult = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                res?.success(null)
                return
            }
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                res?.success(bytes)
            } catch (e: Exception) {
                res?.error("READ_FAILED", e.toString(), null)
            }
            return
        }

        if (requestCode != reqSaveDoc) return
        val res = pendingSaveResult
        val path = pendingSavePath
        pendingSaveResult = null
        pendingSavePath = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null || path == null) {
            res?.success(null) // 用户取消
            return
        }
        try {
            // 8KB 缓冲的流对拷：内存占用与 zip 大小无关
            contentResolver.openOutputStream(uri)?.use { out ->
                java.io.File(path).inputStream().use { it.copyTo(out) }
            }
            res?.success(uri.toString())
        } catch (e: Exception) {
            res?.error("SAVE_FAILED", e.toString(), null)
        }
    }

    private fun ensureMediaLocationPermission() {
        if (android.os.Build.VERSION.SDK_INT < 29) return
        val perm = android.Manifest.permission.ACCESS_MEDIA_LOCATION
        if (checkSelfPermission(perm) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(perm), reqMediaLocation)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 提前申请权限，用户点「导入」时就已经能读原图了
        ensureMediaLocationPermission()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                // 保存 PNG 到系统相册（Pictures/旅迹）。Android 10+ 走 MediaStore，
                // 不需要 WRITE_EXTERNAL_STORAGE。
                if (call.method == "saveImage") {
                    try {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: "luji"
                        if (bytes == null) {
                            result.error("NO_BYTES", "bytes is null", null)
                            return@setMethodCallHandler
                        }
                        val values = android.content.ContentValues().apply {
                            put(android.provider.MediaStore.Images.Media.DISPLAY_NAME,
                                "$name.png")
                            put(android.provider.MediaStore.Images.Media.MIME_TYPE,
                                "image/png")
                            if (android.os.Build.VERSION.SDK_INT >= 29) {
                                put(android.provider.MediaStore.Images.Media.RELATIVE_PATH,
                                    "Pictures/旅迹")
                            }
                        }
                        val uri = contentResolver.insert(
                            android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            values)
                        if (uri == null) {
                            result.error("NO_URI", "insert failed", null)
                            return@setMethodCallHandler
                        }
                        contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        android.util.Log.e("LujiExif", "saveImage failed", e)
                        result.error("SAVE_FAILED", e.toString(), null)
                    }
                    return@setMethodCallHandler
                }

                // 让用户自己选保存位置（ACTION_CREATE_DOCUMENT，SAF）
                if (call.method == "saveAs") {
                    // 接收**文件路径**而不是字节：整个 zip 塞进通道会再占一份全量内存
                    val path = call.argument<String>("path")
                    val name = call.argument<String>("name") ?: "luji-backup.zip"
                    if (path == null) {
                        result.error("NO_PATH", "path is null", null)
                        return@setMethodCallHandler
                    }
                    pendingSaveResult = result
                    pendingSavePath = path
                    try {
                        val intent = android.content.Intent(
                            android.content.Intent.ACTION_CREATE_DOCUMENT
                        ).apply {
                            addCategory(android.content.Intent.CATEGORY_OPENABLE)
                            type = "application/zip"
                            putExtra(android.content.Intent.EXTRA_TITLE, name)
                        }
                        startActivityForResult(intent, reqSaveDoc)
                    } catch (e: Exception) {
                        pendingSaveResult = null
                        pendingSavePath = null
                        result.error("LAUNCH_FAILED", e.toString(), null)
                    }
                    return@setMethodCallHandler
                }

                // 让用户选一个备份 zip，返回字节
                if (call.method == "pickBackup") {
                    pendingOpenResult = result
                    try {
                        val intent = android.content.Intent(
                            android.content.Intent.ACTION_OPEN_DOCUMENT
                        ).apply {
                            addCategory(android.content.Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(intent, reqOpenDoc)
                    } catch (e: Exception) {
                        pendingOpenResult = null
                        result.error("LAUNCH_FAILED", e.toString(), null)
                    }
                    return@setMethodCallHandler
                }

                if (call.method == "readOriginal") {
                    // 用 setRequireOriginal 拿「未经净化」的原始字节：
                    // 不加 ACCESS_MEDIA_LOCATION 时，系统会把 EXIF 的 GPS 清成 0/1。
                    val id = call.argument<Number>("id")?.toLong()
                    if (id == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    // 没有权限就直接告知（否则 setRequireOriginal 会抛
                    // UnsupportedOperationException: Caller must hold ACCESS_MEDIA_LOCATION）
                    if (android.os.Build.VERSION.SDK_INT >= 29 &&
                        checkSelfPermission(android.Manifest.permission.ACCESS_MEDIA_LOCATION)
                        != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        ensureMediaLocationPermission()
                        result.error("NO_MEDIA_LOCATION", "permission not granted", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val base = android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        val uri = android.content.ContentUris.withAppendedId(base, id)

                        // ① 先查 MediaStore 的 LATITUDE/LONGITUDE 列：
                        //    这是系统库里的字段，不经过 FUSE 脱敏，华为上可能仍然保留。
                        try {
                            val c = contentResolver.query(
                                uri,
                                arrayOf(
                                    android.provider.MediaStore.Images.Media.LATITUDE,
                                    android.provider.MediaStore.Images.Media.LONGITUDE
                                ),
                                null, null, null
                            )
                            c?.use {
                                if (it.moveToFirst()) {
                                    val lat = it.getDouble(0)
                                    val lng = it.getDouble(1)
                                    if (lat != 0.0 || lng != 0.0) {
                                        result.success(
                                            HashMap<String, Any?>().apply {
                                                put("lat", lat)
                                                put("lng", lng)
                                                put("source", "mediastore")
                                            }
                                        )
                                        return@setMethodCallHandler
                                    }
                                }
                            }
                        } catch (_: Exception) {}

                        // ② 再用 MediaMetadataRetriever 读 METADATA_KEY_LOCATION（同样是系统库）
                        try {
                            val mmr = android.media.MediaMetadataRetriever()
                            mmr.setDataSource(this@MainActivity, uri)
                            val loc = mmr.extractMetadata(
                                android.media.MediaMetadataRetriever.METADATA_KEY_LOCATION)
                            mmr.release()
                            if (!loc.isNullOrBlank()) {
                                val parts = loc.split("+", "-")
                                if (parts.size >= 3) {
                                    // 格式：ISO6709 纬度±经度
                                    val lat = parts[0].trim().toDoubleOrNull()
                                    val lng = parts[1].trim().toDoubleOrNull()
                                    if (lat != null && lng != null) {
                                        result.success(
                                            HashMap<String, Any?>().apply {
                                                put("lat", lat)
                                                put("lng", lng)
                                                put("source", "retriever")
                                            }
                                        )
                                        return@setMethodCallHandler
                                    }
                                }
                            }
                        } catch (_: Exception) {}

                        val original = if (android.os.Build.VERSION.SDK_INT >= 29) {
                            android.provider.MediaStore.setRequireOriginal(uri)
                        } else uri
                        val bytes = contentResolver.openInputStream(original)
                            ?.use { it.readBytes() }
                        result.success(
                            HashMap<String, Any?>().apply {
                                put("bytes", bytes)
                                put("source", "original")
                            }
                        )
                    } catch (e: Exception) {
                        android.util.Log.e("LujiExif", "readOriginal failed", e)
                        result.error("ORIGINAL_FAILED", e.toString(), null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "read") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null || !File(path).exists()) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                try {
                    // AndroidX ExifInterface：自带 HEIF/HEIC 解析
                    val exif = ExifInterface(path)
                    // getLatLong 兼容 API 24+（latLong 属性要 API 29）
                    val latLong = FloatArray(2)
                    val map = HashMap<String, Any?>()
                    if (exif.getLatLong(latLong)) {
                        map["lat"] = latLong[0].toDouble()
                        map["lng"] = latLong[1].toDouble()
                    }
                    map["takenAt"] =
                        exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                            ?: exif.getAttribute(ExifInterface.TAG_DATETIME)
                    map["width"] = exif.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, 0)
                    map["height"] = exif.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, 0)
                    result.success(map)
                } catch (e: Exception) {
                    result.error("EXIF_FAILED", e.message, null)
                }
            }
    }
}
