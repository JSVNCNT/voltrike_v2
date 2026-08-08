import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")

    // Flutter
    id("dev.flutter.flutter-gradle-plugin")

    // Firebase
    id("com.google.gms.google-services")
}

val localProperties = Properties().apply {
    val propertiesFile = rootProject.file("local.properties")
    if (propertiesFile.exists()) {
        propertiesFile.inputStream().use(::load)
    }
}

val mapsApiKey =
    providers.gradleProperty("MAPS_API_KEY").orNull
        ?: localProperties.getProperty("MAPS_API_KEY")
        ?: System.getenv("MAPS_API_KEY")
        ?: ""

android {
    namespace = "com.example.voltrike_v2"

    // permission_handler_android is compiled against API 37. Keeping the
    // compile SDK at that level is backward-compatible with the Android 16
    // phone and Android 17 emulator used for capstone testing.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // Required by Google Navigation on Android API levels below 34.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.voltrike_v2"

        minSdk = 24

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        debug {
            // D8's artifact transform drops four Navigation 7.6.1 parcelable
            // helpers in this large multi-dex app. Route Java bytecode through
            // R8 so the referenced helpers are kept in the final debug APK.
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")

    // Keep the native SDK aligned with google_navigation_flutter 0.9.4 and
    // below the 7.7 release that duplicates LiveKit/WebRTC's org.jni_zero.
    implementation("com.google.android.libraries.navigation:navigation:7.6.1")
}

flutter {
    source = "../.."
}
