import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const AlbumPrototypeApp());
}

void showPrototypeMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

const Object _fieldUnset = Object();

class LocalAlbumStore {
  static const String _albumsKey = 'albums_json_v1';
  static const String _appearanceKey = 'appearance_json_v1';
  static const String _mediaFolderName = 'album_media';

  static Future<List<AlbumData>?> loadAlbums() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_albumsKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((dynamic item) => AlbumData.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAlbums(List<AlbumData> albums) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(
      albums.map((AlbumData album) => album.toJson()).toList(),
    );
    await prefs.setString(_albumsKey, raw);
  }

  static Future<PrototypeAppearance?> loadAppearance() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_appearanceKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    return PrototypeAppearance(
      themeMode: ThemeMode.values.byName(decoded['themeMode'] as String),
      themeStyle: PrototypeThemeStyle.values.byName(
        decoded['themeStyle'] as String,
      ),
    );
  }

  static Future<void> saveAppearance(PrototypeAppearance appearance) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _appearanceKey,
      jsonEncode(<String, String>{
        'themeMode': appearance.themeMode.name,
        'themeStyle': appearance.themeStyle.name,
      }),
    );
  }

  static Future<String> persistPickedImage(
    XFile image, {
    required String albumId,
  }) async {
    final Directory mediaDir = await _mediaDirectory();
    final String extension = _fileExtension(image.path);
    final String targetPath =
        '${mediaDir.path}${Platform.pathSeparator}${albumId}_${DateTime.now().microsecondsSinceEpoch}$extension';
    await File(image.path).copy(targetPath);
    return targetPath;
  }

  static Future<void> deleteManagedImage(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    final Directory mediaDir = await _mediaDirectory();
    if (!path.startsWith(mediaDir.path)) {
      return;
    }
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> deleteAlbumImages(AlbumData album) async {
    for (final PhotoData photo in album.photos) {
      await deleteManagedImage(photo.imagePath);
    }
  }

  static Future<Directory> _mediaDirectory() async {
    final Directory root = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(
      '${root.path}${Platform.pathSeparator}$_mediaFolderName',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static String _fileExtension(String path) {
    final int dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1) {
      return '.jpg';
    }
    return path.substring(dotIndex);
  }
}

enum PrototypeThemeStyle { warm, walnut, sage }

enum HomeSection { albums, memories, favorites, recent }

enum AlbumSortMode { recent, photoCount, title }

class PrototypeAppearance {
  const PrototypeAppearance({
    required this.themeMode,
    required this.themeStyle,
  });

  final ThemeMode themeMode;
  final PrototypeThemeStyle themeStyle;

  PrototypeAppearance copyWith({
    ThemeMode? themeMode,
    PrototypeThemeStyle? themeStyle,
  }) {
    return PrototypeAppearance(
      themeMode: themeMode ?? this.themeMode,
      themeStyle: themeStyle ?? this.themeStyle,
    );
  }
}

class PrototypePalette {
  const PrototypePalette({
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.ink,
  });

  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color ink;
}

PrototypePalette paletteFor(PrototypeThemeStyle style, Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;
  switch (style) {
    case PrototypeThemeStyle.warm:
      return PrototypePalette(
        background: isDark ? const Color(0xFF2A201A) : const Color(0xFFF6F0E7),
        surface: isDark ? const Color(0xFF3A2C22) : const Color(0xFFFFFCF7),
        primary: const Color(0xFF8E6847),
        secondary: const Color(0xFFC89A6A),
        ink: isDark ? const Color(0xFFF5EDE1) : const Color(0xFF5A3E2A),
      );
    case PrototypeThemeStyle.walnut:
      return PrototypePalette(
        background: isDark ? const Color(0xFF241B1B) : const Color(0xFFF3ECE7),
        surface: isDark ? const Color(0xFF37292A) : const Color(0xFFFFFBF8),
        primary: const Color(0xFF7D5548),
        secondary: const Color(0xFFC59C8D),
        ink: isDark ? const Color(0xFFF2E6E2) : const Color(0xFF4D342D),
      );
    case PrototypeThemeStyle.sage:
      return PrototypePalette(
        background: isDark ? const Color(0xFF1E241D) : const Color(0xFFF0F3EC),
        surface: isDark ? const Color(0xFF2D382B) : const Color(0xFFFCFFFA),
        primary: const Color(0xFF647A56),
        secondary: const Color(0xFF9EB18A),
        ink: isDark ? const Color(0xFFEAF1E4) : const Color(0xFF3E4E35),
      );
  }
}

String themeStyleLabel(PrototypeThemeStyle style) {
  switch (style) {
    case PrototypeThemeStyle.warm:
      return '暖棕';
    case PrototypeThemeStyle.walnut:
      return '胡桃';
    case PrototypeThemeStyle.sage:
      return '鼠尾草';
  }
}

String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return '跟随系统';
    case ThemeMode.light:
      return '浅色';
    case ThemeMode.dark:
      return '深色';
  }
}

String albumSortModeLabel(AlbumSortMode mode) {
  switch (mode) {
    case AlbumSortMode.recent:
      return '最近更新';
    case AlbumSortMode.photoCount:
      return '照片数量';
    case AlbumSortMode.title:
      return '相册名称';
  }
}

String photoStyleLabel(PhotoStyle style) {
  switch (style) {
    case PhotoStyle.mountainLake:
      return '雪山湖泊';
    case PhotoStyle.oldStreet:
      return '老街';
    case PhotoStyle.temple:
      return '寺庙';
    case PhotoStyle.yakField:
      return '草场';
    case PhotoStyle.greenValley:
      return '山谷';
    case PhotoStyle.horses:
      return '马群';
    case PhotoStyle.sunsetSea:
      return '落日海边';
    case PhotoStyle.cityWarm:
      return '城市暖光';
    case PhotoStyle.cafe:
      return '咖啡馆';
    case PhotoStyle.sunlitRoom:
      return '日光房间';
    case PhotoStyle.tabletop:
      return '木桌静物';
    case PhotoStyle.nightLamp:
      return '夜灯';
  }
}

String homeSectionTitle(HomeSection section) {
  switch (section) {
    case HomeSection.albums:
      return '电子相册';
    case HomeSection.memories:
      return '回忆';
    case HomeSection.favorites:
      return '收藏';
    case HomeSection.recent:
      return '最近添加';
  }
}

String homeSectionSubtitle(HomeSection section) {
  switch (section) {
    case HomeSection.albums:
      return '记录生活，珍藏回忆';
    case HomeSection.memories:
      return '按时间回看过去的片段';
    case HomeSection.favorites:
      return '保留你最想反复翻看的内容';
    case HomeSection.recent:
      return '查看最近新建或更新过的相册';
  }
}

List<AlbumData> albumsForSection(List<AlbumData> albums, HomeSection section) {
  switch (section) {
    case HomeSection.albums:
      return albums;
    case HomeSection.memories:
      return <AlbumData>[...albums.reversed];
    case HomeSection.favorites:
      return albums
          .where((AlbumData album) => album.photos.length >= 4)
          .toList();
    case HomeSection.recent:
      final List<AlbumData> sorted = <AlbumData>[...albums];
      sorted.sort((AlbumData a, AlbumData b) {
        return _albumLatestDate(b).compareTo(_albumLatestDate(a));
      });
      return sorted;
  }
}

List<AlbumData> filterAndSortAlbums(
  List<AlbumData> albums, {
  required String searchQuery,
  required AlbumSortMode sortMode,
}) {
  final String query = searchQuery.trim().toLowerCase();
  final List<AlbumData> filtered = query.isEmpty
      ? <AlbumData>[...albums]
      : albums.where((AlbumData album) {
          final String haystack =
              '${album.title} ${album.description} ${album.subtitle}'
                  .toLowerCase();
          return haystack.contains(query);
        }).toList();

  filtered.sort((AlbumData a, AlbumData b) {
    switch (sortMode) {
      case AlbumSortMode.recent:
        return _albumLatestDate(b).compareTo(_albumLatestDate(a));
      case AlbumSortMode.photoCount:
        final int countCompare = b.photos.length.compareTo(a.photos.length);
        if (countCompare != 0) {
          return countCompare;
        }
        return a.title.compareTo(b.title);
      case AlbumSortMode.title:
        return a.title.compareTo(b.title);
    }
  });
  return filtered;
}

DateTime _albumLatestDate(AlbumData album) {
  DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
  for (final PhotoData photo in album.photos) {
    final DateTime? parsed = parseChineseDate(photo.date);
    if (parsed != null && parsed.isAfter(latest)) {
      latest = parsed;
    }
  }
  return latest;
}

DateTime? parseChineseDate(String text) {
  final RegExpMatch? match = RegExp(
    r'^(\d{4})年(\d{1,2})月(\d{1,2})日$',
  ).firstMatch(text);
  if (match == null) {
    return null;
  }
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

Future<PhotoOrientation> detectPhotoOrientation(String path) async {
  try {
    final Uint8List bytes = await File(path).readAsBytes();
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image image) {
      completer.complete(image);
    });
    final ui.Image image = await completer.future;
    return image.height > image.width
        ? PhotoOrientation.portrait
        : PhotoOrientation.landscape;
  } catch (_) {
    return PhotoOrientation.landscape;
  }
}

String formatAlbumDate(DateTime value) {
  return '${value.year}年${value.month}月${value.day}日';
}

String derivePhotoTitle(String note) {
  final String firstLine = note.split('\n').first.trim();
  if (firstLine.isEmpty) {
    return '新的照片';
  }
  return firstLine.length > 18 ? '${firstLine.substring(0, 18)}...' : firstLine;
}

Future<void> showPrototypeSettingsSheet(
  BuildContext context, {
  required PrototypeAppearance appearance,
  required ValueChanged<PrototypeAppearance> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFFFFFCF7),
    builder: (BuildContext context) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '原型设置',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '主题风格和明暗模式会立刻作用到首页、详情页和设置面板。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.68),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 18),
                _PrototypeOptionTile(
                  icon: Icons.palette_outlined,
                  title: '主题风格',
                  subtitle: '当前：${themeStyleLabel(appearance.themeStyle)}',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: PrototypeThemeStyle.values.map((
                      PrototypeThemeStyle style,
                    ) {
                      final bool selected = style == appearance.themeStyle;
                      return ChoiceChip(
                        label: Text(themeStyleLabel(style)),
                        selected: selected,
                        onSelected: (_) {
                          onChanged(appearance.copyWith(themeStyle: style));
                        },
                      );
                    }).toList(),
                  ),
                ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          height: 74,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                Theme.of(context).scaffoldBackgroundColor,
                                Theme.of(context).colorScheme.surface,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 74,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.14),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _PrototypeOptionTile(
                  icon: Icons.devices_outlined,
                  title: '主题模式',
                  subtitle: '当前：${themeModeLabel(appearance.themeMode)}',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ThemeMode.values.map((ThemeMode mode) {
                      final bool selected = mode == appearance.themeMode;
                      return ChoiceChip(
                        label: Text(themeModeLabel(mode)),
                        selected: selected,
                        onSelected: (_) {
                          onChanged(appearance.copyWith(themeMode: mode));
                        },
                      );
                    }).toList(),
                  ),
                ),
                const _PrototypeOptionTile(
                  icon: Icons.cloud_off_outlined,
                  title: '数据状态',
                  subtitle: '当前仍为静态假数据，不连接 Supabase',
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

void openPrototypePage(
  BuildContext context, {
  required String title,
  required String description,
  required IconData icon,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => PrototypePlaceholderPage(
        title: title,
        description: description,
        icon: icon,
      ),
    ),
  );
}

class AlbumPrototypeApp extends StatefulWidget {
  const AlbumPrototypeApp({super.key});

  @override
  State<AlbumPrototypeApp> createState() => _AlbumPrototypeAppState();
}

class _AlbumPrototypeAppState extends State<AlbumPrototypeApp> {
  late List<AlbumData> _albums;
  PrototypeAppearance _appearance = const PrototypeAppearance(
    themeMode: ThemeMode.light,
    themeStyle: PrototypeThemeStyle.warm,
  );

  @override
  void initState() {
    super.initState();
    _albums = buildDemoAlbums();
    unawaited(_loadLocalState());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '电子相册',
      debugShowCheckedModeBanner: false,
      themeMode: _appearance.themeMode,
      theme: _buildTheme(Brightness.light, _appearance.themeStyle),
      darkTheme: _buildTheme(Brightness.dark, _appearance.themeStyle),
      home: AlbumHomePage(
        albums: _albums,
        onAlbumChanged: _updateAlbum,
        onAlbumDeleted: _deleteAlbum,
        appearance: _appearance,
        onAppearanceChanged: _updateAppearance,
        onAlbumCreated: _createAlbum,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness, PrototypeThemeStyle style) {
    final PrototypePalette palette = paletteFor(style, brightness);

    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: brightness,
      primary: palette.primary,
      secondary: palette.secondary,
      surface: palette.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFFD6C6B5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFFD6C6B5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: palette.primary, width: 1.4),
        ),
        hintStyle: const TextStyle(color: Color(0xFF9E8E80)),
      ),
    );
  }

  void _updateAlbum(AlbumData album) {
    setState(() {
      _albums = _albums.map((AlbumData item) {
        return item.id == album.id ? album : item;
      }).toList();
    });
    unawaited(LocalAlbumStore.saveAlbums(_albums));
  }

  void _updateAppearance(PrototypeAppearance appearance) {
    setState(() {
      _appearance = appearance;
    });
    unawaited(LocalAlbumStore.saveAppearance(_appearance));
  }

  void _createAlbum(AlbumData album) {
    setState(() {
      _albums = <AlbumData>[album, ..._albums];
    });
    unawaited(LocalAlbumStore.saveAlbums(_albums));
  }

  void _deleteAlbum(String albumId) {
    final AlbumData? album = _findAlbum(albumId);
    setState(() {
      _albums = _albums.where((AlbumData item) => item.id != albumId).toList();
    });
    if (album != null) {
      unawaited(LocalAlbumStore.deleteAlbumImages(album));
    }
    unawaited(LocalAlbumStore.saveAlbums(_albums));
  }

  AlbumData? _findAlbum(String albumId) {
    for (final AlbumData album in _albums) {
      if (album.id == albumId) {
        return album;
      }
    }
    return null;
  }

  Future<void> _loadLocalState() async {
    final List<AlbumData>? albums = await LocalAlbumStore.loadAlbums();
    final PrototypeAppearance? appearance =
        await LocalAlbumStore.loadAppearance();
    if (!mounted) {
      return;
    }
    setState(() {
      if (albums != null) {
        _albums = albums;
      }
      if (appearance != null) {
        _appearance = appearance;
      }
    });
  }
}

class PrototypePlaceholderPage extends StatelessWidget {
  const PrototypePlaceholderPage({
    required this.title,
    required this.description,
    required this.icon,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCF7),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFE3D7C8)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E5D6),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Icon(
                          icon,
                          size: 40,
                          color: const Color(0xFF8E6847),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF4A3424),
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFF836F5E),
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 22),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('返回首页'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrototypeOptionTile extends StatelessWidget {
  const _PrototypeOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.68),
                    height: 1.5,
                  ),
                ),
                if (child != null) ...<Widget>[
                  const SizedBox(height: 12),
                  child!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<AlbumData> buildDemoAlbums() {
  return <AlbumData>[
    AlbumData(
      id: 'west-sichuan',
      title: '2024 川西之旅',
      subtitle: '42 张照片 · 2024年10月',
      description: '高山、湖泊和秋色草甸，像把整段旅行放进了木质书架里。',
      style: PhotoStyle.mountainLake,
      photos: <PhotoData>[
        PhotoData(
          id: 'a1',
          title: '在四姑娘山的清晨',
          date: '2024年10月2日',
          note: '清晨的光压在山顶上，湖面平静如镜，四周的空气格外清新，让人心绪慢下来。',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.mountainLake,
        ),
        PhotoData(
          id: 'a2',
          title: '藏寨的小路',
          date: '2024年10月3日',
          note: '傍晚的光线很好，走在安静的小路上，感觉时间都慢了下来。',
          orientation: PhotoOrientation.portrait,
          style: PhotoStyle.oldStreet,
        ),
        PhotoData(
          id: 'a3',
          title: '寺庙前的金色屋檐',
          date: '2024年10月4日',
          note: '云层很低，金色屋檐在冷色山景里格外醒目，像一枚温热的记号。',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.temple,
        ),
        PhotoData(
          id: 'a4',
          title: '草甸与牦牛',
          date: '2024年10月5日',
          note: '牦牛在草甸上慢慢移动，远处的雪山像背景布一样铺开。',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.yakField,
        ),
        PhotoData(
          id: 'a5',
          title: '午后山谷',
          date: '2024年10月6日',
          note: '山谷里的阳光偏暖，阴影拉长之后，层次变得特别丰富。',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.greenValley,
        ),
        PhotoData(
          id: 'a6',
          title: '停在坡上的马群',
          date: '2024年10月7日',
          note: '风很大，草被吹出方向，马群低头吃草，画面非常安静。',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.horses,
        ),
      ],
    ),
    AlbumData(
      id: 'xiamen',
      title: '厦门之行',
      subtitle: '26 张照片 · 2023年8月',
      description: '海边日落和城市小巷，整体颜色更暖，像一本晒过太阳的旅行册。',
      style: PhotoStyle.sunsetSea,
      photos: <PhotoData>[
        PhotoData(
          id: 'b1',
          title: '傍晚的海边',
          date: '2023年8月18日',
          note: '太阳快落下去的时候，海面像铺了一层铜色反光，空气里有一点潮湿的咸味。',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.sunsetSea,
        ),
        PhotoData(
          id: 'b2',
          title: '骑楼街角',
          date: '2023年8月19日',
          note: '转过街角的时候，恰好看到暖黄色的店灯，整个巷子都显得柔软起来。',
          orientation: PhotoOrientation.portrait,
          style: PhotoStyle.cityWarm,
        ),
        PhotoData(
          id: 'b3',
          title: '海边咖啡店',
          date: '2023年8月20日',
          note: '窗边的位置很安静，坐下来之后，外面的海风和屋里的咖啡味混在一起。',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.cafe,
        ),
      ],
    ),
    AlbumData(
      id: 'daily',
      title: '日常小片',
      subtitle: '69 张照片 · 2025年2月',
      description: '桌面、花瓶、阳光和一些微小瞬间，节奏更轻，也更适合原型展示。',
      style: PhotoStyle.sunlitRoom,
      photos: <PhotoData>[
        PhotoData(
          id: 'c1',
          title: '午后窗边',
          date: '2025年2月2日',
          note: '阳光斜着照进来，桌子边缘有一点温热，花瓶的影子很长。',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.sunlitRoom,
        ),
        PhotoData(
          id: 'c2',
          title: '木桌上的相机',
          date: '2025年2月5日',
          note: '准备出门前随手拍了一张，木桌的纹理和金属机身很好看。',
          orientation: PhotoOrientation.portrait,
          style: PhotoStyle.tabletop,
        ),
        PhotoData(
          id: 'c3',
          title: '暖光夜晚',
          date: '2025年2月9日',
          note: '房间灯光比较低，整张图偏暖，看起来像一页安静的日记。',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.nightLamp,
        ),
      ],
    ),
  ];
}

class AlbumHomePage extends StatefulWidget {
  const AlbumHomePage({
    required this.albums,
    required this.onAlbumChanged,
    required this.onAlbumDeleted,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onAlbumCreated,
    super.key,
  });

  final List<AlbumData> albums;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<String> onAlbumDeleted;
  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onAppearanceChanged;
  final ValueChanged<AlbumData> onAlbumCreated;

  @override
  State<AlbumHomePage> createState() => _AlbumHomePageState();
}

class _AlbumHomePageState extends State<AlbumHomePage> {
  late final PageController _pageController;
  double _currentPage = 0;
  HomeSection _section = HomeSection.albums;
  String _searchQuery = '';
  AlbumSortMode _sortMode = AlbumSortMode.recent;

  List<AlbumData> get _visibleAlbums => filterAndSortAlbums(
    albumsForSection(widget.albums, _section),
    searchQuery: _searchQuery,
    sortMode: _sortMode,
  );

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.64);
    _pageController.addListener(_handlePageChanged);
  }

  @override
  void dispose() {
    _pageController
      ..removeListener(_handlePageChanged)
      ..dispose();
    super.dispose();
  }

  void _handlePageChanged() {
    setState(() {
      _currentPage =
          _pageController.page ?? _pageController.initialPage.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;
    final Color background = Theme.of(context).scaffoldBackgroundColor;
    final Color surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color.alphaBlend(
                Colors.white.withValues(alpha: 0.26),
                background,
              ),
              Color.alphaBlend(
                Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
                surface,
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: isDesktop
              ? _DesktopHomeLayout(
                  albums: _visibleAlbums,
                  onAlbumChanged: widget.onAlbumChanged,
                  onAlbumDeleted: widget.onAlbumDeleted,
                  appearance: widget.appearance,
                  onAppearanceChanged: widget.onAppearanceChanged,
                  onAlbumCreated: widget.onAlbumCreated,
                  section: _section,
                  onSectionSelected: _selectSection,
                  searchQuery: _searchQuery,
                  sortMode: _sortMode,
                  onSearchChanged: _updateSearchQuery,
                  onSortChanged: _updateSortMode,
                  hasActiveSearch: _searchQuery.trim().isNotEmpty,
                  currentPage: _currentPage,
                  controller: _pageController,
                )
              : _MobileHomeLayout(
                  albums: _visibleAlbums,
                  onAlbumChanged: widget.onAlbumChanged,
                  onAlbumDeleted: widget.onAlbumDeleted,
                  appearance: widget.appearance,
                  onAppearanceChanged: widget.onAppearanceChanged,
                  onAlbumCreated: widget.onAlbumCreated,
                  section: _section,
                  onSectionSelected: _selectSection,
                  searchQuery: _searchQuery,
                  sortMode: _sortMode,
                  onSearchChanged: _updateSearchQuery,
                  onSortChanged: _updateSortMode,
                  hasActiveSearch: _searchQuery.trim().isNotEmpty,
                  currentPage: _currentPage,
                  controller: _pageController,
                ),
        ),
      ),
    );
  }

  void _selectSection(HomeSection section) {
    setState(() {
      _section = section;
      _currentPage = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
      _currentPage = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }

  void _updateSortMode(AlbumSortMode mode) {
    setState(() {
      _sortMode = mode;
      _currentPage = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }
}

class _DesktopHomeLayout extends StatelessWidget {
  const _DesktopHomeLayout({
    required this.albums,
    required this.onAlbumChanged,
    required this.onAlbumDeleted,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onAlbumCreated,
    required this.section,
    required this.onSectionSelected,
    required this.searchQuery,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.hasActiveSearch,
    required this.currentPage,
    required this.controller,
  });

  final List<AlbumData> albums;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<String> onAlbumDeleted;
  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onAppearanceChanged;
  final ValueChanged<AlbumData> onAlbumCreated;
  final HomeSection section;
  final ValueChanged<HomeSection> onSectionSelected;
  final String searchQuery;
  final AlbumSortMode sortMode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AlbumSortMode> onSortChanged;
  final bool hasActiveSearch;
  final double currentPage;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 104,
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _SidebarLabel(
                icon: Icons.auto_stories_rounded,
                label: '电子相册',
              ),
              const SizedBox(height: 28),
              _SidebarItem(
                icon: Icons.menu_book_rounded,
                label: '相册',
                onTap: () => onSectionSelected(HomeSection.albums),
              ),
              _SidebarItem(
                icon: Icons.photo_library_outlined,
                label: '回忆',
                onTap: () => onSectionSelected(HomeSection.memories),
              ),
              _SidebarItem(
                icon: Icons.favorite_border_rounded,
                label: '收藏',
                onTap: () => onSectionSelected(HomeSection.favorites),
              ),
              _SidebarItem(
                icon: Icons.history_rounded,
                label: '最近添加',
                onTap: () => onSectionSelected(HomeSection.recent),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => showPrototypeSettingsSheet(
                  context,
                  appearance: appearance,
                  onChanged: onAppearanceChanged,
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _HomeHeader(
                  appearance: appearance,
                  onAppearanceChanged: onAppearanceChanged,
                  section: section,
                  searchQuery: searchQuery,
                  sortMode: sortMode,
                  onSearchChanged: onSearchChanged,
                  onSortChanged: onSortChanged,
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: _ShelfScene(
                    albums: albums,
                    onAlbumChanged: onAlbumChanged,
                    onAlbumDeleted: onAlbumDeleted,
                    onAlbumCreated: onAlbumCreated,
                    currentPage: currentPage,
                    controller: controller,
                    section: section,
                    hasActiveSearch: hasActiveSearch,
                    desktop: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileHomeLayout extends StatelessWidget {
  const _MobileHomeLayout({
    required this.albums,
    required this.onAlbumChanged,
    required this.onAlbumDeleted,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onAlbumCreated,
    required this.section,
    required this.onSectionSelected,
    required this.searchQuery,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.hasActiveSearch,
    required this.currentPage,
    required this.controller,
  });

  final List<AlbumData> albums;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<String> onAlbumDeleted;
  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onAppearanceChanged;
  final ValueChanged<AlbumData> onAlbumCreated;
  final HomeSection section;
  final ValueChanged<HomeSection> onSectionSelected;
  final String searchQuery;
  final AlbumSortMode sortMode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AlbumSortMode> onSortChanged;
  final bool hasActiveSearch;
  final double currentPage;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: _HomeHeader(
            appearance: appearance,
            onAppearanceChanged: onAppearanceChanged,
            section: section,
            searchQuery: searchQuery,
            sortMode: sortMode,
            onSearchChanged: onSearchChanged,
            onSortChanged: onSortChanged,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            child: _ShelfScene(
              albums: albums,
              onAlbumChanged: onAlbumChanged,
              onAlbumDeleted: onAlbumDeleted,
              onAlbumCreated: onAlbumCreated,
              currentPage: currentPage,
              controller: controller,
              section: section,
              hasActiveSearch: hasActiveSearch,
              desktop: false,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _NavItem(
                icon: Icons.menu_book_rounded,
                label: '相册',
                active: section == HomeSection.albums,
                onTap: () => onSectionSelected(HomeSection.albums),
              ),
              _NavItem(
                icon: Icons.photo_library_outlined,
                label: '回忆',
                active: section == HomeSection.memories,
                onTap: () => onSectionSelected(HomeSection.memories),
              ),
              _NavItem(
                icon: Icons.favorite_border_rounded,
                label: '收藏',
                active: section == HomeSection.favorites,
                onTap: () => onSectionSelected(HomeSection.favorites),
              ),
              _NavItem(
                icon: Icons.history_rounded,
                label: '最近',
                active: section == HomeSection.recent,
                onTap: () => onSectionSelected(HomeSection.recent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.appearance,
    required this.onAppearanceChanged,
    required this.section,
    required this.searchQuery,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onSortChanged,
  });

  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onAppearanceChanged;
  final HomeSection section;
  final String searchQuery;
  final AlbumSortMode sortMode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AlbumSortMode> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    homeSectionTitle(section),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    homeSectionSubtitle(section),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.66),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => showPrototypeSettingsSheet(
                context,
                appearance: appearance,
                onChanged: onAppearanceChanged,
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              child: TextFormField(
                initialValue: searchQuery,
                onChanged: onSearchChanged,
                decoration: const InputDecoration(
                  hintText: '搜索相册名称或描述',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(width: 12),
            PopupMenuButton<AlbumSortMode>(
              tooltip: '排序方式',
              initialValue: sortMode,
              onSelected: onSortChanged,
              itemBuilder: (BuildContext context) {
                return AlbumSortMode.values.map((AlbumSortMode mode) {
                  return PopupMenuItem<AlbumSortMode>(
                    value: mode,
                    child: Text(albumSortModeLabel(mode)),
                  );
                }).toList();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.16),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.swap_vert_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(albumSortModeLabel(sortMode)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShelfScene extends StatelessWidget {
  const _ShelfScene({
    required this.albums,
    required this.onAlbumChanged,
    required this.onAlbumDeleted,
    required this.onAlbumCreated,
    required this.currentPage,
    required this.controller,
    required this.section,
    required this.hasActiveSearch,
    required this.desktop,
  });

  final List<AlbumData> albums;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<String> onAlbumDeleted;
  final ValueChanged<AlbumData> onAlbumCreated;
  final double currentPage;
  final PageController controller;
  final HomeSection section;
  final bool hasActiveSearch;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double sceneHeight = desktop ? 520 : constraints.maxHeight;

        return Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: desktop ? 26 : 18,
                        vertical: desktop ? 0 : 12,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(34),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              Color.alphaBlend(
                                Theme.of(context).colorScheme.surface,
                                Theme.of(context).scaffoldBackgroundColor,
                              ),
                              Theme.of(
                                context,
                              ).colorScheme.secondary.withValues(alpha: 0.22),
                            ],
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.10),
                              blurRadius: 20,
                              offset: Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: <Widget>[
                            Positioned(
                              right: desktop ? 72 : 22,
                              top: desktop ? 54 : 32,
                              child: _DecorPlant(height: desktop ? 138 : 110),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: sceneHeight,
                    child: PageView.builder(
                      controller: controller,
                      itemCount: albums.length,
                      itemBuilder: (BuildContext context, int index) {
                        final AlbumData album = albums[index];
                        final double delta = index - currentPage;
                        final double scale = (1 - (delta.abs() * 0.16)).clamp(
                          0.78,
                          1.0,
                        );
                        final double angle = delta * 0.18;
                        final bool active = delta.abs() < 0.5;

                        return Transform.translate(
                          offset: Offset(delta * -14, desktop ? 10 : 0),
                          child: Transform.scale(
                            scale: scale,
                            child: Transform(
                              alignment: Alignment.bottomCenter,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..rotateY(angle),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (BuildContext context) {
                                        return AlbumDetailPage(
                                          album: album,
                                          onAlbumChanged: onAlbumChanged,
                                        );
                                      },
                                    ),
                                  );
                                },
                                child: _AlbumBookCard(
                                  album: album,
                                  active: active,
                                  onEdit: () => _editAlbum(context, album),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    left: desktop ? 38 : 8,
                    child: _ArrowButton(
                      icon: Icons.chevron_left_rounded,
                      onPressed: () => _animateTo(context, -1),
                    ),
                  ),
                  Positioned(
                    right: desktop ? 38 : 8,
                    child: _ArrowButton(
                      icon: Icons.chevron_right_rounded,
                      onPressed: () => _animateTo(context, 1),
                    ),
                  ),
                ],
              ),
            ),
            if (albums.isEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.14),
                  ),
                ),
                child: Text(
                  hasActiveSearch
                      ? '没有找到匹配的相册。'
                      : section == HomeSection.favorites
                      ? '当前没有可展示的收藏相册。'
                      : '当前没有可展示的相册。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(albums.length, (int index) {
                final bool selected = (currentPage.round()) == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: selected ? 22 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: desktop ? 180 : 168,
              child: ElevatedButton.icon(
                onPressed: () => _createAlbum(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('创建相册'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _animateTo(BuildContext context, int offset) {
    if (albums.isEmpty) {
      return;
    }
    final int current = controller.page?.round() ?? 0;
    final int target = (current + offset).clamp(0, albums.length - 1);
    controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _editAlbum(BuildContext context, AlbumData album) async {
    final _AlbumEditorResult? result = await _showAlbumEditorDialog(
      context,
      title: '编辑相册',
      initialName: album.title,
      initialStyle: album.style,
      initialCoverPhotoId: album.coverPhoto?.id,
      photos: album.photos,
      submitLabel: '保存修改',
    );
    if (!context.mounted || result == null) {
      return;
    }
    if (result.deleteAlbum) {
      final bool confirmed = await _confirmDeleteAlbum(context, album);
      if (!context.mounted || !confirmed) {
        return;
      }
      onAlbumDeleted(album.id);
      return;
    }
    if (result.name.trim().isEmpty) {
      return;
    }
    onAlbumChanged(
      album.copyWith(
        title: result.name.trim(),
        coverPhotoId: result.coverPhotoId,
      ),
    );
  }

  Future<void> _createAlbum(BuildContext context) async {
    final _AlbumEditorResult? result = await _showAlbumEditorDialog(
      context,
      title: '创建相册',
      initialName: '',
      initialStyle: albums.isEmpty ? PhotoStyle.sunlitRoom : albums.first.style,
      photos: const <PhotoData>[],
      submitLabel: '创建相册',
    );
    if (result == null || result.name.trim().isEmpty) {
      return;
    }
    final DateTime now = DateTime.now();
    final String monthText = '${now.year}年${now.month}月';
    final String albumId = 'album-${now.microsecondsSinceEpoch}';
    PhotoData? coverPhoto;
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (image != null) {
      final String storedPath = await LocalAlbumStore.persistPickedImage(
        image,
        albumId: albumId,
      );
      final PhotoOrientation orientation = await detectPhotoOrientation(
        storedPath,
      );
      coverPhoto = PhotoData(
        id: 'photo-${DateTime.now().microsecondsSinceEpoch}',
        title: '相册封面',
        date: formatAlbumDate(DateTime.now()),
        note: '创建相册时选择的封面图片。',
        orientation: orientation,
        style: result.style,
        imagePath: storedPath,
      );
    }
    onAlbumCreated(
      AlbumData(
        id: albumId,
        title: result.name.trim(),
        subtitle: '${coverPhoto == null ? 0 : 1} 张照片 · $monthText',
        description: coverPhoto == null
            ? '新建相册，等待你继续添加照片和文字。'
            : '新建相册，并已为它选择封面图片。',
        style: result.style,
        photos: coverPhoto == null
            ? const <PhotoData>[]
            : <PhotoData>[coverPhoto],
        coverPhotoId: coverPhoto?.id,
      ),
    );
  }

  Future<bool> _confirmDeleteAlbum(
    BuildContext context,
    AlbumData album,
  ) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除相册'),
          content: Text('确认删除“${album.title}”及其中全部照片吗？此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<_AlbumEditorResult?> _showAlbumEditorDialog(
    BuildContext context, {
    required String title,
    required String initialName,
    required PhotoStyle initialStyle,
    String? initialCoverPhotoId,
    required List<PhotoData> photos,
    required String submitLabel,
  }) async {
    String draftName = initialName;
    PhotoStyle draftStyle = initialStyle;
    String? draftCoverPhotoId = initialCoverPhotoId;
    final bool editingExistingAlbum = photos.isNotEmpty;
    final _AlbumEditorResult? result = await showDialog<_AlbumEditorResult>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text(title),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextFormField(
                        initialValue: initialName,
                        autofocus: true,
                        onChanged: (String value) {
                          draftName = value;
                        },
                        decoration: const InputDecoration(hintText: '输入相册名称'),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        editingExistingAlbum ? '选择相册封面' : '选择封面风格',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      if (editingExistingAlbum)
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: photos.map((PhotoData photo) {
                            final bool selected = photo.id == draftCoverPhotoId;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  draftCoverPhotoId = photo.id;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 104,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.primary
                                              .withValues(alpha: 0.18),
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 92,
                                        height: 78,
                                        child: PhotoVisual(photo: photo),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      photo.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: PhotoStyle.values.map((PhotoStyle style) {
                            final bool selected = style == draftStyle;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  draftStyle = style;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 104,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.primary
                                              .withValues(alpha: 0.18),
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 92,
                                        height: 78,
                                        child: ScenicArtwork(style: style),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      photoStyleLabel(style),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      if (editingExistingAlbum) ...<Widget>[
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  draftCoverPhotoId = null;
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('恢复默认封面'),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop(
                                  const _AlbumEditorResult(
                                    name: '',
                                    style: PhotoStyle.sunlitRoom,
                                    deleteAlbum: true,
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                              ),
                              label: const Text(
                                '删除相册',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _AlbumEditorResult(
                        name: draftName,
                        style: draftStyle,
                        coverPhotoId: draftCoverPhotoId,
                      ),
                    );
                  },
                  child: Text(submitLabel),
                ),
              ],
            );
          },
        );
      },
    );
    return result;
  }
}

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({
    required this.album,
    required this.onAlbumChanged,
    super.key,
  });

  final AlbumData album;
  final ValueChanged<AlbumData> onAlbumChanged;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  late AlbumData _album;
  bool _isSelectionMode = false;
  final Set<String> _selectedPhotoIds = <String>{};

  @override
  void initState() {
    super.initState();
    _album = widget.album;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                onPressed: _exitSelectionMode,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: _isSelectionMode
            ? Text('已选择 ${_selectedPhotoIds.length} 张')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(_album.title),
                  Text(
                    _album.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8B7765),
                    ),
                  ),
                ],
              ),
        actions: <Widget>[
          if (_isSelectionMode)
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(
                _selectedPhotoIds.length == _album.photos.length
                    ? '取消全选'
                    : '全选',
              ),
            ),
          if (_isSelectionMode)
            IconButton(
              onPressed: _selectedPhotoIds.isEmpty
                  ? null
                  : _deleteSelectedPhotos,
              tooltip: '批量删除',
              icon: const Icon(Icons.delete_outline_rounded),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: () => _openAddPhotoPage(context),
                child: const Text('添加照片'),
              ),
            ),
        ],
      ),
      floatingActionButton: isDesktop
          ? null
          : _isSelectionMode
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF9A6F47),
              foregroundColor: Colors.white,
              onPressed: _selectedPhotoIds.isEmpty
                  ? null
                  : _deleteSelectedPhotos,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text('删除 ${_selectedPhotoIds.length} 张'),
            )
          : FloatingActionButton(
              backgroundColor: const Color(0xFF9A6F47),
              foregroundColor: Colors.white,
              onPressed: () => _openAddPhotoPage(context),
              child: const Icon(Icons.add_rounded),
            ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 22 : 14,
            8,
            isDesktop ? 22 : 14,
            _isSelectionMode && !isDesktop ? 88 : 16,
          ),
          child: MasonryPhotoGrid(
            album: _album,
            onAlbumChanged: _replaceAlbum,
            selectionMode: _isSelectionMode,
            selectedPhotoIds: _selectedPhotoIds,
            onToggleSelection: _togglePhotoSelection,
            onStartSelection: _startSelection,
          ),
        ),
      ),
    );
  }

  Future<void> _openAddPhotoPage(BuildContext context) async {
    final AlbumData? updatedAlbum = await Navigator.of(context).push<AlbumData>(
      MaterialPageRoute<AlbumData>(
        builder: (BuildContext context) => AddPhotoPage(album: _album),
      ),
    );
    if (!mounted || updatedAlbum == null) {
      return;
    }
    setState(() {
      _album = updatedAlbum;
    });
    widget.onAlbumChanged(updatedAlbum);
  }

  void _replaceAlbum(AlbumData album) {
    setState(() {
      _album = album;
      _selectedPhotoIds.removeWhere((String id) {
        return !_album.photos.any((PhotoData photo) => photo.id == id);
      });
      if (_selectedPhotoIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
    widget.onAlbumChanged(album);
  }

  void _startSelection(PhotoData photo) {
    setState(() {
      _isSelectionMode = true;
      _selectedPhotoIds
        ..clear()
        ..add(photo.id);
    });
  }

  void _togglePhotoSelection(PhotoData photo) {
    setState(() {
      _isSelectionMode = true;
      if (_selectedPhotoIds.contains(photo.id)) {
        _selectedPhotoIds.remove(photo.id);
      } else {
        _selectedPhotoIds.add(photo.id);
      }
      if (_selectedPhotoIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedPhotoIds.clear();
    });
  }

  void _toggleSelectAll() {
    if (_album.photos.isEmpty) {
      return;
    }
    setState(() {
      _isSelectionMode = true;
      if (_selectedPhotoIds.length == _album.photos.length) {
        _selectedPhotoIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedPhotoIds
          ..clear()
          ..addAll(_album.photos.map((PhotoData photo) => photo.id));
      }
    });
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotoIds.isEmpty) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('批量删除照片'),
          content: Text('确定删除已选择的 ${_selectedPhotoIds.length} 张照片吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    final List<PhotoData> deletedPhotos = _album.photos.where((
      PhotoData photo,
    ) {
      return _selectedPhotoIds.contains(photo.id);
    }).toList();
    for (final PhotoData photo in deletedPhotos) {
      await LocalAlbumStore.deleteManagedImage(photo.imagePath);
    }
    if (!mounted) {
      return;
    }

    final AlbumData updatedAlbum = _album.withRemovedPhotos(_selectedPhotoIds);
    setState(() {
      _album = updatedAlbum;
      _isSelectionMode = false;
      _selectedPhotoIds.clear();
    });
    widget.onAlbumChanged(updatedAlbum);
    showPrototypeMessage(context, '已删除 ${deletedPhotos.length} 张照片');
  }
}

class MasonryPhotoGrid extends StatelessWidget {
  const MasonryPhotoGrid({
    required this.album,
    required this.onAlbumChanged,
    required this.selectionMode,
    required this.selectedPhotoIds,
    required this.onToggleSelection,
    required this.onStartSelection,
    super.key,
  });

  final AlbumData album;
  final ValueChanged<AlbumData> onAlbumChanged;
  final bool selectionMode;
  final Set<String> selectedPhotoIds;
  final ValueChanged<PhotoData> onToggleSelection;
  final ValueChanged<PhotoData> onStartSelection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = width >= 1100
            ? 4
            : width >= 760
            ? 3
            : 2;
        final double gap = 12;
        final double itemWidth = (width - ((columns - 1) * gap)) / columns;
        final List<List<PhotoData>> lanes = List<List<PhotoData>>.generate(
          columns,
          (_) => <PhotoData>[],
        );
        final List<double> heights = List<double>.filled(columns, 0);

        for (final PhotoData photo in album.photos) {
          int lane = 0;
          for (int index = 1; index < columns; index++) {
            if (heights[index] < heights[lane]) {
              lane = index;
            }
          }
          lanes[lane].add(photo);
          heights[lane] += _itemHeight(photo, itemWidth) + gap;
        }

        return SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(columns, (int column) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: column == 0 ? 0 : gap),
                  child: Column(
                    children: lanes[column].map((PhotoData photo) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PhotoTile(
                          photo: photo,
                          width: itemWidth,
                          selectionMode: selectionMode,
                          selected: selectedPhotoIds.contains(photo.id),
                          onTap: () {
                            if (selectionMode) {
                              onToggleSelection(photo);
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) {
                                  return PhotoDetailPage(
                                    album: album,
                                    photos: album.photos,
                                    initialIndex: album.photos.indexOf(photo),
                                    onAlbumChanged: onAlbumChanged,
                                  );
                                },
                              ),
                            );
                          },
                          onLongPress: () => onStartSelection(photo),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  double _itemHeight(PhotoData photo, double width) {
    final double ratio = photo.orientation == PhotoOrientation.portrait
        ? 1.26
        : 0.78;
    return width * ratio;
  }
}

class AddPhotoPage extends StatefulWidget {
  const AddPhotoPage({required this.album, super.key});

  final AlbumData album;

  @override
  State<AddPhotoPage> createState() => _AddPhotoPageState();
}

class _AddPhotoPageState extends State<AddPhotoPage> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加照片'),
        actions: <Widget>[
          IconButton(
            onPressed: _isSaving ? null : _savePhoto,
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 5, child: _buildPreviewCard(context)),
                        const SizedBox(width: 18),
                        Expanded(flex: 4, child: _buildFormCard(context)),
                      ],
                    )
                  : Column(
                      children: <Widget>[
                        _buildPreviewCard(context),
                        const SizedBox(height: 18),
                        _buildFormCard(context),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE3D7C8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '图片占位区',
              style: ThemeData.light().textTheme.titleLarge?.copyWith(
                color: const Color(0xFF4F3827),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _isSaving ? null : () => _pickImage(context),
              child: AspectRatio(
                aspectRatio: 1.1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _selectedImage == null
                      ? Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0xFFDCEBFA),
                                Color(0xFF88A9C4),
                              ],
                            ),
                          ),
                          child: const Stack(
                            children: <Widget>[
                              Positioned.fill(
                                child: ScenicArtwork(
                                  style: PhotoStyle.mountainLake,
                                ),
                              ),
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 44,
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      '点击选择图片',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            Image.file(
                              File(_selectedImage!.path),
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              right: 14,
                              bottom: 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.52),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Text(
                                  '重新选择',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE3D7C8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '备注 / 感想',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF4F3827),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 8,
              maxLength: 500,
              decoration: const InputDecoration(hintText: '写下这张照片背后的故事...'),
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF9F3EB),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2D5C7)),
              ),
              child: ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('选择照片'),
                subtitle: Text(
                  _selectedImage == null ? '从本地选择一张图片' : _selectedImage!.name,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _isSaving ? null : () => _pickImage(context),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _isSaving ? null : _savePhoto,
              child: Text(_isSaving ? '保存中...' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (!mounted || image == null) {
      return;
    }
    setState(() {
      _selectedImage = image;
    });
  }

  Future<void> _savePhoto() async {
    final XFile? image = _selectedImage;
    final String note = _controller.text.trim();
    if (image == null) {
      showPrototypeMessage(context, '请先选择一张图片。');
      return;
    }
    if (note.isEmpty) {
      showPrototypeMessage(context, '请先填写备注内容。');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final String storedPath = await LocalAlbumStore.persistPickedImage(
      image,
      albumId: widget.album.id,
    );
    final PhotoOrientation orientation = await detectPhotoOrientation(
      storedPath,
    );
    final String dateText = formatAlbumDate(DateTime.now());
    final PhotoData photo = PhotoData(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      title: derivePhotoTitle(note),
      date: dateText,
      note: note,
      orientation: orientation,
      style: widget.album.style,
      imagePath: storedPath,
    );
    final AlbumData updatedAlbum = widget.album.withInsertedPhoto(photo);

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(updatedAlbum);
  }
}

class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage({
    required this.album,
    required this.photos,
    required this.initialIndex,
    required this.onAlbumChanged,
    super.key,
  });

  final AlbumData album;
  final List<PhotoData> photos;
  final int initialIndex;
  final ValueChanged<AlbumData> onAlbumChanged;

  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage> {
  late int _index;
  late List<PhotoData> _photos;
  late TextEditingController _noteController;
  double _rotationTurns = 0;
  double _zoom = 1;
  bool _isEditingNote = false;

  PhotoData get photo => _photos[_index];

  @override
  void initState() {
    super.initState();
    _photos = List<PhotoData>.from(widget.photos);
    _index = widget.initialIndex;
    _noteController = TextEditingController(text: photo.note);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${_photos.length}'),
        actions: <Widget>[
          IconButton(
            onPressed: _deleteCurrentPhoto,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          IconButton(
            onPressed: () => showPrototypeMessage(context, '收藏功能将在后续版本补上。'),
            icon: const Icon(Icons.favorite_border_rounded),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => FullscreenPhotoPage(
                    photo: photo,
                    initialTurns: _rotationTurns,
                    initialZoom: _zoom,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.fullscreen_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 980 : double.infinity,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 24 : 14,
                8,
                isDesktop ? 24 : 14,
                16,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCF7),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFE3D7C8)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: _LandscapeDetailLayout(
                          photo: photo,
                          zoom: _zoom,
                          turns: _rotationTurns,
                          toolbar: _buildToolbar(),
                          textPanel: _buildTextPanel(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          IconButton(
                            onPressed: _index == 0 ? null : _goPrevious,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                widget.album.title,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF8B7765)),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _index == _photos.length - 1
                                ? null
                                : _goNext,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goPrevious() {
    setState(() {
      _index -= 1;
      _rotationTurns = 0;
      _zoom = 1;
      _isEditingNote = false;
      _noteController.text = photo.note;
    });
  }

  void _goNext() {
    setState(() {
      _index += 1;
      _rotationTurns = 0;
      _zoom = 1;
      _isEditingNote = false;
      _noteController.text = photo.note;
    });
  }

  Widget _buildToolbar() {
    return _DetailToolbar(
      onRotate: () {
        setState(() {
          _rotationTurns += 0.25;
        });
      },
      onZoomIn: () {
        setState(() {
          _zoom = (_zoom + 0.2).clamp(1.0, 2.0);
        });
      },
      onZoomOut: () {
        setState(() {
          _zoom = (_zoom - 0.2).clamp(0.8, 2.0);
        });
      },
    );
  }

  Widget _buildTextPanel() {
    return _PhotoTextPanel(
      photo: photo,
      compact: photo.orientation == PhotoOrientation.portrait,
      isEditing: _isEditingNote,
      controller: _noteController,
      onEdit: () {
        setState(() {
          _isEditingNote = true;
        });
      },
      onCancel: () {
        setState(() {
          _isEditingNote = false;
          _noteController.text = photo.note;
        });
      },
      onSave: _saveNote,
    );
  }

  void _saveNote() {
    final String nextNote = _noteController.text.trim();
    if (nextNote.isEmpty) {
      showPrototypeMessage(context, '文字内容不能为空。');
      return;
    }
    final PhotoData updatedPhoto = photo.copyWith(note: nextNote);
    setState(() {
      _photos[_index] = updatedPhoto;
      _isEditingNote = false;
    });
    final AlbumData updatedAlbum = widget.album.copyWith(
      photos: List<PhotoData>.from(_photos),
    );
    widget.onAlbumChanged(updatedAlbum);
  }

  Future<void> _deleteCurrentPhoto() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除照片'),
          content: Text('确认删除“${photo.title}”吗？此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await LocalAlbumStore.deleteManagedImage(photo.imagePath);
    final AlbumData updatedAlbum = widget.album.withRemovedPhoto(photo.id);
    if (!mounted) {
      return;
    }
    widget.onAlbumChanged(updatedAlbum);
    Navigator.of(context).pop();
  }
}

class FullscreenPhotoPage extends StatefulWidget {
  const FullscreenPhotoPage({
    required this.photo,
    required this.initialTurns,
    required this.initialZoom,
    super.key,
  });

  final PhotoData photo;
  final double initialTurns;
  final double initialZoom;

  @override
  State<FullscreenPhotoPage> createState() => _FullscreenPhotoPageState();
}

class _FullscreenPhotoPageState extends State<FullscreenPhotoPage> {
  late double _turns;
  late double _zoom;

  @override
  void initState() {
    super.initState();
    _turns = widget.initialTurns;
    _zoom = widget.initialZoom;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.photo.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: AspectRatio(
                    aspectRatio:
                        widget.photo.orientation == PhotoOrientation.portrait
                        ? 0.72
                        : 1.58,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 30,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Transform.rotate(
                          angle: math.pi * 2 * _turns,
                          child: Transform.scale(
                            scale: _zoom,
                            child: PhotoVisual(photo: widget.photo),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _DarkActionButton(
                      icon: Icons.remove_rounded,
                      label: '缩小',
                      onTap: () {
                        setState(() {
                          _zoom = (_zoom - 0.2).clamp(0.8, 2.0);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DarkActionButton(
                      icon: Icons.add_rounded,
                      label: '放大',
                      onTap: () {
                        setState(() {
                          _zoom = (_zoom + 0.2).clamp(0.8, 2.0);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DarkActionButton(
                      icon: Icons.rotate_right_rounded,
                      label: '旋转',
                      onTap: () {
                        setState(() {
                          _turns += 0.25;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandscapeDetailLayout extends StatelessWidget {
  const _LandscapeDetailLayout({
    required this.photo,
    required this.zoom,
    required this.turns,
    required this.toolbar,
    required this.textPanel,
  });

  final PhotoData photo;
  final double zoom;
  final double turns;
  final Widget toolbar;
  final Widget textPanel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          flex: 5,
          child: Column(
            children: <Widget>[
              Expanded(
                child: _DetailImageFrame(
                  photo: photo,
                  zoom: zoom,
                  turns: turns,
                ),
              ),
              const SizedBox(height: 12),
              toolbar,
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(flex: 4, child: textPanel),
      ],
    );
  }
}

class _DetailImageFrame extends StatelessWidget {
  const _DetailImageFrame({
    required this.photo,
    required this.zoom,
    required this.turns,
  });

  final PhotoData photo;
  final double zoom;
  final double turns;

  @override
  Widget build(BuildContext context) {
    final double aspectRatio = photo.orientation == PhotoOrientation.portrait
        ? 0.7
        : 1.72;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF0E6DA),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Transform.rotate(
                angle: math.pi * 2 * turns,
                child: Transform.scale(
                  scale: zoom,
                  child: PhotoVisual(photo: photo),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoTextPanel extends StatelessWidget {
  const _PhotoTextPanel({
    required this.photo,
    required this.compact,
    required this.isEditing,
    required this.controller,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  final PhotoData photo;
  final bool compact;
  final bool isEditing;
  final TextEditingController controller;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFDF9F3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 22 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    photo.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF38291D),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isEditing ? '保存文字' : '编辑文字',
                  onPressed: isEditing ? onSave : onEdit,
                  icon: Icon(
                    isEditing ? Icons.check_rounded : Icons.edit_outlined,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              photo.date,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF8D7968)),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: isEditing
                  ? Column(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: controller,
                            maxLines: null,
                            expands: true,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8CABB),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8CABB),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.2,
                                ),
                              ),
                            ),
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  height: 1.7,
                                  color: const Color(0xFF5C4837),
                                ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            children: <Widget>[
                              TextButton(
                                onPressed: onCancel,
                                child: const Text('取消'),
                              ),
                              ElevatedButton(
                                onPressed: onSave,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(88, 44),
                                ),
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Text(
                        photo.note,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.7,
                          color: const Color(0xFF5C4837),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailToolbar extends StatelessWidget {
  const _DetailToolbar({
    required this.onRotate,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onRotate;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7EFE4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _ToolButton(
              icon: Icons.rotate_right_rounded,
              label: '旋转',
              onTap: onRotate,
            ),
            _ToolButton(
              icon: Icons.zoom_in_rounded,
              label: '放大',
              onTap: onZoomIn,
            ),
            _ToolButton(
              icon: Icons.zoom_out_rounded,
              label: '缩小',
              onTap: onZoomOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: const Color(0xFF6E4E35)),
      label: Text(label, style: const TextStyle(color: Color(0xFF6E4E35))),
    );
  }
}

class _DarkActionButton extends StatelessWidget {
  const _DarkActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.width,
    required this.onTap,
    required this.onLongPress,
    required this.selectionMode,
    required this.selected,
  });

  final PhotoData photo;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final double ratio = photo.orientation == PhotoOrientation.portrait
        ? 0.76
        : 1.28;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF7),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? const Color(0xFF9A6F47) : Colors.transparent,
            width: 2,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: width,
              height: width / ratio,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  PhotoVisual(photo: photo),
                  if (selectionMode)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0x55341F11)
                            : const Color(0x22000000),
                      ),
                    ),
                  if (selectionMode)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF9A6F47)
                              : const Color(0xE6FFF8F0),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF9A6F47)
                                : const Color(0xFFCFB396),
                            width: 1.6,
                          ),
                        ),
                        child: Icon(
                          selected
                              ? Icons.check_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF9A6F47),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumBookCard extends StatelessWidget {
  const _AlbumBookCard({
    required this.album,
    required this.active,
    required this.onEdit,
  });

  final AlbumData album;
  final bool active;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final PhotoData? coverPhoto = album.coverPhoto;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 230,
            height: 520,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    margin: EdgeInsets.only(
                      top: active ? 0 : 14,
                      bottom: active ? 14 : 0,
                    ),
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(-0.04),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned(
                          top: 14,
                          bottom: 6,
                          left: 18,
                          child: Container(
                            width: 18,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A281D),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 16,
                                  offset: Offset(8, 0),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 24,
                                offset: Offset(0, 18),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: SizedBox(
                              width: 210,
                              height: 286,
                              child: Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  if (coverPhoto != null)
                                    PhotoVisual(photo: coverPhoto)
                                  else
                                    ScenicArtwork(style: album.style),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: <Color>[
                                          Colors.transparent,
                                          const Color(0x33000000),
                                          const Color(0xB01E140F),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 12,
                                    right: 12,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: onEdit,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        child: Ink(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.88,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                            color: Color(0xFF5A3E2A),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        const Spacer(),
                                        Text(
                                          album.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 24,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          album.subtitle,
                                          style: const TextStyle(
                                            color: Color(0xFFF4E8D7),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFCF7).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE3D7C8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          album.title,
                          style: const TextStyle(
                            color: Color(0xFF4A3424),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          album.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8A7767),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PhotoVisual extends StatelessWidget {
  const PhotoVisual({required this.photo, super.key});

  final PhotoData photo;

  @override
  Widget build(BuildContext context) {
    final String? imagePath = photo.imagePath;
    if (imagePath != null) {
      final File file = File(imagePath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => ScenicArtwork(style: photo.style),
        );
      }
    }
    return ScenicArtwork(style: photo.style);
  }
}

class ScenicArtwork extends StatelessWidget {
  const ScenicArtwork({required this.style, super.key});

  final PhotoStyle style;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ScenicArtworkPainter(style),
      child: const SizedBox.expand(),
    );
  }
}

class ScenicArtworkPainter extends CustomPainter {
  ScenicArtworkPainter(this.style);

  final PhotoStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case PhotoStyle.mountainLake:
        _paintMountainLake(
          canvas,
          size,
          top: const Color(0xFF8FB6D3),
          bottom: const Color(0xFF264A5D),
        );
      case PhotoStyle.oldStreet:
        _paintStreet(canvas, size, warm: true);
      case PhotoStyle.temple:
        _paintTemple(canvas, size);
      case PhotoStyle.yakField:
        _paintField(canvas, size, animal: true);
      case PhotoStyle.greenValley:
        _paintMountainLake(
          canvas,
          size,
          top: const Color(0xFF95B697),
          bottom: const Color(0xFF325444),
        );
      case PhotoStyle.horses:
        _paintField(canvas, size, animal: false);
      case PhotoStyle.sunsetSea:
        _paintSea(canvas, size);
      case PhotoStyle.cityWarm:
        _paintStreet(canvas, size, warm: false);
      case PhotoStyle.cafe:
        _paintCafe(canvas, size);
      case PhotoStyle.sunlitRoom:
        _paintInterior(canvas, size, lamp: false);
      case PhotoStyle.tabletop:
        _paintTable(canvas, size);
      case PhotoStyle.nightLamp:
        _paintInterior(canvas, size, lamp: true);
    }
  }

  void _paintMountainLake(
    Canvas canvas,
    Size size, {
    required Color top,
    required Color bottom,
  }) {
    final Paint sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[top, const Color(0xFFEAF2F7)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    final Paint farMountains = Paint()..color = const Color(0xFFECE7DE);
    final Path farPath = Path()
      ..moveTo(0, size.height * 0.45)
      ..lineTo(size.width * 0.18, size.height * 0.24)
      ..lineTo(size.width * 0.33, size.height * 0.38)
      ..lineTo(size.width * 0.52, size.height * 0.2)
      ..lineTo(size.width * 0.66, size.height * 0.36)
      ..lineTo(size.width * 0.82, size.height * 0.22)
      ..lineTo(size.width, size.height * 0.42)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(farPath, farMountains);

    final Paint nearMountain = Paint()..color = const Color(0xFF274835);
    final Path nearPath = Path()
      ..moveTo(0, size.height * 0.55)
      ..lineTo(size.width * 0.12, size.height * 0.36)
      ..lineTo(size.width * 0.28, size.height * 0.5)
      ..lineTo(size.width * 0.5, size.height * 0.3)
      ..lineTo(size.width * 0.7, size.height * 0.52)
      ..lineTo(size.width * 0.92, size.height * 0.34)
      ..lineTo(size.width, size.height * 0.56)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(nearPath, nearMountain);

    final Paint water = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[const Color(0xFF2A5B6B), bottom],
          ).createShader(
            Rect.fromLTWH(
              0,
              size.height * 0.56,
              size.width,
              size.height * 0.44,
            ),
          );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.56, size.width, size.height * 0.44),
      water,
    );

    final Paint reflection = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.2;
    for (int index = 0; index < 12; index++) {
      final double y = size.height * (0.62 + index * 0.025);
      canvas.drawLine(
        Offset(size.width * 0.12, y),
        Offset(size.width * 0.88, y + 2),
        reflection,
      );
    }
  }

  void _paintStreet(Canvas canvas, Size size, {required bool warm}) {
    final Paint sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: warm
            ? const <Color>[Color(0xFFD3B18D), Color(0xFF6D7B8A)]
            : const <Color>[Color(0xFFB47A4D), Color(0xFF727C94)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    final Paint leftWall = Paint()
      ..color = warm ? const Color(0xFF3E2A20) : const Color(0xFF493126);
    final Paint rightWall = Paint()
      ..color = warm ? const Color(0xFF4B3428) : const Color(0xFF5A4030);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width * 0.42, 0)
        ..lineTo(size.width * 0.24, size.height)
        ..lineTo(0, size.height)
        ..close(),
      leftWall,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.58, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width * 0.76, size.height)
        ..close(),
      rightWall,
    );

    final Paint road = Paint()..color = const Color(0xFF22242A);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.42, 0)
        ..lineTo(size.width * 0.58, 0)
        ..lineTo(size.width * 0.64, size.height)
        ..lineTo(size.width * 0.36, size.height)
        ..close(),
      road,
    );

    final Paint light = Paint()..color = const Color(0x66F5C67A);
    for (int index = 0; index < 5; index++) {
      final double y = size.height * (0.12 + 0.15 * index);
      canvas.drawRect(
        Rect.fromLTWH(size.width * 0.18, y, size.width * 0.08, 8),
        light,
      );
      canvas.drawRect(
        Rect.fromLTWH(size.width * 0.74, y + 10, size.width * 0.08, 8),
        light,
      );
    }
  }

  void _paintTemple(Canvas canvas, Size size) {
    _paintMountainLake(
      canvas,
      size,
      top: const Color(0xFFB0C7D9),
      bottom: const Color(0xFF385055),
    );
    final Paint temple = Paint()..color = const Color(0xFFC58A2E);
    final Paint roof = Paint()..color = const Color(0xFF8B4A22);
    final Rect body = Rect.fromLTWH(
      size.width * 0.56,
      size.height * 0.4,
      size.width * 0.2,
      size.height * 0.24,
    );
    canvas.drawRect(body, temple);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.52, size.height * 0.44)
        ..lineTo(size.width * 0.66, size.height * 0.3)
        ..lineTo(size.width * 0.8, size.height * 0.44)
        ..close(),
      roof,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.48,
        size.height * 0.64,
        size.width * 0.32,
        size.height * 0.04,
      ),
      Paint()..color = const Color(0xFF4A402D),
    );
  }

  void _paintField(Canvas canvas, Size size, {required bool animal}) {
    final Paint sky = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFFBFD6E4), Color(0xFFEFE2C5)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.56, size.width, size.height * 0.44),
      Paint()..color = const Color(0xFF76965B),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * 0.56)
        ..lineTo(size.width * 0.2, size.height * 0.42)
        ..lineTo(size.width * 0.48, size.height * 0.5)
        ..lineTo(size.width * 0.74, size.height * 0.34)
        ..lineTo(size.width, size.height * 0.52)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = const Color(0xFF4F6F46),
    );
    final Paint body = Paint()
      ..color = animal ? const Color(0xFFE9DEC9) : const Color(0xFF463A2F);
    final double y = size.height * 0.68;
    for (int index = 0; index < 3; index++) {
      final double x = size.width * (0.28 + index * 0.18);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 34, height: 22),
        body,
      );
      canvas.drawCircle(Offset(x + 18, y - 6), 8, body);
    }
  }

  void _paintSea(Canvas canvas, Size size) {
    final Paint sky = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFFF8B884), Color(0xFFF6E6C9)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.22),
      28,
      Paint()..color = const Color(0x33FFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.56, size.width, size.height * 0.44),
      Paint()
        ..shader =
            const LinearGradient(
              colors: <Color>[Color(0xFF8C705C), Color(0xFF3B475A)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(
              Rect.fromLTWH(
                0,
                size.height * 0.56,
                size.width,
                size.height * 0.44,
              ),
            ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.74, size.width, size.height * 0.26),
      Paint()..color = const Color(0xFF574233),
    );
    canvas.drawLine(
      Offset(size.width * 0.62, size.height * 0.58),
      Offset(size.width * 0.68, size.height * 0.76),
      Paint()
        ..color = Colors.black87
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      Offset(size.width * 0.6, size.height * 0.55),
      7,
      Paint()..color = Colors.black87,
    );
  }

  void _paintCafe(Canvas canvas, Size size) {
    final Paint bg = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFFCAD6E1), Color(0xFFE6C29F)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.62, size.width, size.height * 0.38),
      Paint()..color = const Color(0xFFC79C6C),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.2,
        size.height * 0.28,
        size.width * 0.6,
        size.height * 0.26,
      ),
      Paint()..color = const Color(0x66FFFFFF),
    );
    canvas.drawCircle(
      Offset(size.width * 0.36, size.height * 0.72),
      18,
      Paint()..color = const Color(0xFF8E6847),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.5, size.height * 0.64, 54, 26),
      Paint()..color = const Color(0xFFFAF5ED),
    );
  }

  void _paintInterior(Canvas canvas, Size size, {required bool lamp}) {
    final Paint wall = Paint()
      ..color = lamp ? const Color(0xFF624A3C) : const Color(0xFFF0E4D6);
    canvas.drawRect(Offset.zero & size, wall);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.72, size.width, size.height * 0.28),
      Paint()..color = const Color(0xFF8D6646),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.16,
        size.width * 0.46,
        size.height * 0.44,
      ),
      Paint()..color = lamp ? const Color(0xFF75573F) : const Color(0xFFF9F5ED),
    );
    if (lamp) {
      canvas.drawCircle(
        Offset(size.width * 0.72, size.height * 0.28),
        34,
        Paint()..color = const Color(0x66F6C875),
      );
      canvas.drawCircle(
        Offset(size.width * 0.72, size.height * 0.28),
        16,
        Paint()..color = const Color(0xFFF6C875),
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(
          size.width * 0.72,
          size.height * 0.18,
          6,
          size.height * 0.42,
        ),
        Paint()..color = const Color(0xFFF3E0B8),
      );
      canvas.drawCircle(
        Offset(size.width * 0.75, size.height * 0.46),
        18,
        Paint()..color = const Color(0xFFB79C72),
      );
    }
  }

  void _paintTable(Canvas canvas, Size size) {
    final Paint bg = Paint()..color = const Color(0xFFEFE3D5);
    canvas.drawRect(Offset.zero & size, bg);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.52, size.width, size.height * 0.48),
      Paint()..color = const Color(0xFF9A724E),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.24,
          size.height * 0.24,
          size.width * 0.34,
          size.height * 0.46,
        ),
        const Radius.circular(18),
      ),
      Paint()..color = const Color(0xFF2B2B2B),
    );
    canvas.drawCircle(
      Offset(size.width * 0.68, size.height * 0.38),
      26,
      Paint()..color = const Color(0xFFC6B295),
    );
    canvas.drawCircle(
      Offset(size.width * 0.68, size.height * 0.38),
      16,
      Paint()..color = const Color(0xFF8E6847),
    );
  }

  @override
  bool shouldRepaint(covariant ScenicArtworkPainter oldDelegate) {
    return oldDelegate.style != style;
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC9B7855),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active
        ? const Color(0xFF8E6847)
        : const Color(0xFF9A8B7D);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarLabel extends StatelessWidget {
  const _SidebarLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFF1E0C8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF6A4B34)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF5A402D),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 18, color: const Color(0xFF8B735D)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Color(0xFF6B5848)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecorPlant extends StatelessWidget {
  const _DecorPlant({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(height * 0.7, height),
      painter: PlantPainter(),
    );
  }
}

class PlantPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint stem = Paint()
      ..color = const Color(0xFF8A6A4F)
      ..strokeWidth = 2;
    final Paint leaf = Paint()..color = const Color(0xFF9A8D5E);
    canvas.drawLine(
      Offset(size.width * 0.52, size.height),
      Offset(size.width * 0.54, size.height * 0.12),
      stem,
    );
    for (int index = 0; index < 5; index++) {
      final double y = size.height * (0.82 - index * 0.14);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.4, y),
          width: 18,
          height: 8,
        ),
        leaf,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.66, y - 10),
          width: 18,
          height: 8,
        ),
        leaf,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.2,
          size.height * 0.84,
          size.width * 0.56,
          size.height * 0.16,
        ),
        const Radius.circular(16),
      ),
      Paint()..color = const Color(0xFFD7C0A8),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class AlbumData {
  const AlbumData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.style,
    required this.photos,
    this.coverPhotoId,
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final PhotoStyle style;
  final List<PhotoData> photos;
  final String? coverPhotoId;

  AlbumData copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? description,
    PhotoStyle? style,
    List<PhotoData>? photos,
    Object? coverPhotoId = _fieldUnset,
  }) {
    return AlbumData(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      description: description ?? this.description,
      style: style ?? this.style,
      photos: photos ?? this.photos,
      coverPhotoId: identical(coverPhotoId, _fieldUnset)
          ? this.coverPhotoId
          : coverPhotoId as String?,
    );
  }

  AlbumData withInsertedPhoto(PhotoData photo) {
    final List<PhotoData> nextPhotos = <PhotoData>[photo, ...photos];
    return copyWith(
      photos: nextPhotos,
      subtitle: _updatedSubtitle(nextPhotos.length),
    );
  }

  AlbumData withUpdatedPhoto(PhotoData photo) {
    final List<PhotoData> nextPhotos = photos.map((PhotoData item) {
      return item.id == photo.id ? photo : item;
    }).toList();
    return copyWith(photos: nextPhotos);
  }

  AlbumData withRemovedPhoto(String photoId) {
    final List<PhotoData> nextPhotos = photos
        .where((PhotoData item) => item.id != photoId)
        .toList();
    return copyWith(
      photos: nextPhotos,
      subtitle: _updatedSubtitle(nextPhotos.length),
      coverPhotoId: coverPhotoId == photoId ? null : coverPhotoId,
    );
  }

  AlbumData withRemovedPhotos(Set<String> photoIds) {
    final List<PhotoData> nextPhotos = photos
        .where((PhotoData item) => !photoIds.contains(item.id))
        .toList();
    return copyWith(
      photos: nextPhotos,
      subtitle: _updatedSubtitle(nextPhotos.length),
      coverPhotoId: photoIds.contains(coverPhotoId) ? null : coverPhotoId,
    );
  }

  PhotoData? get coverPhoto {
    if (coverPhotoId != null) {
      for (final PhotoData photo in photos) {
        if (photo.id == coverPhotoId) {
          return photo;
        }
      }
    }
    if (photos.isEmpty) {
      return null;
    }
    return photos.first;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'style': style.name,
      'coverPhotoId': coverPhotoId,
      'photos': photos.map((PhotoData photo) => photo.toJson()).toList(),
    };
  }

  factory AlbumData.fromJson(Map<String, dynamic> json) {
    return AlbumData(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      description: json['description'] as String,
      style: PhotoStyle.values.byName(json['style'] as String),
      coverPhotoId: json['coverPhotoId'] as String?,
      photos: (json['photos'] as List<dynamic>)
          .map(
            (dynamic item) => PhotoData.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  String _updatedSubtitle(int count) {
    final List<String> parts = subtitle.split('·');
    if (parts.length < 2) {
      return '$count 张照片';
    }
    final String suffix = parts.sublist(1).join('·').trim();
    return '$count 张照片 · $suffix';
  }
}

class PhotoData {
  const PhotoData({
    required this.id,
    required this.title,
    required this.date,
    required this.note,
    required this.orientation,
    required this.style,
    this.imagePath,
  });

  final String id;
  final String title;
  final String date;
  final String note;
  final PhotoOrientation orientation;
  final PhotoStyle style;
  final String? imagePath;

  PhotoData copyWith({
    String? id,
    String? title,
    String? date,
    String? note,
    PhotoOrientation? orientation,
    PhotoStyle? style,
    String? imagePath,
  }) {
    return PhotoData(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      note: note ?? this.note,
      orientation: orientation ?? this.orientation,
      style: style ?? this.style,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'date': date,
      'note': note,
      'orientation': orientation.name,
      'style': style.name,
      'imagePath': imagePath,
    };
  }

  factory PhotoData.fromJson(Map<String, dynamic> json) {
    return PhotoData(
      id: json['id'] as String,
      title: json['title'] as String,
      date: json['date'] as String,
      note: json['note'] as String,
      orientation: PhotoOrientation.values.byName(
        json['orientation'] as String,
      ),
      style: PhotoStyle.values.byName(json['style'] as String),
      imagePath: json['imagePath'] as String?,
    );
  }
}

enum PhotoOrientation { landscape, portrait }

enum PhotoStyle {
  mountainLake,
  oldStreet,
  temple,
  yakField,
  greenValley,
  horses,
  sunsetSea,
  cityWarm,
  cafe,
  sunlitRoom,
  tabletop,
  nightLamp,
}

class _AlbumEditorResult {
  const _AlbumEditorResult({
    required this.name,
    required this.style,
    this.coverPhotoId,
    this.deleteAlbum = false,
  });

  final String name;
  final PhotoStyle style;
  final String? coverPhotoId;
  final bool deleteAlbum;
}
