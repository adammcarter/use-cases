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
}
