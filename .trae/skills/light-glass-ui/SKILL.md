---
name: "light-glass-ui"
description: "Flutter 浅色玻璃拟态（Light Glassmorphism）UI 体系：设计 token、玻璃组件模式与性能规则。用户要求玻璃化/磨砂风 UI、统一卡片/弹窗/导航风格、调整玻璃质感或课程配色、或排查列表滑动掉帧时调用。"
---

# 浅色玻璃拟态 UI 体系（Light Glass UI）

一套在**浅色渐变背景**上实现高级感玻璃拟态的 Flutter 规范与组件模式。源自「华电教务助手」三轮真机迭代，适用于任何 Flutter App（含未来的音乐播放器项目）。

## 0. 第一原则

1. **背景不动**：玻璃的质感来自"透出的背景被柔化"。背景层 = 浅色纵向渐变 + 2~3 个大半径柔光斑（RadialGradient，blur 由外部裁剪或大半径容器实现）。没有丰富背景时，玻璃和白卡片没有区别。
2. **借手法不借深色配色**：市面玻璃 STYLEKIT 多为深色（深色底 + 白 5~12% + 金色强调）。翻译到浅色时：白透明度必须提高到 0.55~0.75、强调色换冷调主色，**绝不照搬深色参数**（白 10% 在浅底上发灰、看不见字）。
3. **光有方向**：顶部白高光是光源，底部 1px 暗缘是背光面，阴影偏冷色（紫灰），三者共同表达"玻璃片悬浮"。
4. **性能红线：BackdropFilter 数量 ≤ 一屏 ~5 个**。滚动列表里的卡片禁止用实时模糊。

## 1. 设计 Token（集中放 theme.dart，全局唯一真相源）

```dart
// 主色系（冷调雾蓝紫；按项目可替换，但保持"主色/柔主色/极浅容器/墨彩文字"四层）
const kPrimary = Color(0xFF6E77B5);         // 实心按钮/选中态（保证白字对比 ≥4.5:1）
const kPrimarySoft = Color(0xFFA4ABD6);     // 装饰渐变/淡彩
const kPrimaryContainer = Color(0xFFE7E9F7);// 选中底
const kInk = Color(0xFF454C84);             // 标题（替代纯黑/深蓝）
const kTextMain = Color(0xFF2E3350);        // 正文
const kTextMuted = Color(0xFF7A8099);       // 次要文字（统一所有灰字，禁止散落 6B7280 等）

// 玻璃材质
const kGlassAlpha = 0.58;    // 实时玻璃白不透明度（面板/弹窗/导航）
const kFrostAlpha = 0.74;    // 静态磨砂白不透明度（滚动列表卡片）
const kGlassBlur  = 24.0;    // sigma（≈ CSS backdrop-blur 50px）；密集大板用 12~16
const kGlassBorder = Color(0xB3FFFFFF);
const kGlassGridLine = Color(0x5998A4C4);   // 分割线/网格线
const kGlassShadow = Color(0x2E5B6691);     // 冷调柔影

// 动效：spring 手感
const Curve kSpring = Cubic(0.16, 1, 0.3, 1);
const Duration kSpringDur = Duration(milliseconds: 420);
```

**饱和度增强**：Flutter 没有 `backdrop-saturate`，用 ColorFilter.matrix（约 1.6 倍）与 blur 组合，透过玻璃的光斑才会亮：

```dart
final kGlassSaturate = ColorFilter.matrix(const [
  1.4722,-0.4290,-0.0432,0,0,
  -0.1278, 1.1710,-0.0432,0,0,
  -0.1278,-0.4290, 1.5568,0,0,
  0,0,0,1,0,
]);
ImageFilter glassBlurFilter({double sigma = kGlassBlur}) =>
    ImageFilter.compose(outer: kGlassSaturate, inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
```

全局微调只改两个值：模糊度 `kGlassBlur`、白浓度 `kGlassAlpha`。

## 2. GlassCard 组件结构（标准三件套）

从外到内：

1. `DecoratedBox`：双层冷影 —— 远影 `kGlassShadow` blur 28 / offset(0,10)，近影 `0x143D4670` blur 6 / offset(0,2)。阴影必须画在 ClipRRect **外层**（否则被裁掉）。
2. `ClipRRect(radius 22)` → `BackdropFilter(glassBlurFilter)` → 白 tint 容器 + 1px 白高光描边。
3. 容器内 Stack：顶部 48px 白色渐变内发光（0.55→0）、底部 1px 暗缘（`0xFF3D4670` @7%）、child。

**必须提供 `live` 开关**：

```dart
child: live
  ? BackdropFilter(filter: glassBlurFilter(sigma: blur), child: body)
  : body,   // 静态磨砂：乳白 kFrostAlpha，零模糊开销，滚动列表用
```

参考实现：`app/lib/widgets/glass_card.dart`。

## 3. 何时用 live / static（性能规则，最重要）

| 场景 | 材质 | 参数 |
|---|---|---|
| 顶部导航条、底部胶囊、弹窗、下拉浮层、独立大面板 | 实时玻璃 live:true | blur 24（大板 12~16），alpha 0.58 |
| **ListView / GridView 里的卡片** | **静态磨砂 live:false** | alpha 0.74，无 BackdropFilter |
| 密集小格（表头 7 格、网格板） | 合并成**一整块** BackdropFilter | 板内用描边拼网格线，绝不每格模糊 |

症状对照：滚动掉帧 = BackdropFilter 过多；把列表卡换 live:false 即可，观感差距很小。静态卡配轻量入场动画做"缓冲"（见 §6）。

## 4. 各组件模式

- **弹窗（Dialog）**：一律用统一的 `_GlassDialog`（见 app.dart）替代系统 AlertDialog：`Dialog(backgroundColor: Colors.transparent, elevation: 0)` 内包 GlassCard（radius 22），`barrierColor: 0x402E3350`（墨紫半透）。标题 kInk 16 w700、正文 kTextMuted 12.5；按钮为胶囊（圆角 13、高 40）：单确认铺满整行 kPrimary 实底；「取消+确认」并排时取消用白 0.5 半透。危险操作（退出登录）确认按钮用柔和红 `0xFFB85450`，pop 语义走 `popResult` 由 showDialog 返回值接住，禁止在按钮回调里二次 pop。
- **下拉浮层**：BottomSheet 内 GlassCard 外包 12px padding 悬浮；选项是独立圆角 14 卡片，**项间留 8px 间隙**；单选选中 = kPrimaryContainer 底 + kPrimarySoft 描边 + 右侧 check；点按 InkWell + 200ms AnimatedContainer。**多选模式**（GlassDropdown `multi:true`）：选项行首 20px 圆角 6 勾选框（选中实底紫+白勾 / 部分选中浅紫底+"−" / 未选半透白），点选**不关面板**、实时回调差量，右上角 kPrimary「完成」胶囊收起；适合"学期快捷勾选课程"这类场景。
- **底部菜单 sheet**（用户菜单类）：透明底 + 墨紫遮罩 + 浮起 GlassCard(radius 22)；菜单项与下拉选项同款卡片，行首图标坐在同色系 12% 浅色圆片上（危险项柔和红），右侧 chevron_right。
- **底部导航**：整条一块 GlassCard(radius 24)；选中项 kPrimary 实底胶囊 + 同色 0.38 柔光、白字 w700；未选透明、kTextMuted；指示器动效用 kSpringDur/kSpring。
- **列表卡（成绩/考试/房间等数据卡）**：GlassCard(radius 18, live:false)，左侧 4px 状态色竖条（圆角 2）+ 主文案 + 右侧小胶囊徽章；状态色用低饱和功能色（绿 0xFF5E9C80 / 蓝 0xFF3B7399 / 橙 0xFFB07432 / 红 0xFFB85450 / 中性灰 0xFFB6BCC9），徽章底色为同色相 8~10% 浅彩。
- **实色课程卡（MacCard）**：不透的粉彩卡（bg 浅/border 粉彩/name 同相深墨彩）+ 白 0.7 高光边 + 同款双层冷影，与玻璃卡同影系。
- **网格板**：一整块 ClipRRect+BackdropFilter（sigma 16，白 0.34），内部单元格用 `border: Border(left, top)` 拼横纵线（kGlassGridLine），外框承担右/下边；周末列铺淡彩 9% 底。
- **输入框/芯片**：白 0.55、圆角 12~14、白 0.65 描边；主按钮 kPrimary 实底高 ≥50、圆角 15、0.4 主色阴影。

## 5. 分类着色：哈希 + 冲突消解（不止于课程）

给一组对象（课程、歌单、分类）分配区分色时，**单纯哈希取模必然碰撞**（生日悖论：10 个对象映射 12 个槽位，同色概率 >95%，换哈希算法/扩色板都不能根治）。

正确做法：

1. 调色板沿色环等间隔排（推荐 12 色、30° 一档，粉彩 = bg 高明度低饱和 / border 中彩 / name 深墨彩保证文字对比）。
2. 哈希只定"初始偏好"：FNV-1a + MurmurHash3 fmix32 雪崩（h*31 对中文 UTF-16 分布差）。
3. **按"同屏共存域"消解**：统计每个对象会和谁同时出现（如课程按星期几），分配时避开同域已用色，冲突顺序探测下一个槽位；处理顺序稳定（按首次出现域 + 名称排序），保证同名对象颜色恒定。
4. 同色只允许出现在永不同屏的对象之间。

参考：`app/lib/theme.dart` 的 `courseHash` / `assignCourseIndices`，页面层算出 `Map<名称, 下标>` 后通过构造参数把颜色传入卡片。

## 6. 动效规则

- 曲线统一 `kSpring`（Cubic(0.16,1,0.3,1)）；面板级 420ms，小控件 200~280ms。
- 列表入场用 Reveal（淡入 + 上移 14 + 缩放 0.98，320ms）：定位是"缓冲滚动顿挫"，不是表演——位移/时长保持克制。
- Tab 切换：IndexedStack 保状态 + 每页包一层 FadeTransition（280ms，scale 0.985→1），仅新激活页 forward，首屏 value:1 不播。
- 动画不能救渲染性能：先去掉多余 BackdropFilter，再谈动画。

## 7. 质量检查清单

- [ ] 新灰字/分割线是否用了 token（kTextMain/kTextMuted/kGlassGridLine），没有新硬编码
- [ ] 一屏 BackdropFilter 数量；列表卡是否 live:false
- [ ] Dialog 是否透明底 + GlassCard（统一 _GlassDialog），barrier 是否墨紫；确认按钮是否单次 pop（popResult 语义）
- [ ] 底部菜单/多选面板是否与下拉同款浮卡体系（图标浅色圆片、勾选框三态）
- [ ] 阴影是否冷调双层、画在 Clip 外层
- [ ] 分类色同屏共存对象是否保证不同（走冲突消解）
- [ ] `flutter analyze` 0 error；真机（低端安卓优先）验证滚动与切页
- [ ] 背景渐变/光斑未被改动；白字按钮对比度足够

## 8. 参考实现（ncepu/app）

- `lib/theme.dart`：全部 token、12 色调色板、courseHash、assignCourseIndices
- `lib/widgets/glass_card.dart`：live/static 双模式玻璃卡（本体系核心）
- `lib/widgets/glass_dropdown.dart`、`capsule_nav.dart`、`reveal.dart`
- `lib/widgets/grade_card.dart` / `exam_card.dart` / `room_card.dart`：静态磨砂列表卡三范例
- `lib/pages/full_timetable_page.dart`：整块磨砂网格板 + 冲突消解接入
- `lib/app.dart`：_TabFade 切换过渡
