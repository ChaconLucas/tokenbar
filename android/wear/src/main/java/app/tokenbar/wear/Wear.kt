package app.tokenbar.wear

import android.content.ComponentName
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.watchface.complications.data.*
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import app.tokenbar.core.*
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** App do relógio: TODOS (as IAs na janela escolhida) ou uma IA com 5h e 7d. Toque nas teclas troca. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val store = Store(this)
        // tokenbar://pair?... também pareia direto no relógio (útil sem celular por perto).
        intent?.dataString?.let { Pairing.parse(it) }?.let { store.pairing = it }
        setContent {
            var snapshot by remember { mutableStateOf(store.snapshot) }
            var agent by remember { mutableStateOf("all") }
            var window by remember { mutableStateOf(if (store.window == "long") "long" else "short") }
            var tick by remember { mutableLongStateOf(0L) }
            LaunchedEffect(Unit) { while (true) { delay(1000); tick++; if (tick % 10 == 0L) snapshot = store.snapshot } }
            var paired by remember { mutableStateOf(store.pairing != null) }
            // Busca sozinho (Wi-Fi do Mac ou servidor): funciona sem o celular. Com celular, ele também manda.
            LaunchedEffect(paired) {
                while (paired) {
                    store.pairing?.let { p ->
                        runCatching { Fetch.best(this@MainActivity, p) }.getOrNull()
                            ?.let { if (it.updatedAt >= store.snapshot.updatedAt) { store.snapshot = it; snapshot = it } }
                    }
                    delay(60_000)
                }
            }
            if (!paired && snapshot.providers.isEmpty()) {
                CodeEntry { code, done ->
                    runCatching { Fetch.pairByCode(this@MainActivity, code) }
                        .onSuccess { store.pairing = it; paired = true; done(null) }
                        .onFailure { done(it.message) }
                }
                return@setContent
            }

            // Tela redonda: margem maior dos lados para nada encostar no contorno.
            Column(Modifier.fillMaxSize().background(Color.Black).padding(start = 30.dp, end = 30.dp, top = 22.dp, bottom = 30.dp),
                   horizontalAlignment = Alignment.CenterHorizontally) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Key(if (agent == "all") "TODOS" else Providers.short(agent),
                        if (agent == "all") 0xFFFFFFFF.toInt() else Palette.base(agent)) {
                        val order = listOf("all") + Providers.all
                        agent = order[(order.indexOf(agent) + 1) % order.size]
                    }
                    if (agent == "all") Key(if (window == "long") "7D" else "5H", 0xFFFFFFFF.toInt()) {
                        window = if (window == "long") "short" else "long"; store.window = window
                    }
                }
                Spacer(Modifier.height(6.dp))
                val items = if (agent == "all") Led.items(snapshot, "all", window) else Led.items(snapshot, agent, "both")
                if (snapshot.providers.isEmpty()) {
                    BasicText("Buscando os números…", style = TextStyle(color = Color.Gray, fontSize = 12.sp))
                } else Canvas(Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(12.dp))) {
                    tick.let { }
                    drawIntoCanvas { Led.grid(it.nativeCanvas, 0f, 0f, size.width, size.height, items, 1, 10f, now()) }
                }
            }
        }
    }
}

@Composable
private fun Key(label: String, color: Int, onClick: () -> Unit) {
    val c = Color(color)
    Box(Modifier.border(1.dp, c.copy(alpha = 0.6f), RoundedCornerShape(50)).clickable(onClick = onClick)
        .padding(horizontal = 9.dp, vertical = 3.dp)) {
        BasicText(label, style = TextStyle(fontFamily = FontFamily.Monospace, color = c, fontSize = 11.sp))
    }
}

/** Recebe do celular os números e o pareamento. */
class PhoneListener : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        val store = Store(this)
        for (e in events) {
            if (e.type != DataEvent.TYPE_CHANGED || e.dataItem.uri.path != "/tokenbar/state") continue
            val map = DataMapItem.fromDataItem(e.dataItem).dataMap
            map.getString("snapshot")?.let { s ->
                runCatching { json.decodeFromString(UsageSnapshot.serializer(), s) }.getOrNull()?.let { store.snapshot = it }
            }
            store.pairing = map.getString("pairing")?.let { Pairing.parse(it) }
        }
        ComplicationDataSourceUpdateRequester.create(this, ComponentName(this, UsageComplication::class.java)).requestUpdateAll()
    }
}

/** Complicação do mostrador: anel com o gasto do Claude (5h), texto curto e longo. */
class UsageComplication : SuspendingComplicationDataSourceService() {
    override fun getPreviewData(type: ComplicationType) = data(type, UsageSnapshot(listOf(
        ProviderUsage("claude", "Claude Code", listOf(UsageWindow("five_hour", "5h", 42.0)), now()),
        ProviderUsage("codex", "Codex", listOf(UsageWindow("primary", "5h", 8.0)), now())), now()))

    override suspend fun onComplicationRequest(request: ComplicationRequest) = data(request.complicationType, Store(this).snapshot)

    private fun data(type: ComplicationType, s: UsageSnapshot): ComplicationData? {
        val claude = s.provider("claude").pick("short")?.used()
        val codex = s.provider("codex").pick("short")?.used()
        val main = claude ?: codex
        val short = main?.let { "${it.toInt()}%" } ?: "--"
        val long = listOfNotNull(claude?.let { "CL ${it.toInt()}%" }, codex?.let { "CX ${it.toInt()}%" }).joinToString(" · ").ifEmpty { "Sem dados" }
        val desc = PlainComplicationText.Builder("Uso das IAs").build()
        return when (type) {
            ComplicationType.RANGED_VALUE -> RangedValueComplicationData.Builder((main ?: 0.0).toFloat(), 0f, 100f, desc)
                .setText(PlainComplicationText.Builder(short).build())
                .setTitle(PlainComplicationText.Builder(if (claude != null) "CL" else "CX").build())
                .build()
            ComplicationType.SHORT_TEXT -> ShortTextComplicationData.Builder(PlainComplicationText.Builder(short).build(), desc)
                .setTitle(PlainComplicationText.Builder(if (claude != null) "CL" else "CX").build()).build()
            ComplicationType.LONG_TEXT -> LongTextComplicationData.Builder(PlainComplicationText.Builder(long).build(), desc).build()
            else -> null
        }
    }
}

/** Teclado numérico: o código de 6 números que o computador mostra em Primeiros passos. Antes, uma tela que explica. */
@Composable
private fun CodeEntry(submit: suspend (String, (String?) -> Unit) -> Unit) {
    var intro by remember { mutableStateOf(true) }
    var code by remember { mutableStateOf("") }
    var msg by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    if (intro) {
        Column(Modifier.fillMaxSize().background(Color.Black).padding(horizontal = 28.dp, vertical = 24.dp),
               horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            val t = TextStyle(color = Color.White, fontSize = 12.sp, textAlign = TextAlign.Center)
            BasicText("No computador: Primeiros passos → Celular e relógio.", style = t)
            Spacer(Modifier.height(4.dp))
            BasicText("Digite o código de 6 números.", style = t)
            Spacer(Modifier.height(6.dp))
            BasicText("Com celular Android pareado, ele recebe sozinho.", style = t.copy(color = Color.Gray, fontSize = 10.sp))
            Spacer(Modifier.height(8.dp))
            Key("DIGITAR", 0xFF33D9F2.toInt()) { intro = false }
        }
        return
    }
    Column(Modifier.fillMaxSize().background(Color.Black).padding(horizontal = 34.dp, vertical = 26.dp),
           horizontalAlignment = Alignment.CenterHorizontally) {
        BasicText(if (busy) "Procurando o computador…" else (msg ?: "Código do computador"),
            style = TextStyle(color = if (msg != null) Color(0xFFFF8A8A) else Color.Gray, fontSize = 11.sp))
        BasicText(code.padEnd(6, '_'), style = TextStyle(fontFamily = FontFamily.Monospace, color = Color.White, fontSize = 20.sp, letterSpacing = 3.sp))
        Spacer(Modifier.height(4.dp))
        val rows = listOf("123", "456", "789", "<0>")
        rows.forEach { r ->
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                r.forEach { ch ->
                    Box(Modifier.size(width = 38.dp, height = 26.dp).border(1.dp, Color.DarkGray, RoundedCornerShape(50))
                        .clickable(enabled = !busy) {
                            when (ch) {
                                '<' -> code = code.dropLast(1)
                                '>' -> if (code.length == 6) {
                                    busy = true; msg = null
                                    scope.launch { submit(code) { err -> busy = false; msg = err; if (err != null) code = "" } }
                                }
                                else -> if (code.length < 6) code += ch
                            }
                        }, contentAlignment = Alignment.Center) {
                        BasicText(when (ch) { '<' -> "⌫"; '>' -> "OK"; else -> ch.toString() },
                            style = TextStyle(color = if (ch == '>') Color(0xFF33D9F2) else Color.White, fontSize = 13.sp))
                    }
                }
            }
            Spacer(Modifier.height(3.dp))
        }
    }
}
