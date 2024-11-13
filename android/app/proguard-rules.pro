# 忽略 Play Core 相关警告
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

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

# 保持 MainActivity
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
