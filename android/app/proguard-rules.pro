# Keep Flutter wrapper & native engine classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep pdfrx / PDFium JNI bindings
-keep class jp.espresso3389.pdfrx.** { *; }
-dontwarn jp.espresso3389.pdfrx.**
