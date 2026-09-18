plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")

    // Flutter debe aplicarse después de Android y Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.sonara"

    compileSdk = flutter.compileSdkVersion

    // Requerido para las librerías nativas utilizadas por extractor.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
    jniLibs {
        keepDebugSymbols += setOf(
            "**/libaria2c.zip.so",
            "**/libffmpeg.zip.so",
            "**/libpython.zip.so"
            )
        }
    }

    defaultConfig {
        applicationId = "com.example.sonara"

        // extractor requiere Android API 24 o superior.
        minSdk = 24

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget =
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}