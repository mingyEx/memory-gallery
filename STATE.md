## 当前阶段
基础 MVP 已可编译、可测试，主界面已改为类似演示文稿的浏览结构；下一步应补对应交互与持久化验证。

## 已完成
- Flutter 项目已创建，主代码集中在 `lib/main.dart`。
- 已实现相册条目本地存储：选择图片、填写备注、保存、列表展示、删除。
- 已实现本地持久化仓储抽象：`AlbumRepository`、`LocalAlbumRepository`、`InMemoryAlbumRepository`。
- 已实现外观设置：主题模式、背景主色、壁纸选择/清除、设置持久化。
- 已有一个基础 widget test：验证首页基础控件和示例记录渲染。
- 已修复 `onSettingsChanged` 的同步/异步签名不匹配问题。
- 已把主题样式调整为更接近 Windows 原生应用的明暗配色与控件外观。
- 已把主题切换控件改为分段选择样式，并重做首页层级、留白和记录卡片布局，使其更接近桌面应用。
- 已把主浏览区改为类似 PPT 的结构：左侧缩略图列表，右侧大图与备注详情。
- 已把颜色选择改成规整色板按钮，并把壁纸设置区改成更接近系统设置页的预览卡片。
- 已补充深色模式测试，确认 `ThemeMode.dark` 设置生效。
- `flutter analyze` 与 `flutter test` 当前均通过。

## 进行中
- 暂无明确进行中的功能开发记录。

## 下一步
- 为外观设置补交互测试，至少覆盖从设置面板切换主题与背景色后的状态更新。
- 为主浏览区补交互测试，至少覆盖点击缩略图后右侧大图内容切换。
- 为本地持久化补测试，至少覆盖保存条目后重新加载。
- 评估是否要把 `lib/main.dart` 拆分为页面、模型、仓储，降低单文件维护成本。

For Flutter projects:
- Before running flutter analyze, run flutter pub get only if needed.
- Prefer flutter analyze --no-pub.
- Do not run long Flutter commands repeatedly.
- If a Flutter command appears stuck, stop and report the exact command.
