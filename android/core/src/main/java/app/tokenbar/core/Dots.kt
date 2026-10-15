package app.tokenbar.core

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF

/** Fonte 5×7 de matriz de pontos — a mesma do app da Apple. */
object DotFont {
    private val g: Map<Char, List<String>> = mapOf(
        '0' to listOf(".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
        '1' to listOf("..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."),
        '2' to listOf(".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"),
        '3' to listOf("#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."),
        '4' to listOf("...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."),
        '5' to listOf("#####", "#....", "####.", "....#", "....#", "#...#", ".###."),
        '6' to listOf("..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."),
        '7' to listOf("#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."),
        '8' to listOf(".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."),
        '9' to listOf(".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."),
        '%' to listOf("##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##"),
        ':' to listOf("..", "##", "##", "..", "##", "##", ".."),
        '-' to listOf(".....", ".....", ".....", "#####", ".....", ".....", "....."),
        ' ' to listOf("...", "...", "...", "...", "...", "...", "..."),
        'A' to listOf(".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
        'C' to listOf(".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."),
        'D' to listOf("###..", "#..#.", "#...#", "#...#", "#...#", "#..#.", "###.."),
        'E' to listOf("#####", "#....", "#....", "####.", "#....", "#....", "#####"),
        'H' to listOf("#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
        'K' to listOf("#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"),
        'L' to listOf("#....", "#....", "#....", "#....", "#....", "#....", "#####"),
        'N' to listOf("#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"),
        'O' to listOf(".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
        'R' to listOf("####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"),
        'S' to listOf(".####", "#....", "#....", ".###.", "....#", "....#", "####."),
        'T' to listOf("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."),
        'U' to listOf("#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
        'X' to listOf("#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"),
        'B' to listOf("####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."),
        'I' to listOf(".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."),
        'P' to listOf("####.", "#...#", "#...#", "####.", "#....", "#....", "#...."),
        'V' to listOf("#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."),
        'F' to listOf("#####", "#....", "#....", "####.", "#....", "#....", "#...."),
        // O resto do alfabeto: nomes de IA e textos em inglês nunca saem em branco.
        'G' to listOf(".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"),
        'J' to listOf("..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."),
        'M' to listOf("#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"),
        'Q' to listOf(".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"),
        'W' to listOf("#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."),
        'Y' to listOf("#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."),
        'Z' to listOf("#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"),
        '.' to listOf("..", "..", "..", "..", "..", "##", "##"),
        '/' to listOf(".....", "....#", "...#.", "..#..", ".#...", "#....", "....."),
    )

    fun glyph(c: Char) = g[c.uppercaseChar()] ?: g[' ']!!
    fun width(text: String, scale: Int = 1) = (text.sumOf { glyph(it)[0].length } + maxOf(0, text.length - 1)) * scale
}

/** Grade de pontos: 0 apagado, 1 fundo colorido, 2 texto, 3 texto apagado. */
class DotBitmap(val cols: Int, val rows: Int) {
    val cells = ByteArray(cols * rows)
    operator fun set(x: Int, y: Int, v: Int) { if (x in 0 until cols && y in 0 until rows) cells[y * cols + x] = v.toByte() }
    operator fun get(x: Int, y: Int): Int = cells[y * cols + x].toInt()

    fun draw(text: String, x: Int, y: Int, scale: Int = 1, value: Int = 2) {
        var cx = x
        for (ch in text) {
            val gl = DotFont.glyph(ch)
            gl.forEachIndexed { row, line ->
                line.forEachIndexed { col, px ->
                    if (px == '#') for (sy in 0 until scale) for (sx in 0 until scale) set(cx + col * scale + sx, y + row * scale + sy, value)
                }
            }
            cx += (gl[0].length + 1) * scale
        }
    }

    fun fill(fraction: Double) {
        val n = (fraction.coerceIn(0.0, 1.0) * cols).toInt()
        for (x in 0 until n) for (y in 0 until rows) set(x, y, 1)
    }
}

/** Cores padrão (as mesmas do Mac). */
object Palette {
    const val CLAUDE = 0xFF9E5CFF.toInt()
    const val CODEX = 0xFF33D9F2.toInt()
    const val RED = 0xFFFF3838.toInt()
    private val extra = intArrayOf(0xFFFF9E33.toInt(), 0xFF59D973.toInt(), 0xFFFFD940.toInt(), 0xFF6699FF.toInt(), 0xFFFF73A6.toInt())
    fun base(id: String) = when (id) {
        "claude" -> CLAUDE; "codex" -> CODEX
        else -> Providers.color(id) ?: extra[Math.floorMod(id.hashCode(), extra.size)]
    }
    /** Vermelho a partir de 85%. */
    fun fill(id: String, pct: Double) = if (pct >= 85) RED else base(id)
}

/** Desenha painéis de LED num Canvas do Android (app, widget e relógio). */
object Led {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    fun render(c: Canvas, b: DotBitmap, left: Float, top: Float, dot: Float, color: Int, textColor: Int = 0xFFFFFFFF.toInt()) {
        val gap = dot * 0.16f; val size = dot - gap
        for (y in 0 until b.rows) for (x in 0 until b.cols) {
            paint.color = when (b[x, y]) {
                2 -> textColor
                3 -> withAlpha(textColor, 0.72f)
                1 -> withAlpha(color, 0.62f)
                else -> withAlpha(color, 0.10f)
            }
            val l = left + x * dot; val t = top + y * dot
            c.drawOval(RectF(l, t, l + size, t + size), paint)
        }
    }

    fun withAlpha(color: Int, a: Float) = (color and 0x00FFFFFF) or ((a * 255).toInt().coerceIn(0, 255) shl 24)

    /** Grade fixa: margem 2 · título 7 · vão 3 · número 7k · margem 2. */
    fun rowsFor(k: Int) = 2 + 7 + 3 + 7 * k + 2

    /** Mínimo de colunas: evita pontos gigantes quando o painel é grande e o texto é curto. */
    var minCols = 40

    fun colsNeeded(k: Int, title: String) =
        maxOf(minCols, DotFont.width("100%", k) + 4, 2 + DotFont.width(title) + 6 + DotFont.width("0:00") + 2)

    fun dotFor(w: Float, h: Float, k: Int, title: String) =
        maxOf(1f, minOf(h / rowsFor(k), w / colsNeeded(k, title)))

    fun bestScale(w: Float, h: Float, title: String, maxScale: Int = 6): Int {
        for (k in maxScale downTo 2) if (dotFor(w, h, k, title) >= 2.5f && 12 + 7 * k + 2 <= h / dotFor(w, h, k, title)) return k
        return 1
    }

    /** Um painel: título e tempo em cima, % grande no centro, fundo cheio até o gasto. */
    fun panel(c: Canvas, l: Float, t: Float, w: Float, h: Float, window: UsageWindow?, title: String,
              providerId: String, nowSec: Double, k: Int = bestScale(w, h, title), longest: String = title) {
        val pct = window?.used(nowSec) ?: 0.0
        val dot = dotFor(w, h, k, longest)
        val cols = maxOf(10, (w / dot).toInt()); val rows = maxOf(rowsFor(k), (h / dot).toInt())
        val b = DotBitmap(cols, rows)
        b.fill(pct / 100)
        val time = timeLeft(window, nowSec)
        val name = if (2 + DotFont.width(title) + 6 + DotFont.width(time) + 2 <= cols) title
                   else title.replace("CLAUDE", "CL").replace("CODEX", "CX")
        b.draw(name, 2, 2)
        if (window != null && 2 + DotFont.width(name) + 6 + DotFont.width(time) + 2 <= cols)
            b.draw(time, cols - 2 - DotFont.width(time), 2, value = 3)
        val big = if (window == null) "--" else "${minOf(pct.toInt(), 999)}%"
        val y = 12 + maxOf(0, (rows - 2 - 12 - 7 * k) / 2)
        b.draw(big, (cols - DotFont.width(big, k)) / 2, y, k)
        render(c, b, l, t, dot, Palette.fill(providerId, pct))
    }

    /** Vários painéis numa grade, todos com a mesma escala (nada sobrepõe). */
    data class Item(val providerId: String, val window: UsageWindow?, val title: String)

    fun items(s: UsageSnapshot, agent: String, window: String, visible: List<String> = Providers.all): List<Item> {
        val ids = if (agent == "all") visible else listOf(agent)
        return ids.flatMap { id ->
            val p = s.provider(id)
            val ws: List<UsageWindow?> = if (window == "both") (p?.windows?.ifEmpty { null } ?: listOf(null)) else listOf(p.pick(window))
            ws.map { w ->
                val title = when {
                    ids.size == 1 -> w?.label?.uppercase() ?: Providers.short(id)
                    window == "both" -> Providers.abbr(id) + " " + (w?.label?.uppercase() ?: "")
                    else -> Providers.short(id)
                }
                Item(id, w, title)
            }
        }
    }

    fun grid(c: Canvas, l: Float, t: Float, w: Float, h: Float, items: List<Item>, columns: Int, gap: Float, nowSec: Double) {
        if (items.isEmpty()) return
        val rowsN = (items.size + columns - 1) / columns
        val pw = (w - gap * (columns - 1)) / columns
        val ph = (h - gap * (rowsN - 1)) / rowsN
        val longest = items.maxBy { DotFont.width(it.title) }.title
        val k = bestScale(pw, ph, longest)
        items.forEachIndexed { i, it ->
            val r = i / columns; val col = i % columns
            panel(c, l + col * (pw + gap), t + r * (ph + gap), pw, ph, it.window, it.title, it.providerId, nowSec, k, longest)
        }
    }

    /** Desenha a grade num Bitmap (widgets e complicações). */
    fun bitmap(wPx: Int, hPx: Int, items: List<Item>, columns: Int, nowSec: Double = now()): Bitmap {
        val bmp = Bitmap.createBitmap(maxOf(wPx, 10), maxOf(hPx, 10), Bitmap.Config.ARGB_8888)
        grid(Canvas(bmp), 0f, 0f, bmp.width.toFloat(), bmp.height.toFloat(), items, columns, 8f, nowSec)
        return bmp
    }
}
