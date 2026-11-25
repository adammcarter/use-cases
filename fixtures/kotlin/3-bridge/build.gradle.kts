plugins {
    kotlin("jvm") version "2.4.20"
}

group = "com.example"
version = "0.9.0"

repositories {
    mavenCentral()
}

dependencies {
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
    // `use-cases validate` passes the run's report folder; without it, Gradle writes where it always does
    providers.gradleProperty("junitDir").orNull?.let { reports.junitXml.outputLocation.set(file(it)) }
}
