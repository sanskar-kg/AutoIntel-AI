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

    // Some Flutter plugins still declare generated resValues without opting in.
    // AGP 9 disables that feature by default, so enable it for Android libraries.
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension> {
            buildFeatures.resValues = true
        }

        // payu_checkoutpro_flutter 1.4.5 still declares compileSdk 31 even
        // though its current AndroidX dependencies require API 34 or newer.
        if (project.name == "payu_checkoutpro_flutter") {
            extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension> {
                finalizeDsl { libraryExtension ->
                    libraryExtension.compileSdk = 36
                }
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
