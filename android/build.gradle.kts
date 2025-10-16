// android/build.gradle.kts  (root of the Android project)

plugins {
    // Match the AGP version that is already on the classpath (8.7.0)
    id("com.android.application") apply false
    id("com.android.library") apply false

    // Kotlin version aligned with recent Flutter templates
    id("org.jetbrains.kotlin.android") apply false

    // Google Services plugin for Firebase
    // id("com.google.gms.google-services") version "4.4.2" apply false

    // Flutter loader plugin (usually added by Flutter template; harmless if present)
    // id("dev.flutter.flutter-plugin-loader") version "1.0.0" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// your existing custom buildDir redirection
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
