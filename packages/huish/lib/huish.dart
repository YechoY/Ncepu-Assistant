// huish —— 惠生活798 饮水模块唯一出口。
//
// 宿主接入方式：
//   pubspec.yaml: huish: { path: packages/huish }
//   import 'package:huish/huish.dart';
//   日志注入（可选）：在 ProviderScope overrides 中
//     huishApiClientProvider.overrideWithValue(
//       HuishApiClient(logger: (tag, msg) => AppDebugLog.instance.log(tag, msg)),
//     )
//   —— 不注入则模块静默运行（无日志）。
//
// 模块对宿主零依赖：设计体系来自 glass_ui，日志通过构造注入。

library huish;

export 'src/huish_api_client.dart' show HuishApiClient;
export 'src/huish_auth_state.dart';
export 'src/huish_home_page.dart' show HuishHomePage;
export 'src/huish_login_page.dart' show HuishLoginPage;
