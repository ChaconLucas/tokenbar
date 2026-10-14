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
data class ProviderUsage(val id: String, val name: String, val windows: List<UsageWindow>, val observedAt: Double)

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

/** Ordem e nomes das IAs. */
object Providers {
    val all = listOf("claude", "codex")
    fun short(id: String) = if (id == "codex") "CODEX" else "CLAUDE"
    fun abbr(id: String) = if (id == "codex") "CX" else "CL"
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
        get() = p.getString("snapshot", null)?.let { runCatching { json.decodeFromString<UsageSnapshot>(it) }.getOrNull() } ?: UsageSnapshot.EMPTY
        set(v) { p.edit().putString("snapshot", json.encodeToString(UsageSnapshot.serializer(), v)).apply() }

    var pairing: Pairing?
        get() = p.getString("pairing", null)?.let { runCatching { json.decodeFromString<Pairing>(it) }.getOrNull() }
        set(v) { p.edit().apply { if (v == null) remove("pairing") else putString("pairing", json.encodeToString(Pairing.serializer(), v)) }.apply() }

    var window: String
        get() = p.getString("window", "short") ?: "short"
        set(v) { p.edit().putString("window", v).apply() }

    var visible: List<String>
        get() = (p.getString("visible", null)?.split(",")?.filter { it in Providers.all })?.ifEmpty { null } ?: Providers.all
        set(v) { p.edit().putString("visible", v.joinToString(",")).apply() }

    /** Limites já avisados neste ciclo ("claude.five_hour.80" → resetsAt). */
    fun alerted(key: String): Double = p.getFloat("alert.$key", 0f).toDouble()
    fun markAlerted(key: String, cycle: Double) { p.edit().putFloat("alert.$key", cycle.toFloat()).apply() }
}
