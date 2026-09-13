# NCEPU 教务助手 — 开发文档

面向后续开发者的快速入门文档。本项目登录华北电力大学教务系统，查询**课表、课程成绩、考试安排、空闲教室**，数据本地缓存、离线可用。分两端：**Windows 桌面版（Python + pywebview + Vue3）** 与 **安卓版（Flutter）**。

## 快速了解

- **桌面版技术栈**：Python（后端）+ pywebview（桌面壳）+ Vue 3（前端）+ PyInstaller（打包）
- **安卓版技术栈**：Flutter（Dart），工程在 `app/`
- **运行（桌面）**：`python main.py`（需校园网才能登录和刷新，离线可看缓存）
- **打包（桌面）**：双击 `build_exe.bat`，产物在 `dist\NCEPU教务助手.exe`（单个 exe，约 30MB）
- **打包（安卓）**：`flutter build apk --release --target-platform android-arm64`
- **数据**：桌面版在程序目录下 `data\`；安卓版在 App 私有目录

## 文档导航

| 文档 | 内容 |
|---|---|
| [01-架构与技术栈.md](01-架构与技术栈.md) | 架构图、文件职责、前后端接口契约、双端架构 |
| [02-核心接口与解析.md](02-核心接口与解析.md) | 教务系统各接口的请求 / 返回 / 解析细节 |
| [03-踩坑记录.md](03-踩坑记录.md) | 开发过程中踩过的坑与解决方案（必读） |
| [04-打包运行与数据.md](04-打包运行与数据.md) | 运行、打包、数据存储、安全与发布 |
| [05-开发计划与安卓规划.md](05-开发计划与安卓规划.md) | 当前状态、双端现状、待办事项 |
| [superpowers/specs/](superpowers/specs/2026-08-21-华电教务助手-flutter-design.md) | 安卓版（Flutter）设计说明 |
| [superpowers/plans/](superpowers/plans/2026-08-21-华电教务助手-flutter-app.md) | 安卓版（Flutter）实现计划 |

## 当前功能清单（两端基本一致）

- **登录**：无验证码，强智教务加密算法（先取加密种子，再生成 encoded）
- **课表**：按日期查询（服务器自己算第几周）、上周/下周切换、课程卡片独立配色
- **课程成绩**：6 列展示；筛选（学期/课程名/属性）；排序（学期/成绩/学分）；平均学分绩
- **考试安排**：6 列展示，已考完的整行置灰
- **空闲教室**：校区/教学楼/星期/节次/周次条件；按当前时间自动选节次
- **启动弹窗**：关于信息（创建人/联系方式，占位符待填）
- **记住账号密码 / 本地缓存**：离线可看缓存；旧数据（`~/.ncepu_jwc`）自动迁移（桌面版）

## 常见命令

```bash
# 桌面版
python main.py
build_exe.bat
# 语法检查
python -c "import py_compile; [py_compile.compile(f, doraise=True) for f in ['main.py','bridge.py','client.py','storage.py']]"
node --check web/app.js

# 安卓版（Flutter）
cd app
flutter run
flutter build apk --release --target-platform android-arm64
```

> 教务系统仅校园网可达；桌面版依赖系统 WebView2（Win10/11 一般自带）。
