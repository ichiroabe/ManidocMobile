package jp.fusion.upper.manidoc_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/// Storage Access Framework 越しにワークスペース(Google Drive でも端末内でも可)を
/// 読み書きするためのブリッジ。Drive API を使わないので OAuth は一切不要。
///
/// Dart 側は「ツリーURI + ドキュメントID」の2つの文字列だけを扱う。
class MainActivity : FlutterActivity() {

    private val channelName = "manidoc/saf"
    private val pickRequest = 4201
    private var pendingPick: MethodChannel.Result? = null
    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> dispatch(call, result) }
    }

    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickTree" -> pickTree(result)
            "hasPermission" -> result.success(hasPermission(call.str("tree")))
            "listChildren" -> onIo(result) {
                listChildren(call.str("tree"), call.strOrNull("doc"))
            }
            "stat" -> onIo(result) { stat(call.str("tree"), call.str("doc")) }
            "readBytes" -> onIo(result) {
                readBytes(call.str("tree"), call.str("doc"))
            }
            "writeBytes" -> onIo(result) {
                writeBytes(call.str("tree"), call.str("doc"), call.argument<ByteArray>("bytes")!!)
            }
            "createFile" -> onIo(result) {
                createFile(
                    call.str("tree"), call.strOrNull("parent"),
                    call.str("name"), call.str("mime"),
                    call.argument<ByteArray>("bytes")
                )
            }
            "createDir" -> onIo(result) {
                createDir(call.str("tree"), call.strOrNull("parent"), call.str("name"))
            }
            "delete" -> onIo(result) { delete(call.str("tree"), call.str("doc")) }
            else -> result.notImplemented()
        }
    }

    private fun MethodCall.str(key: String): String = argument<String>(key)!!
    private fun MethodCall.strOrNull(key: String): String? = argument<String>(key)

    /// 通信を伴うので必ず別スレッド。失敗は例外にせず null / false を返し、
    /// 呼び出し側(既存の DriveService と同じ流儀)で握りつぶせるようにする。
    private fun onIo(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            val reply = try {
                block()
            } catch (e: Throwable) {
                null
            }
            main.post { result.success(reply) }
        }
    }

    // --- フォルダ選択 -------------------------------------------------------

    private fun pickTree(result: MethodChannel.Result) {
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        startActivityForResult(intent, pickRequest)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest) return
        val pending = pendingPick ?: return
        pendingPick = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(null)
            return
        }
        // 永続化しないと次回起動時に選び直しになる
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Throwable) {
        }
        val docId = DocumentsContract.getTreeDocumentId(uri)
        pending.success(
            mapOf(
                "tree" to uri.toString(),
                "doc" to docId,
                "name" to displayName(uri, docId)
            )
        )
    }

    private fun hasPermission(tree: String): Boolean {
        val uri = Uri.parse(tree)
        return contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && it.isWritePermission
        }
    }

    // --- ヘルパ -------------------------------------------------------------

    /// doc が null のときはツリーのルートを指す
    private fun docUri(tree: String, doc: String?): Uri {
        val treeUri = Uri.parse(tree)
        val id = doc ?: DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
    }

    private fun childrenUri(tree: String, doc: String?): Uri {
        val treeUri = Uri.parse(tree)
        val id = doc ?: DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, id)
    }

    private fun displayName(tree: Uri, doc: String): String? {
        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, doc)
        return contentResolver.query(
            uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null
        )?.use { if (it.moveToFirst()) it.getString(0) else null }
    }

    // --- 一覧・読み書き -----------------------------------------------------

    private fun listChildren(tree: String, doc: String?): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            childrenUri(tree, doc),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
            ),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getString(0),
                        "name" to c.getString(1),
                        "mime" to c.getString(2),
                        "size" to if (c.isNull(3)) null else c.getLong(3),
                        "modified" to if (c.isNull(4)) null else c.getLong(4)
                    )
                )
            }
        }
        return out
    }

    /// 1件分のメタ情報。上書き前に「他所で更新されていないか」を見るのに使う。
    private fun stat(tree: String, doc: String): Map<String, Any?>? =
        contentResolver.query(
            docUri(tree, doc),
            arrayOf(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
            ),
            null, null, null
        )?.use { c ->
            if (!c.moveToFirst()) return@use null
            mapOf(
                "name" to c.getString(0),
                "size" to if (c.isNull(1)) null else c.getLong(1),
                "modified" to if (c.isNull(2)) null else c.getLong(2)
            )
        }

    private fun readBytes(tree: String, doc: String): ByteArray? =
        contentResolver.openInputStream(docUri(tree, doc))?.use { it.readBytes() }

    private fun writeBytes(tree: String, doc: String, bytes: ByteArray): Boolean {
        // "wt" = truncate。既存の中身が残らないようにする
        contentResolver.openOutputStream(docUri(tree, doc), "wt")?.use { it.write(bytes) }
            ?: return false
        return true
    }

    private fun createFile(
        tree: String, parent: String?, name: String, mime: String, bytes: ByteArray?
    ): String? {
        val created = DocumentsContract.createDocument(
            contentResolver, docUri(tree, parent), mime, name
        ) ?: return null
        if (bytes != null) {
            contentResolver.openOutputStream(created, "wt")?.use { it.write(bytes) }
        }
        return DocumentsContract.getDocumentId(created)
    }

    private fun createDir(tree: String, parent: String?, name: String): String? {
        val created = DocumentsContract.createDocument(
            contentResolver, docUri(tree, parent),
            DocumentsContract.Document.MIME_TYPE_DIR, name
        ) ?: return null
        return DocumentsContract.getDocumentId(created)
    }

    private fun delete(tree: String, doc: String): Boolean =
        DocumentsContract.deleteDocument(contentResolver, docUri(tree, doc))
}
