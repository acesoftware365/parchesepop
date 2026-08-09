import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningPropertiesFile.isFile) {
        releaseSigningPropertiesFile.inputStream().use(::load)
    }
}

val requiredReleaseSigningKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val missingReleaseSigningKeys = requiredReleaseSigningKeys.filter {
    releaseSigningProperties.getProperty(it).isNullOrBlank()
}
val releaseKeystoreFile = releaseSigningProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let(rootProject::file)
val hasProductionReleaseSigning =
    releaseSigningPropertiesFile.isFile &&
        missingReleaseSigningKeys.isEmpty() &&
        releaseKeystoreFile?.isFile == true

val requestedTaskNames = gradle.startParameter.taskNames.map(String::lowercase)
val releaseApkWasRequestedExplicitly = requestedTaskNames.any {
    it.contains("assemble") && it.contains("release")
}
val releaseBundleWasRequestedExplicitly = requestedTaskNames.any {
    it.contains("bundle") && it.contains("release")
}
val allowDebugSignedReleaseApk =
    providers.gradleProperty("allowDebugSignedReleaseApk").orNull
        ?.equals("true", ignoreCase = true) == true ||
        providers.environmentVariable("PARCHES_POP_ALLOW_DEBUG_RELEASE_APK").orNull
            ?.equals("true", ignoreCase = true) == true
val useDebugSigningForLocalReleaseApk =
    !hasProductionReleaseSigning &&
        allowDebugSignedReleaseApk &&
        releaseApkWasRequestedExplicitly &&
        !releaseBundleWasRequestedExplicitly

android {
    namespace = "com.liisgo.parchesepop"
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
        applicationId = "com.liisgo.parchesepop"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasProductionReleaseSigning) {
            create("productionRelease") {
                storeFile = releaseKeystoreFile
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasProductionReleaseSigning -> signingConfigs.getByName("productionRelease")
                useDebugSigningForLocalReleaseApk -> signingConfigs.getByName("debug")
                else -> null
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val appReleaseTasks = allTasks.filter {
        it.path.startsWith(":app:") && it.name.contains("release", ignoreCase = true)
    }
    if (appReleaseTasks.isEmpty() || hasProductionReleaseSigning) {
        return@whenReady
    }

    val releaseBundleIsInTaskGraph = appReleaseTasks.any {
        it.name.contains("bundle", ignoreCase = true)
    }
    val localDebugApkIsAllowed =
        useDebugSigningForLocalReleaseApk && !releaseBundleIsInTaskGraph
    if (localDebugApkIsAllowed) {
        logger.warn(
            "Building a local-only release APK with the Android debug key. " +
                "Do not distribute or upload this APK.",
        )
        return@whenReady
    }

    val configurationProblem = when {
        !releaseSigningPropertiesFile.isFile ->
            "android/key.properties does not exist."
        missingReleaseSigningKeys.isNotEmpty() ->
            "android/key.properties is missing: ${missingReleaseSigningKeys.joinToString()}."
        releaseKeystoreFile?.isFile != true ->
            "The storeFile configured in android/key.properties does not exist."
        else -> "The production signing configuration is incomplete."
    }
    throw GradleException(
        """
        Parchís Pop production signing is required for this release build.
        $configurationProblem

        Copy android/key.properties.example to android/key.properties and enter the
        Play upload-key values. App bundles never fall back to debug signing.

        For a local test APK only, opt in explicitly with:
        PARCHES_POP_ALLOW_DEBUG_RELEASE_APK=true flutter build apk --release
        """.trimIndent(),
    )
}

flutter {
    source = "../.."
}
