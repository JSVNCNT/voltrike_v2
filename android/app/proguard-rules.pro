# Google Navigation 7.6.1 is pre-obfuscated. D8 drops this parcelable helper
# package in the large debug APK unless R8 retains it explicitly.
-keep class com.google.android.libraries.navigation.internal.nc.** { *; }
