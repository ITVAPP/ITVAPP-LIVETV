package itvapp_live_tv

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.app.UiModeManager
import android.content.res.Configuration
import android.os.Build
import android.content.pm.PackageManager
import android.util.Log
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "net.itvapp.livetv"

    override fun onCreate(savedInstanceState: Bundle?) {
        window.setBackgroundDrawableResource(android.R.color.transparent)
        super.onCreate(savedInstanceState)
        // 注册通知渠道
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = CHANNEL // 使用包名作为渠道 ID
            // 动态获取桌面图标名称（android:label）
            val channelName = try {
                val appInfo = packageManager.getApplicationInfo(packageName, 0)
                packageManager.getApplicationLabel(appInfo).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                "itvapp live" // 回退名称，防止异常
            }
            val importance = NotificationManager.IMPORTANCE_DEFAULT
            val channel = NotificationChannel(channelId, channelName, importance)
            channel.description = "Notification for live TV playback"
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isTV") {
                val isTV = isTVDevice()
                result.success(isTV)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun isTVDevice(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        val isTelevision = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        val isTVBox = Build.DEVICE.contains("box", ignoreCase = true) || Build.MODEL.contains("box", ignoreCase = true)
        val isTVFingerprint = Build.FINGERPRINT.contains("tv", ignoreCase = true) || Build.FINGERPRINT.contains("box", ignoreCase = true)
        val pm = packageManager
        val hasLeanbackFeature = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        return isTelevision || isTVBox || isTVFingerprint || hasLeanbackFeature
    }
}
