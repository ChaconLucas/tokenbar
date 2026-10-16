plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "app.tokenbar.app"
    compileSdk = 35
    defaultConfig {
        applicationId = "app.tokenbar"   // o relógio usa o mesmo id: é assim que o Wear OS liga os dois
        minSdk = 26
        targetSdk = 35
        versionCode = 25
        versionName = "0.5.3"
    }
    // Assinatura definitiva: a chave fica fora do repositório (~/.tokenbar-keys). Sem ela, gera só o debug.
    val keyFile = file(System.getProperty("user.home") + "/.tokenbar-keys/release.jks")
    signingConfigs {
        if (keyFile.exists()) create("release") {
            storeFile = keyFile
            storePassword = file(System.getProperty("user.home") + "/.tokenbar-keys/storepass.txt").readText().trim()
            keyAlias = "tokenbar"
            keyPassword = storePassword
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
}
