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
            // Com servidor, o relógio busca sozinho (funciona longe do celular).
            LaunchedEffect(Unit) {
                while (true) {
                    store.pairing?.takeIf { it.server != null }?.let { p ->
                        runCatching { Fetch.server(p) }.getOrNull()?.let { if (it.updatedAt >= store.snapshot.updatedAt) { store.snapshot = it; snapshot = it } }
                    }
                    delay(60_000)
                }
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
                    BasicText("Abra o TokenBar no celular.", style = TextStyle(color = Color.Gray, fontSize = 12.sp))
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
