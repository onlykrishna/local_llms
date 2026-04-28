# llamadart (llama.cpp JNI layer)
-keep class com.llamadart.** { *; }
-keep class dev.leehack.** { *; }
-keepclassmembers class * { native <methods>; }
-dontwarn dev.leehack.**

# Flutter plugins
-keep class io.flutter.plugins.** { *; }

# Android core (needed by llamadart JNI)
-keep class android.view.** { *; }
-keep class android.widget.** { *; }
-keep class android.content.** { *; }
-keep class android.app.** { *; }

# Connectivity Plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Dio / OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class com.squareup.okhttp3.** { *; }
