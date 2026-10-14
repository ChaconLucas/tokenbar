package app.tokenbar.core

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.resume

/** Busca os números: Wi-Fi local (o Mac anunciado por Bonjour/NSD) e, se houver, o servidor. Fica o mais novo. */
object Fetch {
    class Failure(msg: String) : Exception(msg)

    suspend fun best(context: Context, p: Pairing): UsageSnapshot = coroutineScope {
        val lan = async { runCatching { lan(context, p) } }
        val srv = async { if (p.server == null) null else runCatching { server(p) } }
        val results = listOfNotNull(lan.await().getOrNull(), srv.await()?.getOrNull())
        results.maxByOrNull { it.updatedAt }
            ?: throw Failure(srv.await()?.exceptionOrNull()?.message ?: lan.await().exceptionOrNull()?.message ?: "Sem resposta")
    }

    suspend fun server(p: Pairing): UsageSnapshot = withContext(Dispatchers.IO) {
        get(URL(p.server!!.trimEnd('/') + "/v1/usage"), p.token)
    }

    /** Acha o Mac com o mesmo id do pareamento na rede e pede /v1/usage. */
    suspend fun lan(context: Context, p: Pairing): UsageSnapshot {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val info = withTimeoutOrNull(5000) { discover(nsd, p.lanId) } ?: throw Failure("Mac não encontrado no Wi-Fi")
        val host = info.host?.hostAddress ?: throw Failure("Mac sem endereço")
        val h = if (host.contains(':')) "[$host]" else host
        return withContext(Dispatchers.IO) { get(URL("http://$h:${info.port}/v1/usage"), p.token) }
    }

    /** Relógio sem celular: acha qualquer Mac com TokenBar no Wi-Fi e troca o código de 6 números pelo pareamento. */
    suspend fun pairByCode(context: Context, code: String): Pairing {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val info = withTimeoutOrNull(8000) { discover(nsd, null) } ?: throw Failure("Nenhum Mac com TokenBar no Wi-Fi")
        val host = info.host?.hostAddress ?: throw Failure("Mac sem endereço")
        val h = if (host.contains(':')) "[$host]" else host
        return withContext(Dispatchers.IO) {
            val c = (URL("http://$h:${info.port}/v1/pair?code=$code").openConnection() as HttpURLConnection).apply {
                connectTimeout = 6000; readTimeout = 6000
            }
            try {
                when (c.responseCode) {
                    200 -> {
                        val body = c.inputStream.bufferedReader().readText()
                        val link = Regex("\"link\"\\s*:\\s*\"([^\"]+)\"").find(body)?.groupValues?.get(1)?.replace("\\/", "/")
                        link?.let { Pairing.parse(it) } ?: throw Failure("Resposta inválida do Mac")
                    }
                    401 -> throw Failure("Código errado")
                    429 -> throw Failure("Muitas tentativas: espere 1 minuto")
                    else -> throw Failure("Resposta ${c.responseCode}")
                }
            } finally { c.disconnect() }
        }
    }

    /** lanId nulo = o primeiro Mac encontrado. */
    private suspend fun discover(nsd: NsdManager, lanId: String?): NsdServiceInfo =
        suspendCancellableCoroutine { cont ->
            var done = false
            lateinit var listener: NsdManager.DiscoveryListener
            listener = object : NsdManager.DiscoveryListener {
                override fun onServiceFound(s: NsdServiceInfo) {
                    @Suppress("DEPRECATION")
                    nsd.resolveService(s, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(si: NsdServiceInfo, code: Int) {}
                        override fun onServiceResolved(si: NsdServiceInfo) {
                            val id = si.attributes["id"]?.let { String(it) }
                            if ((lanId == null || id == lanId) && !done) { done = true; runCatching { nsd.stopServiceDiscovery(listener) }; cont.resume(si) }
                        }
                    })
                }
                override fun onStartDiscoveryFailed(t: String, e: Int) {}
                override fun onStopDiscoveryFailed(t: String, e: Int) {}
                override fun onDiscoveryStarted(t: String) {}
                override fun onDiscoveryStopped(t: String) {}
                override fun onServiceLost(s: NsdServiceInfo) {}
            }
            nsd.discoverServices("_tokenbar._tcp", NsdManager.PROTOCOL_DNS_SD, listener)
            cont.invokeOnCancellation { if (!done) runCatching { nsd.stopServiceDiscovery(listener) } }
        }

    private fun get(url: URL, token: String): UsageSnapshot {
        val c = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 6000; readTimeout = 6000
            setRequestProperty("Authorization", "Bearer $token")
            useCaches = false
        }
        try {
            when (c.responseCode) {
                200 -> return json.decodeFromString(UsageSnapshot.serializer(), c.inputStream.bufferedReader().readText())
                401 -> throw Failure("O Mac recusou a chave (pareie de novo)")
                404 -> throw Failure("Nenhum dado enviado ainda pelo Mac")
                else -> throw Failure("Resposta ${c.responseCode}")
            }
        } finally { c.disconnect() }
    }
}
