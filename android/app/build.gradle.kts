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
        jvmTarget = "17"
        // Explicitly allow Media3's UnstableApi to prevent strict Kotlin compiler failures
        freeCompilerArgs = freeCompilerArgs + "-opt-in=androidx.media3.common.util.UnstableApi"
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
    // Jetpack Media3 for Native Hardware-Accelerated Video Editing
    implementation("androidx.media3:media3-transformer:1.3.0")
    implementation("androidx.media3:media3-effect:1.3.0")
    implementation("androidx.media3:media3-common:1.3.0")
    
    // Required by Media3 for ImmutableList and other collections used in MainActivity.kt
    implementation("com.google.guava:guava:32.1.3-android")
}

flutter {
    source = "../.."
}