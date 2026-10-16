package app.tokenbar.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.*
import androidx.core.content.FileProvider
import app.tokenbar.core.Lang
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Atualiza sozinho pelo GitHub Releases (sem loja). Só instala por cima se a chave for a mesma. */
class Updater(private val context: Context) {
    private val prefs = context.getSharedPreferences("update", Context.MODE_PRIVATE)
    private var latest by mutableStateOf(prefs.getString("latest", null))
    private var busy by mutableStateOf<String?>(null)    // chave em português: "BAIXANDO %d%%" ou um erro curto
    private var pct by mutableIntStateOf(0)

    /** O que a tecla mostra; nulo = nada a fazer. */
    val label: String? get() = busy?.let { Lang.f(it, pct) }
        ?: if (latest?.let { newer(it, BuildConfig.VERSION_NAME) } == true) Lang.t("ATUALIZAR") else null

    /** Na abertura e depois a cada 6 h, no máximo. */
    suspend fun watch() {
        while (true) {
            val wait = prefs.getLong("checked", 0) + EVERY - System.currentTimeMillis()
            if (wait > 0) delay(wait)
            runCatching { fetchLatest() }.onSuccess { latest = it; prefs.edit().putString("latest", it).apply() }
            prefs.edit().putLong("checked", System.currentTimeMillis()).apply()
        }
    }

    suspend fun install() {
        if (busy != null) return
        // Sem "instalar apps desconhecidos", o Android recusa: leva à tela de permitir.
        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
            runCatching {
                context.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            flash("PERMITA E TOQUE DE NOVO")
            return
        }
        pct = 0; busy = DOWNLOADING
        val apk = runCatching { download() }.getOrElse { flash("FALHOU O DOWNLOAD"); return }
        busy = null
        runCatching {
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", apk)
            context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
        }.onFailure { flash("NÃO ABRIU O INSTALADOR") }
    }

    private suspend fun flash(msg: String) { busy = msg; delay(4000); busy = null }

    private suspend fun fetchLatest(): String = withContext(Dispatchers.IO) {
        val c = (URL(API).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000; readTimeout = 10_000
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "TokenBar-Android")
        }
        try {
            if (c.responseCode != 200) error("Resposta ${c.responseCode}")
            val body = c.inputStream.bufferedReader().readText()
            Regex("\"tag_name\"\\s*:\\s*\"([^\"]+)\"").find(body)?.groupValues?.get(1) ?: error("Sem versão")
        } finally { c.disconnect() }
    }

    private suspend fun download(): File = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "update").apply { mkdirs() }
        val out = File(dir, "TokenBar.apk")
        val c = (URL(apk(latest ?: error("Sem versão"))).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000; readTimeout = 30_000
            setRequestProperty("User-Agent", "TokenBar-Android")
        }
        try {
            if (c.responseCode != 200) error("Resposta ${c.responseCode}")
            val total = c.contentLengthLong
            c.inputStream.use { input ->
                out.outputStream().use { o ->
                    val buf = ByteArray(64 * 1024)
                    var done = 0L
                    var shown = -1
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        o.write(buf, 0, n)
                        done += n
                        val pct = if (total > 0) (done * 100 / total).toInt() else -1
                        if (pct != shown) { shown = pct; withContext(Dispatchers.Main) { this@Updater.pct = pct.coerceAtLeast(0); busy = DOWNLOADING } }
                    }
                }
            }
            out
        } finally { c.disconnect() }
    }

    companion object {
        private const val DOWNLOADING = "BAIXANDO %d%%"
        private const val EVERY = 6 * 60 * 60 * 1000L
        private const val API = "https://api.github.com/repos/ChaconLucas/tokenbar/releases/latest"
        /** Pelo número da versão: o atalho "latest/download" do GitHub demora a apontar para a nova. */
        private fun apk(tag: String) = "https://github.com/ChaconLucas/tokenbar/releases/download/$tag/TokenBar-Android.apk"

        /** "v0.3.1" > "0.3.0"? Números por posição; o que não for número vale 0. */
        fun newer(tag: String, current: String): Boolean {
            fun parts(v: String) = v.trim().removePrefix("v").substringBefore('-').split('.').map { it.toIntOrNull() ?: 0 }
            val a = parts(tag); val b = parts(current)
            for (i in 0 until maxOf(a.size, b.size)) {
                val x = a.getOrElse(i) { 0 }; val y = b.getOrElse(i) { 0 }
                if (x != y) return x > y
            }
            return false
        }
    }
}
