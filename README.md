# Memory Gallery

`Memory Gallery` 是一个基于 Flutter 的跨端相册应用，当前主要面向 `Windows` 和 `Android` 两个平台。项目目标不是做通用素材管理器，而是强调“回忆整理”的浏览体验：更大的封面舞台、更接近书架的相册首页、可编辑的照片文字信息，以及桌面端和移动端分别适配过的阅读布局。

## 当前状态

项目已经具备可持续使用的本地单机能力：

- 相册创建、编辑、删除
- 相册封面选择、缩放和取景偏移
- 首页书架式相册浏览
- 相册详情瀑布流浏览
- 照片详情页图文阅读与编辑
- 收藏、回收站、搜索、排序
- 本地持久化
- 本地数据导出 / 导入
- Windows 与 Android 双端运行和安装包输出

当前仓库仍在持续迭代，重点仍然是本地体验、界面打磨和跨端一致性，不包含后端服务。

## 核心功能

### 相册与照片管理

- 创建相册、编辑相册名、删除相册
- 从相册内图片选择封面
- 支持封面缩放与取景偏移，并可实时预览
- 添加照片、删除照片、批量删除
- 多选、全选 / 取消全选
- 删除照片先进入回收站，而不是直接丢失
- 回收站支持恢复、彻底删除、清空

### 浏览与阅读体验

- 首页采用书架式相册展示，而不是普通列表
- 相册详情使用瀑布流，更适合不同纵横比图片混排
- 首页支持 `相册 / 收藏 / 回收站` 三个主视图
- 收藏状态可在照片详情页真实切换并持久化
- 收藏页和回收站页都支持独立浏览和搜索

### 图文信息编辑

- 照片详情页支持备注文字编辑
- 照片日期可编辑并持久化
- 选图时自动读取照片 EXIF 或文件日期
- 相册描述可编辑并持久化
- 首页和详情页会同步展示相册描述
- 照片详情页支持 `A- / A+` 调节备注字号

### 数据能力

- 使用本地持久化保存相册、照片和设置
- 设置页支持导出本地数据为 `zip` 备份
- 支持从 `zip` 导入并覆盖当前本地数据

## 跨端设计

项目不是简单共用一套界面，而是保持交互目标一致、布局按设备能力调整。

### Windows 端

- 首页采用左侧边栏 + 右侧主舞台布局
- 搜索入口位于左侧放大镜按钮，点击后弹出搜索框
- 主页支持三态切换：
  - 单相册聚焦
  - 六宫格
  - 紧凑书脊墙
- 照片详情页采用左右分栏
- 图片与文字区域之间支持拖动分割线调整宽度
- 照片详情页默认尽量按整图显示，放大时保持图片中心不变，并可拖动查看局部
- 第 4 子窗口右上角的铅笔按钮仅编辑该窗口中的描述文本，不会打开整套相册编辑界面
- 当前保留了子窗口编号和红色调试框，便于后续按区域精确沟通与调试

### Android 端

- 已同步桌面端最新首页与详情能力
- `相册 / 收藏 / 回收站` 改为底部导航
- `相册` 入口同样支持三态切换：
  - 单相册
  - 六宫格
  - 书脊墙
- 主界面单相册模式采用上图下文
- 照片详情页采用上图下文
- 单相册封面后方取消白色叠层边框，让封面直接浮在背景图上

## 技术栈

- Flutter
- Dart
- `shared_preferences`
- `path_provider`
- `file_picker`
- `image_picker`
- `exif`
- `archive`
- `flutter_markdown_plus`

## 本地运行

### 环境要求

- Flutter SDK
- Dart SDK
- Android Studio / Android SDK
- Windows 端运行时需要启用 Flutter Windows 桌面支持

### 安装依赖

```bash
flutter pub get
```

### 运行 Windows

```bash
flutter run -d windows
```

### 运行 Android

```bash
flutter run -d <android-device-id>
```

## 验证命令

日常改动至少建议执行：

```bash
flutter analyze --no-pub
flutter test
```

仓库当前阶段已经多次验证：

- `flutter analyze`
- `flutter analyze --no-pub`
- `flutter test`
- `flutter run -d windows`
- `flutter run -d emulator-5554`

## 安装包

当前项目已经支持输出测试用安装包：

- Android APK：`build/installers/album_app_android_release.apk`
- Windows 安装器：`build/installers/album_app_windows_setup.exe`

Windows 安装器脚本位于：

- `tool/windows_installer/album_app.iss`

说明：

- 当前 Android `release` 包仍按项目默认配置使用调试签名，适合实体机侧载测试，不适合直接上架。

## 仓库结构

```text
lib/                     Flutter 主代码
test/                    Widget 测试
android/                 Android 工程
windows/                 Windows 工程
tool/windows_installer/  Windows 安装器脚本
docs/                    项目协作与状态记录
```

## 近期重点

- 在实体 Android 机上继续核对底部导航、三态切换和单相册视觉
- 继续确认相册详情页和照片详情页的布局边界
- 再打磨紧凑模式视觉
- 评估主页模式切换的动效与状态记忆
- 继续收敛子窗口标号与调试框的保留范围，必要时再逐步删除

## 说明

这个项目当前是本地优先、界面驱动的相册应用原型。它已经不是 Flutter 默认模板，但也还不是最终产品形态。后续迭代会继续优先处理：

- 跨端体验统一
- 浏览与阅读质感
- 本地数据可靠性
- 安装与测试流程
