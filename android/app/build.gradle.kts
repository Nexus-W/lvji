plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tripnest.luji"
    // receive_sharing_intent 要求 compileSdk >= 37（Flutter 默认是 36）。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tripnest.luji"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // 腾讯地图 SDK 的 Key：从项目根目录 .env 读（.env 已 gitignore，不进仓库）
        manifestPlaceholders["TMAP_KEY"] = run {
            val env = rootProject.file("../.env")
            if (env.exists()) {
                env.readLines()
                    .firstOrNull { it.trim().startsWith("TMAP_KEY=") }
                    ?.substringAfter("=")?.trim() ?: ""
            } else ""
        }
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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
    // 独立实现的 EXIF 解析器：系统自带的 android.media.ExifInterface 对 HEIC
    // 的支持依赖厂商（鸿蒙/新版本 Android 会读不到 GPS 和时间），
    // AndroidX 版本自带 HEIF 解析，跨机型稳定。
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}
