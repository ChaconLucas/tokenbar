package app.tokenbar.core

import android.content.Context
import android.net.Uri
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Mesmo formato que o Mac envia (datas em segundos desde 1970). */
@Serializable
data class UsageWindow(
    val id: String,
    val label: String,
    val usedPercent: Double,
    val resetsAt: Double? = null,
    val windowMinutes: Int? = null,
) {
    /** Depois do reset a janela começa do zero, mesmo sem número novo. */
    fun used(nowSec: Double = now()): Double = if (resetsAt != null && resetsAt <= nowSec) 0.0 else usedPercent
    fun didReset(nowSec: Double = now()): Boolean = resetsAt != null && resetsAt <= nowSec
}

@Serializable
data class ProviderUsage(val id: String, val name: String, val windows: List<UsageWindow>, val observedAt: Double,
                         val color: String? = null)

@Serializable
data class UsageSnapshot(val providers: List<ProviderUsage>, val updatedAt: Double) {
    fun provider(id: String) = providers.firstOrNull { it.id == id }
    companion object { val EMPTY = UsageSnapshot(emptyList(), 0.0) }
}

fun now(): Double = System.currentTimeMillis() / 1000.0

val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

/** Chave secreta do pareamento; o servidor é opcional (sem ele, só Wi-Fi local). */
@Serializable
data class Pairing(val token: String, val server: String? = null) {
    /** Os 8 primeiros caracteres: é o que o Mac anuncia no Wi-Fi para o celular achar o Mac certo. */
    val lanId: String get() = token.take(8)

    val link: String get() = buildString {
        append("tokenbar://pair?token=").append(Uri.encode(token))
        if (server != null) append("&server=").append(Uri.encode(server))
    }

    companion object {
        fun parse(text: String): Pairing? {
            val uri = runCatching { Uri.parse(text.trim()) }.getOrNull() ?: return null
            if (uri.scheme != "tokenbar" || uri.host != "pair") return null
            val token = uri.getQueryParameter("token") ?: return null
            if (token.length < 32) return null
            return Pairing(token, uri.getQueryParameter("server"))
        }
    }
}

/** As IAs com dados: Claude e Codex primeiro, depois qualquer outra que o Mac mandar. */
object Providers {
    @Volatile private var last: UsageSnapshot = UsageSnapshot.EMPTY
    fun update(s: UsageSnapshot) { last = s }

    val all: List<String>
        get() {
            val ids = last.providers.map { it.id }
            val known = listOf("claude", "codex")
            val list = known.filter { ids.isEmpty() || it in ids } + ids.filter { it !in known }
            return list.ifEmpty { known }
        }

    fun short(id: String) = when (id) {
        "claude" -> "CLAUDE"; "codex" -> "CODEX"
        else -> (last.provider(id)?.name ?: id).uppercase().take(8)
    }
    fun abbr(id: String) = when (id) {
        "claude" -> "CL"; "codex" -> "CX"
        else -> short(id).replace(" ", "").take(2)
    }
    /** Cor que a IA mandou ("#RRGGBB"), se houver. */
    fun color(id: String): Int? = last.provider(id)?.color?.removePrefix("#")?.toLongOrNull(16)?.let { (0xFF000000 or it).toInt() }
}

/** Escolha de janela: "short" (5h), "long" (7d) ou "both". */
fun ProviderUsage?.pick(window: String): UsageWindow? {
    val ws = this?.windows ?: return null
    return if (window == "long") ws.getOrNull(1) ?: ws.firstOrNull() else ws.firstOrNull()
}

/** "0:43", "6D" — o mesmo texto curto do Mac. */
fun timeLeft(w: UsageWindow?, nowSec: Double = now()): String {
    val r = w?.resetsAt ?: return ""
    if (w.didReset(nowSec)) return "OK"
    val s = maxOf(0, (r - nowSec).toInt())
    val d = s / 86400; val h = (s % 86400) / 3600; val m = (s % 3600) / 60
    return if (d > 0) "${d}D" else "$h:" + m.toString().padStart(2, '0')
}

/** Tudo o que o app guarda no aparelho. */
class Store(context: Context) {
    private val p = context.getSharedPreferences("tokenbar", Context.MODE_PRIVATE)

    var snapshot: UsageSnapshot
        get() = (p.getString("snapshot", null)?.let { runCatching { json.decodeFromString<UsageSnapshot>(it) }.getOrNull() } ?: UsageSnapshot.EMPTY)
            .also { Providers.update(it) }
        set(v) { Providers.update(v); p.edit().putString("snapshot", json.encodeToString(UsageSnapshot.serializer(), v)).apply() }

    var pairing: Pairing?
        get() = p.getString("pairing", null)?.let { runCatching { json.decodeFromString<Pairing>(it) }.getOrNull() }
        set(v) { p.edit().apply { if (v == null) remove("pairing") else putString("pairing", json.encodeToString(Pairing.serializer(), v)) }.apply() }

    var window: String
        get() = p.getString("window", "short") ?: "short"
        set(v) { p.edit().putString("window", v).apply() }

    /** Guarda as IAs DESLIGADAS: uma IA nova já chega ligada. */
    var visible: List<String>
        get() {
            val hidden = p.getString("hidden", "")!!.split(",").toSet()
            return Providers.all.filter { it !in hidden }.ifEmpty { Providers.all }
        }
        set(v) { p.edit().putString("hidden", Providers.all.filter { it !in v }.joinToString(",")).apply() }

    /** Limites já avisados neste ciclo ("claude.five_hour.80" → resetsAt). */
    fun alerted(key: String): Double = p.getFloat("alert.$key", 0f).toDouble()
    fun markAlerted(key: String, cycle: Double) { p.edit().putFloat("alert.$key", cycle.toFloat()).apply() }
}
