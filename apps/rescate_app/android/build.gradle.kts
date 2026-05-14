allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Fix: camera_android_camerax (any version) is missing a transitive dependency on
// concurrent-futures. camera-core 1.5+ references CallbackToFutureAdapter from that
// library, but the plugin doesn't declare it. We inject it into every Android subproject
// so it is on the compile classpath when camera_android_camerax is compiled.
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            dependencies {
                try {
                    add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
                } catch (_: Exception) {
                    // Some subprojects may not support implementation configuration
                }
            }
        }
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
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
