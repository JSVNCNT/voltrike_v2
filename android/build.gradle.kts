import org.gradle.api.file.Directory
import org.gradle.api.tasks.Delete
import com.android.build.api.dsl.LibraryExtension

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
    val newSubprojectBuildDir: Directory =
        newBuildDir.dir(project.name)

    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// livekit_noise_filter 0.2.1 still pins its Android library module to API 34,
// although VolTrike already compiles the application at API 37. Keep the
// filter module aligned with the app so current AndroidX metadata can build;
// this does not change minSdk or targetSdk.
subprojects {
    if (name == "livekit_noise_filter") {
        afterEvaluate {
            extensions.configure<LibraryExtension> {
                compileSdk = 37
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
