package app.tokenbar.app

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import app.tokenbar.core.*
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val store by lazy { Store(this) }
    private var pairing by mutableStateOf<Pairing?>(null)
    private var snapshot by mutableStateOf(UsageSnapshot.EMPTY)
    private var error by mutableStateOf<String?>(null)
    private var guide by mutableStateOf(false)
    private val prefs by lazy { getSharedPreferences("guia", MODE_PRIVATE) }
    private val updater by lazy { Updater(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Tela cheia de verdade e sempre acesa.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        if (Build.VERSION.SDK_INT >= 33)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)

        pairing = store.pairing
        snapshot = store.snapshot
        // O guia abre sozinho só para quem nunca pareou nem pulou.
        guide = pairing == null && !prefs.getBoolean("pulou", false)
        handle(intent)
        Sync.schedule(this)

        setContent {
            val scope = rememberCoroutineScope()
            LaunchedEffect(Unit) { updater.watch() }
            val onUpdate = { scope.launch { updater.install() }; Unit }
            LaunchedEffect(pairing) {
                while (pairing != null) {
                    Sync.refresh(this@MainActivity)
                        .onSuccess { snapshot = it; error = null }
                        .onFailure { error = it.message }
                    delay(60_000)
                }
            }
            Box(Modifier.fillMaxSize().background(Color.Black)) {
                val paired = pairing != null
                Device(snapshot, store, if (paired) error else null, paired, updater.label, onUpdate, onGuide = { guide = true }, onUnpair = {
                    store.pairing = null; pairing = null; guide = true
                })
                if (guide) Guide(paired, error, ::pairWith, ::scan, ::openSite, if (paired) null else updater.label, onUpdate) {
                    guide = false
                    if (!paired) { prefs.edit().putBoolean("pulou", true).apply(); error = null }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        intent?.dataString?.let { pairWith(it) }
    }

    private fun pairWith(text: String) {
        val p = Pairing.parse(text) ?: run { error = "Link de pareamento inválido"; return }
        store.pairing = p
        pairing = p
        error = null
        guide = false
    }

    private fun openSite() {
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/ChaconLucas/tokenbar"))) }
    }

    /** Leitor de QR do Google Play (sem pedir permissão de câmera). */
    private fun scan() {
        GmsBarcodeScanning.getClient(this).startScan()
            .addOnSuccessListener { code -> code.rawValue?.let(::pairWith) }
            .addOnFailureListener { error = "Não deu para ler o QR" }
    }
}

internal val mono = TextStyle(fontFamily = FontFamily.Monospace, color = Color.White, fontSize = 15.sp)

/** Quando não chega número: o que conferir. */
@Composable
private fun Help(onClose: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.92f)).clickable(onClick = onClose), contentAlignment = Alignment.Center) {
        Column(Modifier.border(1.dp, Color.DarkGray, RoundedCornerShape(12.dp)).background(Color.Black, RoundedCornerShape(12.dp)).padding(24.dp)) {
            Text("NÃO CHEGA NÚMERO?", mono.copy(fontSize = 18.sp))
            Spacer(Modifier.height(12.dp))
            listOf(
                "O computador está ligado e com o TokenBar aberto?",
                "Celular e computador no mesmo Wi-Fi?",
                "No Mac, permita conexões de entrada para o TokenBar (firewall).",
                "Escaneie o QR de novo (SAIR e parear outra vez).",
            ).forEach { Text("• $it", mono.copy(color = Color.LightGray, fontSize = 14.sp)); Spacer(Modifier.height(6.dp)) }
            Spacer(Modifier.height(8.dp))
            Key("FECHAR", 0xFFFFFFFF.toInt()) { onClose() }
        }
    }
}

@Composable
internal fun Text(s: String, style: TextStyle) = androidx.compose.foundation.text.BasicText(s, style = style)

@Composable
internal fun Key(label: String, color: Int, on: Boolean = true, big: Boolean = false, onClick: () -> Unit) {
    val c = Color(if (on) color else 0xFF666666.toInt())
    Box(
        Modifier.border(1.dp, c.copy(alpha = 0.6f), RoundedCornerShape(50)).background(Color.Black, RoundedCornerShape(50))
            .clickable(onClick = onClick).padding(horizontal = if (big) 24.dp else 14.dp, vertical = if (big) 12.dp else 6.dp)
    ) { Text(label, mono.copy(color = c, fontSize = if (big) 18.sp else 14.sp)) }
}

/** O aparelho: teclas em cima, display de LED ocupando o resto; deslizar troca de IA. */
@Composable
private fun Device(snapshot: UsageSnapshot, store: Store, error: String?, paired: Boolean, update: String?, onUpdate: () -> Unit, onGuide: () -> Unit, onUnpair: () -> Unit) {
    var visible by remember { mutableStateOf(store.visible) }
    var window by remember { mutableStateOf(store.window) }
    val pager = rememberPagerState { visible.size }
    var tick by remember { mutableLongStateOf(0L) }
    var help by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { while (true) { delay(1000); tick++ } }

    Box(Modifier.fillMaxSize()) {
    Column(Modifier.fillMaxSize().padding(horizontal = 18.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Providers.all.forEach { id ->
                Key(if (Providers.all.size > 2) Providers.abbr(id) else Providers.short(id), Palette.base(id), id in visible) {
                    val next = if (id in visible) visible - id else Providers.all.filter { it in visible || it == id }
                    if (next.isNotEmpty()) { visible = next; store.visible = next }
                }
                Spacer(Modifier.width(8.dp))
            }
            Spacer(Modifier.weight(1f))
            // Versão nova no GitHub: baixa e abre o instalador.
            if (update != null) { Key(update, Palette.CODEX) { onUpdate() }; Spacer(Modifier.width(8.dp)) }
            Key(when (window) { "long" -> "7D"; "both" -> "5H 7D"; else -> "5H" }, 0xFFFFFFFF.toInt()) {
                window = when (window) { "short" -> "long"; "long" -> "both"; else -> "short" }
                store.window = window
            }
            Spacer(Modifier.width(8.dp))
            // Sem pareamento não há número: a tecla leva de volta ao guia.
            if (paired) {
                Key("?", 0xFFFFFFFF.toInt()) { onGuide() }
                Spacer(Modifier.width(8.dp))
                Key("SAIR", 0xFFFF6B6B.toInt(), true) { onUnpair() }
            } else Key("PAREAR", Palette.CLAUDE) { onGuide() }
        }
        Spacer(Modifier.height(8.dp))
        HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth()) { page ->
            val id = visible.getOrElse(page) { visible.first() }
            val items = Led.items(snapshot, id, window)
            Canvas(Modifier.fillMaxSize()) {
                tick.let { }   // redesenha a cada segundo (contagem regressiva)
                drawIntoCanvas { c ->
                    // Uma IA: 5h e 7d em linhas; a IA vai no título quando há uma só janela.
                    val shown = if (items.size == 1) listOf(items[0].copy(title = Providers.short(id) + " " + (items[0].window?.label?.uppercase() ?: ""))) else items
                    Led.minCols = 72   // celular deitado: pontos finos, número grande
                    Led.grid(c.nativeCanvas, 0f, 0f, size.width, size.height, shown, 1, 14f, now())
                }
            }
        }
        if (error != null) Row(Modifier.clickable { help = true }, verticalAlignment = Alignment.CenterVertically) {
            Text(error.uppercase(), mono.copy(color = Color(0xFFFF8A8A), fontSize = 12.sp))
            Spacer(Modifier.width(10.dp))
            Key("AJUDA", 0xFFFF8A8A.toInt()) { help = true }
        }
    }
    if (help) Help { help = false }
    }
}
