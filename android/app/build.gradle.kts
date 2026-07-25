plugins {
    id("com.android.application")
    id("kotlin-android")

    // Flutter
    id("dev.flutter.flutter-gradle-plugin")

    // Firebase
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.voltrike_v2"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // Required by google_navigation_flutter
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.voltrike_v2"

        // Required by Navigation SDK
        minSdk = 24

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Required by google_navigation_flutter
    coreLibraryDesugaring("com.android.tools:desugar_jdk_nio:2.1.5")
}

flutter {
    source = "../.."
}