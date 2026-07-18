import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

gradle.taskGraph.whenReady {
    val releasePackagingTaskPrefixes = listOf(
        "assemble",
        "bundle",
        "package",
        "sign",
        "validateSigning",
    )
    val schedulesReleasePackaging = allTasks.any { task ->
        task.project == project &&
            task.name.contains("release", ignoreCase = true) &&
            releasePackagingTaskPrefixes.any { prefix ->
                task.name.startsWith(prefix, ignoreCase = true)
            }
    }
    if (schedulesReleasePackaging && !hasReleaseSigning) {
        throw GradleException(
            "Release signing is not configured. Copy key.properties.example to " +
                "android/key.properties and provide an upload keystore."
        )
    }
}

android {
    namespace = "com.rainchen537.handsbnbu"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.ispace_timeline"
        minSdk = 23
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}

flutter {
    source = "../.."
}
