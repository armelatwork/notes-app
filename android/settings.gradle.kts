pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

// AGP 8.x requires a namespace in every Android library module.
// Older packages (e.g. isar_flutter_libs 3.1.0+1) omit it; patch them here
// via beforeProject so the afterEvaluate callback is registered in time.
gradle.beforeProject {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            try {
                val getNamespace = ext.javaClass.getMethod("getNamespace")
                if (getNamespace.invoke(ext) == null) {
                    ext.javaClass.getMethod("setNamespace", String::class.java)
                        .invoke(ext, group.toString())
                }
            } catch (_: Exception) {}
        }
    }
}
