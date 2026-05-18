import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.rescate_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget = JvmTarget.JVM_17
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.rescate_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // R8 minification needs explicit -dontwarn rules for JDK AWT /
            // ImageIO classes pulled transitively by GraphHopper (via Apache
            // XmlGraphics Commons). Those code paths are never executed on
            // Android.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Fix: camera_android_camerax 0.6.30 references camera-core 1.5.3 which uses
    // CallbackToFutureAdapter from concurrent-futures, but doesn't declare it as a
    // dependency. Adding it explicitly ensures the class is on the compile classpath.
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    implementation("com.graphhopper:graphhopper-core:1.0")
    implementation("com.graphhopper:graphhopper-reader-osm:1.0")
    implementation("org.slf4j:slf4j-simple:1.7.36")
    // Android does not ship javax.xml.stream (StAX). GraphHopper's OSM XML reader needs it.
    implementation("javax.xml.stream:stax-api:1.0-2")
    implementation("com.fasterxml:aalto-xml:1.3.2")
}
