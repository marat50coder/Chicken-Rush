# Chicken Rush — ProGuard / R8 rules for release builds.

# Flutter engine + plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugins.webviewflutter.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core (deferred components / split installs). Pulled in transitively
# via flutter — we don't actually use split installs but R8 complains if
# we don't silence the warnings.
-dontwarn com.google.android.play.core.**

# Firebase — reflective access from the SDK.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# AppsFlyer SDK — reflection + native callbacks.
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# JNI native methods must survive shrinking so rust_guard FFI resolves.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Parcelables need their CREATOR field intact.
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Strip Android logging in release — belt-and-braces alongside Dart's
# assert()-wrapped debug prints.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# flutter_secure_storage uses tink via reflection.
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
