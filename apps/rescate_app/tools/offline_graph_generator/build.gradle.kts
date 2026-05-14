plugins {
    application
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    implementation("com.graphhopper:graphhopper-core:1.0")
    implementation("com.graphhopper:graphhopper-reader-osm:1.0")
}

application {
    mainClass.set("com.rescate.tools.GenerateGraph")
}
