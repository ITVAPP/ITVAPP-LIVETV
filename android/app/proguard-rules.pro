# VLC Player specific rules
-keep class org.videolan.libvlc.** { *; }

# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }

# 保持你的 MainActivity
-keep class itvapp_live_tv.MainActivity { *; }

# 保持 MethodChannel 相关代码
-keep class io.flutter.plugin.common.MethodChannel { *; }
-keep class io.flutter.plugin.common.MethodChannel$* { *; }

# 保持 native 方法
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保持 Android 系统相关类
-keep class android.app.UiModeManager { *; }
-keep class android.content.pm.PackageManager { *; }

# 日志相关（如果需要在发布版本中保留日志）
# -keep class android.util.Log { *; }

# 添加以下规则来解决 R8 缺失类的错误
# Google Play Split 相关类的警告处理
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Flutter 应用分包相关类的保持
-keep class io.flutter.app.FlutterPlayStoreSplitApplication { *; }
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
