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
                listChildren(
                    call.str("tree"),
                    call.strOrNull("doc"),
                    call.argument<Boolean>("refresh") ?: false
                )
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

    /// 取り直しを頼み、終わった合図が来るまで待つ。合図を取りこぼさないよう
    /// 先に見張りを立ててから頼む。来なければ待たずに進む（古い一覧のままだが、
    /// 次に開いたときには間に合っている）。
    private fun waitForRefresh(uri: Uri) {
        val done = java.util.concurrent.CountDownLatch(1)
        val observer = object : android.database.ContentObserver(main) {
            override fun onChange(selfChange: Boolean) = done.countDown()
        }
        contentResolver.registerContentObserver(uri, false, observer)
        try {
            val accepted = try {
                contentResolver.refresh(uri, null, null)
            } catch (e: Throwable) {
                false
            }
            if (accepted) done.await(refreshWaitSeconds, java.util.concurrent.TimeUnit.SECONDS)
        } finally {
            contentResolver.unregisterContentObserver(observer)
        }
    }

    private fun awaitChange(uri: Uri) {
        val done = java.util.concurrent.CountDownLatch(1)
        val observer = object : android.database.ContentObserver(main) {
            override fun onChange(selfChange: Boolean) = done.countDown()
        }
        contentResolver.registerContentObserver(uri, false, observer)
        try {
            done.await(refreshWaitSeconds, java.util.concurrent.TimeUnit.SECONDS)
        } finally {
            contentResolver.unregisterContentObserver(observer)
        }
    }

    private val refreshWaitSeconds = 15L

    private val childProjection = arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_SIZE,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED
    )

    private fun listChildren(
        tree: String,
        doc: String?,
        refresh: Boolean = false
    ): List<Map<String, Any?>> {
        val uri = childrenUri(tree, doc)

        // Google ドライブのプロバイダは、フォルダの子一覧を自前のキャッシュから
        // 返す。デスクトップ版が置いたファイルは、検索では見つかるのに一覧には
        // 出てこない、という状態がしばらく続く（実機で確認済み）。
        //
        // 取り直しを頼んでも、その場では古いままの一覧が返る。取り込みが終わると
        // 通知が飛んでくるので、それを待ってから引き直す。ファイル管理アプリが
        // フォルダを開いたときにやっているのと同じことをしている。
        if (refresh && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            waitForRefresh(uri)
        }

        var cursor = contentResolver.query(uri, childProjection, null, null, null)

        // 取得が終わっていない段階では EXTRA_LOADING=true を付けた
        // 「途中までの一覧」が返る。これも通知を待って引き直す。
        if (cursor != null && cursor.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false)) {
            awaitChange(cursor.notificationUri ?: uri)
            cursor.close()
            cursor = contentResolver.query(uri, childProjection, null, null, null)
        }

        val out = mutableListOf<Map<String, Any?>>()
        cursor?.use { c ->
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
