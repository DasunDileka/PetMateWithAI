plugins {
    id("com.android.application")
    // Reads android/app/google-services.json and injects the Firebase project
    // configuration at build time, so no Firebase keys live in Dart source.
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Must match the package_name in google-services.json.
    namespace = "dasun.petmate.com"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time APIs that are not present
        // on older Android runtimes; desugaring back-ports them.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "dasun.petmate.com"
        // Cloud Firestore requires API 23 or above; 24 is Flutter's own floor.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Debug signing keeps `flutter run --release` working for the
            // demonstration build. A production release would use its own
            // keystore supplied through android/key.properties (gitignored).
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Keeps the emulator build fast; the demo does not need every ABI.
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
