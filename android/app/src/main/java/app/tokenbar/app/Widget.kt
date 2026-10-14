package app.tokenbar.app

import android.content.Context
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.ContentScale
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.graphics.Color
import app.tokenbar.core.Led
import app.tokenbar.core.Store

/** Widget da tela inicial: o mesmo painel de LED. Pequeno = 2 painéis; largo = 5h e 7d de todas as IAs. */
class UsageWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { Content() }
    }

    @androidx.compose.runtime.Composable
    private fun Content() {
        val ctx = LocalContext.current
        val size: DpSize = LocalSize.current
        val store = Store(ctx)
        val density = ctx.resources.displayMetrics.density
        val wide = size.width > size.height * 1.5f
        val window = if (wide) "both" else store.window
        val items = Led.items(store.snapshot, "all", window, store.visible)
        val wPx = ((size.width.value - 16) * density).toInt()
        val hPx = ((size.height.value - 16) * density).toInt()
        val bmp = Led.bitmap(wPx, hPx, items, columns = if (wide && items.size > 2) 2 else 1)
        Box(
            GlanceModifier.fillMaxSize().background(ColorProvider(Color.Black)).cornerRadius(20.dp).padding(8.dp)
                .clickable(actionStartActivity(android.content.Intent(ctx, MainActivity::class.java)))
        ) {
            Image(ImageProvider(bmp), contentDescription = "Uso das IAs", modifier = GlanceModifier.fillMaxSize(),
                  contentScale = ContentScale.Fit)
        }
    }
}

class UsageWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = UsageWidget()
}
