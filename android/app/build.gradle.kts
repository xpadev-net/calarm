import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val androidSigningPropertiesPath = System.getenv("CALARM_ANDROID_SIGNING_PROPERTIES")
val androidSigningProperties = androidSigningPropertiesPath?.let { path ->
    Properties().apply {
        load(file(path).inputStream())
    }
}

fun requiredSigningProperty(name: String): String = androidSigningProperties
    ?.getProperty(name)
    ?.takeIf { value -> value.isNotBlank() }
    ?: error("Missing Android release signing property: $name")

android {
    namespace = "dev.xpa.calarm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.xpa.calarm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val ciReleaseSigningConfig = androidSigningPropertiesPath?.let {
        signingConfigs.create("ciRelease").apply {
            storeFile = file(requiredSigningProperty("storeFile"))
            storePassword = requiredSigningProperty("storePassword")
            keyAlias = requiredSigningProperty("keyAlias")
            keyPassword = requiredSigningProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = ciReleaseSigningConfig ?: signingConfigs.getByName("debug")
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

gradle.taskGraph.whenReady {
    if (androidSigningPropertiesPath == null && allTasks.any { task ->
            task.project == project && task.name.contains("Release")
        }) {
        error("CALARM_ANDROID_SIGNING_PROPERTIES must be set for release builds")
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16")
}

tasks.matching { it.name == "packageDebugUnitTestForUnitTest" }.configureEach {
    dependsOn("copyFlutterAssetsDebug")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
