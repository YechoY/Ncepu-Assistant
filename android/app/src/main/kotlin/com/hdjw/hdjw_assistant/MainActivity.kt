package com.hdjw.hdjw_assistant

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.alipay.sdk.app.PayTask
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// 应用内更新：open_filex 只负责打开 APK，不处理 Android 8+ 的
/// 「安装未知应用」授权；这里提供两个方法给 Dart 侧调用：
///   canRequestInstall   —— 是否已授予安装未知应用权限
///   openInstallSetting  —— 跳转系统设置页让用户手动开启
///
/// 支付宝支付：channel 'ujing/alipay' / method 'payV2'（对齐参考项目 FlandreSY），
/// PayTask.payV2 必须在非主线程调用，SDK 自行展示收银台 UI。
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app_installer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )
                    "openInstallSetting" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ujing/alipay")
            .setMethodCallHandler { call, result ->
                if (call.method == "payV2") {
                    val orderInfo = call.argument<String>("orderInfo")
                    if (orderInfo.isNullOrEmpty()) {
                        result.error("INVALID_ORDER", "orderInfo is empty", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val payTask = PayTask(this@MainActivity)
                            val payResult: Map<String, String> =
                                payTask.payV2(orderInfo, true)
                            Handler(Looper.getMainLooper()).post {
                                result.success(payResult)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("PAY_ERROR", e.message ?: "Unknown Alipay error", null)
                            }
                        }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }
    }
}
