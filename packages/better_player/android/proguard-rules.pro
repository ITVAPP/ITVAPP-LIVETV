# Cronet
-keep class org.chromium.net.** { *; }
-keep class com.google.net.cronet.** { *; }

# EXO
-dontwarn org.kxml2.io.**
-dontwarn org.xmlpull.v1.**
-dontwarn android.content.res.**
-dontwarn org.slf4j.impl.StaticLoggerBinder
-keep class org.xmlpull.** { *; }
-keepclassmembers class org.xmlpull.** { *; }
