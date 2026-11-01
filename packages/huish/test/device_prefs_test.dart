// huish 模块测试 —— 设备本地偏好（device_prefs.dart）。
// 用 SharedPreferences.setMockInitialValues 提供内存存储，不触平台通道。

import 'package:flutter_test/flutter_test.dart';
import 'package:huish/src/device_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('分组管理', () {
    test('空存储返回仅含 default', () async {
      expect(await DevicePrefs.loadGroups(), ['default']);
    });

    test('addGroup：空名 / default / 重名均拒绝', () async {
      expect(await DevicePrefs.addGroup(''), isFalse);
      expect(await DevicePrefs.addGroup('  '), isFalse);
      expect(await DevicePrefs.addGroup('default'), isFalse);
      expect(await DevicePrefs.addGroup('宿舍楼A'), isTrue);
      expect(await DevicePrefs.addGroup('宿舍楼A'), isFalse); // 重名
      expect(await DevicePrefs.loadGroups(), ['default', '宿舍楼A']);
    });

    test('addGroup 名称自动 trim', () async {
      expect(await DevicePrefs.addGroup('  教学楼B  '), isTrue);
      expect(await DevicePrefs.loadGroups(), contains('教学楼B'));
    });

    test('renameGroup：default 不可改，改名后其下设备同步迁移', () async {
      await DevicePrefs.addGroup('旧组');
      await DevicePrefs.updateDeviceCustom('dev1', groupId: '旧组');

      await DevicePrefs.renameGroup('default', '新组'); // 拒绝
      expect(await DevicePrefs.loadGroups(), contains('default'));

      await DevicePrefs.renameGroup('旧组', '新组');
      expect(await DevicePrefs.loadGroups(), ['default', '新组']);
      final customs = await DevicePrefs.loadDeviceCustoms();
      expect(customs['dev1']!.groupId, '新组');
    });

    test('renameGroup：新名已存在时拒绝', () async {
      await DevicePrefs.addGroup('A');
      await DevicePrefs.addGroup('B');
      await DevicePrefs.renameGroup('A', 'B'); // 冲突
      expect(await DevicePrefs.loadGroups(), ['default', 'A', 'B']);
    });

    test('deleteGroup：default 不可删，其下设备移回 default', () async {
      await DevicePrefs.addGroup('临时组');
      await DevicePrefs.updateDeviceCustom('dev2', groupId: '临时组');

      await DevicePrefs.deleteGroup('default'); // 拒绝
      expect(await DevicePrefs.loadGroups(), contains('default'));

      await DevicePrefs.deleteGroup('临时组');
      expect(await DevicePrefs.loadGroups(), ['default']);
      final customs = await DevicePrefs.loadDeviceCustoms();
      expect(customs['dev2']!.groupId, 'default');
    });

    test('deleteGroup：不存在的分组静默忽略', () async {
      await DevicePrefs.deleteGroup('不存在');
      expect(await DevicePrefs.loadGroups(), ['default']);
    });
  });

  group('设备自定义信息', () {
    test('updateDeviceCustom：新增与部分更新', () async {
      await DevicePrefs.updateDeviceCustom('dev1', customName: '我的水机');
      var customs = await DevicePrefs.loadDeviceCustoms();
      expect(customs['dev1']!.customName, '我的水机');
      expect(customs['dev1']!.groupId, 'default');

      await DevicePrefs.updateDeviceCustom('dev1', groupId: '教学区');
      customs = await DevicePrefs.loadDeviceCustoms();
      expect(customs['dev1']!.customName, '我的水机'); // 名字未被覆盖
      expect(customs['dev1']!.groupId, '教学区');
    });

    test('removeDevice：清自定义信息与各分组排序记录', () async {
      await DevicePrefs.addGroup('A');
      await DevicePrefs.updateDeviceCustom('dev1', customName: 'x');
      await DevicePrefs.saveDeviceOrder({
        'default': ['dev1', 'dev2'],
        'A': ['dev1'],
      });

      await DevicePrefs.removeDevice('dev1');
      expect(await DevicePrefs.loadDeviceCustoms(), isNot(contains('dev1')));
      expect(await DevicePrefs.loadDeviceOrder(), {
        'default': ['dev2'],
        'A': <String>[],
      });
    });

    test('损坏的 JSON 缓存返回空映射而非抛异常', () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('huish_device_custom', '{broken json');
      expect(await DevicePrefs.loadDeviceCustoms(), isEmpty);
    });
  });

  group('取水会话持久化', () {
    test('save / load 往返', () async {
      await DevicePrefs.saveActiveSession(
        deviceId: 'dev9',
        startOut: 12.5,
        startTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      final s = await DevicePrefs.loadActiveSession();
      expect(s, isNotNull);
      expect(s!.deviceId, 'dev9');
      expect(s.startOut, 12.5);
    });

    test('超过 30 分钟的会话自动清除并返回 null', () async {
      final stale = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 31 * 60;
      await DevicePrefs.saveActiveSession(
        deviceId: 'dev9',
        startOut: 0,
        startTs: stale,
      );
      expect(await DevicePrefs.loadActiveSession(), isNull);
      // 已被清除：再次读取仍为 null
      expect(await DevicePrefs.loadActiveSession(), isNull);
    });

    test('clearActiveSession 后读取为 null', () async {
      await DevicePrefs.saveActiveSession(
        deviceId: 'dev9',
        startOut: 1,
        startTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await DevicePrefs.clearActiveSession();
      expect(await DevicePrefs.loadActiveSession(), isNull);
    });

    test('损坏的会话 JSON 返回 null', () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('huish_active_session', 'not-json');
      expect(await DevicePrefs.loadActiveSession(), isNull);
    });
  });

  group('一键取水状态', () {
    test('setQuickOn / isQuickOn 开关', () async {
      expect(await DevicePrefs.isQuickOn(), isFalse);
      await DevicePrefs.setQuickOn(true);
      expect(await DevicePrefs.isQuickOn(), isTrue);
      await DevicePrefs.setQuickOn(false);
      expect(await DevicePrefs.isQuickOn(), isFalse);
    });

    test('everRunning 标记：mark / clear', () async {
      expect(await DevicePrefs.isQuickEverRunning(), isFalse);
      await DevicePrefs.markQuickEverRunning();
      expect(await DevicePrefs.isQuickEverRunning(), isTrue);
      await DevicePrefs.clearQuickEverRunning();
      expect(await DevicePrefs.isQuickEverRunning(), isFalse);
    });

    test('换绑快捷设备后旧会话标记作废', () async {
      await DevicePrefs.markQuickEverRunning();
      await DevicePrefs.setQuickDevice('devA', 'A楼水机');
      expect(await DevicePrefs.isQuickEverRunning(), isFalse);
      expect(await DevicePrefs.getQuickDeviceId(), 'devA');
      expect(await DevicePrefs.getQuickDeviceName(), 'A楼水机');
    });

    test('clearQuickDevice 同样清会话标记', () async {
      await DevicePrefs.setQuickDevice('devA', 'A楼水机');
      await DevicePrefs.markQuickEverRunning();
      await DevicePrefs.clearQuickDevice();
      expect(await DevicePrefs.getQuickDeviceId(), isNull);
      expect(await DevicePrefs.isQuickEverRunning(), isFalse);
    });
  });

  group('本机停水记录', () {
    test('mark 后在窗口期内可查，clear 后失效', () async {
      expect(await DevicePrefs.wasRecentlyStopped('dev1'), isFalse);
      await DevicePrefs.markStoppedByMe('dev1');
      expect(await DevicePrefs.wasRecentlyStopped('dev1'), isTrue);
      await DevicePrefs.clearStoppedByMe('dev1');
      expect(await DevicePrefs.wasRecentlyStopped('dev1'), isFalse);
    });

    test('不同设备互不影响', () async {
      await DevicePrefs.markStoppedByMe('dev1');
      expect(await DevicePrefs.wasRecentlyStopped('dev2'), isFalse);
    });
  });
}
