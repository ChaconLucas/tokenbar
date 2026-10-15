plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "app.tokenbar.wear"
    compileSdk = 35
    defaultConfig {
        applicationId = "app.tokenbar"   // igual ao do celular: o Wear OS só liga apps com o mesmo id
        minSdk = 30
        targetSdk = 34
        versionCode = 13
        versionName = "0.4.1"
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
    buildFeatures { compose = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.wear.compose:compose-material:1.4.0")
    implementation("androidx.wear.compose:compose-foundation:1.4.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("androidx.wear.watchface:watchface-complications-data-source-ktx:1.2.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
}
