# ─────────────────────────────────────────────────────────────
# R8 / ProGuard 保留规则（仅 release 生效）
# ─────────────────────────────────────────────────────────────
# 目前使用的插件（sqflite、flutter_secure_storage 等）均自带 consumer
# 混淆规则，无需在此额外声明。若将来引入反射型插件再补充。

# ── mobile_scanner / MLKit ───────────────────────────────────
# 插件自带 consumer 规则只 keep 了一层包（com.google.mlkit.* 不含子包），
# R8 full mode 下 MLKit 子包类被混淆破坏，release 包相机启动报
# "Attempt to invoke virtual method 'java.lang.Class getClass()' on a null
# object reference"。此处补全量 keep。
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.steenbakker.mobile_scanner.** { *; }
