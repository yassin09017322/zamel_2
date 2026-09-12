plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    // ضفنا رقم الإصدار هنا مباشرة عشان نلزم السيرفر يحمله بدون أعذار! 👇
    id("com.google.gms.google-services") version "4.4.1"
}

android {
    namespace = "com.example.zamel_2"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.example.zamel_2"
        minSdk = 21 // تم التعديل هنا إلى 21
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
