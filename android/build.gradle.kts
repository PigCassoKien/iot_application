import org.gradle.api.tasks.Delete

// android/build.gradle (hoặc build.gradle.kts nếu bạn dùng Kotlin DSL)
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.4")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Align Android/Gradle build outputs with Flutter's expected locations.
rootProject.buildDir = file("../build")
subprojects {
    layout.buildDirectory.set(file("../build/${project.name}"))
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}

// Plugins are managed by Flutter tooling and the Gradle plugin classpath.
// Avoid declaring platform plugin versions here to prevent classpath/version conflicts.

// Note: removed malformed/leftover lines that caused script compilation errors.