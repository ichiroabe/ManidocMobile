import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// リリース署名の設定は android/key.properties（gitignore 済み）か環境変数から読む。
// CI は Secret を環境変数で渡す。どちらも無い環境（手元の動作確認など）は
// 従来どおり debug キーにフォールバックする。
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingSetting(key: String, env: String): String? =
    keystoreProperties.getProperty(key) ?: System.getenv(env)

val releaseStorePath = signingSetting("storeFile", "ANDROID_KEYSTORE_PATH")
val hasReleaseSigning =
    releaseStorePath != null && file(releaseStorePath).exists()

android {
    namespace = "jp.fusion.upper.manidoc_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "jp.fusion.upper.manidoc_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStorePath!!)
                storePassword =
                    signingSetting("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingSetting("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword =
                    signingSetting("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // 署名情報が揃っていない環境では debug キーで署名する。
            // 配布物は必ず release 署名でビルドすること（鍵が変わると上書き更新できない）。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
