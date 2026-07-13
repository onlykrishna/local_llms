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
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val configureProject = {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val compileOptions = android.javaClass.getMethod("getCompileOptions").invoke(android)
                compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java)
                    .invoke(compileOptions, JavaVersion.VERSION_17)
                compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java)
                    .invoke(compileOptions, JavaVersion.VERSION_17)
            } catch (e: Exception) {}
        }

        val kotlinOptions = extensions.findByName("kotlinOptions")
            ?: (android as? ExtensionAware)?.extensions?.findByName("kotlinOptions")
        if (kotlinOptions != null) {
            try {
                kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java)
                    .invoke(kotlinOptions, "17")
            } catch (e: Exception) {}
        }

        tasks.configureEach {
            if (name.contains("Kotlin")) {
                try {
                    val kOpts = property("kotlinOptions")
                    if (kOpts != null) {
                        kOpts.javaClass.getMethod("setJvmTarget", String::class.java)
                            .invoke(kOpts, "17")
                    }
                } catch (e: Exception) {}
            }
            if (this is JavaCompile) {
                sourceCompatibility = "17"
                targetCompatibility = "17"
            }
        }
    }

    if (state.executed) {
        configureProject()
    } else {
        afterEvaluate {
            configureProject()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
