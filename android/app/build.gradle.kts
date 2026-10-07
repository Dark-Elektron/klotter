import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
// The upload key is optional for building: a fresh clone, or CI for a pull
// request, has no key.properties and signs release builds with the debug key.
val hasUploadKey = keystorePropertiesFile.exists()
if (hasUploadKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.darkelektron.klotter"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.darkelektron.klotter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only made when there is a key to make it from. Reading the absent
        // values with `as String` threw while Gradle configured the project,
        // which failed every build without key.properties, debug ones too.
        if (hasUploadKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // The upload key when it is configured. Otherwise the debug key, so
            // `flutter run --release` works on any checkout; such an APK cannot
            // update an install signed with the upload key, which is why CI
            // never publishes one.
            signingConfig =
                if (hasUploadKey) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }

        // getByName("release") {
        //     // Use "=" for assignments in Kotlin
        //     signingConfig = signingConfigs.getByName("debug") // Use "debug" if you haven't set up a release key yet
        //     isMinifyEnabled = true
        //     isShrinkResources = true
        //     
        //     // Function call syntax with parentheses
        //     proguardFiles(
        //         getDefaultProguardFile("proguard-android-optimize.txt"),
        //         "proguard-rules.pro"
        //     )
        // }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ...
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("com.google.android.material:material:1.14.0-alpha08")
    // ...
}

