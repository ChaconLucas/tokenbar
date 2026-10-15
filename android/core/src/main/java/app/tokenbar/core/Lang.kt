package app.tokenbar.core

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

/**
 * Idioma do app: o português é a chave; o inglês sai do mapa. Chave sem tradução = português.
 * O idioma mora num estado observável: trocar recompõe toda a tela na hora.
 * Widget, avisos e relógio chamam [load] antes de desenhar (leem a preferência guardada).
 */
object Lang {
    /** "auto", "pt" ou "en" — o que o usuário escolheu. */
    var pref by mutableStateOf("auto")
        private set
    /** "pt" ou "en" — o que está valendo. */
    var current by mutableStateOf(resolve("auto"))
        private set

    fun resolve(pref: String) = when (pref) {
        "pt", "en" -> pref
        else -> if (Locale.getDefault().language == "pt") "pt" else "en"
    }

    fun load(context: Context) = adopt(Store(context).lang)

    fun set(context: Context, value: String) { Store(context).lang = value; adopt(value) }

    private fun adopt(value: String) { pref = value; current = resolve(value) }

    /** AUTO → PT → EN → AUTO. */
    fun next(value: String = pref) = when (value) { "auto" -> "pt"; "pt" -> "en"; else -> "auto" }

    fun t(pt: String): String {
        if (current != "en") return pt
        en[pt]?.let { return it }
        // Mensagens com número no fim ("Resposta 500").
        prefixes.forEach { (a, b) -> if (pt.startsWith(a)) return b + pt.removePrefix(a) }
        return pt
    }

    fun f(ptFormat: String, vararg args: Any?): String = String.format(Locale.ROOT, t(ptFormat), *args)

    private val prefixes = listOf("Resposta " to "Response ")

    private val en: Map<String, String> = mapOf(
        // Erros (core/Net.kt, Sync, pareamento)
        "Sem resposta" to "No response",
        "Mac não encontrado no Wi-Fi" to "Mac not found on Wi-Fi",
        "Mac sem endereço" to "Mac has no address",
        "Nenhum Mac com TokenBar no Wi-Fi" to "No Mac with TokenBar on Wi-Fi",
        "Resposta inválida do Mac" to "Invalid response from the Mac",
        "Código errado" to "Wrong code",
        "Muitas tentativas: espere 1 minuto" to "Too many tries: wait 1 minute",
        "O Mac recusou a chave (pareie de novo)" to "The Mac rejected the key (pair again)",
        "Nenhum dado enviado ainda pelo Mac" to "The Mac hasn't sent any data yet",
        "Não pareado" to "Not paired",
        "Link de pareamento inválido" to "Invalid pairing link",
        "Não deu para ler o QR" to "Couldn't read the QR code",

        // Aparelho (teclas e ajuda)
        "SAIR" to "UNPAIR",
        "PAREAR" to "PAIR",
        "AJUDA" to "HELP",
        "FECHAR" to "CLOSE",
        "NÃO CHEGA NÚMERO?" to "NO NUMBERS?",
        "O computador está ligado e com o TokenBar aberto?" to "Is the computer on, with TokenBar open?",
        "Celular e computador no mesmo Wi-Fi?" to "Phone and computer on the same Wi-Fi?",
        "No Mac, permita conexões de entrada para o TokenBar (firewall)." to "On the Mac, allow incoming connections for TokenBar (firewall).",
        "Escaneie o QR de novo (SAIR e parear outra vez)." to "Scan the QR again (UNPAIR and pair once more).",

        // Atualização
        "ATUALIZAR" to "UPDATE",
        "BAIXANDO %d%%" to "DOWNLOADING %d%%",
        "PERMITA E TOQUE DE NOVO" to "ALLOW AND TAP AGAIN",
        "FALHOU O DOWNLOAD" to "DOWNLOAD FAILED",
        "NÃO ABRIU O INSTALADOR" to "INSTALLER DIDN'T OPEN",

        // Guia
        "PRIMEIROS PASSOS  %d/%d" to "GETTING STARTED  %d/%d",
        "PRIMEIROS PASSOS" to "GETTING STARTED",
        "CELULAR E RELÓGIO" to "PHONE & WATCH",
        "PULAR" to "SKIP",
        "VOLTAR" to "BACK",
        "AVANÇAR" to "NEXT",
        "PRONTO" to "DONE",
        "ABRIR SITE" to "OPEN SITE",
        "ESCANEAR QR" to "SCAN QR",
        "ou cole o link" to "or paste the link",
        "INSTALE NO COMPUTADOR" to "INSTALL ON THE COMPUTER",
        "Mac, Windows ou Linux: o computador lê os limites das IAs." to "Mac, Windows or Linux: the computer reads your AI limits.",
        "ABRA O GUIA NELE" to "OPEN ITS GUIDE",
        "No computador: Primeiros passos → Celular e relógio." to "On the computer: Getting started → Phone & watch.",
        "ESCANEIE O QR" to "SCAN THE QR",
        "Aponte o celular para o QR do computador." to "Point the phone at the computer's QR.",
        "MESMO WI-FI" to "SAME WI-FI",
        "Celular e computador na mesma rede. Fora de casa: servidor opcional." to "Phone and computer on the same network. Away from home: optional server.",

        // Avisos e widget
        "Limites de IA" to "AI limits",
        "Quase no limite." to "Almost at the limit.",
        "Passou de %d%% do limite." to "Over %d%% of the limit.",
        "Uso das IAs" to "AI usage",

        // Relógio
        "TODOS" to "ALL",
        "Sem dados" to "No data",
        "Buscando os números…" to "Fetching the numbers…",
        "Digite o código de 6 números." to "Enter the 6-digit code.",
        "Com celular Android pareado, ele recebe sozinho." to "With a paired Android phone, it arrives on its own.",
        "DIGITAR" to "ENTER CODE",
        "Procurando o computador…" to "Looking for the computer…",
        "Código do computador" to "Computer code",
    )
}
