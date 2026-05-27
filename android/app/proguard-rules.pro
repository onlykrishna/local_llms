# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# GetX
-keep class com.jonkheer.** { *; }

# OkHttp (used by Firebase)
-dontwarn okhttp3.**
-dontwarn okio.**

# Syncfusion PDF
-keep class com.syncfusion.** { *; }

# Keep model classes
-keep class com.aeologic.adhoc.aiapp.** { *; }

# Dart / Flutter obfuscation rules
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

# Google Play Core (deferred components references in Flutter core)
-dontwarn com.google.android.play.core.**

