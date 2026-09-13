# ─────────────────────────────────────────────────────────────
# R8 / ProGuard 保留规则（仅 release 生效）
# ─────────────────────────────────────────────────────────────

# WorkManager 0.6.0：它通过反射实例化 Room 生成的 WorkDatabase_Impl，
# 后台 SystemJobService、Worker 类也靠反射/清单注册，整体保留最稳妥。
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.ListenableWorker
-dontwarn androidx.work.**

# Room：数据库实现类与实体由编译器生成、运行期反射加载
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep @androidx.room.Entity class *
-dontwarn androidx.room.paging.**

# flutter_local_notifications：插件原生类经 JNI/清单反射引用
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# 应用自身的 WorkManager 后台入口（被系统以反射方式回调，release 下不能被裁）
-keep class com.hdjw.hdjw_assistant.** { *; }
