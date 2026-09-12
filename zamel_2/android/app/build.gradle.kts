plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") version "4.4.1"
}

android {
    namespace = "com.example.zamel_2"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // ❌ تم حذف isCoreLibraryDesugaringEnabled نهائياً
    }

    defaultConfig {
        applicationId = "com.example.zamel_2"
        minSdk = 26 // 🔥 الحل الجذري: رفعنا الحد الأدنى لتخطي طلبات المكتبة
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // ❌ تم حذف multiDexEnabled لأنه لم يعد مطلوباً في API 26
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
    // ❌ تم حذف سطر coreLibraryDesugaring نهائياً
}
