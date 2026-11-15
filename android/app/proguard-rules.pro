# Flutter & Native App Keep Rules
-keep class vce1.sakuraview.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep flutter_downloader background worker & callback entrypoints
-keep class vn.hunghd.flutterdownloader.** { *; }
-keepclassmembers class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# Keep optional transitive Tika / MIME & Play Core references gracefully when shrunk
-dontwarn com.google.android.play.core.**
-dontwarn org.apache.tika.**
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
-dontwarn okhttp3.**
-dontwarn okio.**
