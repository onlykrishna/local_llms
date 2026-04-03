# llamadart (llama.cpp JNI layer)
-keep class com.llamadart.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

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
