# Release builds run R8. The Kakao map SDK's native library (libK3fAndroid.so) looks Java classes and fields up BY NAME
# over JNI (e.g. com.kakao.vectormap.internal.MapViewHolder.listener). R8 removes/renames them as "unused", the lookup
# fails with NoSuchFieldError, and the whole app aborts (SIGABRT) the moment the Map tab opens. Debug builds skip R8,
# so this only ever happens in an installed release APK.
-keep class com.kakao.vectormap.** { *; }
-keep interface com.kakao.vectormap.** { *; }
-keepclasseswithmembernames class * { native <methods>; }
-dontwarn com.kakao.vectormap.**
