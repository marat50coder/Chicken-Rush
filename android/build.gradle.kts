allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Force every Android library subproject to compile against the same
    // compileSdk as our app module. A few plugins (e.g. file_picker
    // 8.1.4) still hard-code compileSdk = 34 and would otherwise fail
    // CheckAarMetadata because their transitive deps require 36+.
    //
    // Registered BEFORE evaluationDependsOn(":app") below — once the
    // subproject is evaluated Gradle refuses the afterEvaluate callback.
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
