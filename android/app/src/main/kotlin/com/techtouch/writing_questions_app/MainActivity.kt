package com.techtouch.writing_questions_app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
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
 * **لماذا لا يُستخدم `registerForActivityResult`؟** لأنه من `ComponentActivity`
 * في `androidx.activity`، وصنف [FlutterActivity] يرث `android.app.Activity`
 * مباشرةً (لا `ComponentActivity`)، فسِجل نتائج النشاط غير متاح له — والبديل
 * الوحيد هو تغيير صنف مضيف التطبيق كاملاً إلى `FlutterFragmentActivity`، وهو
 * تغيير على مستوى مضيف الواجهة لا يستدعيه هذا المطلب.
 *
 * عقد SAF نفسه بسيط وثابت: Intent النتيجة يحمل الـ URI في `data`، وغيابه أو
 * `RESULT_CANCELED` يعني إلغاء المستخدم — ولذلك نبنيه ونقرأه صراحةً بلا
 * وسائط: أوضح للقارئ، وبلا اعتماد على تفاصيل داخلية لأي مكتبة.
 *
 * الأنواع المسموح بها صريحة ومقصودة: JSON أولاً، ثم الأنواع التي تصنّف بها
 * بعض إدارة الملفات ملفات JSON (`text/plain`, `application/octet-stream`)،
 * حتى لا يُحجب الملف عن الاختيار على أي جهاز.
 */
class MainActivity : FlutterActivity() {
    private var pendingReadResult: MethodChannel.Result? = null
    private var pendingWriteResult: MethodChannel.Result? = null
    private var pendingWriteBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_FILES_CHANNEL,
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "pickBackupFile" -> pickBackupFile(result)
                "saveBackupFile" -> saveBackupFile(
                    result,
                    call.argument<String>("suggestedName"),
                    call.argument<ByteArray>("bytes"),
                )

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

    /** يفتح منتقي ملفات النظام لاختيار نسخة احتياطية (النتيجة في [onActivityResult]). */
    @Suppress("DEPRECATION")
    private fun pickBackupFile(result: MethodChannel.Result) {
        if (pendingReadResult != null) {
            result.error("busy", "هناك طلب اختيار ملف قائم بالفعل.", null)
            return
        }
        pendingReadResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, READABLE_MIME_TYPES)
        }
        startActivityForResult(intent, REQUEST_OPEN_DOCUMENT)
    }

    /** يفتح حوار النظام لحفظ نسخة احتياطية باسم مقترح (النتيجة في [onActivityResult]). */
    @Suppress("DEPRECATION")
    private fun saveBackupFile(
        result: MethodChannel.Result,
        suggestedName: String?,
        bytes: ByteArray?,
    ) {
        if (suggestedName.isNullOrBlank() || bytes == null) {
            result.error("bad_arguments", "بيانات النسخة الاحتياطية غير مكتملة.", null)
            return
        }
        if (pendingWriteResult != null) {
            result.error("busy", "هناك طلب حفظ ملف قائم بالفعل.", null)
            return
        }
        pendingWriteResult = result
        pendingWriteBytes = bytes
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, suggestedName)
        }
        startActivityForResult(intent, REQUEST_CREATE_DOCUMENT)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_OPEN_DOCUMENT -> completeRead(resultCode, data)
            REQUEST_CREATE_DOCUMENT -> completeWrite(resultCode, data)
        }
    }

    /** يقرأ الملف المختار ويعيد `{name, bytes}`؛ `null` = أُلغيت العملية. */
    private fun completeRead(resultCode: Int, data: Intent?) {
        val result = pendingReadResult ?: return
        pendingReadResult = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(null)
            return
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

    /** يكتب النسخة في الملف الذي اختاره المدرس؛ `null` = أُلغيت العملية. */
    private fun completeWrite(resultCode: Int, data: Intent?) {
        val result = pendingWriteResult ?: return
        val bytes = pendingWriteBytes
        pendingWriteResult = null
        pendingWriteBytes = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null || bytes == null) {
            result.success(null)
            return
        }
        try {
            val stream = contentResolver.openOutputStream(uri)
            if (stream == null) {
                result.error("write_failed", "تعذر إنشاء الملف المحدد.", null)
                return
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

    /** اسم الملف المعروض للـ URI المختار (اسمه الذي يراه المدرس في إدارة الملفات). */
    private fun displayNameOf(uri: Uri): String {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else ""
            } ?: ""
        } catch (error: Exception) {
            ""
        }
    }

    /** اسم إصدار التطبيق (فارغ إن تعذّرت قراءته). */
    @Suppress("DEPRECATION")
    private fun appVersionName(): String {
        return try {
            val versionName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                ).versionName
            } else {
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

        /** أنواع الملفات المقبولة في منتقي النسخة الاحتياطية. */
        val READABLE_MIME_TYPES = arrayOf(
            "application/json",
            "text/plain",
            "application/octet-stream",
        )

        // رموز طلب خاصة بهذا التطبيق بعيدة عن رموز إضافات Flutter القياسية.
        const val REQUEST_OPEN_DOCUMENT = 0x4255
        const val REQUEST_CREATE_DOCUMENT = 0x4256
    }
}
