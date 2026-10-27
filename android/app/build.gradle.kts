plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val privateKeystore = System.getenv("ANDROID_KEYSTORE_PATH")
val privateSigning = !privateKeystore.isNullOrBlank() &&
    !System.getenv("ANDROID_STORE_PASSWORD").isNullOrBlank() &&
    !System.getenv("ANDROID_KEY_PASSWORD").isNullOrBlank() &&
    !System.getenv("ANDROID_KEY_ALIAS").isNullOrBlank()


android {
    namespace = "studio.reaz.ai_voice_studio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = if (System.getenv("VOICE_STUDIO_SIDE_BY_SIDE") == "1") "studio.reaz.ai_voice_studio.offline" else "studio.reaz.ai_voice_studio"
        manifestPlaceholders["studioAppLabel"] = if (System.getenv("VOICE_STUDIO_SIDE_BY_SIDE") == "1") "কণ্ঠশিল্প অফলাইন" else "কণ্ঠশিল্প"
        minSdk = 26
        ndk { abiFilters += "arm64-v8a" }
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs.excludes += listOf("**/armeabi-v7a/**", "**/x86_64/**", "**/x86/**")
    }
    signingConfigs {
        if (privateSigning) {
            create("privateRelease") {
                storeFile = file(privateKeystore!!)
                storePassword = System.getenv("ANDROID_STORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            // Personal test APK. Configure a private release keystore before public distribution.
            signingConfig = signingConfigs.getByName(if (privateSigning) "privateRelease" else "debug")
        }
    }
}

flutter {
    source = "../.."
}
