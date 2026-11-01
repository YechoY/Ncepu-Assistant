// laundry 包唯一出口。
// 宿主只 import 这个文件：
//   import 'package:laundry/laundry.dart';
// 然后把 LaundryHomePage 挂到路由上即可——登录态、协议、UI 全部自包含。

export 'src/laundry_auth_state.dart';
export 'src/laundry_home_page.dart';
export 'src/laundry_login_page.dart';
export 'src/laundry_order_page.dart';
