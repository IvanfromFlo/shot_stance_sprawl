plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yourname.shot_stance_sprawl"
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
        applicationId = "com.yourname.shot_stance_sprawl"
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
    // Jetpack Media3 for Native Hardware-Accelerated Video Editing (Replaces FFmpeg)
    implementation("androidx.media3:media3-transformer:1.3.0")
    implementation("androidx.media3:media3-effect:1.3.0")
    implementation("androidx.media3:media3-common:1.3.0")
}

flutter {
    source = "../.."
}