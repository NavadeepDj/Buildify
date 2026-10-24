plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Read only the device connector credential, never account API credentials.
// This also configures ordinary `flutter run` builds without extra CLI flags.
val connectorEnv = rootProject.file("../.env")
val connectorToken = if (connectorEnv.isFile) {
    connectorEnv.readLines().firstOrNull {
        it.trimStart().startsWith("CF_TUNNEL_TOKEN=")
    }?.substringAfter('=')?.trim()?.removeSurrounding("\"")?.removeSurrounding("'") ?: ""
} else ""
require(connectorToken.isEmpty() || Regex("[A-Za-z0-9_+/=\\-]{40,}").matches(connectorToken)) {
    "Invalid CF_TUNNEL_TOKEN in the local .env"
}

android {
    namespace = "com.example.buildify_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"
    buildFeatures { buildConfig = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        buildConfigField("String", "CF_TUNNEL_TOKEN", "\"$connectorToken\"")
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.buildify_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Force AGP to extract jniLibs into nativeLibraryDir on install.
    // We use jniLibs to ship llama-server (renamed to libllama-server.so) and
    // its companion .so files so Android allows executing the binary.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

configurations.all {
    resolutionStrategy {
        force("androidx.browser:browser:1.8.0")
        force("androidx.core:core:1.19.1")
        force("androidx.core:core-ktx:1.19.1")
    }
}
