package app.tokenbar.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.tokenbar.core.Fetch
import app.tokenbar.core.Providers
import app.tokenbar.core.Store
import app.tokenbar.core.UsageSnapshot
import app.tokenbar.core.json
import app.tokenbar.core.now
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await
import java.util.concurrent.TimeUnit

/** Busca, guarda e espalha: widget, relógio e avisos. Usado pelo app aberto e pela tarefa em segundo plano. */
object Sync {
    suspend fun refresh(context: Context): Result<UsageSnapshot> {
        val store = Store(context)
        val p = store.pairing ?: return Result.failure(Exception("Não pareado"))
        return runCatching { Fetch.best(context, p) }.onSuccess { s ->
            store.snapshot = s
            runCatching { UsageWidget().updateAll(context) }
            runCatching { sendToWatch(context, s, store) }
            Alerts.check(context, s, store)
        }
    }

    /** O relógio recebe a chave e os números prontos (funciona sem servidor). */
    suspend fun sendToWatch(context: Context, s: UsageSnapshot, store: Store) {
        val req = PutDataMapRequest.create("/tokenbar/state").apply {
            dataMap.putString("snapshot", json.encodeToString(UsageSnapshot.serializer(), s))
            dataMap.putString("pairing", store.pairing?.link ?: "")
            dataMap.putLong("sent", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(context).putDataItem(req).await()
    }

    /** A cada ~15 min (o Android decide), mesmo com o app fechado. */
    fun schedule(context: Context) {
        val req = PeriodicWorkRequestBuilder<RefreshWorker>(15, TimeUnit.MINUTES).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork("refresh", ExistingPeriodicWorkPolicy.KEEP, req)
    }
}

class RefreshWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result = if (Sync.refresh(applicationContext).isSuccess) Result.success() else Result.retry()
}

/** Avisa ao passar de 80% e 95% de uma janela — uma vez por ciclo de reset. */
object Alerts {
    private const val CHANNEL = "limits"

    fun check(context: Context, s: UsageSnapshot, store: Store) {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Limites de IA", NotificationManager.IMPORTANCE_DEFAULT))
        val t = now()
        for (p in s.providers) for (w in p.windows) for (limit in listOf(80, 95)) {
            val used = w.used(t)
            val key = "${p.id}.${w.id}.$limit"
            val cycle = w.resetsAt ?: 0.0
            if (used < limit || store.alerted(key) == cycle) continue
            store.markAlerted(key, cycle)
            val name = "${Providers.short(p.id).lowercase().replaceFirstChar { it.uppercase() }} ${w.label.uppercase()}"
            val n = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("$name: ${used.toInt()}%")
                .setContentText(if (limit >= 95) "Quase no limite." else "Passou de $limit% do limite.")
                .setAutoCancel(true)
                .build()
            runCatching { nm.notify(key.hashCode(), n) }
        }
    }
}
