plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = "com.convay.hls_player"
version = "0.1.0"

val lifecycleVersion = "2.9.4"
val annotationVersion = "1.9.1"
val media3Version = "1.8.0"
val workVersion = "2.10.5"

android {
    namespace = "uz.shs.better_player_plus"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }
}

dependencies {
    implementation("androidx.media:media:1.7.1")

    implementation("androidx.media3:media3-ui:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
    implementation("androidx.media3:media3-datasource-cronet:$media3Version")
    implementation("androidx.media3:media3-exoplayer-smoothstreaming:$media3Version")

    implementation("androidx.lifecycle:lifecycle-runtime-ktx:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-common:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-common-java8:$lifecycleVersion")

    implementation("androidx.annotation:annotation:$annotationVersion")
    implementation("androidx.work:work-runtime:$workVersion")
}
