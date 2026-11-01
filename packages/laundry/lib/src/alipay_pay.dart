// laundry/alipay_pay.dart —— 支付宝原生支付（对齐参考项目 RealPaymentLauncher）。
//
// 原生端：MainActivity.kt 注册 channel 'ujing/alipay' 的 'payV2' 方法，
// 调 com.alipay.sdk.app.PayTask(activity).payV2(orderInfo, true)，
// SDK 自行拉起收银台并返回 result map（resultStatus / memo / result）。
// 依赖：android/app/build.gradle.kts → com.alipay.sdk:alipaysdk-android。

import 'package:flutter/services.dart';

class AlipayPay {
  static const MethodChannel _channel = MethodChannel('ujing/alipay');

  /// 调起支付宝收银台。返回 (resultStatus, message)：
  ///   9000 支付成功 / 8000 处理中 / 6001 用户取消 / 4000 支付失败 / 其余见支付宝文档。
  /// 原生未接入（如 iOS）映射为 status = 'NO_PLUGIN'，SDK 异常映射为 'PAY_ERROR'，
  /// 均不伪装成功，由调用方按「支付未完成」处理。
  static Future<({String status, String message})> payV2(String orderInfo) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'payV2',
        {'orderInfo': orderInfo},
      );
      final status = result?['resultStatus']?.toString() ?? '';
      final memo = result?['memo']?.toString() ?? '';
      return (status: status, message: memo);
    } on MissingPluginException {
      return (status: 'NO_PLUGIN', message: '支付宝支付暂未支持当前平台');
    } on PlatformException catch (e) {
      return (status: 'PAY_ERROR', message: e.message ?? '支付宝调起失败（${e.code}）');
    }
  }
}
