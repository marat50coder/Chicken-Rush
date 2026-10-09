import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after Android + Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Apply Google Services only when google-services.json is present. This
// lets the project build before Firebase credentials are provisioned —
// while the file is absent the gray-flow gate stays dormant.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

android {
    namespace = "com.crimsonpixel.arcade"

    // compileSdk stays high so the current Firebase + AppsFlyer +
    // flutter_local_notifications stack resolves cleanly. targetSdk
    // picks the latest stable Android version Play currently requires.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications ≥18 pulls in java.time.* which
        // only lands on API 26+ without desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.crimsonpixel.arcade"
        // API 26 (Android 8.0) is the floor imposed by the current
        // Firebase + AppsFlyer stack. Do NOT raise without reason —
        // every extra API level slices eligible installs.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Only the 4 ABIs rust_guard is cross-compiled for; keeps APK slim
        // and guarantees we never ship an ABI without a matching .so.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
        }
    }

    packaging {
        jniLibs {
            // Required by System.loadLibrary when extractNativeLibs=false.
            useLegacyPackaging = false
        }
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
