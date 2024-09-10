package itvapp_live_tv

import android.content.Context
import android.app.UiModeManager
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "net.itvapp.isTV" // 修改后的 Channel 名称

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 设置 Platform Channel
        MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isTV") {
                val isTV = isTV() // 调用 isTV 方法判断设备是否为电视
                result.success(isTV)
            } else {
                result.notImplemented()
            }
        }
    }

    // 使用 UiModeManager 判断是否为电视
    private fun isTV(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        return uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }
}
