import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key's location and passwords, created by
// scripts/create-release-key.sh. Kept out of git (see .gitignore).
val releaseKey = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "ke.co.urizon.salio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent: Android treats an APK with another ID as another app, so
        // this can never change once shops install Salio (docs/10, D2).
        applicationId = "ke.co.urizon.salio"
        // Written out rather than taken from Flutter, so a Flutter upgrade
        // cannot quietly drop phones or change the target (docs/10, D17).
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One flavour per server. Each has its own ID and name, so all three
    // install side by side and a test build never replaces a shop's app.
    // The server address for each is in lib/app/environment.dart.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
        }
        create("prod") {
            dimension = "env"
        }
    }

    signingConfigs {
        if (!releaseKey.isEmpty) {
            create("release") {
                storeFile = file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Phones install an update only when it is signed with the same
            // key as the installed app, so every release must use the one
            // release key. Without it the release build fails rather than
            // quietly signing with this machine's debug key.
            signingConfig = signingConfigs.findByName("release")
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

// Every APK of build N has version code N, whatever its processor type
// (docs/10, D19). With --split-per-abi Flutter's plugin rewrites it to
// ABI x 1000 + N; the updater compares plain build numbers, and DairyGo
// missed two releases when that offset was not taken off. The plugin sets
// it in a variant callback registered when the plugin is applied; this one
// is registered after it, so it runs next, for the same variant, and wins.
// (In afterEvaluate it would be too late: Gradle has locked the value.)
// The release script checks the result on every APK.
@Suppress("DEPRECATION")
android.applicationVariants.configureEach {
    val buildNumber = versionCode
    outputs.forEach { output ->
        (output as com.android.build.gradle.api.ApkVariantOutput).versionCodeOverride = buildNumber
    }
}

// Fail early with instructions instead of producing an unsigned release.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        it.project == project && it.name.contains("Release") &&
            (it.name.startsWith("assemble") || it.name.startsWith("bundle"))
    }
    if (buildsRelease && releaseKey.isEmpty) {
        throw GradleException(
            "No release key: android/key.properties is missing. " +
                "Run mobile-v2/scripts/create-release-key.sh once (see mobile-v2/README.md), " +
                "or copy key.properties and the keystore from your backup.",
        )
    }
}
