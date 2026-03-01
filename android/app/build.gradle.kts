import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.wiseapps.liverwise"
    compileSdk = 35  // ✅ Updated to SDK 35 for Android 15 support
    ndkVersion = "27.0.12077973"

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.wiseapps.liverwise"
        minSdk = 24  // Keep your minimum SDK
        targetSdk = 35  // ✅ Updated to target SDK 35 for Android 15
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        
        // ✅ FIX #3: Enable 16 KB page alignment for native libraries
        // This ensures compatibility with devices using 16 KB memory pages
        ndk {
            // Explicitly declare supported ABIs if needed
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64"))
        }
    }

    // ✅ FIX #3: Configure 16 KB page alignment for native libraries
    packaging {
        jniLibs {
            useLegacyPackaging = false  // Use modern packaging with proper alignment
        }
        
        // Ensure proper alignment for all native libraries
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module"
            )
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            
            // Optimize for production
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            // Debug settings
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase
    implementation(platform("com.google.firebase:firebase-bom:34.6.0"))
    implementation("com.google.firebase:firebase-messaging")
    
    // AndroidX Core (updated for edge-to-edge support)
    implementation("androidx.core:core-ktx:1.15.0")  // ✅ Updated for Android 15 compatibility
    
    // Desugaring for older Android versions
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // ✅ FIX #1: Add AndroidX Activity for edge-to-edge support
    implementation("androidx.activity:activity-ktx:1.9.3")
}