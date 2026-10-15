package app.tokenbar.app

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.tokenbar.core.Palette
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.min

private val PURPLE = Color(0xFF9E5CFF)
private val PINK = Color(0xFFEE29C2)
private val CYAN = Color(0xFF5AD8FF)
private val FRAME = Color(0xFF8C8C9A)
private val OFF = Color(0xFF1C1C24)
private const val WHITE = 0xFFFFFFFF.toInt()

private class Slide(val title: String, val line: String)

private val slides = listOf(
    Slide("INSTALE NO COMPUTADOR", "Mac, Windows ou Linux: o computador lê os limites das IAs."),
    Slide("ABRA O GUIA NELE", "No computador: Primeiros passos → Celular e relógio."),
    Slide("ESCANEIE O QR", "Aponte o celular para o QR do computador."),
    Slide("MESMO WI-FI", "Celular e computador na mesma rede. Fora de casa: servidor opcional."),
)

/** Primeiros passos em 4 telas: o desenho mostra, a frase só confirma. */
@Composable
internal fun Guide(paired: Boolean, error: String?, onLink: (String) -> Unit, onScan: () -> Unit, onSite: () -> Unit, update: String?, onUpdate: () -> Unit, onClose: () -> Unit) {
    val pager = rememberPagerState { slides.size }
    val scope = rememberCoroutineScope()
    val loop = rememberInfiniteTransition(label = "guia")
        .animateFloat(0f, 1f, infiniteRepeatable(tween(3000, easing = LinearEasing)), label = "laço")
    var text by remember { mutableStateOf("") }
    val gray = mono.copy(color = Color.Gray, fontSize = 13.sp)
    val page = pager.currentPage
    val last = page == slides.lastIndex

    // Fundo opaco que segura os toques: o aparelho fica por baixo.
    Box(Modifier.fillMaxSize().background(Color.Black).clickable(remember { MutableInteractionSource() }, null) {}) {
        Column(Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("PRIMEIROS PASSOS  ${page + 1}/${slides.size}", gray)
                Spacer(Modifier.weight(1f))
                if (update != null) { Key(update, Palette.CODEX) { onUpdate() }; Spacer(Modifier.width(8.dp)) }
                Key(if (paired) "FECHAR" else "PULAR", WHITE) { onClose() }
            }
            HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth()) { p ->
                Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Canvas(Modifier.weight(1f).fillMaxHeight().padding(vertical = 8.dp)) {
                        val t = loop.value   // lido só no desenho: anima sem recompor
                        stage { when (p) { 0 -> install(t); 1 -> openGuide(t); 2 -> scanQr(t); else -> wifi(t) } }
                    }
                    Spacer(Modifier.width(28.dp))
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                        Text(slides[p].title, mono.copy(fontSize = 22.sp))
                        Spacer(Modifier.height(10.dp))
                        Text(slides[p].line, mono.copy(color = Color.LightGray, fontSize = 15.sp))
                        Spacer(Modifier.height(18.dp))
                        when (p) {
                            0 -> Key("ABRIR SITE", WHITE) { onSite() }
                            2 -> {
                                Key("ESCANEAR QR", Palette.CODEX, big = true) { onScan() }
                                Spacer(Modifier.height(14.dp))
                                Text("ou cole o link", gray)
                                Spacer(Modifier.height(6.dp))
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    BasicTextField(text, { text = it }, textStyle = mono.copy(fontSize = 13.sp), cursorBrush = SolidColor(Color.White), singleLine = true,
                                        modifier = Modifier.weight(1f).border(1.dp, Color.DarkGray, RoundedCornerShape(8.dp)).padding(8.dp))
                                    Spacer(Modifier.width(10.dp))
                                    Key("PAREAR", Palette.CLAUDE) { onLink(text) }
                                }
                            }
                        }
                        if (error != null) {
                            Spacer(Modifier.height(10.dp))
                            Text(error, mono.copy(color = Color(0xFFFF8A8A), fontSize = 13.sp))
                        }
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Key("VOLTAR", WHITE, page > 0) { if (page > 0) scope.launch { pager.animateScrollToPage(page - 1) } }
                Spacer(Modifier.weight(1f))
                slides.indices.forEach { i ->
                    Box(Modifier.padding(horizontal = 4.dp).size(if (i == page) 9.dp else 7.dp)
                        .background(if (i == page) CYAN else Color.DarkGray, CircleShape))
                }
                Spacer(Modifier.weight(1f))
                Key(if (last) "PRONTO" else "AVANÇAR", if (last) Palette.CODEX else WHITE) {
                    if (last) onClose() else scope.launch { pager.animateScrollToPage(page + 1) }
                }
            }
        }
    }
}

// ---- Desenhos: palco virtual de 320x200, escalado para caber. ----

private const val VW = 320f
private const val VH = 200f

private fun DrawScope.stage(block: DrawScope.() -> Unit) {
    val s = min(size.width / VW, size.height / VH)
    translate((size.width - VW * s) / 2, (size.height - VH * s) / 2) { scale(s, s, Offset.Zero) { block() } }
}

/** Fração de [t] entre a e b, presa em 0..1. */
private fun ph(t: Float, a: Float, b: Float) = ((t - a) / (b - a)).coerceIn(0f, 1f)
private fun ease(x: Float) = x * x * (3 - 2 * x)

private fun DrawScope.glow(c: Color, x: Float, y: Float, r: Float, a: Float = 1f) {
    drawCircle(c.copy(alpha = 0.22f * a), r * 2.3f, Offset(x, y))
    drawCircle(c.copy(alpha = a), r, Offset(x, y))
}

private val ink = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { typeface = android.graphics.Typeface.MONOSPACE }

private fun DrawScope.label(s: String, x: Float, y: Float, size: Float, c: Color) =
    drawContext.canvas.nativeCanvas.drawText(s, x, y, ink.apply { textSize = size; color = c.toArgb() })

/** Notebook; devolve a área da tela. */
private fun DrawScope.laptop(x: Float, y: Float, w: Float, h: Float): Rect {
    drawRoundRect(FRAME, Offset(x, y), Size(w, h), CornerRadius(6f), style = Stroke(2f))
    val base = Path().apply {
        moveTo(x - 6, y + h + 3); lineTo(x + w + 6, y + h + 3); lineTo(x + w + 18, y + h + 12); lineTo(x - 18, y + h + 12); close()
    }
    drawPath(base, FRAME, style = Stroke(2f, join = StrokeJoin.Round))
    return Rect(x + 7, y + 7, x + w - 7, y + h - 7)
}

/** Celular em pé; devolve a área da tela. */
private fun DrawScope.phone(x: Float, y: Float, w: Float, h: Float): Rect {
    drawRoundRect(Color.Black, Offset(x, y), Size(w, h), CornerRadius(9f))
    drawRoundRect(FRAME, Offset(x, y), Size(w, h), CornerRadius(9f), style = Stroke(2f))
    drawLine(FRAME, Offset(x + w / 2 - 6, y + 6), Offset(x + w / 2 + 6, y + 6), 2f, StrokeCap.Round)
    return Rect(x + 5, y + 12, x + w - 5, y + h - 9)
}

/** Display de LED: barra roxa e barra rosa enchendo da esquerda. */
private fun DrawScope.led(r: Rect, purple: Float, pink: Float, on: Float = 1f, cols: Int = 24) {
    val rows = 9
    val dx = r.width / cols
    val dy = r.height / rows
    val rad = min(dx, dy) * 0.32f
    for (j in 0 until rows) for (i in 0 until cols) {
        val x = r.left + dx * (i + 0.5f)
        val y = r.top + dy * (j + 0.5f)
        val (c, f) = when (j) { 1, 2 -> PURPLE to purple; 5, 6 -> PINK to pink; else -> OFF to 0f }
        if (i < cols * f) glow(c, x, y, rad, on) else drawCircle(OFF, rad, Offset(x, y))
    }
}

private fun DrawScope.qr(x: Float, y: Float, s: Float, a: Float) {
    if (a <= 0f) return
    val n = 13
    val c = s / (n + 2)
    drawRoundRect(Color.White.copy(alpha = a), Offset(x, y), Size(s, s), CornerRadius(3f))
    for (i in 0 until n) for (j in 0 until n) if (qrCell(i, j, n))
        drawRect(Color.Black.copy(alpha = a), Offset(x + c * (i + 1), y + c * (j + 1)), Size(c + 0.3f, c + 0.3f))
}

/** Padrão fixo com os três quadrados de canto: só para parecer um QR. */
private fun qrCell(i: Int, j: Int, n: Int): Boolean {
    fun finder(a: Int, b: Int): Boolean? =
        if (a !in 0..4 || b !in 0..4) null else a == 0 || a == 4 || b == 0 || b == 4 || (a == 2 && b == 2)
    finder(i, j)?.let { return it }
    finder(i - (n - 5), j)?.let { return it }
    finder(i, j - (n - 5))?.let { return it }
    if ((i <= 5 && j <= 5) || (i >= n - 6 && j <= 5) || (i <= 5 && j >= n - 6)) return false
    return (i * 7 + j * 11 + i * j * 3) % 5 < 2
}

private fun DrawScope.check(cx: Float, cy: Float, r: Float, a: Float) {
    drawCircle(CYAN.copy(alpha = 0.18f * a), r * (0.7f + 0.3f * a), Offset(cx, cy))
    val p = Path().apply { moveTo(cx - r * 0.45f, cy); lineTo(cx - r * 0.1f, cy + r * 0.35f); lineTo(cx + r * 0.5f, cy - r * 0.35f) }
    drawPath(p, CYAN.copy(alpha = a), style = Stroke(3f, cap = StrokeCap.Round, join = StrokeJoin.Round))
}

/** 1: o programa desce para o notebook e a tela vira um display de LED. */
private fun DrawScope.install(t: Float) {
    val scr = laptop(70f, 40f, 180f, 112f)
    val d = ph(t, 0f, 0.25f)
    if (d < 1f) {
        val y = 6f + 30f * ease(d)
        val c = CYAN.copy(alpha = 1f - d)
        drawLine(c, Offset(160f, y - 16f), Offset(160f, y), 2.5f, StrokeCap.Round)
        drawPath(Path().apply { moveTo(153f, y - 7f); lineTo(160f, y); lineTo(167f, y - 7f) }, c, style = Stroke(2.5f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
    val on = ph(t, 0.15f, 0.3f) * (1f - ph(t, 0.92f, 1f))
    val f = ease(ph(t, 0.3f, 0.85f))
    led(scr, 0.85f * f, 0.55f * f, on)
}

/** 2: no notebook, Primeiros passos → Celular e relógio, e surge o QR. */
private fun DrawScope.openGuide(t: Float) {
    val scr = laptop(70f, 34f, 180f, 116f)
    val menu = 1f - ph(t, 0.42f, 0.52f)
    if (menu > 0f) {
        label("PRIMEIROS PASSOS", scr.left + 6f, scr.top + 14f, 10f, Color.White.copy(alpha = menu))
        val pick = ph(t, 0.2f, 0.3f)
        for (k in 0..2) {
            val top = scr.top + 24f + k * 24f
            val hot = k == 2
            val border = if (hot) lerp(Color(0xFF3A3A46), CYAN, pick) else Color(0xFF3A3A46)
            drawRoundRect(border.copy(alpha = menu), Offset(scr.left + 6f, top), Size(scr.width - 12f, 18f), CornerRadius(4f), style = Stroke(1.5f))
            if (hot) label("CELULAR E RELÓGIO", scr.left + 12f, top + 12.5f, 8.5f, (if (pick > 0f) CYAN else Color.LightGray).copy(alpha = menu))
            else drawRoundRect(Color(0xFF3A3A46).copy(alpha = menu), Offset(scr.left + 12f, top + 7f), Size(40f + 30f * k, 4f), CornerRadius(2f))
        }
        // o toque no item
        val tap = ph(t, 0.22f, 0.42f)
        if (tap in 0.001f..0.999f) drawCircle(CYAN.copy(alpha = 1f - tap), 4f + 12f * tap, Offset(scr.right - 22f, scr.top + 81f), style = Stroke(2f))
    }
    val q = ph(t, 0.5f, 0.65f) * (1f - ph(t, 0.92f, 1f))
    if (q > 0f) {
        label("CELULAR E RELÓGIO", scr.left + 6f, scr.top + 12f, 8.5f, CYAN.copy(alpha = q))
        qr(scr.center.x - 38f, scr.top + 19f, 76f, q)
    }
}

private fun lerp(a: Color, b: Color, f: Float) = Color(
    a.red + (b.red - a.red) * f, a.green + (b.green - a.green) * f, a.blue + (b.blue - a.blue) * f, a.alpha + (b.alpha - a.alpha) * f)

/** 3: o celular chega perto, a linha varre o QR e aparece o ✓. */
private fun DrawScope.scanQr(t: Float) {
    val scr = laptop(26f, 40f, 168f, 108f)
    val qx = scr.center.x - 40f
    val qy = scr.center.y - 40f
    qr(qx, qy, 80f, 1f)
    val px = 282f - 52f * ease(ph(t, 0f, 0.3f))
    val py = 44f
    val beam = ph(t, 0.3f, 0.4f) * (1f - ph(t, 0.7f, 0.8f))
    if (beam > 0f) drawPath(Path().apply { moveTo(px, py + 55f); lineTo(qx + 80f, qy); lineTo(qx + 80f, qy + 80f); close() }, CYAN.copy(alpha = 0.12f * beam))
    val ok = ph(t, 0.72f, 0.8f) * (1f - ph(t, 0.93f, 1f))
    if (ok > 0f) drawRoundRect(CYAN.copy(alpha = 0.8f * ok), Offset(qx - 3f, qy - 3f), Size(86f, 86f), CornerRadius(5f), style = Stroke(2f))

    val s = phone(px, py, 58f, 110f)
    // visor da câmera: cantos ciano
    val v = Rect(s.left + 4f, s.center.y - 22f, s.right - 4f, s.center.y + 22f)
    val k = 7f
    listOf(v.topLeft to Offset(1f, 1f), Offset(v.right, v.top) to Offset(-1f, 1f), Offset(v.left, v.bottom) to Offset(1f, -1f), v.bottomRight to Offset(-1f, -1f))
        .forEach { (o, d) ->
            drawLine(CYAN, o, Offset(o.x + k * d.x, o.y), 2f, StrokeCap.Round)
            drawLine(CYAN, o, Offset(o.x, o.y + k * d.y), 2f, StrokeCap.Round)
        }
    qr(s.center.x - 17f, s.center.y - 17f, 34f, ph(t, 0.25f, 0.35f) * (1f - ph(t, 0.7f, 0.75f)))
    if (t in 0.35f..0.7f) {
        val y = v.top + 3f + (v.height - 6f) * (1f - abs(1f - 2f * ph(t, 0.35f, 0.7f)))
        drawLine(CYAN.copy(alpha = 0.3f), Offset(v.left + 2f, y), Offset(v.right - 2f, y), 6f)
        drawLine(CYAN, Offset(v.left + 2f, y), Offset(v.right - 2f, y), 1.5f)
    }
    if (ok > 0f) check(s.center.x, s.center.y, 16f, ok)
}

/** 4: notebook e celular, o Wi-Fi pulsando e os números indo de um para o outro. */
private fun DrawScope.wifi(t: Float) {
    val scr = laptop(30f, 70f, 130f, 86f)
    led(scr, 0.8f, 0.5f)
    val s = phone(240f, 60f, 54f, 100f)
    led(s, 0.8f, 0.5f, cols = 10)
    // ondas: ponto + 3 arcos acendendo em sequência
    val cx = 205f
    val cy = 58f
    val p = (t * 2f) % 1f
    for (k in 0..3) {
        val a = 0.15f + 0.85f * ph(p, k * 0.18f, k * 0.18f + 0.1f) * (1f - ph(p, 0.8f, 1f))
        if (k == 0) glow(CYAN, cx, cy, 3f, a)
        else {
            val r = k * 12f
            drawArc(CYAN.copy(alpha = a), 225f, 90f, false, Offset(cx - r, cy - r), Size(r * 2, r * 2), style = Stroke(3f, cap = StrokeCap.Round))
        }
    }
    // pacotes de dados do notebook para o celular
    for (i in 0..2) {
        val f = (t + i / 3f) % 1f
        val x = 182f + (232f - 182f) * f
        val y = 112f - 14f * (1f - (2f * f - 1f) * (2f * f - 1f))
        glow(CYAN, x, y, 2.4f, ph(f, 0f, 0.15f) * (1f - ph(f, 0.85f, 1f)))
    }
}
