import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")   // thêm dòng này
}

android {
    namespace = "com.example.application"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Enable core library desugaring for libraries that require newer Java APIs
        // (required by some plugins like flutter_local_notifications).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.application"
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
}

dependencies {
    // Required for core library desugaring support (bumped for plugin requirements)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

afterEvaluate {
    val flutterProjectRoot = rootDir.parentFile
    if (flutterProjectRoot != null) {
        val flutterOutputDir = File(flutterProjectRoot, "build/app/outputs/flutter-apk")
        flutterOutputDir.mkdirs()

        mapOf(
            "Debug" to "debug",
            "Profile" to "profile",
            "Release" to "release",
        ).forEach { (taskSuffix, folder) ->
            tasks.matching { it.name == "package$taskSuffix" }.configureEach {
                doLast {
                    val apk = file("$buildDir/outputs/apk/$folder/app-${folder}.apk")
                    if (apk.exists()) {
                        copy {
                            from(apk)
                            into(flutterOutputDir)
                        }
                    }
                }
            }
        }
    }
}
