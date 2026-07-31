# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Firebase
-keep class io.flutter.plugins.firebase.messaging.** { *; }
-keep class io.flutter.plugins.firebase.core.** { *; }
-dontwarn io.flutter.plugins.firebase.messaging.**
-dontwarn io.flutter.plugins.firebase.core.**
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class java.time.** { *; }

# Preserve custom Android classes if any
-keep class com.woopress.shop.** { *; }

# Fix R8 missing class warnings
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**
