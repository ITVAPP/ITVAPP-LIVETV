package itvapp_live_tv
import android.content.Context
import android.app.UiModeManager
import android.content.res.Configuration
import android.os.Build
import android.content.pm.PackageManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "net.itvapp.isTV"
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 设置 Platform Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isTV") {
                val isTV = isTVDevice() // 调用扩展后的 isTVDevice 方法判断设备是否为电视
                Log.d("MainActivity", "isTV: $isTV") // 输出调试信息
                result.success(isTV)
            } else {
                result.notImplemented()
            }
        }
    }

    // 扩展 isTV 方法，增加对电视盒子和设备指纹的检测
    private fun isTVDevice(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        // 判断是否为电视模式
        val isTelevision = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        Log.d("MainActivity", "isTelevision: $isTelevision") // 输出调试信息

        // 检查设备名称是否包含 "box"，用于识别电视盒子
        val isTVBox = Build.DEVICE.contains("box", ignoreCase = true) || Build.MODEL.contains("box", ignoreCase = true)
        Log.d("MainActivity", "isTVBox: $isTVBox") // 输出调试信息

        // 检查设备指纹是否包含 "tv" 或 "box"，用于进一步确认电视或电视盒子
        val isTVFingerprint = Build.FINGERPRINT.contains("tv", ignoreCase = true) || Build.FINGERPRINT.contains("box", ignoreCase = true)
        Log.d("MainActivity", "isTVFingerprint: $isTVFingerprint") // 输出调试信息

        // 检查是否有 Leanback 特性，专为电视设计的用户界面
        val pm = packageManager
        val hasLeanbackFeature = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        Log.d("MainActivity", "hasLeanbackFeature: $hasLeanbackFeature") // 输出调试信息

        // 返回是否为电视、电视盒子或具有 Leanback 特性的设备
        return isTelevision || isTVBox || isTVFingerprint || hasLeanbackFeature
    }
}
