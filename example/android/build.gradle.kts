allprojects {
    repositories {
        google()
        mavenCentral()
        // Until the Kirora Android SDK is on a public repository: point KIRORA_ANDROID_REPOS at its
        // build/staging-repo folders (path-separated; wins over a stale local publish) ...
        System.getenv("KIRORA_ANDROID_REPOS")?.split(File.pathSeparator)?.filter { it.isNotBlank() }?.forEach {
            maven { url = uri(it) }
        }
        // ... or publish it locally (`./gradlew publishToMavenLocal` in the Android SDK project).
        mavenLocal()
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
