package com.techtouch.writing_questions_app

import android.net.Uri
import android.os.Build
import android.content.pm.PackageManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * واجهة النظام الخاصة بالنسخ الاحتياطي:
 *
 * - `writing_questions_app/backup_files`: اختيار ملف نسخة احتياطية من الجهاز
 *   (`ACTION_OPEN_DOCUMENT`) وحفظ نسخة في ملف يختاره المدرس
 *   (`ACTION_CREATE_DOCUMENT`) عبر Storage Access Framework — بلا أي صلاحية
 *   تخزين مطلوبة، وبلا حزم خارجية.
 * - `writing_questions_app/app_info`: اسم إصدار التطبيق لعرضه في الإعدادات
 *   وكتابته في ترويسة النسخة الاحتياطية.
 *
 * الأنواع المسموح بها صريحة ومقصودة: JSON أولاً، ثم الأنواع التي تصنّف بها
 * بعض إدارة الملفات ملفات JSON (`text/plain`, `application/octet-stream`)،
 * حتى لا يُحجب الملف عن الاختيار على أي جهاز.
 */
class MainActivity : FlutterActivity() {
    private var pendingReadResult: MethodChannel.Result? = null
    private var pendingWriteResult: MethodChannel.Result? = null
    private var pendingWriteBytes: ByteArray? = null

    private val pickBackupFile: ActivityResultLauncher<Array<String>> =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
            val result = pendingReadResult ?: return@registerForActivityResult
            pendingReadResult = null
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes == null || bytes.isEmpty()) {
                    result.error("read_failed", "تعذر قراءة الملف المحدد.", null)
                } else {
                    result.success(
                        mapOf(
                            "name" to displayNameOf(uri),
                            "bytes" to bytes,
                        )
                    )
                }
            } catch (error: Exception) {
                result.error(
                    "read_failed",
                    error.message ?: "تعذر قراءة الملف المحدد.",
                    null,
                )
            }
        }

    private val saveBackupFile: ActivityResultLauncher<String> =
        registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri: Uri? ->
            val result = pendingWriteResult ?: return@registerForActivityResult
            val bytes = pendingWriteBytes
            pendingWriteResult = null
            pendingWriteBytes = null
            if (uri == null || bytes == null) {
                // أُلغيت العملية من المستخدم.
                result.success(null)
                return@registerForActivityResult
            }
            try {
                val stream = contentResolver.openOutputStream(uri)
                if (stream == null) {
                    result.error("write_failed", "تعذر إنشاء الملف المحدد.", null)
                    return@registerForActivityResult
                }
                stream.use { it.write(bytes) }
                result.success(uri.toString())
            } catch (error: Exception) {
                result.error(
                    "write_failed",
                    error.message ?: "تعذر حفظ الملف المحدد.",
                    null,
                )
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_FILES_CHANNEL,
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "pickBackupFile" -> {
                    if (pendingReadResult != null) {
                        result.error("busy", "هناك طلب اختيار ملف قائم بالفعل.", null)
                        return@setMethodCallHandler
                    }
                    pendingReadResult = result
                    pickBackupFile.launch(
                        arrayOf("application/json", "text/plain", "application/octet-stream")
                    )
                }

                "saveBackupFile" -> {
                    val suggestedName = call.argument<String>("suggestedName")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (suggestedName.isNullOrBlank() || bytes == null) {
                        result.error("bad_arguments", "بيانات النسخة الاحتياطية غير مكتملة.", null)
                        return@setMethodCallHandler
                    }
                    if (pendingWriteResult != null) {
                        result.error("busy", "هناك طلب حفظ ملف قائم بالفعل.", null)
                        return@setMethodCallHandler
                    }
                    pendingWriteResult = result
                    pendingWriteBytes = bytes
                    saveBackupFile.launch(suggestedName)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_INFO_CHANNEL,
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            if (call.method == "appVersion") {
                result.success(appVersionName())
            } else {
                result.notImplemented()
            }
        }
    }

    /** اسم الملف المعروض للـ URI المختار (اسمه الذي يراه المدرس في إدارة الملفات). */
    private fun displayNameOf(uri: Uri): String {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else ""
            } ?: ""
        } catch (error: Exception) {
            ""
        }
    }

    /** اسم إصدار التطبيق (فارغ إن تعذّرت قراءته). */
    private fun appVersionName(): String {
        return try {
            val versionName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0)).versionName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0).versionName
            }
            versionName ?: ""
        } catch (error: Exception) {
            ""
        }
    }

    private companion object {
        const val BACKUP_FILES_CHANNEL = "writing_questions_app/backup_files"
        const val APP_INFO_CHANNEL = "writing_questions_app/app_info"
    }
}
