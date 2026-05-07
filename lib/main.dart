import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:exif/exif.dart';
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
typedef DataActionCallback = Future<void> Function();
typedef TrashRestoreCallback = String Function(TrashPhotoEntry entry);
typedef AlbumsChangedCallback = void Function(List<AlbumData> albums);

class LocalAlbumStore {
  static const String _albumsKey = 'albums_json_v1';
  static const String _appearanceKey = 'appearance_json_v1';
  static const String _recycleBinKey = 'recycle_bin_json_v1';
  static const String _mediaFolderName = 'album_media';
  static const String _backgroundFolderName = 'album_backgrounds';
  static const String _backupMetadataPath = 'backup.json';
  static const String _backupMediaFolder = 'media';
  static const String _backupBackgroundFolder = 'background';

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

  static Future<List<TrashPhotoEntry>?> loadRecycleBin() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_recycleBinKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (dynamic item) =>
              TrashPhotoEntry.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  static Future<void> saveRecycleBin(List<TrashPhotoEntry> entries) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(
      entries.map((TrashPhotoEntry entry) => entry.toJson()).toList(),
    );
    await prefs.setString(_recycleBinKey, raw);
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
    await prefs.setString(_appearanceKey, jsonEncode(appearance.toJson()));
  }

  static Future<void> exportBackup({
    required List<AlbumData> albums,
    required PrototypeAppearance appearance,
    required String targetPath,
  }) async {
    final Archive archive = Archive();
    PrototypeAppearance exportedAppearance = appearance;
    final List<Map<String, dynamic>> exportedAlbums = <Map<String, dynamic>>[];
    for (final AlbumData album in albums) {
      final List<Map<String, dynamic>> exportedPhotos =
          <Map<String, dynamic>>[];
      for (final PhotoData photo in album.photos) {
        final Map<String, dynamic> photoJson = photo.toJson();
        final String? imagePath = photo.imagePath;
        if (imagePath != null && imagePath.isNotEmpty) {
          final File file = File(imagePath);
          if (await file.exists()) {
            final List<int> bytes = await file.readAsBytes();
            final String relativePath =
                '$_backupMediaFolder/${album.id}_${photo.id}${_fileExtension(imagePath)}';
            archive.add(ArchiveFile(relativePath, bytes.length, bytes));
            photoJson['imagePath'] = relativePath;
          } else {
            photoJson['imagePath'] = null;
          }
        }
        exportedPhotos.add(photoJson);
      }
      final Map<String, dynamic> albumJson = album.toJson();
      albumJson['photos'] = exportedPhotos;
      exportedAlbums.add(albumJson);
    }

    final String? backgroundImagePath = appearance.backgroundImagePath;
    if (backgroundImagePath != null && backgroundImagePath.isNotEmpty) {
      final File file = File(backgroundImagePath);
      if (await file.exists()) {
        final List<int> bytes = await file.readAsBytes();
        final String relativePath =
            '$_backupBackgroundFolder/custom_background${_fileExtension(backgroundImagePath)}';
        archive.add(ArchiveFile(relativePath, bytes.length, bytes));
        exportedAppearance = appearance.copyWith(
          backgroundImagePath: relativePath,
        );
      } else {
        exportedAppearance = appearance.copyWith(backgroundImagePath: null);
      }
    }

    archive.add(
      ArchiveFile.string(
        _backupMetadataPath,
        jsonEncode(<String, dynamic>{
          'version': 1,
          'exportedAt': DateTime.now().toIso8601String(),
          'appearance': exportedAppearance.toJson(),
          'albums': exportedAlbums,
        }),
      ),
    );

    final List<int> encoded = ZipEncoder().encode(archive);
    await File(targetPath).writeAsBytes(encoded, flush: true);
  }

  static Future<LocalImportSnapshot> importBackup(String backupPath) async {
    final File backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      throw const FileSystemException('备份文件不存在');
    }

    final List<int> bytes = await backupFile.readAsBytes();
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final ArchiveFile metadataFile =
        archive.findFile(_backupMetadataPath) ??
        (throw const FormatException('备份包缺少 backup.json'));
    final Map<String, dynamic> metadata =
        jsonDecode(utf8.decode(metadataFile.content as List<int>))
            as Map<String, dynamic>;
    PrototypeAppearance appearance = PrototypeAppearance.fromJson(
      metadata['appearance'] as Map<String, dynamic>,
    );
    final List<dynamic> albumsJson =
        metadata['albums'] as List<dynamic>? ??
        (throw const FormatException('备份包缺少相册数据'));

    final List<String> createdFiles = <String>[];
    try {
      final List<AlbumData> albums = <AlbumData>[];
      for (final dynamic albumItem in albumsJson) {
        final Map<String, dynamic> albumJson = Map<String, dynamic>.from(
          albumItem as Map<String, dynamic>,
        );
        final List<dynamic> photosJson =
            albumJson['photos'] as List<dynamic>? ?? <dynamic>[];
        final List<Map<String, dynamic>> importedPhotos =
            <Map<String, dynamic>>[];
        for (final dynamic photoItem in photosJson) {
          final Map<String, dynamic> photoJson = Map<String, dynamic>.from(
            photoItem as Map<String, dynamic>,
          );
          final String? relativePath = photoJson['imagePath'] as String?;
          if (relativePath != null && relativePath.isNotEmpty) {
            final ArchiveFile mediaFile =
                archive.findFile(relativePath) ??
                (throw FormatException('备份包缺少图片：$relativePath'));
            final String importedPath = await _restoreImportedMedia(
              albumId: albumJson['id'] as String,
              photoId: photoJson['id'] as String,
              relativePath: relativePath,
              bytes: mediaFile.content as List<int>,
            );
            createdFiles.add(importedPath);
            photoJson['imagePath'] = importedPath;
          }
          importedPhotos.add(photoJson);
        }
        albumJson['photos'] = importedPhotos;
        albums.add(AlbumData.fromJson(albumJson));
      }
      final String? backgroundImagePath = appearance.backgroundImagePath;
      if (backgroundImagePath != null && backgroundImagePath.isNotEmpty) {
        final ArchiveFile backgroundFile =
            archive.findFile(backgroundImagePath) ??
            (throw FormatException('备份包缺少背景图：$backgroundImagePath'));
        final String importedBackgroundPath = await _restoreImportedBackground(
          relativePath: backgroundImagePath,
          bytes: backgroundFile.content as List<int>,
        );
        createdFiles.add(importedBackgroundPath);
        appearance = appearance.copyWith(
          backgroundImagePath: importedBackgroundPath,
        );
      }
      return LocalImportSnapshot(albums: albums, appearance: appearance);
    } catch (_) {
      for (final String path in createdFiles) {
        final File file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      rethrow;
    }
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

  static Future<String?> duplicateManagedImage(
    String? sourcePath, {
    required String albumId,
  }) async {
    if (sourcePath == null || sourcePath.isEmpty) {
      return null;
    }
    final File sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null;
    }
    final Directory mediaDir = await _mediaDirectory();
    final String extension = _fileExtension(sourcePath);
    final String targetPath =
        '${mediaDir.path}${Platform.pathSeparator}${albumId}_${DateTime.now().microsecondsSinceEpoch}$extension';
    await sourceFile.copy(targetPath);
    return targetPath;
  }

  static Future<String> persistBackgroundImage(String sourcePath) async {
    final Directory backgroundDir = await _backgroundDirectory();
    final String extension = _fileExtension(sourcePath);
    final String targetPath =
        '${backgroundDir.path}${Platform.pathSeparator}custom_background_${DateTime.now().microsecondsSinceEpoch}$extension';
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  static Future<void> deleteManagedBackground(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    final Directory backgroundDir = await _backgroundDirectory();
    if (!path.startsWith(backgroundDir.path)) {
      return;
    }
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
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

  static Future<Directory> _backgroundDirectory() async {
    final Directory root = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(
      '${root.path}${Platform.pathSeparator}$_backgroundFolderName',
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

  static Future<String> _restoreImportedMedia({
    required String albumId,
    required String photoId,
    required String relativePath,
    required List<int> bytes,
  }) async {
    final Directory mediaDir = await _mediaDirectory();
    final String extension = _fileExtension(relativePath);
    final String targetPath =
        '${mediaDir.path}${Platform.pathSeparator}${albumId}_${photoId}_${DateTime.now().microsecondsSinceEpoch}$extension';
    await File(targetPath).writeAsBytes(bytes, flush: true);
    return targetPath;
  }

  static Future<String> _restoreImportedBackground({
    required String relativePath,
    required List<int> bytes,
  }) async {
    final Directory backgroundDir = await _backgroundDirectory();
    final String extension = _fileExtension(relativePath);
    final String targetPath =
        '${backgroundDir.path}${Platform.pathSeparator}custom_background_${DateTime.now().microsecondsSinceEpoch}$extension';
    await File(targetPath).writeAsBytes(bytes, flush: true);
    return targetPath;
  }
}

enum PrototypeThemeStyle { warm, walnut, sage }

enum HomeSection { albums, memories, favorites, trash, recent }

enum AlbumSortMode { recent, photoCount, title }

class PrototypeAppearance {
  const PrototypeAppearance({
    required this.themeMode,
    required this.themeStyle,
    this.backgroundImagePath,
  });

  final ThemeMode themeMode;
  final PrototypeThemeStyle themeStyle;
  final String? backgroundImagePath;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeMode': themeMode.name,
      'themeStyle': themeStyle.name,
      'backgroundImagePath': backgroundImagePath,
    };
  }

  factory PrototypeAppearance.fromJson(Map<String, dynamic> json) {
    return PrototypeAppearance(
      themeMode: ThemeMode.values.byName(json['themeMode'] as String),
      themeStyle: PrototypeThemeStyle.values.byName(
        json['themeStyle'] as String,
      ),
      backgroundImagePath: json['backgroundImagePath'] as String?,
    );
  }

  PrototypeAppearance copyWith({
    ThemeMode? themeMode,
    PrototypeThemeStyle? themeStyle,
    Object? backgroundImagePath = _fieldUnset,
  }) {
    return PrototypeAppearance(
      themeMode: themeMode ?? this.themeMode,
      themeStyle: themeStyle ?? this.themeStyle,
      backgroundImagePath: identical(backgroundImagePath, _fieldUnset)
          ? this.backgroundImagePath
          : backgroundImagePath as String?,
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
    case HomeSection.trash:
      return '回收站';
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
    case HomeSection.trash:
      return '暂存从其他页面删除的照片';
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
      return albums;
    case HomeSection.trash:
      return albums;
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

class FavoritePhotoEntry {
  const FavoritePhotoEntry({
    required this.album,
    required this.photo,
    required this.photoIndex,
  });

  final AlbumData album;
  final PhotoData photo;
  final int photoIndex;
}

class TrashPhotoEntry {
  const TrashPhotoEntry({
    required this.id,
    required this.albumId,
    required this.albumTitle,
    required this.photo,
    required this.originalPhotoIndex,
    required this.deletedAt,
  });

  final String id;
  final String albumId;
  final String albumTitle;
  final PhotoData photo;
  final int originalPhotoIndex;
  final String deletedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'albumId': albumId,
      'albumTitle': albumTitle,
      'photo': photo.toJson(),
      'originalPhotoIndex': originalPhotoIndex,
      'deletedAt': deletedAt,
    };
  }

  factory TrashPhotoEntry.fromJson(Map<String, dynamic> json) {
    return TrashPhotoEntry(
      id: json['id'] as String,
      albumId: json['albumId'] as String,
      albumTitle: json['albumTitle'] as String,
      photo: PhotoData.fromJson(json['photo'] as Map<String, dynamic>),
      originalPhotoIndex: json['originalPhotoIndex'] as int? ?? 0,
      deletedAt: json['deletedAt'] as String,
    );
  }
}

List<FavoritePhotoEntry> favoritePhotoEntries(
  List<AlbumData> albums, {
  required String searchQuery,
}) {
  final String query = searchQuery.trim().toLowerCase();
  final List<FavoritePhotoEntry> entries = <FavoritePhotoEntry>[];
  for (final AlbumData album in albums) {
    for (int index = 0; index < album.photos.length; index += 1) {
      final PhotoData photo = album.photos[index];
      if (!photo.isFavorite) {
        continue;
      }
      if (query.isNotEmpty) {
        final String haystack =
            '${photo.title} ${photo.note} ${photo.date} ${album.title} ${album.description}'
                .toLowerCase();
        if (!haystack.contains(query)) {
          continue;
        }
      }
      entries.add(
        FavoritePhotoEntry(album: album, photo: photo, photoIndex: index),
      );
    }
  }
  entries.sort((FavoritePhotoEntry a, FavoritePhotoEntry b) {
    return b.photo.date.compareTo(a.photo.date);
  });
  return entries;
}

List<TrashPhotoEntry> filterTrashPhotoEntries(
  List<TrashPhotoEntry> entries, {
  required String searchQuery,
}) {
  final String query = searchQuery.trim().toLowerCase();
  if (query.isEmpty) {
    return entries;
  }
  return entries.where((TrashPhotoEntry entry) {
    final String haystack =
        '${entry.photo.title} ${entry.photo.note} ${entry.photo.date} ${entry.albumTitle} ${entry.deletedAt}'
            .toLowerCase();
    return haystack.contains(query);
  }).toList();
}

TrashPhotoEntry createTrashPhotoEntry({
  required AlbumData album,
  required PhotoData photo,
  required int originalPhotoIndex,
}) {
  return TrashPhotoEntry(
    id: '${album.id}_${photo.id}_${DateTime.now().microsecondsSinceEpoch}',
    albumId: album.id,
    albumTitle: album.title,
    photo: photo,
    originalPhotoIndex: originalPhotoIndex,
    deletedAt: DateTime.now().toIso8601String(),
  );
}

DateTime? parseChineseDate(String text) {
  final RegExpMatch? match = RegExp(
    r'^(\d{4})年(\d{1,2})月(\d{1,2})日$',
  ).firstMatch(text);
  if (match == null) {
    return null;
  }
  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final DateTime parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
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

DateTime? parseExifDate(String text) {
  final RegExpMatch? match = RegExp(
    r'^(\d{4}):(\d{1,2}):(\d{1,2})(?: (\d{1,2}):(\d{1,2}):(\d{1,2}))?$',
  ).firstMatch(text.trim());
  if (match == null) {
    return null;
  }
  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final int hour = int.tryParse(match.group(4) ?? '0') ?? 0;
  final int minute = int.tryParse(match.group(5) ?? '0') ?? 0;
  final int second = int.tryParse(match.group(6) ?? '0') ?? 0;
  final DateTime parsed = DateTime(year, month, day, hour, minute, second);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

Future<DateTime> resolvePhotoDate(String path) async {
  try {
    final Map<String, IfdTag> data = await readExifFromBytes(
      await File(path).readAsBytes(),
    );
    for (final String key in <String>[
      'EXIF DateTimeOriginal',
      'EXIF DateTimeDigitized',
      'Image DateTime',
    ]) {
      final IfdTag? tag = data[key];
      if (tag == null) {
        continue;
      }
      final DateTime? parsed = parseExifDate(tag.printable);
      if (parsed != null) {
        return parsed;
      }
    }
  } catch (_) {}
  try {
    return await File(path).lastModified();
  } catch (_) {
    return DateTime.now();
  }
}

String derivePhotoTitle(String note) {
  final String firstLine = note.split('\n').first.trim();
  if (firstLine.isEmpty) {
    return '新的照片';
  }
  return firstLine.length > 18 ? '${firstLine.substring(0, 18)}...' : firstLine;
}

String derivePhotoTitleFromPath(String path) {
  final String separatorNormalized = path.replaceAll('\\', '/');
  final String filename = separatorNormalized.split('/').last.trim();
  final int dotIndex = filename.lastIndexOf('.');
  final String basename = dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
  final String compact = basename.trim();
  if (compact.isEmpty) {
    return '新的照片';
  }
  return compact.length > 18 ? '${compact.substring(0, 18)}...' : compact;
}

Future<void> showPrototypeSettingsSheet(
  BuildContext context, {
  required PrototypeAppearance appearance,
  required ValueChanged<PrototypeAppearance> onChanged,
  required DataActionCallback onExportDataPressed,
  required DataActionCallback onImportDataPressed,
  required DataActionCallback onCustomBackgroundPressed,
  required DataActionCallback onClearBackgroundPressed,
}) {
  final bool isDesktop = MediaQuery.of(context).size.width >= 900;
  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 120,
            vertical: 60,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFFCF7),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFFE6D9CC)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 28,
                    offset: Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 14, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '桌面设置',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF3E2C20),
                                ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                      child: _PrototypeSettingsContent(
                        appearance: appearance,
                        onChanged: onChanged,
                        onExportDataPressed: onExportDataPressed,
                        onImportDataPressed: onImportDataPressed,
                        onCustomBackgroundPressed: onCustomBackgroundPressed,
                        onClearBackgroundPressed: onClearBackgroundPressed,
                        desktop: true,
                      ),
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
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFFFFFCF7),
    builder: (BuildContext context) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: _PrototypeSettingsContent(
              appearance: appearance,
              onChanged: onChanged,
              onExportDataPressed: onExportDataPressed,
              onImportDataPressed: onImportDataPressed,
              onCustomBackgroundPressed: onCustomBackgroundPressed,
              onClearBackgroundPressed: onClearBackgroundPressed,
              desktop: false,
            ),
          ),
        ),
      );
    },
  );
}

class _PrototypeSettingsContent extends StatelessWidget {
  const _PrototypeSettingsContent({
    required this.appearance,
    required this.onChanged,
    required this.onExportDataPressed,
    required this.onImportDataPressed,
    required this.onCustomBackgroundPressed,
    required this.onClearBackgroundPressed,
    required this.desktop,
  });

  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onChanged;
  final DataActionCallback onExportDataPressed;
  final DataActionCallback onImportDataPressed;
  final DataActionCallback onCustomBackgroundPressed;
  final DataActionCallback onClearBackgroundPressed;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          desktop ? '桌面界面设置会立即生效。' : '主题风格和明暗模式会立刻作用到首页、详情页和设置面板。',
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
            borderRadius: BorderRadius.circular(5),
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
                  height: desktop ? 112 : 74,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Theme.of(context).scaffoldBackgroundColor,
                        Theme.of(context).colorScheme.surface,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: desktop ? 112 : 74,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(5),
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
                      width: desktop ? 58 : 46,
                      height: desktop ? 58 : 46,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(5),
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
        _PrototypeOptionTile(
          icon: Icons.wallpaper_outlined,
          title: '自定义背景',
          subtitle: appearance.backgroundImagePath == null
              ? '当前使用默认渐变背景。'
              : '已使用本地背景图，可随时替换或清除。',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: onCustomBackgroundPressed,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(
                  appearance.backgroundImagePath == null ? '选择背景' : '更换背景',
                ),
              ),
              if (appearance.backgroundImagePath != null)
                OutlinedButton.icon(
                  onPressed: onClearBackgroundPressed,
                  icon: const Icon(Icons.layers_clear_outlined, size: 18),
                  label: const Text('清除背景'),
                ),
            ],
          ),
        ),
        const _PrototypeOptionTile(
          icon: Icons.cloud_off_outlined,
          title: '数据状态',
          subtitle: '当前仍为静态假数据，不连接 Supabase',
        ),
        _PrototypeOptionTile(
          icon: Icons.folder_zip_outlined,
          title: '本地数据备份',
          subtitle: '导出当前相册、备注、主题和已托管图片；导入会覆盖当前本地数据。',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onExportDataPressed,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('导出备份'),
              ),
              FilledButton.tonalIcon(
                onPressed: onImportDataPressed,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('导入备份'),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
  List<TrashPhotoEntry> _recycleBin = <TrashPhotoEntry>[];
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
        recycleBin: _recycleBin,
        onAlbumChanged: _updateAlbum,
        onAlbumDeleted: _deleteAlbum,
        onPhotosTrashed: _trashPhotos,
        onAlbumsChanged: _replaceAlbums,
        onTrashPhotoRestored: _restoreTrashPhoto,
        onTrashPhotoDeleted: _deleteTrashPhoto,
        onTrashEmptied: _emptyTrash,
        appearance: _appearance,
        onAppearanceChanged: _updateAppearance,
        onAlbumCreated: _createAlbum,
        onExportDataPressed: _exportLocalData,
        onImportDataPressed: _importLocalData,
        onCustomBackgroundPressed: _pickCustomBackground,
        onClearBackgroundPressed: _clearCustomBackground,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: Color(0xFFD6C6B5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: Color(0xFFD6C6B5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
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

  void _trashPhotos(List<TrashPhotoEntry> entries) {
    setState(() {
      _recycleBin = <TrashPhotoEntry>[...entries, ..._recycleBin];
    });
    unawaited(LocalAlbumStore.saveRecycleBin(_recycleBin));
  }

  String _restoreTrashPhoto(TrashPhotoEntry entry) {
    const String fallbackAlbumTitle = '最近恢复';
    int albumIndex = _albums.indexWhere(
      (AlbumData album) => album.id == entry.albumId,
    );
    bool createdFallbackAlbum = false;
    if (albumIndex == -1) {
      albumIndex = _albums.indexWhere(
        (AlbumData album) => album.title == fallbackAlbumTitle,
      );
      if (albumIndex == -1) {
        final AlbumData fallbackAlbum = AlbumData(
          id: 'album-restored-${DateTime.now().microsecondsSinceEpoch}',
          title: fallbackAlbumTitle,
          subtitle: '0 张照片 · 最近恢复',
          description: '自动接收从回收站恢复、但原相册已不存在的照片。',
          style: entry.photo.style,
          photos: const <PhotoData>[],
        );
        _albums = <AlbumData>[fallbackAlbum, ..._albums];
        albumIndex = 0;
        createdFallbackAlbum = true;
      }
    }
    final AlbumData targetAlbum = _albums[albumIndex];
    PhotoData restoredPhoto = entry.photo;
    final bool hasConflict = targetAlbum.photos.any(
      (PhotoData photo) => photo.id == restoredPhoto.id,
    );
    if (hasConflict) {
      restoredPhoto = restoredPhoto.copyWith(
        id: 'restored-${DateTime.now().microsecondsSinceEpoch}',
      );
    }
    final AlbumData updatedAlbum = targetAlbum.withInsertedPhotoAt(
      entry.originalPhotoIndex,
      restoredPhoto,
    );
    setState(() {
      _albums = _albums.map((AlbumData album) {
        return album.id == updatedAlbum.id ? updatedAlbum : album;
      }).toList();
      _recycleBin = _recycleBin
          .where((TrashPhotoEntry item) => item.id != entry.id)
          .toList();
    });
    unawaited(LocalAlbumStore.saveAlbums(_albums));
    unawaited(LocalAlbumStore.saveRecycleBin(_recycleBin));
    if (createdFallbackAlbum) {
      return fallbackAlbumTitle;
    }
    return targetAlbum.title;
  }

  void _deleteTrashPhoto(TrashPhotoEntry entry) {
    setState(() {
      _recycleBin = _recycleBin
          .where((TrashPhotoEntry item) => item.id != entry.id)
          .toList();
    });
    unawaited(LocalAlbumStore.deleteManagedImage(entry.photo.imagePath));
    unawaited(LocalAlbumStore.saveRecycleBin(_recycleBin));
  }

  void _emptyTrash() {
    final List<TrashPhotoEntry> deletedEntries = List<TrashPhotoEntry>.from(
      _recycleBin,
    );
    setState(() {
      _recycleBin = <TrashPhotoEntry>[];
    });
    unawaited(_deleteTrashImages(deletedEntries));
    unawaited(LocalAlbumStore.saveRecycleBin(_recycleBin));
  }

  Future<void> _deleteTrashImages(List<TrashPhotoEntry> entries) async {
    for (final TrashPhotoEntry entry in entries) {
      await LocalAlbumStore.deleteManagedImage(entry.photo.imagePath);
    }
  }

  void _updateAppearance(PrototypeAppearance appearance) {
    setState(() {
      _appearance = appearance;
    });
    unawaited(LocalAlbumStore.saveAppearance(_appearance));
  }

  Future<void> _pickCustomBackground() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择自定义背景',
      type: FileType.custom,
      allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp', 'bmp'],
      withData: false,
    );
    final String? sourcePath = result?.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      return;
    }
    final String? previousPath = _appearance.backgroundImagePath;
    final String persistedPath = await LocalAlbumStore.persistBackgroundImage(
      sourcePath,
    );
    if (!mounted) {
      await LocalAlbumStore.deleteManagedBackground(persistedPath);
      return;
    }
    setState(() {
      _appearance = _appearance.copyWith(backgroundImagePath: persistedPath);
    });
    if (previousPath != null && previousPath != persistedPath) {
      await LocalAlbumStore.deleteManagedBackground(previousPath);
    }
    await LocalAlbumStore.saveAppearance(_appearance);
  }

  Future<void> _clearCustomBackground() async {
    final String? previousPath = _appearance.backgroundImagePath;
    if (previousPath == null) {
      return;
    }
    setState(() {
      _appearance = _appearance.copyWith(backgroundImagePath: null);
    });
    await LocalAlbumStore.deleteManagedBackground(previousPath);
    await LocalAlbumStore.saveAppearance(_appearance);
  }

  Future<void> _exportLocalData() async {
    final String timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final String? targetPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出本地相册数据',
      fileName: 'album_backup_$timestamp.zip',
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (targetPath == null || targetPath.isEmpty) {
      return;
    }
    await LocalAlbumStore.exportBackup(
      albums: _albums,
      appearance: _appearance,
      targetPath: targetPath,
    );
  }

  Future<void> _importLocalData() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入本地相册数据',
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
      withData: false,
    );
    final String? sourcePath = result?.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      return;
    }
    final LocalImportSnapshot snapshot = await LocalAlbumStore.importBackup(
      sourcePath,
    );
    final List<AlbumData> previousAlbums = _albums;
    final String? previousBackgroundPath = _appearance.backgroundImagePath;
    for (final AlbumData album in previousAlbums) {
      await LocalAlbumStore.deleteAlbumImages(album);
    }
    await LocalAlbumStore.deleteManagedBackground(previousBackgroundPath);
    if (!mounted) {
      await LocalAlbumStore.deleteManagedBackground(
        snapshot.appearance.backgroundImagePath,
      );
      return;
    }
    setState(() {
      _albums = snapshot.albums;
      _appearance = snapshot.appearance;
    });
    await LocalAlbumStore.saveAlbums(_albums);
    await LocalAlbumStore.saveAppearance(_appearance);
  }

  void _createAlbum(AlbumData album) {
    setState(() {
      _albums = <AlbumData>[album, ..._albums];
    });
    unawaited(LocalAlbumStore.saveAlbums(_albums));
  }

  void _replaceAlbums(List<AlbumData> albums) {
    setState(() {
      _albums = albums;
    });
    unawaited(LocalAlbumStore.saveAlbums(_albums));
  }

  void _deleteAlbum(String albumId) {
    final AlbumData? album = _findAlbum(albumId);
    final List<TrashPhotoEntry> trashedEntries =
        album == null
            ? const <TrashPhotoEntry>[]
            : album.photos.asMap().entries.map((MapEntry<int, PhotoData> entry) {
                return createTrashPhotoEntry(
                  album: album,
                  photo: entry.value,
                  originalPhotoIndex: entry.key,
                );
              }).toList();
    setState(() {
      _albums = _albums.where((AlbumData item) => item.id != albumId).toList();
      if (trashedEntries.isNotEmpty) {
        _recycleBin = <TrashPhotoEntry>[...trashedEntries, ..._recycleBin];
      }
    });
    unawaited(LocalAlbumStore.saveAlbums(_albums));
    if (trashedEntries.isNotEmpty) {
      unawaited(LocalAlbumStore.saveRecycleBin(_recycleBin));
    }
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
    final List<TrashPhotoEntry>? recycleBin =
        await LocalAlbumStore.loadRecycleBin();
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
      if (recycleBin != null) {
        _recycleBin = recycleBin;
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
                  borderRadius: BorderRadius.circular(5),
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
                          borderRadius: BorderRadius.circular(5),
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
        borderRadius: BorderRadius.circular(5),
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
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 0),
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
    required this.recycleBin,
    required this.onAlbumChanged,
    required this.onAlbumDeleted,
    required this.onPhotosTrashed,
    required this.onAlbumsChanged,
    required this.onTrashPhotoRestored,
    required this.onTrashPhotoDeleted,
    required this.onTrashEmptied,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onAlbumCreated,
    required this.onExportDataPressed,
    required this.onImportDataPressed,
    required this.onCustomBackgroundPressed,
    required this.onClearBackgroundPressed,
    super.key,
  });

  final List<AlbumData> albums;
  final List<TrashPhotoEntry> recycleBin;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<String> onAlbumDeleted;
  final ValueChanged<List<TrashPhotoEntry>> onPhotosTrashed;
  final AlbumsChangedCallback onAlbumsChanged;
  final TrashRestoreCallback onTrashPhotoRestored;
  final ValueChanged<TrashPhotoEntry> onTrashPhotoDeleted;
  final VoidCallback onTrashEmptied;
  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onAppearanceChanged;
  final ValueChanged<AlbumData> onAlbumCreated;
  final DataActionCallback onExportDataPressed;
  final DataActionCallback onImportDataPressed;
  final DataActionCallback onCustomBackgroundPressed;
  final DataActionCallback onClearBackgroundPressed;

  @override
  State<AlbumHomePage> createState() => _AlbumHomePageState();
}

enum DesktopAlbumViewMode { focus, grid, compact }

class _AlbumHomePageState extends State<AlbumHomePage> {
  late final PageController _pageController;
  late final TextEditingController _desktopSearchController;
  late final FocusNode _desktopSearchFocusNode;
  double _currentPage = 0;
  String _searchQuery = '';
  bool _desktopSearchOpen = false;
  DesktopAlbumViewMode _desktopViewMode = DesktopAlbumViewMode.focus;
  HomeSection _section = HomeSection.albums;

  List<AlbumData> get _visibleAlbums => filterAndSortAlbums(
    albumsForSection(widget.albums, _section),
    searchQuery: _searchQuery,
    sortMode: AlbumSortMode.recent,
  );

  List<FavoritePhotoEntry> get _favoritePhotos =>
      favoritePhotoEntries(widget.albums, searchQuery: _searchQuery);

  List<TrashPhotoEntry> get _trashPhotos =>
      filterTrashPhotoEntries(widget.recycleBin, searchQuery: _searchQuery);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.72);
    _desktopSearchController = TextEditingController(text: _searchQuery);
    _desktopSearchFocusNode = FocusNode();
    _pageController.addListener(_handlePageChanged);
  }

  @override
  void dispose() {
    _desktopSearchController.dispose();
    _desktopSearchFocusNode.dispose();
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
      bottomNavigationBar: isDesktop
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _MobileSectionBar(
                  section: _section,
                  onSectionChanged: _setSection,
                  desktopViewMode: _desktopViewMode,
                  onAlbumModeToggle: _toggleDesktopViewMode,
                ),
              ),
            ),
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
                  onExportDataPressed: widget.onExportDataPressed,
                  onImportDataPressed: widget.onImportDataPressed,
                  onCustomBackgroundPressed: widget.onCustomBackgroundPressed,
                  onClearBackgroundPressed: widget.onClearBackgroundPressed,
                  section: _section,
                  favoritePhotos: _favoritePhotos,
                  trashPhotos: _trashPhotos,
                  onPhotosTrashed: widget.onPhotosTrashed,
                  onAlbumsChanged: widget.onAlbumsChanged,
                  onTrashPhotoRestored: widget.onTrashPhotoRestored,
                  onTrashPhotoDeleted: widget.onTrashPhotoDeleted,
                  onTrashEmptied: widget.onTrashEmptied,
                  searchQuery: _searchQuery,
                  onSearchPressed: _toggleDesktopSearch,
                  onSearchChanged: _updateSearchQuery,
                  onSearchClosed: _closeDesktopSearch,
                  onSectionChanged: _setSection,
                  hasActiveSearch:
                      _desktopSearchOpen || _searchQuery.trim().isNotEmpty,
                  searchOpen: _desktopSearchOpen,
                  searchController: _desktopSearchController,
                  searchFocusNode: _desktopSearchFocusNode,
                  desktopViewMode: _desktopViewMode,
                  onDesktopViewToggle: _toggleDesktopViewMode,
                  currentPage: _currentPage,
                  controller: _pageController,
                  onDesktopFocusNavigate: _navigateDesktopFocus,
                )
              : _MobileHomeLayout(
                  albums: _visibleAlbums,
                  onAlbumChanged: widget.onAlbumChanged,
                  onAlbumDeleted: widget.onAlbumDeleted,
                  appearance: widget.appearance,
                  onAppearanceChanged: widget.onAppearanceChanged,
                  onAlbumCreated: widget.onAlbumCreated,
                  onExportDataPressed: widget.onExportDataPressed,
                  onImportDataPressed: widget.onImportDataPressed,
                  onCustomBackgroundPressed: widget.onCustomBackgroundPressed,
                  onClearBackgroundPressed: widget.onClearBackgroundPressed,
                  section: _section,
                  desktopViewMode: _desktopViewMode,
                  favoritePhotos: _favoritePhotos,
                  trashPhotos: _trashPhotos,
                  onPhotosTrashed: widget.onPhotosTrashed,
                  onAlbumsChanged: widget.onAlbumsChanged,
                  onTrashPhotoRestored: widget.onTrashPhotoRestored,
                  onTrashPhotoDeleted: widget.onTrashPhotoDeleted,
                  onTrashEmptied: widget.onTrashEmptied,
                  searchQuery: _searchQuery,
                  onSearchChanged: _updateSearchQuery,
                  hasActiveSearch: _searchQuery.trim().isNotEmpty,
                  currentPage: _currentPage,
                  controller: _pageController,
                ),
        ),
      ),
    );
  }

  void _toggleDesktopViewMode() {
    setState(() {
      switch (_desktopViewMode) {
        case DesktopAlbumViewMode.focus:
          _desktopViewMode = DesktopAlbumViewMode.grid;
        case DesktopAlbumViewMode.grid:
          _desktopViewMode = DesktopAlbumViewMode.compact;
        case DesktopAlbumViewMode.compact:
          _desktopViewMode = DesktopAlbumViewMode.focus;
      }
    });
  }

  void _setSection(HomeSection section) {
    if (_section == section) {
      return;
    }
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

  void _navigateDesktopFocus(int offset) {
    if (_visibleAlbums.isEmpty) {
      return;
    }
    setState(() {
      final int currentIndex = _currentPage.round().clamp(
        0,
        _visibleAlbums.length - 1,
      );
      _currentPage = (currentIndex + offset)
          .clamp(0, _visibleAlbums.length - 1)
          .toDouble();
    });
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
      _currentPage = 0;
    });
    if (_desktopSearchController.text != value) {
      _desktopSearchController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }

  void _toggleDesktopSearch() {
    if (_desktopSearchOpen) {
      _closeDesktopSearch();
      return;
    }
    setState(() {
      _desktopSearchOpen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _desktopSearchFocusNode.requestFocus();
      _desktopSearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _desktopSearchController.text.length,
      );
    });
  }

  void _closeDesktopSearch() {
    _desktopSearchFocusNode.unfocus();
    if (!_desktopSearchOpen) {
      return;
    }
    setState(() {
      _desktopSearchOpen = false;
    });
  }
}

class _DesktopHomeLayout extends StatelessWidget {
  const _DesktopHomeLayout({
    required this.albums,
    required this.favoritePhotos,
    required this.trashPhotos,
    required this.onPhotosTrashed,
    required this.onAlbumsChanged,
    required this.onTrashPhotoRestored,
    required this.onTrashPhotoDeleted,
    required this.onTrashEmptied,
    required this.onAlbumChanged,
    required this.onAlbumDeleted,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onAlbumCreated,
    required this.onExportDataPressed,
    required this.onImportDataPressed,
    required this.onCustomBackgroundPressed,
    required this.onClearBackgroundPressed,
    required this.section,
    required this.onSectionChanged,
    required this.searchQuery,
    required this.onSearchPressed,
    required this.onSearchChanged,
    required this.onSearchClosed,
    required this.hasActiveSearch,
    required this.searchOpen,
    required this.searchController,
    required this.searchFocusNode,
    required this.desktopViewMode,
    required this.onDesktopViewToggle,
    required this.currentPage,
    required this.controller,
    required this.onDesktopFocusNavigate,
  });

  final List<AlbumData> albums;
  final List<FavoritePhotoEntry> favoritePhotos;
  final List<TrashPhotoEntry> trashPhotos;
  final ValueChanged<List<TrashPhotoEntry>> onPhotosTrashed;
  final AlbumsChangedCallback onAlbumsChanged;
  final TrashRestoreCallback onTrashPhotoRestored;
  final ValueChanged<TrashPhotoEntry> onTrashPhotoDeleted;
  final VoidCallback onTrashEmptied;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<String> onAlbumDeleted;
  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onAppearanceChanged;
  final ValueChanged<AlbumData> onAlbumCreated;
  final DataActionCallback onExportDataPressed;
  final DataActionCallback onImportDataPressed;
  final DataActionCallback onCustomBackgroundPressed;
  final DataActionCallback onClearBackgroundPressed;
  final HomeSection section;
  final ValueChanged<HomeSection> onSectionChanged;
  final String searchQuery;
  final VoidCallback onSearchPressed;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClosed;
  final bool hasActiveSearch;
  final bool searchOpen;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final DesktopAlbumViewMode desktopViewMode;
  final VoidCallback onDesktopViewToggle;
  final double currentPage;
  final PageController controller;
  final ValueChanged<int> onDesktopFocusNavigate;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 84,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _DesktopSidebar(
                    section: section,
                    onSectionChanged: onSectionChanged,
                    searchActive: hasActiveSearch,
                    onSearchTap: onSearchPressed,
                    onCreateAlbum: () => _ShelfScene.createAlbum(
                      context,
                      onAlbumCreated,
                      albums,
                    ),
                    desktopViewMode: desktopViewMode,
                    onDesktopViewToggle: onDesktopViewToggle,
                    appearance: appearance,
                    onAppearanceChanged: onAppearanceChanged,
                    onExportDataPressed: onExportDataPressed,
                    onImportDataPressed: onImportDataPressed,
                    onCustomBackgroundPressed: onCustomBackgroundPressed,
                    onClearBackgroundPressed: onClearBackgroundPressed,
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: _showDebugSectionFrames
                              ? Border.all(
                                  color: const Color(0xFFE53935),
                                  width: 2,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                  const _SectionMarker(number: 1),
                ],
              ),
            ),
            const SizedBox(width: 0),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _ShelfScene(
                    albums: albums,
                    favoritePhotos: favoritePhotos,
                    trashPhotos: trashPhotos,
                    onPhotosTrashed: onPhotosTrashed,
                    onAlbumsChanged: onAlbumsChanged,
                    onTrashPhotoRestored: onTrashPhotoRestored,
                    onTrashPhotoDeleted: onTrashPhotoDeleted,
                    onTrashEmptied: onTrashEmptied,
                    onAlbumChanged: onAlbumChanged,
                    onAlbumDeleted: onAlbumDeleted,
                    onAlbumCreated: onAlbumCreated,
                    currentPage: currentPage,
                    controller: controller,
                    section: section,
                    hasActiveSearch: hasActiveSearch,
                    desktopViewMode: desktopViewMode,
                    desktop: true,
                    backgroundImagePath: appearance.backgroundImagePath,
                    onDesktopFocusNavigate: onDesktopFocusNavigate,
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: _showDebugSectionFrames
                              ? Border.all(
                                  color: const Color(0xFFE53935),
                                  width: 2,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                  const _SectionMarker(number: 2),
                ],
              ),
            ),
          ],
        ),
        if (searchOpen)
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey<String>('desktop-search-dismiss-layer'),
              behavior: HitTestBehavior.opaque,
              onTap: onSearchClosed,
              child: const SizedBox.expand(),
            ),
          ),
        if (searchOpen)
          Positioned(
            left: 96,
            top: 18,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Stack(
                children: <Widget>[
                  Material(
                    key: const ValueKey<String>('desktop-search-panel'),
                    color: const Color(0xFFFFFCF7),
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFE5D7C8)),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 22,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: searchController,
                        focusNode: searchFocusNode,
                        onChanged: onSearchChanged,
                        onTapOutside: (_) => onSearchClosed(),
                        decoration: InputDecoration(
                          hintText: '搜索相册',
                          isDense: true,
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 18,
                          ),
                          suffixIcon: searchQuery.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () => onSearchChanged(''),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: _showDebugSectionFrames
                              ? Border.all(
                                  color: const Color(0xFFE53935),
                                  width: 2,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                  const _SectionMarker(number: 3),
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
    required this.favoritePhotos,
    required this.trashPhotos,
    required this.onPhotosTrashed,
    required this.onAlbumsChanged,
    required this.onTrashPhotoRestored,
    required this.onTrashPhotoDeleted,
    required this.onTrashEmptied,
    required this.onAlbumChanged,
    required this.onAlbumDeleted,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onAlbumCreated,
    required this.onExportDataPressed,
    required this.onImportDataPressed,
    required this.onCustomBackgroundPressed,
    required this.onClearBackgroundPressed,
    required this.section,
    required this.desktopViewMode,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.hasActiveSearch,
    required this.currentPage,
    required this.controller,
  });

  final List<AlbumData> albums;
  final List<FavoritePhotoEntry> favoritePhotos;
  final List<TrashPhotoEntry> trashPhotos;
  final ValueChanged<List<TrashPhotoEntry>> onPhotosTrashed;
  final AlbumsChangedCallback onAlbumsChanged;
  final TrashRestoreCallback onTrashPhotoRestored;
  final ValueChanged<TrashPhotoEntry> onTrashPhotoDeleted;
  final VoidCallback onTrashEmptied;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<String> onAlbumDeleted;
  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onAppearanceChanged;
  final ValueChanged<AlbumData> onAlbumCreated;
  final DataActionCallback onExportDataPressed;
  final DataActionCallback onImportDataPressed;
  final DataActionCallback onCustomBackgroundPressed;
  final DataActionCallback onClearBackgroundPressed;
  final HomeSection section;
  final DesktopAlbumViewMode desktopViewMode;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final bool hasActiveSearch;
  final double currentPage;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _HomeHeader(
            appearance: appearance,
            onAppearanceChanged: onAppearanceChanged,
            searchQuery: searchQuery,
            onSearchChanged: onSearchChanged,
            onCreateAlbum: () =>
                _ShelfScene.createAlbum(context, onAlbumCreated, albums),
            onExportDataPressed: onExportDataPressed,
            onImportDataPressed: onImportDataPressed,
            onCustomBackgroundPressed: onCustomBackgroundPressed,
            onClearBackgroundPressed: onClearBackgroundPressed,
            desktop: false,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            child: _ShelfScene(
              albums: albums,
              favoritePhotos: favoritePhotos,
              trashPhotos: trashPhotos,
              onPhotosTrashed: onPhotosTrashed,
              onAlbumsChanged: onAlbumsChanged,
              onTrashPhotoRestored: onTrashPhotoRestored,
              onTrashPhotoDeleted: onTrashPhotoDeleted,
              onTrashEmptied: onTrashEmptied,
              onAlbumChanged: onAlbumChanged,
              onAlbumDeleted: onAlbumDeleted,
              onAlbumCreated: onAlbumCreated,
              currentPage: currentPage,
              controller: controller,
              section: section,
              hasActiveSearch: hasActiveSearch,
              desktopViewMode: desktopViewMode,
              desktop: false,
              backgroundImagePath: appearance.backgroundImagePath,
              onDesktopFocusNavigate: (_) {},
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileSectionBar extends StatelessWidget {
  const _MobileSectionBar({
    required this.section,
    required this.onSectionChanged,
    required this.desktopViewMode,
    required this.onAlbumModeToggle,
  });

  final HomeSection section;
  final ValueChanged<HomeSection> onSectionChanged;
  final DesktopAlbumViewMode desktopViewMode;
  final VoidCallback onAlbumModeToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('mobile-home-section-bar'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _MobileSectionButton(
              label: _mobileAlbumModeLabel(desktopViewMode),
              icon: _mobileAlbumModeIcon(
                section == HomeSection.albums,
                desktopViewMode,
              ),
              selected: section == HomeSection.albums,
              onTap: () {
                if (section == HomeSection.albums) {
                  onAlbumModeToggle();
                  return;
                }
                onSectionChanged(HomeSection.albums);
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _MobileSectionButton(
              label: '收藏',
              icon: section == HomeSection.favorites
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              selected: section == HomeSection.favorites,
              onTap: () => onSectionChanged(HomeSection.favorites),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _MobileSectionButton(
              label: '回收站',
              icon: Icons.delete_sweep_rounded,
              selected: section == HomeSection.trash,
              onTap: () => onSectionChanged(HomeSection.trash),
            ),
          ),
        ],
      ),
    );
  }
}

String _mobileAlbumModeLabel(DesktopAlbumViewMode mode) {
  switch (mode) {
    case DesktopAlbumViewMode.focus:
      return '单相册';
    case DesktopAlbumViewMode.grid:
      return '六宫格';
    case DesktopAlbumViewMode.compact:
      return '书脊墙';
  }
}

IconData _mobileAlbumModeIcon(
  bool selected,
  DesktopAlbumViewMode mode,
) {
  switch (mode) {
    case DesktopAlbumViewMode.focus:
      return selected ? Icons.photo_album_rounded : Icons.photo_album_outlined;
    case DesktopAlbumViewMode.grid:
      return Icons.grid_view_rounded;
    case DesktopAlbumViewMode.compact:
      return Icons.view_stream_rounded;
  }
}

class _MobileSectionButton extends StatelessWidget {
  const _MobileSectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color selectedColor = Theme.of(context).colorScheme.primary;
    final Color idleColor = const Color(0xFF7F6248);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected
                ? selectedColor.withValues(alpha: 0.22)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: selected ? selectedColor : idleColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? selectedColor : idleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionMarker extends StatelessWidget {
  const _SectionMarker({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF4A3424).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const bool _showDebugSectionFrames = true;

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.appearance,
    required this.onAppearanceChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onCreateAlbum,
    required this.onExportDataPressed,
    required this.onImportDataPressed,
    required this.onCustomBackgroundPressed,
    required this.onClearBackgroundPressed,
    required this.desktop,
  });

  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onAppearanceChanged;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCreateAlbum;
  final DataActionCallback onExportDataPressed;
  final DataActionCallback onImportDataPressed;
  final DataActionCallback onCustomBackgroundPressed;
  final DataActionCallback onClearBackgroundPressed;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: desktop ? 210 : 180),
          child: TextFormField(
            initialValue: searchQuery,
            onChanged: onSearchChanged,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '搜索',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.94),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.14),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.14),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onCreateAlbum,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('创建相册'),
        ),
        if (!desktop) ...<Widget>[
          const SizedBox(width: 10),
          IconButton(
            onPressed: () => showPrototypeSettingsSheet(
              context,
              appearance: appearance,
              onChanged: onAppearanceChanged,
              onExportDataPressed: onExportDataPressed,
              onImportDataPressed: onImportDataPressed,
              onCustomBackgroundPressed: onCustomBackgroundPressed,
              onClearBackgroundPressed: onClearBackgroundPressed,
            ),
            style: IconButton.styleFrom(
              minimumSize: const Size(38, 38),
              padding: const EdgeInsets.all(8),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.94),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.14),
                ),
              ),
            ),
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: '设置',
          ),
        ],
      ],
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.section,
    required this.onSectionChanged,
    required this.searchActive,
    required this.onSearchTap,
    required this.onCreateAlbum,
    required this.desktopViewMode,
    required this.onDesktopViewToggle,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onExportDataPressed,
    required this.onImportDataPressed,
    required this.onCustomBackgroundPressed,
    required this.onClearBackgroundPressed,
  });

  final HomeSection section;
  final ValueChanged<HomeSection> onSectionChanged;
  final bool searchActive;
  final VoidCallback onSearchTap;
  final VoidCallback onCreateAlbum;
  final DesktopAlbumViewMode desktopViewMode;
  final VoidCallback onDesktopViewToggle;
  final PrototypeAppearance appearance;
  final ValueChanged<PrototypeAppearance> onAppearanceChanged;
  final DataActionCallback onExportDataPressed;
  final DataActionCallback onImportDataPressed;
  final DataActionCallback onCustomBackgroundPressed;
  final DataActionCallback onClearBackgroundPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: const Color(0xFFE8DCCF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF8E6847),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(
                Icons.auto_stories_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: section == HomeSection.albums
                    ? const Color(0xFFF3E8DB)
                    : const Color(0xFFF8F1E8),
                borderRadius: BorderRadius.circular(5),
              ),
              child: IconButton(
                onPressed: () {
                  if (section == HomeSection.albums) {
                    onDesktopViewToggle();
                    return;
                  }
                  onSectionChanged(HomeSection.albums);
                },
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                icon: section == HomeSection.albums
                    ? _DesktopAlbumModeIcon(mode: desktopViewMode)
                    : const Icon(
                        Icons.photo_album_rounded,
                        color: Color(0xFF7A573A),
                        size: 22,
                      ),
                tooltip: section == HomeSection.albums
                    ? switch (desktopViewMode) {
                        DesktopAlbumViewMode.focus => '相册，点击切换为六宫格',
                        DesktopAlbumViewMode.grid => '相册，点击切换为紧凑模式',
                        DesktopAlbumViewMode.compact => '相册，点击切换为单相册',
                      }
                    : '相册',
              ),
            ),
            const SizedBox(height: 12),
            IconButton(
              onPressed: () => onSectionChanged(HomeSection.favorites),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: section == HomeSection.favorites
                    ? const Color(0xFFF3E8DB)
                    : const Color(0xFFF8F1E8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              icon: Icon(
                section == HomeSection.favorites
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 22,
                color: const Color(0xFF7A573A),
              ),
              tooltip: '收藏',
            ),
            const SizedBox(height: 12),
            IconButton(
              key: const ValueKey<String>('desktop-search-button'),
              onPressed: onSearchTap,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: searchActive
                    ? const Color(0xFFECDCCB)
                    : const Color(0xFFF8F1E8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              icon: Icon(
                Icons.search_rounded,
                size: 22,
                color: searchActive
                    ? const Color(0xFF704A31)
                    : const Color(0xFF8A6A4F),
              ),
              tooltip: '搜索',
            ),
            const SizedBox(height: 12),
            IconButton(
              onPressed: onCreateAlbum,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: const Color(0xFFF3E8DB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              icon: const Icon(
                Icons.add_rounded,
                size: 24,
                color: Color(0xFF7A573A),
              ),
              tooltip: '创建相册',
            ),
            const SizedBox(height: 12),
            const Spacer(),
            IconButton(
              onPressed: () => onSectionChanged(HomeSection.trash),
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                backgroundColor: section == HomeSection.trash
                    ? const Color(0xFFF3E8DB)
                    : const Color(0xFFF8F1E8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              icon: const Icon(
                Icons.delete_sweep_rounded,
                size: 20,
                color: Color(0xFF76553A),
              ),
              tooltip: '回收站',
            ),
            const SizedBox(height: 12),
            IconButton(
              onPressed: () => showPrototypeSettingsSheet(
                context,
                appearance: appearance,
                onChanged: onAppearanceChanged,
                onExportDataPressed: onExportDataPressed,
                onImportDataPressed: onImportDataPressed,
                onCustomBackgroundPressed: onCustomBackgroundPressed,
                onClearBackgroundPressed: onClearBackgroundPressed,
              ),
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                backgroundColor: const Color(0xFFF8F1E8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              icon: const Icon(
                Icons.settings_outlined,
                size: 20,
                color: Color(0xFF76553A),
              ),
              tooltip: '设置',
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopAlbumModeIcon extends StatelessWidget {
  const _DesktopAlbumModeIcon({required this.mode});

  final DesktopAlbumViewMode mode;

  @override
  Widget build(BuildContext context) {
    if (mode == DesktopAlbumViewMode.focus) {
      return const Icon(
        Icons.grid_view_rounded,
        size: 22,
        color: Color(0xFF7A573A),
      );
    }
    if (mode == DesktopAlbumViewMode.grid) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned(
              left: 3,
              child: Transform.rotate(
                angle: -0.18,
                child: Container(
                  width: 6,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7A573A),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
            Container(
              width: 8,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF9A744F),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            Positioned(
              right: 3,
              child: Transform.rotate(
                angle: 0.18,
                child: Container(
                  width: 6,
                  height: 15,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB48A63),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: 22,
      height: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF7A573A), width: 1.6),
        ),
        child: Center(
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: const Color(0xFF7A573A),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShelfScene extends StatelessWidget {
  const _ShelfScene({
    required this.albums,
    required this.favoritePhotos,
    required this.trashPhotos,
    required this.onPhotosTrashed,
    required this.onAlbumsChanged,
    required this.onTrashPhotoRestored,
    required this.onTrashPhotoDeleted,
    required this.onTrashEmptied,
    required this.onAlbumChanged,
    required this.onAlbumDeleted,
    required this.onAlbumCreated,
    required this.currentPage,
    required this.controller,
    required this.section,
    required this.hasActiveSearch,
    required this.desktopViewMode,
    required this.desktop,
    required this.onDesktopFocusNavigate,
    this.backgroundImagePath,
  });

  final List<AlbumData> albums;
  final List<FavoritePhotoEntry> favoritePhotos;
  final List<TrashPhotoEntry> trashPhotos;
  final ValueChanged<List<TrashPhotoEntry>> onPhotosTrashed;
  final AlbumsChangedCallback onAlbumsChanged;
  final TrashRestoreCallback onTrashPhotoRestored;
  final ValueChanged<TrashPhotoEntry> onTrashPhotoDeleted;
  final VoidCallback onTrashEmptied;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<String> onAlbumDeleted;
  final ValueChanged<AlbumData> onAlbumCreated;
  final double currentPage;
  final PageController controller;
  final HomeSection section;
  final bool hasActiveSearch;
  final DesktopAlbumViewMode desktopViewMode;
  final bool desktop;
  final ValueChanged<int> onDesktopFocusNavigate;
  final String? backgroundImagePath;

  static Future<void> createAlbum(
    BuildContext context,
    ValueChanged<AlbumData> onAlbumCreated,
    List<AlbumData> existingAlbums,
  ) {
    return _createAlbumFlow(context, onAlbumCreated, existingAlbums);
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius panelRadius = desktop
        ? BorderRadius.zero
        : BorderRadius.circular(5);
    if (section == HomeSection.favorites) {
      return _FavoritePhotoScene(
        entries: favoritePhotos,
        onAlbumChanged: onAlbumChanged,
        desktop: desktop,
        hasActiveSearch: hasActiveSearch,
        backgroundImagePath: backgroundImagePath,
      );
    }

    if (section == HomeSection.trash) {
      return _TrashPhotoScene(
        entries: trashPhotos,
        desktop: desktop,
        hasActiveSearch: hasActiveSearch,
        onTrashPhotoRestored: onTrashPhotoRestored,
        onTrashPhotoDeleted: onTrashPhotoDeleted,
        onTrashEmptied: onTrashEmptied,
        backgroundImagePath: backgroundImagePath,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double sceneHeight = desktop
            ? constraints.maxHeight * 0.94
            : constraints.maxHeight;
        final bool showGrid = desktopViewMode == DesktopAlbumViewMode.grid;
        final bool showCompact = desktopViewMode == DesktopAlbumViewMode.compact;
        final bool hasCustomBackground =
            backgroundImagePath != null &&
            backgroundImagePath!.isNotEmpty &&
            File(backgroundImagePath!).existsSync();

        return Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: desktop ? 0 : 18,
                        vertical: desktop ? 0 : 12,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: panelRadius,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: desktop
                                  ? const Color(0x22000000)
                                  : Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.10),
                              blurRadius: desktop ? 26 : 20,
                              offset: Offset(0, desktop ? 18 : 16),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: panelRadius,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              if (hasCustomBackground)
                                Image.file(
                                  File(backgroundImagePath!),
                                  fit: BoxFit.cover,
                                )
                              else
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: <Color>[
                                        desktop
                                            ? const Color(0xFFE9D3BA)
                                            : Color.alphaBlend(
                                                Theme.of(
                                                  context,
                                                ).colorScheme.surface,
                                                Theme.of(
                                                  context,
                                                ).scaffoldBackgroundColor,
                                              ),
                                        desktop
                                            ? const Color(0xFF9C6E46)
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .secondary
                                                  .withValues(alpha: 0.22),
                                      ],
                                    ),
                                  ),
                                ),
                              if (hasCustomBackground)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: <Color>[
                                        Colors.white.withValues(alpha: 0.08),
                                        const Color(
                                          0xFF6A4B34,
                                        ).withValues(alpha: 0.32),
                                      ],
                                    ),
                                  ),
                                ),
                              if (!desktop)
                                Positioned(
                                  right: 22,
                                  top: 32,
                                  child: _DecorPlant(height: 110),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showGrid)
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 34 : 16,
                          desktop ? 26 : 18,
                          desktop ? 34 : 16,
                          desktop ? 26 : 18,
                        ),
                        child: _DesktopAlbumGrid(
                          albums: albums,
                          onAlbumChanged: onAlbumChanged,
                          onAlbumTap: (AlbumData album) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) {
                                  return AlbumDetailPage(
                                    album: album,
                                    albums: albums,
                                    onAlbumChanged: onAlbumChanged,
                                    onAlbumsChanged: onAlbumsChanged,
                                    onPhotosTrashed: onPhotosTrashed,
                                  );
                                },
                              ),
                            );
                          },
                          onAlbumEdit: (AlbumData album) =>
                              _editAlbum(context, album),
                        ),
                      ),
                    )
                  else if (showCompact)
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 26 : 14,
                          desktop ? 24 : 18,
                          desktop ? 26 : 14,
                          desktop ? 24 : 18,
                        ),
                        child: _DesktopAlbumSpineWall(
                          albums: albums,
                          onAlbumTap: (AlbumData album) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) {
                                  return AlbumDetailPage(
                                    album: album,
                                    albums: albums,
                                    onAlbumChanged: onAlbumChanged,
                                    onAlbumsChanged: onAlbumsChanged,
                                    onPhotosTrashed: onPhotosTrashed,
                                  );
                                },
                              ),
                            );
                          },
                          onAlbumEdit: (AlbumData album) =>
                              _editAlbum(context, album),
                          onAlbumDelete: (AlbumData album) async {
                            final bool confirmed = await _confirmDeleteAlbum(
                              context,
                              album,
                            );
                            if (!context.mounted || !confirmed) {
                              return;
                            }
                            onAlbumDeleted(album.id);
                          },
                          onCreateAlbum: () {
                            _createAlbumFlow(
                              context,
                              onAlbumCreated,
                              albums,
                            );
                          },
                        ),
                      ),
                    )
                  else ...<Widget>[
                    SizedBox(
                      height: sceneHeight,
                      child: desktop
                          ? Builder(
                              builder: (BuildContext context) {
                                if (albums.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final int currentIndex = currentPage
                                    .round()
                                    .clamp(0, albums.length - 1);
                                final AlbumData album = albums[currentIndex];
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    34,
                                    26,
                                    34,
                                    18,
                                  ),
                                  child: _DesktopFocusedAlbumStage(
                                    album: album,
                                    onAlbumChanged: onAlbumChanged,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (BuildContext context) {
                                            return AlbumDetailPage(
                                              album: album,
                                              albums: albums,
                                              onAlbumChanged: onAlbumChanged,
                                              onAlbumsChanged: onAlbumsChanged,
                                              onPhotosTrashed: onPhotosTrashed,
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            )
                          : PageView.builder(
                              controller: controller,
                              itemCount: albums.length,
                              itemBuilder: (BuildContext context, int index) {
                                final AlbumData album = albums[index];
                                final double delta = index - currentPage;
                                final double scale = (1 - (delta.abs() * 0.10))
                                    .clamp(0.78, 1.0);
                                final double angle = delta * 0.16;
                                final bool active = delta.abs() < 0.5;

                                return Transform.translate(
                                  offset: Offset(delta * -6, 0),
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
                                                  albums: albums,
                                                  onAlbumChanged:
                                                      onAlbumChanged,
                                                  onAlbumsChanged:
                                                      onAlbumsChanged,
                                                  onPhotosTrashed:
                                                      onPhotosTrashed,
                                                );
                                              },
                                            ),
                                          );
                                        },
                                        child: _MobileFocusedAlbumStage(
                                          album: album,
                                          active: active,
                                          onAlbumChanged: onAlbumChanged,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Positioned(
                      left: desktop ? 14 : 8,
                      child: _ArrowButton(
                        icon: Icons.chevron_left_rounded,
                        onPressed: () => desktop
                            ? onDesktopFocusNavigate(-1)
                            : _animateTo(context, -1),
                        subdued: desktop,
                      ),
                    ),
                    Positioned(
                      right: desktop ? 14 : 8,
                      child: _ArrowButton(
                        icon: Icons.chevron_right_rounded,
                        onPressed: () => desktop
                            ? onDesktopFocusNavigate(1)
                            : _animateTo(context, 1),
                        subdued: desktop,
                      ),
                    ),
                  ],
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
                  borderRadius: BorderRadius.circular(5),
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
            if (desktopViewMode == DesktopAlbumViewMode.focus) ...<Widget>[
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
                      borderRadius: BorderRadius.circular(5),
                    ),
                  );
                }),
              ),
            ],
          ],
        );
      },
    );
  }

  void _animateTo(BuildContext context, int offset) {
    if (albums.isEmpty || !controller.hasClients) {
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
      initialDescription: album.description,
      initialStyle: album.style,
      initialCoverPhotoId: album.coverPhoto?.id,
      initialCoverScale: album.coverScale,
      initialCoverOffsetX: album.coverOffsetX,
      initialCoverOffsetY: album.coverOffsetY,
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
        description: result.description.trim(),
        coverPhotoId: result.coverPhotoId,
        coverScale: result.coverScale,
        coverOffsetX: result.coverOffsetX,
        coverOffsetY: result.coverOffsetY,
      ),
    );
  }

  static Future<String?> _showAlbumCoverPickerDialog(
    BuildContext context,
    AlbumData album,
  ) async {
    if (album.photos.isEmpty) {
      showPrototypeMessage(context, '当前相册还没有照片可用作封面');
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: SizedBox(
            width: 520,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '选择封面照片',
                    style: Theme.of(dialogContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '从当前相册内部照片中选择一张作为封面。',
                    style: Theme.of(dialogContext).textTheme.bodySmall
                        ?.copyWith(color: const Color(0xFF8B7765)),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1,
                          ),
                      itemCount: album.photos.length,
                      itemBuilder: (BuildContext context, int index) {
                        final PhotoData photo = album.photos[index];
                        final bool selected = photo.id == album.coverPhoto?.id;
                        return InkWell(
                          onTap: () {
                            Navigator.of(dialogContext).pop(photo.id);
                          },
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFD56A5F)
                                    : const Color(0xFFD7C7B6),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  PhotoVisual(photo: photo),
                                  if (selected)
                                    const Positioned(
                                      right: 6,
                                      top: 6,
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFFD56A5F),
                                        size: 18,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('取消'),
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


  static Future<void> _createAlbumFlow(
    BuildContext context,
    ValueChanged<AlbumData> onAlbumCreated,
    List<AlbumData> existingAlbums,
  ) async {
    final _AlbumEditorResult? result = await _showAlbumEditorDialog(
      context,
      title: '创建相册',
      initialName: '',
      initialDescription: '',
      initialStyle: existingAlbums.isEmpty
          ? PhotoStyle.sunlitRoom
          : existingAlbums.first.style,
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
      final DateTime coverDate = await resolvePhotoDate(image.path);
      final PhotoOrientation orientation = await detectPhotoOrientation(
        storedPath,
      );
      coverPhoto = PhotoData(
        id: 'photo-${DateTime.now().microsecondsSinceEpoch}',
        title: '相册封面',
        date: formatAlbumDate(coverDate),
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
        description: result.description.trim().isEmpty
            ? coverPhoto == null
                  ? '新建相册，等待你继续添加照片和文字。'
                  : '新建相册，并已为它选择封面图片。'
            : result.description.trim(),
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

  static Future<_AlbumEditorResult?> _showAlbumEditorDialog(
    BuildContext context, {
    required String title,
    required String initialName,
    required String initialDescription,
    required PhotoStyle initialStyle,
    String? initialCoverPhotoId,
    double initialCoverScale = 1,
    double initialCoverOffsetX = 0,
    double initialCoverOffsetY = 0,
    required List<PhotoData> photos,
    required String submitLabel,
  }) async {
    String draftName = initialName;
    String draftDescription = initialDescription;
    PhotoStyle draftStyle = initialStyle;
    String? draftCoverPhotoId = initialCoverPhotoId;
    double draftCoverScale = initialCoverScale;
    double draftCoverOffsetX = initialCoverOffsetX;
    double draftCoverOffsetY = initialCoverOffsetY;
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
                      const SizedBox(height: 14),
                      TextFormField(
                        initialValue: initialDescription,
                        minLines: 2,
                        maxLines: 4,
                        onChanged: (String value) {
                          draftDescription = value;
                        },
                        decoration: const InputDecoration(hintText: '输入相册描述'),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        editingExistingAlbum ? '选择相册封面' : '选择封面风格',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      if (editingExistingAlbum)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _AlbumCoverPreview(
                              photo: _resolveCoverPhoto(
                                photos,
                                draftCoverPhotoId,
                              ),
                              style: draftStyle,
                              coverScale: draftCoverScale,
                              coverOffsetX: draftCoverOffsetX,
                              coverOffsetY: draftCoverOffsetY,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: photos.map((PhotoData photo) {
                                final bool selected =
                                    photo.id == draftCoverPhotoId;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      draftCoverPhotoId = photo.id;
                                      draftCoverScale = 1;
                                      draftCoverOffsetX = 0;
                                      draftCoverOffsetY = 0;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 104,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: selected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.18),
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
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
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '封面缩放',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Slider(
                              value: draftCoverScale,
                              min: 1,
                              max: 2.2,
                              divisions: 12,
                              label: draftCoverScale.toStringAsFixed(2),
                              onChanged: (double value) {
                                setState(() {
                                  draftCoverScale = value;
                                });
                              },
                            ),
                            Text(
                              '水平位置',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Slider(
                              value: draftCoverOffsetX,
                              min: -1,
                              max: 1,
                              divisions: 20,
                              label: draftCoverOffsetX.toStringAsFixed(2),
                              onChanged: (double value) {
                                setState(() {
                                  draftCoverOffsetX = value;
                                });
                              },
                            ),
                            Text(
                              '垂直位置',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Slider(
                              value: draftCoverOffsetY,
                              min: -1,
                              max: 1,
                              divisions: 20,
                              label: draftCoverOffsetY.toStringAsFixed(2),
                              onChanged: (double value) {
                                setState(() {
                                  draftCoverOffsetY = value;
                                });
                              },
                            ),
                          ],
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
                                  borderRadius: BorderRadius.circular(5),
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
                                      borderRadius: BorderRadius.circular(5),
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
                                  draftCoverScale = 1;
                                  draftCoverOffsetX = 0;
                                  draftCoverOffsetY = 0;
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
                                    description: '',
                                    style: PhotoStyle.sunlitRoom,
                                    coverScale: 1,
                                    coverOffsetX: 0,
                                    coverOffsetY: 0,
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
                        description: draftDescription,
                        style: draftStyle,
                        coverPhotoId: draftCoverPhotoId,
                        coverScale: draftCoverScale,
                        coverOffsetX: draftCoverOffsetX,
                        coverOffsetY: draftCoverOffsetY,
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

  static PhotoData? _resolveCoverPhoto(
    List<PhotoData> photos,
    String? coverId,
  ) {
    if (photos.isEmpty) {
      return null;
    }
    if (coverId != null) {
      for (final PhotoData photo in photos) {
        if (photo.id == coverId) {
          return photo;
        }
      }
    }
    return photos.first;
  }
}

class _DesktopAlbumGrid extends StatefulWidget {
  const _DesktopAlbumGrid({
    required this.albums,
    required this.onAlbumChanged,
    required this.onAlbumTap,
    required this.onAlbumEdit,
  });

  final List<AlbumData> albums;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<AlbumData> onAlbumTap;
  final ValueChanged<AlbumData> onAlbumEdit;

  @override
  State<_DesktopAlbumGrid> createState() => _DesktopAlbumGridState();
}

class _DesktopAlbumGridState extends State<_DesktopAlbumGrid> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.albums.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 700;
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: !compact,
          trackVisibility: !compact,
          child: GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.only(right: compact ? 0 : 10),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: compact ? 2 : 3,
              crossAxisSpacing: compact ? 14 : 24,
              mainAxisSpacing: compact ? 14 : 24,
              childAspectRatio: compact ? 0.72 : 0.84,
            ),
            itemCount: widget.albums.length,
            itemBuilder: (BuildContext context, int index) {
              final AlbumData album = widget.albums[index];
              return _DesktopAlbumGridCard(
                album: album,
                compact: compact,
                onTap: () => widget.onAlbumTap(album),
                onEdit: () => widget.onAlbumEdit(album),
              );
            },
          ),
        );
      },
    );
  }
}

class _DesktopAlbumGridCard extends StatelessWidget {
  const _DesktopAlbumGridCard({
    required this.album,
    required this.compact,
    required this.onTap,
    required this.onEdit,
  });

  final AlbumData album;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final Widget card = GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF7).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE7D7C6)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x19000000),
              blurRadius: 22,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      AlbumCoverVisual(album: album),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.transparent,
                              const Color(0x1A000000),
                              const Color(0x8A1E140F),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: compact ? 8 : 10,
                        right: compact ? 8 : 10,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onEdit,
                            borderRadius: BorderRadius.circular(5),
                            child: Ink(
                              width: compact ? 30 : 34,
                              height: compact ? 30 : 34,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.90),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.edit_outlined,
                                size: compact ? 16 : 18,
                                color: const Color(0xFF5A3E2A),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF4A3424),
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 14 : 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                album.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF866E5B),
                  fontSize: compact ? 11 : 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (compact) {
      return card;
    }
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.75,
        heightFactor: 0.75,
        child: card,
      ),
    );
  }
}

class _DesktopAlbumSpineWall extends StatefulWidget {
  const _DesktopAlbumSpineWall({
    required this.albums,
    required this.onAlbumTap,
    required this.onAlbumEdit,
    required this.onAlbumDelete,
    required this.onCreateAlbum,
  });

  final List<AlbumData> albums;
  final ValueChanged<AlbumData> onAlbumTap;
  final ValueChanged<AlbumData> onAlbumEdit;
  final ValueChanged<AlbumData> onAlbumDelete;
  final VoidCallback onCreateAlbum;

  @override
  State<_DesktopAlbumSpineWall> createState() => _DesktopAlbumSpineWallState();
}

class _DesktopAlbumSpineWallState extends State<_DesktopAlbumSpineWall> {
  late final ScrollController _scrollController;

  double _spineWidthFor(AlbumData album) {
    final int seed = album.id.hashCode.abs();
    return (100 + (seed % 51).toDouble()) * 0.75;
  }

  double _spineHeightFor(AlbumData album, double availableHeight) {
    final int seed = album.title.hashCode.abs();
    final double baseHeight = (availableHeight * 0.56).clamp(240.0, 420.0);
    return (baseHeight + (seed % 51)).clamp(240.0, 470.0);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.albums.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 540;
        final double baselineY = availableHeight * (2 / 3);

        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ...List<Widget>.generate(widget.albums.length, (
                        int index,
                      ) {
                        final AlbumData album = widget.albums[index];
                        final double width = _spineWidthFor(album);
                        final double height = _spineHeightFor(
                          album,
                          availableHeight,
                        );
                        final double topInset = ((baselineY - height) + 150)
                            .clamp(
                          0.0,
                          availableHeight,
                        );
                        return Padding(
                          padding: EdgeInsets.only(
                            top: topInset,
                            right: 8,
                          ),
                          child: _DesktopAlbumSpineCard(
                            album: album,
                            width: width,
                            height: height,
                            onTap: () => widget.onAlbumTap(album),
                            onEdit: () => widget.onAlbumEdit(album),
                            onDelete: () => widget.onAlbumDelete(album),
                          ),
                        );
                      }),
                      Padding(
                        padding: EdgeInsets.only(
                          top: ((baselineY - 240) + 150).clamp(
                            0.0,
                            availableHeight,
                          ),
                        ),
                        child: _DesktopAddAlbumSpineCard(
                          width: 100,
                          height: 240,
                          onTap: widget.onCreateAlbum,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopAlbumSpineCard extends StatelessWidget {
  const _DesktopAlbumSpineCard({
    required this.album,
    required this.width,
    required this.height,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final AlbumData album;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final List<Color> palette = _spinePalette(album.style);
    final bool compact = height <= 220 || width <= 72;
    final double verticalPadding = compact ? 12 : 18;
    final double notchWidth = compact ? 16 : 24;
    final double notchHeight = compact ? 3 : 5;
    final double titleSize = compact ? 14 : 18;
    final String verticalTitle = album.title.characters.join('\n');
    final List<String> subtitleParts = album.subtitle.split('·');
    final String rawDateLabel = subtitleParts.length > 1
        ? subtitleParts.last.trim()
        : album.subtitle.trim();
    final RegExp yearMonthPattern = RegExp(r'(\d{4})年\s*(\d{1,2})月');
    final RegExpMatch? yearMonthMatch = yearMonthPattern.firstMatch(
      rawDateLabel,
    );
    final String dateLabel = yearMonthMatch == null
        ? rawDateLabel
        : '${yearMonthMatch.group(1)} · ${yearMonthMatch.group(2)}';
    final double dateBottom = math.max(12, (height / 8) - 10);
    final double dateSize = compact ? 10 : 12;
    final double coverThumbSize = math.max(40, width - 10);
    final double coverThumbTop = math.max(
      verticalPadding + notchHeight + 12,
      (height / 3) - (coverThumbSize / 2),
    );
    final double dateTop = height - dateBottom - dateSize - 2;
    final double titleTop = coverThumbTop + coverThumbSize;
    final double titleHeight = math.max(24, dateTop - titleTop);

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (TapDownDetails details) async {
        final String? action = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
            PopupMenuItem<String>(value: 'delete', child: Text('删除')),
          ],
        );
        if (action == 'edit') {
          onEdit();
        } else if (action == 'delete') {
          onDelete();
        }
      },
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: palette,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 14,
                      offset: Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.34),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: verticalPadding,
                  ),
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: notchWidth,
                        height: notchHeight,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 5,
              top: coverThumbTop,
              width: coverThumbSize,
              height: coverThumbSize,
              child: IgnorePointer(
                child: SizedBox(
                  width: coverThumbSize,
                  height: coverThumbSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: AlbumCoverVisual(album: album),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 5,
              top: titleTop,
              width: coverThumbSize,
              height: titleHeight,
              child: IgnorePointer(
                child: SizedBox(
                  width: coverThumbSize,
                  height: titleHeight,
                  child: Center(
                    child: Text(
                      verticalTitle,
                      maxLines: math.max(1, titleHeight ~/ titleSize),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w700,
                        height: 1.02,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: dateBottom,
              child: IgnorePointer(
                child: Text(
                  dateLabel,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: dateSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Color> _spinePalette(PhotoStyle style) {
    switch (style) {
      case PhotoStyle.sunlitRoom:
      case PhotoStyle.tabletop:
      case PhotoStyle.cafe:
        return const <Color>[Color(0xFFC38955), Color(0xFF7C5437)];
      case PhotoStyle.greenValley:
      case PhotoStyle.yakField:
        return const <Color>[Color(0xFF6E8D79), Color(0xFF425B49)];
      case PhotoStyle.mountainLake:
      case PhotoStyle.sunsetSea:
        return const <Color>[Color(0xFF7EB6C9), Color(0xFF3F738A)];
      case PhotoStyle.cityWarm:
      case PhotoStyle.oldStreet:
        return const <Color>[Color(0xFF7E5F92), Color(0xFF463458)];
      case PhotoStyle.temple:
      case PhotoStyle.horses:
      case PhotoStyle.nightLamp:
        return const <Color>[Color(0xFFAA7A54), Color(0xFF6A452F)];
    }
  }
}

class _DesktopAddAlbumSpineCard extends StatelessWidget {
  const _DesktopAddAlbumSpineCard({
    required this.width,
    required this.height,
    required this.onTap,
  });

  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
          ),
          child: const Center(
            child: Icon(
              Icons.add_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({
    required this.album,
    required this.albums,
    required this.onAlbumChanged,
    required this.onAlbumsChanged,
    required this.onPhotosTrashed,
    super.key,
  });

  final AlbumData album;
  final List<AlbumData> albums;
  final ValueChanged<AlbumData> onAlbumChanged;
  final AlbumsChangedCallback onAlbumsChanged;
  final ValueChanged<List<TrashPhotoEntry>> onPhotosTrashed;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  late AlbumData _album;
  bool _isSelectionMode = false;
  bool _isImportingPhotos = false;
  final Set<String> _selectedPhotoIds = <String>{};

  List<PhotoData> get _selectedPhotos {
    return _album.photos.where((PhotoData photo) {
      return _selectedPhotoIds.contains(photo.id);
    }).toList();
  }

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
        flexibleSpace: Stack(
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: _showDebugSectionFrames
                        ? Border.all(
                            color: const Color(0xFFE53935),
                            width: 2,
                          )
                        : null,
                  ),
                ),
              ),
            ),
            const _SectionMarker(number: 4),
          ],
        ),
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
          if (!_isSelectionMode)
            TextButton.icon(
              onPressed: _album.photos.isEmpty ? null : _enterSelectionMode,
              icon: const Icon(Icons.select_all_rounded),
              label: const Text('批量选中'),
            ),
          if (_isSelectionMode)
            TextButton.icon(
              onPressed: _exitSelectionMode,
              icon: const Icon(Icons.deselect_rounded),
              label: const Text('取消批量选中'),
            ),
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
            ),
          if (_isSelectionMode)
            IconButton(
              onPressed: _selectedPhotoIds.isEmpty
                  ? null
                  : _moveSelectedPhotos,
              tooltip: '移动',
              icon: const Icon(Icons.drive_file_move_rounded),
            ),
          if (_isSelectionMode)
            IconButton(
              onPressed: _selectedPhotoIds.isEmpty
                  ? null
                  : _copySelectedPhotos,
              tooltip: '复制',
              icon: const Icon(Icons.content_copy_rounded),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: _isImportingPhotos ? null : _importPhotosFromFiles,
                child: Text(_isImportingPhotos ? '导入中...' : '添加照片'),
              ),
            ),
        ],
      ),
      floatingActionButton: isDesktop
          ? null
          : _isSelectionMode
          ? null
          : FloatingActionButton(
              backgroundColor: const Color(0xFF9A6F47),
              foregroundColor: Colors.white,
              onPressed: _isImportingPhotos ? null : _importPhotosFromFiles,
              child: _isImportingPhotos
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.add_rounded),
            ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 22 : 14,
            8,
            isDesktop ? 22 : 14,
            _isSelectionMode && !isDesktop ? 88 : 16,
          ),
          child: Column(
            children: <Widget>[
              Stack(
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      _album.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6F5A49),
                        height: 1.55,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: _showDebugSectionFrames
                              ? Border.all(
                                  color: const Color(0xFFE53935),
                                  width: 2,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                  const _SectionMarker(number: 5),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    MasonryPhotoGrid(
                      album: _album,
                      onAlbumChanged: _replaceAlbum,
                      onPhotosTrashed: widget.onPhotosTrashed,
                      selectionMode: _isSelectionMode,
                      selectedPhotoIds: _selectedPhotoIds,
                      onToggleSelection: _togglePhotoSelection,
                      onStartSelection: _startSelection,
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: _showDebugSectionFrames
                                ? Border.all(
                                    color: const Color(0xFFE53935),
                                    width: 2,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                    const _SectionMarker(number: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importPhotosFromFiles() async {
    setState(() {
      _isImportingPhotos = true;
    });
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      lockParentWindow: true,
    );
    if (!mounted) {
      return;
    }
    if (result == null || result.files.isEmpty) {
      setState(() {
        _isImportingPhotos = false;
      });
      return;
    }

    final List<PhotoData> importedPhotos = <PhotoData>[];
    try {
      for (final PlatformFile file in result.files) {
        final String? sourcePath = file.path;
        if (sourcePath == null || sourcePath.isEmpty) {
          continue;
        }
        final XFile image = XFile(sourcePath);
        final String storedPath = await LocalAlbumStore.persistPickedImage(
          image,
          albumId: _album.id,
        );
        final DateTime detectedDate = await resolvePhotoDate(sourcePath);
        final PhotoOrientation orientation = await detectPhotoOrientation(
          storedPath,
        );
        importedPhotos.add(
          PhotoData(
            id: 'local-${DateTime.now().microsecondsSinceEpoch}-${importedPhotos.length}',
            title: derivePhotoTitleFromPath(sourcePath),
            date: formatAlbumDate(detectedDate),
            note: '',
            orientation: orientation,
            style: _album.style,
            imagePath: storedPath,
          ),
        );
      }
    } catch (_) {
      for (final PhotoData photo in importedPhotos) {
        await LocalAlbumStore.deleteManagedImage(photo.imagePath);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isImportingPhotos = false;
      });
      showPrototypeMessage(context, '导入失败，请重试。');
      return;
    }

    if (!mounted) {
      return;
    }
    if (importedPhotos.isEmpty) {
      setState(() {
        _isImportingPhotos = false;
      });
      showPrototypeMessage(context, '未找到可导入的图片。');
      return;
    }

    AlbumData updatedAlbum = _album;
    for (final PhotoData photo in importedPhotos.reversed) {
      updatedAlbum = updatedAlbum.withInsertedPhoto(photo);
    }
    setState(() {
      _album = updatedAlbum;
      _isImportingPhotos = false;
    });
    widget.onAlbumChanged(updatedAlbum);
    showPrototypeMessage(context, '已导入 ${importedPhotos.length} 张照片');
  }

  void _replaceAlbum(AlbumData album) {
    setState(() {
      _album = album;
      _selectedPhotoIds.removeWhere((String id) {
        return !_album.photos.any((PhotoData photo) => photo.id == id);
      });
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

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedPhotoIds.clear();
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
    if (!mounted) {
      return;
    }

    final List<TrashPhotoEntry> trashedEntries = deletedPhotos.map((
      PhotoData photo,
    ) {
      return createTrashPhotoEntry(
        album: _album,
        photo: photo,
        originalPhotoIndex: _album.photos.indexWhere(
          (PhotoData item) => item.id == photo.id,
        ),
      );
    }).toList();

    final AlbumData updatedAlbum = _album.withRemovedPhotos(_selectedPhotoIds);
    setState(() {
      _album = updatedAlbum;
      _isSelectionMode = false;
      _selectedPhotoIds.clear();
    });
    widget.onAlbumChanged(updatedAlbum);
    widget.onPhotosTrashed(trashedEntries);
    showPrototypeMessage(context, '已移入回收站 ${deletedPhotos.length} 张照片');
  }

  Future<void> _moveSelectedPhotos() async {
    await _transferSelectedPhotos(copyOnly: false);
  }

  Future<void> _copySelectedPhotos() async {
    await _transferSelectedPhotos(copyOnly: true);
  }

  Future<void> _transferSelectedPhotos({required bool copyOnly}) async {
    if (_selectedPhotoIds.isEmpty) {
      return;
    }
    final _AlbumTransferTarget? target = await _showAlbumTransferTargetPicker(
      context,
      copyOnly: copyOnly,
    );
    if (!mounted || target == null) {
      return;
    }

    final List<PhotoData> selectedPhotos = _selectedPhotos;
    if (selectedPhotos.isEmpty) {
      return;
    }

    final List<AlbumData> allAlbums = List<AlbumData>.from(widget.albums);
    final int sourceIndex = allAlbums.indexWhere(
      (AlbumData album) => album.id == _album.id,
    );
    if (sourceIndex == -1) {
      return;
    }

    AlbumData sourceAlbum = allAlbums[sourceIndex];
    AlbumData? targetAlbum;
    int targetIndex = -1;
    if (target.createNew) {
      final String? newAlbumName = await _promptNewAlbumName(context);
      if (!mounted || newAlbumName == null) {
        return;
      }
      final DateTime now = DateTime.now();
      targetAlbum = AlbumData(
        id: 'album-${now.microsecondsSinceEpoch}',
        title: newAlbumName,
        subtitle: '${selectedPhotos.length} 张照片 · ${now.year}年${now.month}月',
        description: '',
        style: _album.style,
        photos: const <PhotoData>[],
      );
      allAlbums.insert(0, targetAlbum);
      targetIndex = 0;
    } else {
      targetIndex = allAlbums.indexWhere(
        (AlbumData album) => album.id == target.albumId,
      );
      if (targetIndex == -1) {
        return;
      }
      targetAlbum = allAlbums[targetIndex];
    }

    final List<PhotoData> transferPhotos = <PhotoData>[];
    for (final PhotoData photo in selectedPhotos) {
      if (copyOnly) {
        final String? duplicatedImagePath = await LocalAlbumStore
            .duplicateManagedImage(
              photo.imagePath,
              albumId: targetAlbum.id,
            );
        transferPhotos.add(
          photo.copyWith(
            id: 'copy-${DateTime.now().microsecondsSinceEpoch}-${transferPhotos.length}',
            imagePath: duplicatedImagePath ?? photo.imagePath,
          ),
        );
      } else {
        transferPhotos.add(photo);
      }
    }

    AlbumData updatedTarget = targetAlbum;
    for (final PhotoData photo in transferPhotos.reversed) {
      updatedTarget = updatedTarget.withInsertedPhoto(photo);
    }
    allAlbums[targetIndex] = updatedTarget;

    if (!copyOnly) {
      sourceAlbum = sourceAlbum.withRemovedPhotos(_selectedPhotoIds);
      allAlbums[sourceIndex] = sourceAlbum;
    }

    setState(() {
      _album = copyOnly ? _album : sourceAlbum;
      _isSelectionMode = false;
      _selectedPhotoIds.clear();
    });
    widget.onAlbumsChanged(allAlbums);
    if (!copyOnly) {
      widget.onAlbumChanged(sourceAlbum);
    }
    if (!mounted) {
      return;
    }
    showPrototypeMessage(
      context,
      copyOnly
          ? '已复制 ${selectedPhotos.length} 张照片到“${updatedTarget.title}”'
          : '已移动 ${selectedPhotos.length} 张照片到“${updatedTarget.title}”',
    );
  }

  Future<_AlbumTransferTarget?> _showAlbumTransferTargetPicker(
    BuildContext context, {
    required bool copyOnly,
  }) async {
    final List<AlbumData> targetAlbums = widget.albums.where((AlbumData album) {
      return album.id != _album.id;
    }).toList();
    return showDialog<_AlbumTransferTarget>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          child: SizedBox(
            width: 360,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    copyOnly ? '复制到其他相册' : '移动到其他相册',
                    style: Theme.of(dialogContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final AlbumData album in targetAlbums)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () {
                                Navigator.of(dialogContext).pop(
                                  _AlbumTransferTarget.existing(album.id),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFBDA58C),
                                  ),
                                ),
                                child: Text(
                                  album.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(dialogContext)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF4F3827),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        InkWell(
                          onTap: () {
                            Navigator.of(
                              dialogContext,
                            ).pop(const _AlbumTransferTarget.createNew());
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFBDA58C),
                              ),
                            ),
                            child: Row(
                              children: <Widget>[
                                const Icon(Icons.add_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  '新建列表',
                                  style: Theme.of(dialogContext)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF4F3827),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('取消'),
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

  Future<String?> _promptNewAlbumName(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('新建列表'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入相册名称',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
    if (result == null || result.trim().isEmpty) {
      return null;
    }
    return result.trim();
  }
}

class MasonryPhotoGrid extends StatelessWidget {
  const MasonryPhotoGrid({
    required this.album,
    required this.onAlbumChanged,
    required this.onPhotosTrashed,
    required this.selectionMode,
    required this.selectedPhotoIds,
    required this.onToggleSelection,
    required this.onStartSelection,
    super.key,
  });

  final AlbumData album;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<List<TrashPhotoEntry>> onPhotosTrashed;
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
        final double gap = 6;
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
                        padding: EdgeInsets.only(bottom: gap),
                        child: _PhotoTile(
                          photo: photo,
                          width: itemWidth,
                          selectionMode: selectionMode,
                          selected: selectedPhotoIds.contains(photo.id),
                          selectedBorderColor: const Color(0xFFFF3B30),
                          selectedBorderWidth: 2,
                          showSelectionCheckmark: false,
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
                                    onPhotosTrashed: onPhotosTrashed,
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
    return (width * ratio) + 34;
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
  final TextEditingController _dateController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    _dateController.dispose();
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
        borderRadius: BorderRadius.circular(5),
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
              borderRadius: BorderRadius.circular(5),
              onTap: _isSaving ? null : () => _pickImage(context),
              child: AspectRatio(
                aspectRatio: 1.1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
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
                                  borderRadius: BorderRadius.circular(5),
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
        borderRadius: BorderRadius.circular(5),
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
            const SizedBox(height: 12),
            TextField(
              controller: _dateController,
              decoration: const InputDecoration(
                labelText: '照片日期',
                hintText: '例如 2024年10月2日',
              ),
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF9F3EB),
                borderRadius: BorderRadius.circular(5),
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
    final DateTime detectedDate = await resolvePhotoDate(image.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedImage = image;
      _dateController.text = formatAlbumDate(detectedDate);
    });
  }

  Future<void> _savePhoto() async {
    final XFile? image = _selectedImage;
    final String note = _controller.text.trim();
    final String dateText = _dateController.text.trim();
    if (image == null) {
      showPrototypeMessage(context, '请先选择一张图片。');
      return;
    }
    if (note.isEmpty) {
      showPrototypeMessage(context, '请先填写备注内容。');
      return;
    }
    final DateTime? parsedDate = parseChineseDate(dateText);
    if (parsedDate == null) {
      showPrototypeMessage(context, '请填写有效日期，例如 2024年10月2日。');
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
    final PhotoData photo = PhotoData(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      title: derivePhotoTitle(note),
      date: formatAlbumDate(parsedDate),
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
    required this.onPhotosTrashed,
    super.key,
  });

  final AlbumData album;
  final List<PhotoData> photos;
  final int initialIndex;
  final ValueChanged<AlbumData> onAlbumChanged;
  final ValueChanged<List<TrashPhotoEntry>> onPhotosTrashed;

  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage> {
  late int _index;
  late List<PhotoData> _photos;
  late final FocusNode _pageFocusNode;
  late TextEditingController _titleController;
  late TextEditingController _noteController;
  late TextEditingController _dateController;
  double _rotationTurns = 0;
  double _zoom = 1;
  Offset _panOffset = Offset.zero;
  double _noteFontSize = 16;
  double _textPanelFraction = 0.30;
  bool _isEditingDetails = false;
  bool _textPanelCollapsed = false;

  PhotoData get photo => _photos[_index];

  @override
  void initState() {
    super.initState();
    _photos = List<PhotoData>.from(widget.photos);
    _index = widget.initialIndex;
    _pageFocusNode = FocusNode(debugLabel: 'photo-detail-page');
    _titleController = TextEditingController(text: photo.title);
    _noteController = TextEditingController(text: photo.note);
    _dateController = TextEditingController(text: photo.date);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pageFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _pageFocusNode.dispose();
    _titleController.dispose();
    _noteController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;
    final Widget detailContent = _LandscapeDetailLayout(
      photo: photo,
      zoom: _zoom,
      turns: _rotationTurns,
      panOffset: _panOffset,
      onPanUpdate: (Offset nextOffset) {
        setState(() {
          _panOffset = nextOffset;
        });
      },
      toolbar: _buildToolbar(),
      textPanel: _buildTextPanel(),
      textPanelVisible: !_textPanelCollapsed,
      onExpandTextPanel: () {
        setState(() {
          _textPanelCollapsed = false;
        });
      },
      desktop: isDesktop,
      textPanelFraction: _textPanelFraction,
      onTextPanelFractionChanged: (double value) {
        setState(() {
          _textPanelFraction = value.clamp(0.22, 0.42);
        });
      },
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight * (2 / 3),
        title: Text('${_index + 1} / ${_photos.length}'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _replaceCurrentPhoto,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('选择其他照片'),
          ),
          IconButton(
            onPressed: _deleteCurrentPhoto,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          IconButton(
            onPressed: _toggleFavorite,
            icon: Icon(
              photo.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
          ),
          IconButton(
            tooltip: '全屏模式',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => FullscreenPhotoPage(
                    photo: photo,
                    initialTurns: _rotationTurns,
                    initialZoom: _zoom,
                    initialPanOffset: _panOffset,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.fullscreen_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Focus(
          focusNode: _pageFocusNode,
          autofocus: true,
          onKeyEvent: _handlePageKeyEvent,
              child: isDesktop
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                      child: Stack(
                        children: <Widget>[
                          detailContent,
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: _showDebugSectionFrames
                                      ? Border.all(
                                          color: const Color(0xFFE53935),
                                          width: 2,
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                          const _SectionMarker(number: 7),
                        ],
                      ),
                    )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: double.infinity),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                      child: Stack(
                        children: <Widget>[
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFCF7),
                              borderRadius: BorderRadius.circular(5),
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
                              child: detailContent,
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: _showDebugSectionFrames
                                      ? Border.all(
                                          color: const Color(0xFFE53935),
                                          width: 2,
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                          const _SectionMarker(number: 7),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  void _goPrevious() {
    if (_index == 0) {
      _showEdgeMessage('已经是第一张照片');
      return;
    }
    setState(() {
      _index -= 1;
      _rotationTurns = 0;
      _zoom = 1;
      _panOffset = Offset.zero;
      _resetEditingState();
    });
    _pageFocusNode.requestFocus();
  }

  void _toggleFavorite() {
    final PhotoData updatedPhoto = photo.copyWith(
      isFavorite: !photo.isFavorite,
    );
    final List<PhotoData> updatedPhotos = List<PhotoData>.from(_photos);
    updatedPhotos[_index] = updatedPhoto;
    final AlbumData updatedAlbum = widget.album.copyWith(photos: updatedPhotos);
    setState(() {
      _photos = updatedPhotos;
    });
    widget.onAlbumChanged(updatedAlbum);
    showPrototypeMessage(context, updatedPhoto.isFavorite ? '已加入收藏' : '已取消收藏');
  }

  void _goNext() {
    if (_index == _photos.length - 1) {
      _showEdgeMessage('已经是最后一张照片');
      return;
    }
    setState(() {
      _index += 1;
      _rotationTurns = 0;
      _zoom = 1;
      _panOffset = Offset.zero;
      _resetEditingState();
    });
    _pageFocusNode.requestFocus();
  }

  Widget _buildToolbar() {
    return _DetailToolbar(
      onPrevious: _goPrevious,
      onNext: _goNext,
      canGoPrevious: _index > 0,
      canGoNext: _index < _photos.length - 1,
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
          _zoom = (_zoom - 0.2).clamp(1.0, 2.0);
          if (_zoom == 1) {
            _panOffset = Offset.zero;
          }
        });
      },
    );
  }

  Widget _buildTextPanel() {
    return Column(
      children: <Widget>[
        Expanded(
          child: _PhotoTextPanel(
            photo: photo,
            compact: photo.orientation == PhotoOrientation.portrait,
            isEditing: _isEditingDetails,
            titleController: _titleController,
            noteController: _noteController,
            dateController: _dateController,
            noteFontSize: _noteFontSize,
            onEdit: () {
              setState(() {
                _isEditingDetails = true;
              });
            },
            onCancel: () {
              setState(() {
                _resetEditingState();
              });
            },
            onPickDate: _pickDate,
            onIncreaseFont: () {
              setState(() {
                _noteFontSize = (_noteFontSize + 1).clamp(13.0, 22.0);
              });
            },
            onDecreaseFont: () {
              setState(() {
                _noteFontSize = (_noteFontSize - 1).clamp(13.0, 22.0);
              });
            },
            onSave: _savePhotoDetails,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '隐藏文字面板',
            onPressed: () {
              setState(() {
                _textPanelCollapsed = true;
              });
            },
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ],
    );
  }

  void _resetEditingState() {
    _isEditingDetails = false;
    _titleController.text = photo.title;
    _noteController.text = photo.note;
    _dateController.text = photo.date;
  }

  Future<void> _pickDate() async {
    final DateTime initialDate =
        parseChineseDate(_dateController.text.trim()) ??
        parseChineseDate(photo.date) ??
        DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择照片日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _dateController.text = formatAlbumDate(picked);
    });
  }

  void _savePhotoDetails() {
    final String nextTitle = _titleController.text.trim();
    final String nextNote = _noteController.text.trim();
    final String nextDateText = _dateController.text.trim();
    if (nextTitle.isEmpty) {
      showPrototypeMessage(context, '标题不能为空。');
      return;
    }
    if (nextNote.isEmpty) {
      showPrototypeMessage(context, '文字内容不能为空。');
      return;
    }
    final DateTime? parsedDate = parseChineseDate(nextDateText);
    if (parsedDate == null) {
      showPrototypeMessage(context, '日期格式应为 2024年10月2日。');
      return;
    }
    final PhotoData updatedPhoto = photo.copyWith(
      title: nextTitle,
      note: nextNote,
      date: formatAlbumDate(parsedDate),
    );
    setState(() {
      _photos[_index] = updatedPhoto;
      _isEditingDetails = false;
      _titleController.text = updatedPhoto.title;
      _dateController.text = updatedPhoto.date;
    });
    final AlbumData updatedAlbum = widget.album.copyWith(
      photos: List<PhotoData>.from(_photos),
    );
    widget.onAlbumChanged(updatedAlbum);
  }

  Future<void> _replaceCurrentPhoto() async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (!mounted || image == null) {
      return;
    }
    final String storedPath = await LocalAlbumStore.persistPickedImage(
      image,
      albumId: widget.album.id,
    );
    final PhotoOrientation orientation = await detectPhotoOrientation(
      storedPath,
    );
    final DateTime detectedDate = await resolvePhotoDate(image.path);
    final String previousImagePath = photo.imagePath ?? '';
    final PhotoData updatedPhoto = photo.copyWith(
      imagePath: storedPath,
      orientation: orientation,
      date: formatAlbumDate(detectedDate),
    );
    final List<PhotoData> updatedPhotos = List<PhotoData>.from(_photos);
    updatedPhotos[_index] = updatedPhoto;
    setState(() {
      _photos = updatedPhotos;
      _dateController.text = updatedPhoto.date;
      _rotationTurns = 0;
      _zoom = 1;
      _panOffset = Offset.zero;
    });
    widget.onAlbumChanged(widget.album.copyWith(photos: updatedPhotos));
    if (previousImagePath.isNotEmpty) {
      unawaited(LocalAlbumStore.deleteManagedImage(previousImagePath));
    }
    if (!mounted) {
      return;
    }
    showPrototypeMessage(context, '已更换当前照片');
  }

  KeyEventResult _handlePageKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isEditingDetails) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goPrevious();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goNext();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showEdgeMessage(String message) {
    _pageFocusNode.requestFocus();
    final Brightness brightness = Theme.of(context).brightness;
    final Color textColor = brightness == Brightness.dark
        ? const Color(0xFFFDF9F3)
        : const Color(0xFF20150E);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Center(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0x66000000),
                    blurRadius: 10,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          duration: const Duration(milliseconds: 1400),
        ),
      );
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
    final TrashPhotoEntry trashedEntry = createTrashPhotoEntry(
      album: widget.album,
      photo: photo,
      originalPhotoIndex: widget.album.photos.indexWhere(
        (PhotoData item) => item.id == photo.id,
      ),
    );
    final AlbumData updatedAlbum = widget.album.withRemovedPhoto(photo.id);
    if (!mounted) {
      return;
    }
    widget.onPhotosTrashed(<TrashPhotoEntry>[trashedEntry]);
    widget.onAlbumChanged(updatedAlbum);
    showPrototypeMessage(context, '已移入回收站');
    Navigator.of(context).pop();
  }
}

class FullscreenPhotoPage extends StatefulWidget {
  const FullscreenPhotoPage({
    required this.photo,
    required this.initialTurns,
    required this.initialZoom,
    this.initialPanOffset = Offset.zero,
    super.key,
  });

  final PhotoData photo;
  final double initialTurns;
  final double initialZoom;
  final Offset initialPanOffset;

  @override
  State<FullscreenPhotoPage> createState() => _FullscreenPhotoPageState();
}

class _FullscreenPhotoPageState extends State<FullscreenPhotoPage> {
  late double _turns;
  late double _zoom;
  late Offset _panOffset;

  @override
  void initState() {
    super.initState();
    _turns = widget.initialTurns;
    _zoom = widget.initialZoom;
    _panOffset = widget.initialPanOffset;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _DetailImageFrame(
                photo: widget.photo,
                zoom: _zoom,
                turns: _turns,
                panOffset: _panOffset,
                onPanUpdate: (Offset nextOffset) {
                  setState(() {
                    _panOffset = nextOffset;
                  });
                },
                desktop: true,
                backgroundColor: const Color(0xFF141414),
              ),
            ),
            Positioned(
              top: 6,
              left: 8,
              right: 8,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            Positioned(
              left: 18,
              right: 18,
              bottom: 22,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _DarkActionButton(
                      icon: Icons.remove_rounded,
                      label: '缩小',
                      onTap: () {
                        setState(() {
                          _zoom = (_zoom - 0.2).clamp(0.8, 2.0);
                          if (_zoom <= 1) {
                            _panOffset = Offset.zero;
                          }
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
    required this.panOffset,
    required this.onPanUpdate,
    required this.toolbar,
    required this.textPanel,
    required this.textPanelVisible,
    required this.onExpandTextPanel,
    required this.desktop,
    required this.textPanelFraction,
    required this.onTextPanelFractionChanged,
  });

  final PhotoData photo;
  final double zoom;
  final double turns;
  final Offset panOffset;
  final ValueChanged<Offset> onPanUpdate;
  final Widget toolbar;
  final Widget textPanel;
  final bool textPanelVisible;
  final VoidCallback onExpandTextPanel;
  final bool desktop;
  final double textPanelFraction;
  final ValueChanged<double> onTextPanelFractionChanged;

  @override
  Widget build(BuildContext context) {
    if (!desktop) {
      if (!textPanelVisible) {
        return Column(
          key: const ValueKey<String>('mobile-photo-detail-layout'),
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: _DetailImageFrame(
                            photo: photo,
                            zoom: zoom,
                            turns: turns,
                            panOffset: panOffset,
                            onPanUpdate: onPanUpdate,
                            desktop: desktop,
                          ),
                        ),
                        const SizedBox(height: 12),
                        toolbar,
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: '显示文字面板',
                      onPressed: onExpandTextPanel,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }
      return Column(
        key: const ValueKey<String>('mobile-photo-detail-layout'),
        children: <Widget>[
          Expanded(
            flex: photo.orientation == PhotoOrientation.portrait ? 5 : 4,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: _DetailImageFrame(
                    photo: photo,
                    zoom: zoom,
                    turns: turns,
                    panOffset: panOffset,
                    onPanUpdate: onPanUpdate,
                    desktop: desktop,
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: toolbar,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: photo.orientation == PhotoOrientation.portrait ? 4 : 5,
            child: textPanel,
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!textPanelVisible) {
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: _DetailImageFrame(
                        photo: photo,
                        zoom: zoom,
                        turns: turns,
                        panOffset: panOffset,
                        onPanUpdate: onPanUpdate,
                        desktop: desktop,
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: toolbar,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  tooltip: '显示文字面板',
                  onPressed: onExpandTextPanel,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
              ),
            ],
          );
        }
        const double gap = 20;
        final double panelFraction = textPanelFraction.clamp(0.22, 0.42);
        final double availableWidth = constraints.maxWidth - gap;
        final double textWidth = (availableWidth * panelFraction).clamp(
          260.0,
          460.0,
        );
        final double imageWidth = (availableWidth - textWidth).clamp(
          380.0,
          double.infinity,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: imageWidth,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _DetailImageFrame(
                      photo: photo,
                      zoom: zoom,
                      turns: turns,
                      panOffset: panOffset,
                      onPanUpdate: onPanUpdate,
                      desktop: desktop,
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: toolbar,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: gap,
              child: _DragDivider(
                onHorizontalDragUpdate: (double delta) {
                  final double next =
                      textPanelFraction - (delta / constraints.maxWidth);
                  onTextPanelFractionChanged(next);
                },
              ),
            ),
            SizedBox(width: textWidth, child: textPanel),
          ],
        );
      },
    );
  }
}

double _viewerPhotoAspectRatio(PhotoData photo, double turns) {
  final double baseAspect = photo.orientation == PhotoOrientation.portrait
      ? 0.72
      : 1.58;
  final int quarterTurns = ((turns * 4).round() % 4 + 4) % 4;
  return quarterTurns.isOdd ? 1 / baseAspect : baseAspect;
}

Size _containedPhotoSize({
  required Size viewportSize,
  required double photoAspectRatio,
}) {
  final double viewportAspect = viewportSize.width / viewportSize.height;
  if (viewportAspect > photoAspectRatio) {
    final double height = viewportSize.height;
    return Size(height * photoAspectRatio, height);
  }
  final double width = viewportSize.width;
  return Size(width, width / photoAspectRatio);
}

Offset _clampPhotoPanOffset({
  required Size viewportSize,
  required double photoAspectRatio,
  required double zoom,
  required Offset panOffset,
}) {
  if (zoom <= 1) {
    return Offset.zero;
  }
  final Size containedSize = _containedPhotoSize(
    viewportSize: viewportSize,
    photoAspectRatio: photoAspectRatio,
  );
  final double scaledWidth = containedSize.width * zoom;
  final double scaledHeight = containedSize.height * zoom;
  final double maxDx = math.max(0, (scaledWidth - viewportSize.width) / 2);
  final double maxDy = math.max(0, (scaledHeight - viewportSize.height) / 2);
  return Offset(
    panOffset.dx.clamp(-maxDx, maxDx),
    panOffset.dy.clamp(-maxDy, maxDy),
  );
}

class _DragDivider extends StatelessWidget {
  const _DragDivider({required this.onHorizontalDragUpdate});

  final ValueChanged<double> onHorizontalDragUpdate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (DragUpdateDetails details) {
                onHorizontalDragUpdate(details.delta.dx);
              },
              child: Center(
                child: Container(
                  width: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: const Color(0xFFE9D9C7),
                  ),
                  child: Center(
                    child: Container(
                      width: 2,
                      height: 84,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: const Color(0xFFB89472),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailImageFrame extends StatelessWidget {
  const _DetailImageFrame({
    required this.photo,
    required this.zoom,
    required this.turns,
    required this.panOffset,
    required this.onPanUpdate,
    required this.desktop,
    this.backgroundColor = const Color(0xFFF0E6DA),
  });

  final PhotoData photo;
  final double zoom;
  final double turns;
  final Offset panOffset;
  final ValueChanged<Offset> onPanUpdate;
  final bool desktop;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewportSize = constraints.biggest;
        final double photoAspectRatio = _viewerPhotoAspectRatio(photo, turns);
        final Offset effectivePanOffset = _clampPhotoPanOffset(
          viewportSize: viewportSize,
          photoAspectRatio: photoAspectRatio,
          zoom: zoom,
          panOffset: panOffset,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: GestureDetector(
              onPanUpdate: zoom > 1
                  ? (DragUpdateDetails details) {
                      onPanUpdate(
                        _clampPhotoPanOffset(
                          viewportSize: viewportSize,
                          photoAspectRatio: photoAspectRatio,
                          zoom: zoom,
                          panOffset: effectivePanOffset + details.delta,
                        ),
                      );
                    }
                  : null,
              child: SizedBox.expand(
                child: Transform.translate(
                  offset: effectivePanOffset,
                  child: Transform.rotate(
                    angle: math.pi * 2 * turns,
                    child: Transform.scale(
                      alignment: Alignment.center,
                      scale: zoom,
                      child: PhotoVisual(
                        photo: photo,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhotoTextPanel extends StatelessWidget {
  const _PhotoTextPanel({
    required this.photo,
    required this.compact,
    required this.isEditing,
    required this.titleController,
    required this.noteController,
    required this.dateController,
    required this.noteFontSize,
    required this.onEdit,
    required this.onCancel,
    required this.onPickDate,
    required this.onIncreaseFont,
    required this.onDecreaseFont,
    required this.onSave,
  });

  final PhotoData photo;
  final bool compact;
  final bool isEditing;
  final TextEditingController titleController;
  final TextEditingController noteController;
  final TextEditingController dateController;
  final double noteFontSize;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onPickDate;
  final VoidCallback onIncreaseFont;
  final VoidCallback onDecreaseFont;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFDF9F3),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE8D9C8)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 22 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: isEditing
                      ? TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: '照片标题',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(5),
                              borderSide: const BorderSide(
                                color: Color(0xFFD8CABB),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(5),
                              borderSide: const BorderSide(
                                color: Color(0xFFD8CABB),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(5),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.2,
                              ),
                            ),
                          ),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF38291D),
                              ),
                        )
                      : Text(
                          photo.title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
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
            const SizedBox(height: 12),
            if (isEditing)
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: dateController,
                      decoration: InputDecoration(
                        labelText: '照片日期',
                        hintText: '例如 2024年10月2日',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8CABB),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8CABB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.2,
                          ),
                        ),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6A5544),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: '选择日期',
                    onPressed: onPickDate,
                    icon: const Icon(Icons.calendar_month_rounded),
                  ),
                ],
              )
            else
              Text(
                photo.date,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF8D7968),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _TinyTextScaleButton(label: 'A-', onTap: onDecreaseFont),
                const SizedBox(width: 6),
                _TinyTextScaleButton(label: 'A+', onTap: onIncreaseFont),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: isEditing
                  ? Column(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: noteController,
                            maxLines: null,
                            expands: true,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8CABB),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8CABB),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.2,
                                ),
                              ),
                            ),
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontSize: noteFontSize,
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
                      child: MarkdownBody(
                        data: photo.note,
                        selectable: false,
                        styleSheet: MarkdownStyleSheet.fromTheme(
                          Theme.of(context),
                        ).copyWith(
                          p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: noteFontSize,
                            height: 1.7,
                            color: const Color(0xFF5C4837),
                          ),
                          h1: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: const Color(0xFF38291D),
                                fontWeight: FontWeight.w700,
                              ),
                          h2: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: const Color(0xFF38291D),
                            fontWeight: FontWeight.w700,
                          ),
                          h3: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFF38291D),
                                fontWeight: FontWeight.w700,
                              ),
                          strong: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontSize: noteFontSize,
                                height: 1.7,
                                color: const Color(0xFF3E2F24),
                                fontWeight: FontWeight.w700,
                              ),
                          em: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: noteFontSize,
                            height: 1.7,
                            color: const Color(0xFF5C4837),
                            fontStyle: FontStyle.italic,
                          ),
                          blockquote: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontSize: noteFontSize,
                                height: 1.7,
                                color: const Color(0xFF6F5A49),
                              ),
                          code: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontSize: noteFontSize - 1,
                                color: const Color(0xFF5A4231),
                              ),
                          codeblockDecoration: BoxDecoration(
                            color: const Color(0xFFF4EADF),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          blockSpacing: 14,
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

class _TinyTextScaleButton extends StatelessWidget {
  const _TinyTextScaleButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E7D9),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE0D1C0)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B5645),
          ),
        ),
      ),
    );
  }
}

class _DetailToolbar extends StatelessWidget {
  const _DetailToolbar({
    required this.onPrevious,
    required this.onNext,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onRotate,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onRotate;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _ToolButton(
          icon: Icons.chevron_left_rounded,
          label: '上一张',
          onTap: onPrevious,
          enabled: canGoPrevious,
        ),
        _ToolButton(
          icon: Icons.zoom_out_rounded,
          label: '缩小',
          onTap: onZoomOut,
        ),
        _ToolButton(
          icon: Icons.zoom_in_rounded,
          label: '放大',
          onTap: onZoomIn,
        ),
        _ToolButton(
          icon: Icons.rotate_right_rounded,
          label: '旋转',
          onTap: onRotate,
        ),
        _ToolButton(
          icon: Icons.chevron_right_rounded,
          label: '下一张',
          onTap: onNext,
          enabled: canGoNext,
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Widget button = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7EFE4),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE2C9B1)),
      ),
      child: TextButton(
        onPressed: enabled ? onTap : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(52, 52),
          padding: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? const Color(0xFF6E4E35) : const Color(0xFFBEAA96),
        ),
      ),
    );
    if (Theme.of(context).platform == TargetPlatform.android) {
      return button;
    }
    return Tooltip(message: label, child: button);
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
    final Widget button = InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Ink(
        width: 52,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Center(
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
    if (Theme.of(context).platform == TargetPlatform.android) {
      return button;
    }
    return Tooltip(message: label, child: button);
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
    this.selectedBorderColor,
    this.selectedBorderWidth = 2,
    this.showSelectionCheckmark = true,
  });

  final PhotoData photo;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selectionMode;
  final bool selected;
  final Color? selectedBorderColor;
  final double selectedBorderWidth;
  final bool showSelectionCheckmark;

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
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected
                ? (selectedBorderColor ?? const Color(0xFF9A6F47))
                : Colors.transparent,
            width: selected ? selectedBorderWidth : 2,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
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
                      if (selectionMode && showSelectionCheckmark)
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
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  photo.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8B7765),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumTextEditorPane extends StatelessWidget {
  const _AlbumTextEditorPane({
    required this.album,
    required this.compact,
    required this.isEditing,
    required this.titleController,
    required this.descriptionController,
    required this.onStartEditing,
    required this.onCancel,
    required this.onSave,
  });

  final AlbumData album;
  final bool compact;
  final bool isEditing;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final VoidCallback onStartEditing;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: isEditing
                  ? TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '输入相册名字',
                        border: OutlineInputBorder(),
                      ),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF4A3424),
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Text(
                      album.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF4A3424),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            if (isEditing)
              IconButton(
                tooltip: '保存相册信息',
                onPressed: onSave,
                icon: const Icon(Icons.check_rounded),
              )
            else
              IconButton(
                tooltip: '编辑相册文字',
                onPressed: onStartEditing,
                icon: const Icon(Icons.edit_outlined),
              ),
            if (isEditing)
              IconButton(
                tooltip: '取消编辑',
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          album.subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF8A7767),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: 42,
          height: 2,
          color: const Color(0xFFC89A6A),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: isEditing
              ? TextField(
                  controller: descriptionController,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    hintText: '输入相册描述',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E4A3A),
                    height: compact ? 1.65 : 1.8,
                  ),
                )
              : SingleChildScrollView(
                  child: Text(
                    album.description.trim().isEmpty
                        ? '这个相册还没有描述。'
                        : album.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E4A3A),
                      height: compact ? 1.75 : 1.85,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _MobileFocusedAlbumStage extends StatefulWidget {
  const _MobileFocusedAlbumStage({
    required this.album,
    required this.active,
    required this.onAlbumChanged,
  });

  final AlbumData album;
  final bool active;
  final ValueChanged<AlbumData> onAlbumChanged;

  @override
  State<_MobileFocusedAlbumStage> createState() =>
      _MobileFocusedAlbumStageState();
}

class _MobileFocusedAlbumStageState extends State<_MobileFocusedAlbumStage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  bool _editingText = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.album.title);
    _descriptionController =
        TextEditingController(text: widget.album.description);
  }

  @override
  void didUpdateWidget(covariant _MobileFocusedAlbumStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album != widget.album && !_editingText) {
      _titleController.text = widget.album.title;
      _descriptionController.text = widget.album.description;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editingText = true;
      _titleController.text = widget.album.title;
      _descriptionController.text = widget.album.description;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingText = false;
      _titleController.text = widget.album.title;
      _descriptionController.text = widget.album.description;
    });
  }

  void _saveEditing() {
    widget.onAlbumChanged(
      widget.album.copyWith(
        title: _titleController.text.trim().isEmpty
            ? widget.album.title
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
      ),
    );
    setState(() {
      _editingText = false;
    });
  }

  Future<void> _pickCover() async {
    final String? coverPhotoId = await _ShelfScene._showAlbumCoverPickerDialog(
      context,
      widget.album,
    );
    if (!mounted || coverPhotoId == null) {
      return;
    }
    widget.onAlbumChanged(widget.album.copyWith(coverPhotoId: coverPhotoId));
  }

  @override
  Widget build(BuildContext context) {
    final AlbumData album = widget.album;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: 320,
            height: 520,
            child: DecoratedBox(
              key: const ValueKey<String>('mobile-focused-album-stage'),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFCF7).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFFE6D9CC)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 22,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      flex: 6,
                      child: AnimatedPadding(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.only(
                          top: widget.active ? 0 : 10,
                          bottom: widget.active ? 0 : 6,
                        ),
                        child: AspectRatio(
                          aspectRatio: 1.04,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 24,
                                  offset: Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              fit: StackFit.expand,
                              children: <Widget>[
                                for (int layer = 5; layer >= 1; layer -= 1)
                                  Positioned.fill(
                                    child: Transform.translate(
                                      offset: Offset(layer * 3, layer * 3),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: <Widget>[
                                      AlbumCoverVisual(album: album),
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: <Color>[
                                              Colors.transparent,
                                              const Color(0x22000000),
                                              const Color(0xAA1E140F),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: IconButton.filledTonal(
                                          tooltip: '编辑封面',
                                          onPressed: _pickCover,
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 20,
                                        right: 20,
                                        bottom: 20,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      flex: 4,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: _AlbumTextEditorPane(
                          album: album,
                          compact: true,
                          isEditing: _editingText,
                          titleController: _titleController,
                          descriptionController: _descriptionController,
                          onStartEditing: _startEditing,
                          onCancel: _cancelEditing,
                          onSave: _saveEditing,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopFocusedAlbumStage extends StatefulWidget {
  const _DesktopFocusedAlbumStage({
    required this.album,
    required this.onTap,
    required this.onAlbumChanged,
  });

  final AlbumData album;
  final VoidCallback onTap;
  final ValueChanged<AlbumData> onAlbumChanged;

  @override
  State<_DesktopFocusedAlbumStage> createState() =>
      _DesktopFocusedAlbumStageState();
}

class _DesktopFocusedAlbumStageState extends State<_DesktopFocusedAlbumStage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  bool _editingText = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.album.title);
    _descriptionController =
        TextEditingController(text: widget.album.description);
  }

  @override
  void didUpdateWidget(covariant _DesktopFocusedAlbumStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album != widget.album && !_editingText) {
      _titleController.text = widget.album.title;
      _descriptionController.text = widget.album.description;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editingText = true;
      _titleController.text = widget.album.title;
      _descriptionController.text = widget.album.description;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingText = false;
      _titleController.text = widget.album.title;
      _descriptionController.text = widget.album.description;
    });
  }

  void _saveEditing() {
    widget.onAlbumChanged(
      widget.album.copyWith(
        title: _titleController.text.trim().isEmpty
            ? widget.album.title
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
      ),
    );
    setState(() {
      _editingText = false;
    });
  }

  Future<void> _pickCover() async {
    final String? coverPhotoId = await _ShelfScene._showAlbumCoverPickerDialog(
      context,
      widget.album,
    );
    if (!mounted || coverPhotoId == null) {
      return;
    }
    widget.onAlbumChanged(widget.album.copyWith(coverPhotoId: coverPhotoId));
  }

  @override
  Widget build(BuildContext context) {
    final AlbumData album = widget.album;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7).withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE6D9CC)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 22,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 5,
              child: GestureDetector(
                onTap: widget.onTap,
                child: AspectRatio(
                  aspectRatio: 1.18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 24,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      fit: StackFit.expand,
                      children: <Widget>[
                        for (int layer = 5; layer >= 1; layer -= 1)
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(layer * 3, layer * 3),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              AlbumCoverVisual(album: album),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: <Color>[
                                      Colors.transparent,
                                      const Color(0x22000000),
                                      const Color(0xAA1E140F),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 14,
                                right: 14,
                                child: IconButton.filledTonal(
                                  tooltip: '编辑封面',
                                  onPressed: _pickCover,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 24,
                                right: 24,
                                bottom: 24,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      album.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      album.subtitle,
                                      style: const TextStyle(
                                        color: Color(0xFFF4E8D7),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
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
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                  child: _AlbumTextEditorPane(
                    album: album,
                    compact: false,
                    isEditing: _editingText,
                    titleController: _titleController,
                    descriptionController: _descriptionController,
                    onStartEditing: _startEditing,
                    onCancel: _cancelEditing,
                    onSave: _saveEditing,
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

class _FavoritePhotoScene extends StatelessWidget {
  const _FavoritePhotoScene({
    required this.entries,
    required this.onAlbumChanged,
    required this.desktop,
    required this.hasActiveSearch,
    this.backgroundImagePath,
  });

  final List<FavoritePhotoEntry> entries;
  final ValueChanged<AlbumData> onAlbumChanged;
  final bool desktop;
  final bool hasActiveSearch;
  final String? backgroundImagePath;

  @override
  Widget build(BuildContext context) {
    final bool hasCustomBackground =
        backgroundImagePath != null &&
        backgroundImagePath!.isNotEmpty &&
        File(backgroundImagePath!).existsSync();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: desktop ? 4 : 18,
                  vertical: desktop ? 0 : 12,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: desktop
                            ? const Color(0x22000000)
                            : Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.10),
                        blurRadius: desktop ? 26 : 20,
                        offset: Offset(0, desktop ? 18 : 16),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Theme.of(
                                  context,
                                ).colorScheme.surface.withValues(alpha: 0.98),
                                Theme.of(
                                  context,
                                ).colorScheme.secondary.withValues(alpha: 0.12),
                              ],
                            ),
                          ),
                        ),
                        if (hasCustomBackground)
                          Positioned.fill(
                            child: Opacity(
                              opacity: desktop ? 0.22 : 0.18,
                              child: Image.file(
                                File(backgroundImagePath!),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        if (entries.isEmpty)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Text(
                                hasActiveSearch ? '没有找到匹配的收藏照片。' : '当前还没有收藏照片。',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.68),
                                    ),
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              desktop ? 26 : 14,
                              desktop ? 24 : 14,
                              desktop ? 26 : 14,
                              desktop ? 18 : 14,
                            ),
                            child: _FavoritePhotoGrid(
                              entries: entries,
                              onAlbumChanged: onAlbumChanged,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FavoritePhotoGrid extends StatelessWidget {
  const _FavoritePhotoGrid({
    required this.entries,
    required this.onAlbumChanged,
  });

  final List<FavoritePhotoEntry> entries;
  final ValueChanged<AlbumData> onAlbumChanged;

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
        final List<List<FavoritePhotoEntry>> lanes =
            List<List<FavoritePhotoEntry>>.generate(
              columns,
              (_) => <FavoritePhotoEntry>[],
            );
        final List<double> heights = List<double>.filled(columns, 0);

        for (final FavoritePhotoEntry entry in entries) {
          int lane = 0;
          for (int index = 1; index < columns; index += 1) {
            if (heights[index] < heights[lane]) {
              lane = index;
            }
          }
          lanes[lane].add(entry);
          heights[lane] += _itemHeight(entry.photo, itemWidth) + gap;
        }

        return SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(columns, (int column) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: column == 0 ? 0 : gap),
                  child: Column(
                    children: lanes[column].map((FavoritePhotoEntry entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _FavoritePhotoTile(
                          entry: entry,
                          width: itemWidth,
                          onAlbumChanged: onAlbumChanged,
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

class _FavoritePhotoTile extends StatelessWidget {
  const _FavoritePhotoTile({
    required this.entry,
    required this.width,
    required this.onAlbumChanged,
  });

  final FavoritePhotoEntry entry;
  final double width;
  final ValueChanged<AlbumData> onAlbumChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _PhotoTile(
          photo: entry.photo,
          width: width,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) {
                  return PhotoDetailPage(
                    album: entry.album,
                    photos: entry.album.photos,
                    initialIndex: entry.photoIndex,
                    onAlbumChanged: onAlbumChanged,
                    onPhotosTrashed: (_) {},
                  );
                },
              ),
            );
          },
          onLongPress: () {},
          selectionMode: false,
          selected: false,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.photo.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF4F3827),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.album.title} · ${entry.photo.date}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF8B7765)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrashPhotoScene extends StatefulWidget {
  const _TrashPhotoScene({
    required this.entries,
    required this.desktop,
    required this.hasActiveSearch,
    required this.onTrashPhotoRestored,
    required this.onTrashPhotoDeleted,
    required this.onTrashEmptied,
    this.backgroundImagePath,
  });

  final List<TrashPhotoEntry> entries;
  final bool desktop;
  final bool hasActiveSearch;
  final TrashRestoreCallback onTrashPhotoRestored;
  final ValueChanged<TrashPhotoEntry> onTrashPhotoDeleted;
  final VoidCallback onTrashEmptied;
  final String? backgroundImagePath;

  @override
  State<_TrashPhotoScene> createState() => _TrashPhotoSceneState();
}

class _TrashPhotoSceneState extends State<_TrashPhotoScene> {
  final Set<String> _selectedEntryIds = <String>{};
  bool _selectionMode = false;

  bool get _isSelectionMode => _selectionMode;

  @override
  void didUpdateWidget(covariant _TrashPhotoScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final Set<String> availableIds = widget.entries
        .map((TrashPhotoEntry entry) => entry.id)
        .toSet();
    _selectedEntryIds.removeWhere((String id) => !availableIds.contains(id));
    if (widget.entries.isEmpty) {
      _selectionMode = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasCustomBackground =
        widget.backgroundImagePath != null &&
        widget.backgroundImagePath!.isNotEmpty &&
        File(widget.backgroundImagePath!).existsSync();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.desktop ? 4 : 18,
        vertical: widget.desktop ? 0 : 12,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: widget.desktop
                  ? const Color(0x22000000)
                  : Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.10),
              blurRadius: widget.desktop ? 26 : 20,
              offset: Offset(0, widget.desktop ? 18 : 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.98),
                      const Color(0xFFE9DED2),
                    ],
                  ),
                ),
              ),
              if (hasCustomBackground)
                Positioned.fill(
                  child: Opacity(
                    opacity: widget.desktop ? 0.16 : 0.12,
                    child: Image.file(
                      File(widget.backgroundImagePath!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              if (widget.entries.isEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.desktop ? 26 : 14,
                    widget.desktop ? 24 : 14,
                    widget.desktop ? 26 : 14,
                    widget.desktop ? 18 : 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _TrashPhotoSceneHeader(
                        entryCount: widget.entries.length,
                        onEmptyPressed: null,
                        onSelectionPressed: null,
                        onRestoreSelectedPressed: null,
                        selectionMode: false,
                        selectedCount: 0,
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.14),
                              ),
                            ),
                            child: Text(
                              widget.hasActiveSearch
                                  ? '没有找到匹配的回收站照片。'
                                  : '回收站里还没有照片。',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.68),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.desktop ? 26 : 14,
                    widget.desktop ? 24 : 14,
                    widget.desktop ? 26 : 14,
                    widget.desktop ? 18 : 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _TrashPhotoSceneHeader(
                        entryCount: widget.entries.length,
                        onEmptyPressed: () => _handleEmptyTrash(context),
                        onSelectionPressed: _toggleSelectionMode,
                        onRestoreSelectedPressed: () => _restoreSelected(context),
                        selectionMode: _isSelectionMode,
                        selectedCount: _selectedEntryIds.length,
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: _TrashPhotoGrid(
                          entries: widget.entries,
                          onTrashPhotoRestored: widget.onTrashPhotoRestored,
                          onTrashPhotoDeleted: widget.onTrashPhotoDeleted,
                          selectionMode: _isSelectionMode,
                          selectedEntryIds: _selectedEntryIds,
                          onSelectionChanged: _toggleEntrySelection,
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
  }

  Future<void> _handleEmptyTrash(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('清空回收站'),
          content: Text('确认彻底删除回收站里的 ${widget.entries.length} 张照片吗？此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    widget.onTrashEmptied();
    showPrototypeMessage(context, '已清空回收站');
  }

  void _toggleSelectionMode() {
    setState(() {
      if (_isSelectionMode) {
        _selectionMode = false;
        _selectedEntryIds.clear();
      } else {
        _selectionMode = true;
      }
    });
  }

  void _toggleEntrySelection(TrashPhotoEntry entry) {
    setState(() {
      if (_selectedEntryIds.contains(entry.id)) {
        _selectedEntryIds.remove(entry.id);
      } else {
        _selectedEntryIds.add(entry.id);
      }
    });
  }

  void _restoreSelected(BuildContext context) {
    if (_selectedEntryIds.isEmpty) {
      showPrototypeMessage(context, '请先选择要恢复的照片');
      return;
    }
    final List<TrashPhotoEntry> selectedEntries = widget.entries.where((
      TrashPhotoEntry entry,
    ) {
      return _selectedEntryIds.contains(entry.id);
    }).toList();
    if (selectedEntries.isEmpty) {
      return;
    }
    for (final TrashPhotoEntry entry in selectedEntries) {
      widget.onTrashPhotoRestored(entry);
    }
    setState(() {
      _selectionMode = false;
      _selectedEntryIds.clear();
    });
    showPrototypeMessage(context, '已批量恢复 ${selectedEntries.length} 张照片');
  }
}

class _TrashPhotoSceneHeader extends StatelessWidget {
  const _TrashPhotoSceneHeader({
    required this.entryCount,
    required this.onEmptyPressed,
    required this.onSelectionPressed,
    required this.onRestoreSelectedPressed,
    required this.selectionMode,
    required this.selectedCount,
  });

  final int entryCount;
  final VoidCallback? onEmptyPressed;
  final VoidCallback? onSelectionPressed;
  final VoidCallback? onRestoreSelectedPressed;
  final bool selectionMode;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '回收站',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF4F3827),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                selectedCount > 0
                    ? '已选中 $selectedCount 张照片，可批量恢复。'
                    : entryCount == 0
                    ? '删除的照片会暂存在这里。'
                    : '当前共 $entryCount 张照片，可恢复或彻底删除。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF8B7765),
                ),
              ),
            ],
          ),
        ),
        if (onSelectionPressed != null)
          TextButton.icon(
            onPressed: onSelectionPressed,
            icon: Icon(
              selectionMode ? Icons.deselect_rounded : Icons.select_all_rounded,
            ),
            label: Text(selectionMode ? '取消批量选中' : '批量选中'),
          ),
        if (onRestoreSelectedPressed != null)
          TextButton.icon(
            onPressed: selectionMode ? onRestoreSelectedPressed : null,
            icon: const Icon(Icons.restore_page_rounded),
            label: const Text('批量恢复'),
          ),
        if (onEmptyPressed != null)
          TextButton.icon(
            onPressed: onEmptyPressed,
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('清空回收站'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}

class _TrashPhotoGrid extends StatelessWidget {
  const _TrashPhotoGrid({
    required this.entries,
    required this.onTrashPhotoRestored,
    required this.onTrashPhotoDeleted,
    required this.selectionMode,
    required this.selectedEntryIds,
    required this.onSelectionChanged,
  });

  final List<TrashPhotoEntry> entries;
  final TrashRestoreCallback onTrashPhotoRestored;
  final ValueChanged<TrashPhotoEntry> onTrashPhotoDeleted;
  final bool selectionMode;
  final Set<String> selectedEntryIds;
  final ValueChanged<TrashPhotoEntry> onSelectionChanged;

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
        final List<List<TrashPhotoEntry>> lanes =
            List<List<TrashPhotoEntry>>.generate(
              columns,
              (_) => <TrashPhotoEntry>[],
            );
        final List<double> heights = List<double>.filled(columns, 0);

        for (final TrashPhotoEntry entry in entries) {
          int lane = 0;
          for (int index = 1; index < columns; index += 1) {
            if (heights[index] < heights[lane]) {
              lane = index;
            }
          }
          lanes[lane].add(entry);
          heights[lane] += _itemHeight(entry.photo, itemWidth) + gap;
        }

        return SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(columns, (int column) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: column == 0 ? 0 : gap),
                  child: Column(
                    children: lanes[column].map((TrashPhotoEntry entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TrashPhotoTile(
                          entry: entry,
                          width: itemWidth,
                          onTrashPhotoRestored: onTrashPhotoRestored,
                          onTrashPhotoDeleted: onTrashPhotoDeleted,
                          selectionMode: selectionMode,
                          selected: selectedEntryIds.contains(entry.id),
                          onSelectionChanged: onSelectionChanged,
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

class _TrashPhotoTile extends StatelessWidget {
  const _TrashPhotoTile({
    required this.entry,
    required this.width,
    required this.onTrashPhotoRestored,
    required this.onTrashPhotoDeleted,
    required this.selectionMode,
    required this.selected,
    required this.onSelectionChanged,
  });

  final TrashPhotoEntry entry;
  final double width;
  final TrashRestoreCallback onTrashPhotoRestored;
  final ValueChanged<TrashPhotoEntry> onTrashPhotoDeleted;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<TrashPhotoEntry> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _PhotoTile(
          photo: entry.photo,
          width: width,
          onTap: () {
            if (selectionMode) {
              onSelectionChanged(entry);
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) {
                  return FullscreenPhotoPage(
                    photo: entry.photo,
                    initialTurns: 0,
                    initialZoom: 1,
                  );
                },
              ),
            );
          },
          onLongPress: () => onSelectionChanged(entry),
          selectionMode: selectionMode,
          selected: selected,
          selectedBorderColor: const Color(0xFFFF3B30),
          selectedBorderWidth: 2,
          showSelectionCheckmark: false,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.photo.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF4F3827),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.albumTitle} · 删除于 ${entry.deletedAt}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF8B7765)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => _handleRestore(context),
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('恢复'),
                  ),
                  TextButton.icon(
                    onPressed: () => _handleDelete(context),
                    icon: const Icon(Icons.delete_forever_rounded, size: 18),
                    label: const Text('彻底删除'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleRestore(BuildContext context) {
    final String restoredAlbumTitle = onTrashPhotoRestored(entry);
    showPrototypeMessage(context, '已恢复到“$restoredAlbumTitle”');
  }

  Future<void> _handleDelete(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('彻底删除照片'),
          content: Text('确认彻底删除“${entry.photo.title}”吗？此操作不可撤销。'),
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
    if (!context.mounted) {
      return;
    }
    onTrashPhotoDeleted(entry);
    showPrototypeMessage(context, '已彻底删除');
  }
}

class PhotoVisual extends StatelessWidget {
  const PhotoVisual({
    required this.photo,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.scale = 1,
    super.key,
  });

  final PhotoData photo;
  final BoxFit fit;
  final Alignment alignment;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    final String? imagePath = photo.imagePath;
    if (imagePath != null) {
      final File file = File(imagePath);
      if (file.existsSync()) {
        child = Image.file(
          file,
          fit: fit,
          alignment: alignment,
          errorBuilder: (_, _, _) => ScenicArtwork(style: photo.style),
        );
        return Transform.scale(
          scale: scale,
          alignment: alignment,
          child: child,
        );
      }
    }
    child = ScenicArtwork(style: photo.style);
    return Transform.scale(scale: scale, alignment: alignment, child: child);
  }
}

class AlbumCoverVisual extends StatelessWidget {
  const AlbumCoverVisual({required this.album, super.key});

  final AlbumData album;

  @override
  Widget build(BuildContext context) {
    final PhotoData? coverPhoto = album.coverPhoto;
    if (coverPhoto == null) {
      return ScenicArtwork(style: album.style);
    }
    return PhotoVisual(
      photo: coverPhoto,
      alignment: Alignment(album.coverOffsetX, album.coverOffsetY),
      scale: album.coverScale,
    );
  }
}

class _AlbumCoverPreview extends StatelessWidget {
  const _AlbumCoverPreview({
    required this.photo,
    required this.style,
    required this.coverScale,
    required this.coverOffsetX,
    required this.coverOffsetY,
  });

  final PhotoData? photo;
  final PhotoStyle style;
  final double coverScale;
  final double coverOffsetX;
  final double coverOffsetY;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (photo != null)
            PhotoVisual(
              photo: photo!,
              alignment: Alignment(coverOffsetX, coverOffsetY),
              scale: coverScale,
            )
          else
            ScenicArtwork(style: style),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  const Color(0x12000000),
                  const Color(0x6A1E140F),
                ],
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Text(
              photo == null ? '当前使用默认封面样式' : '拖动滑块调整封面取景范围',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
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
        const Radius.circular(5),
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
  const _ArrowButton({
    required this.icon,
    required this.onPressed,
    this.subdued = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: subdued ? const Color(0x66FFF7EE) : const Color(0xCC9B7855),
      shape: const CircleBorder(),
      elevation: subdued ? 0 : 1,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            color: subdued ? const Color(0xFF7F5F44) : Colors.white,
            size: 28,
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
        const Radius.circular(5),
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
    this.coverScale = 1,
    this.coverOffsetX = 0,
    this.coverOffsetY = 0,
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final PhotoStyle style;
  final List<PhotoData> photos;
  final String? coverPhotoId;
  final double coverScale;
  final double coverOffsetX;
  final double coverOffsetY;

  AlbumData copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? description,
    PhotoStyle? style,
    List<PhotoData>? photos,
    Object? coverPhotoId = _fieldUnset,
    double? coverScale,
    double? coverOffsetX,
    double? coverOffsetY,
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
      coverScale: coverScale ?? this.coverScale,
      coverOffsetX: coverOffsetX ?? this.coverOffsetX,
      coverOffsetY: coverOffsetY ?? this.coverOffsetY,
    );
  }

  AlbumData withInsertedPhoto(PhotoData photo) {
    final List<PhotoData> nextPhotos = <PhotoData>[photo, ...photos];
    return copyWith(
      photos: nextPhotos,
      subtitle: _updatedSubtitle(nextPhotos.length),
    );
  }

  AlbumData withInsertedPhotoAt(int index, PhotoData photo) {
    final List<PhotoData> nextPhotos = List<PhotoData>.from(photos);
    final int safeIndex = index.clamp(0, nextPhotos.length);
    nextPhotos.insert(safeIndex, photo);
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
      'coverScale': coverScale,
      'coverOffsetX': coverOffsetX,
      'coverOffsetY': coverOffsetY,
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
      coverScale: (json['coverScale'] as num?)?.toDouble() ?? 1,
      coverOffsetX: (json['coverOffsetX'] as num?)?.toDouble() ?? 0,
      coverOffsetY: (json['coverOffsetY'] as num?)?.toDouble() ?? 0,
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
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String date;
  final String note;
  final PhotoOrientation orientation;
  final PhotoStyle style;
  final String? imagePath;
  final bool isFavorite;

  PhotoData copyWith({
    String? id,
    String? title,
    String? date,
    String? note,
    PhotoOrientation? orientation,
    PhotoStyle? style,
    String? imagePath,
    bool? isFavorite,
  }) {
    return PhotoData(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      note: note ?? this.note,
      orientation: orientation ?? this.orientation,
      style: style ?? this.style,
      imagePath: imagePath ?? this.imagePath,
      isFavorite: isFavorite ?? this.isFavorite,
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
      'isFavorite': isFavorite,
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
      isFavorite: json['isFavorite'] as bool? ?? false,
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
    required this.description,
    required this.style,
    this.coverPhotoId,
    this.coverScale = 1,
    this.coverOffsetX = 0,
    this.coverOffsetY = 0,
    this.deleteAlbum = false,
  });

  final String name;
  final String description;
  final PhotoStyle style;
  final String? coverPhotoId;
  final double coverScale;
  final double coverOffsetX;
  final double coverOffsetY;
  final bool deleteAlbum;
}

class _AlbumTransferTarget {
  const _AlbumTransferTarget._({
    this.albumId,
    this.createNew = false,
  });

  const _AlbumTransferTarget.existing(String albumId)
    : this._(albumId: albumId);

  const _AlbumTransferTarget.createNew() : this._(createNew: true);

  final String? albumId;
  final bool createNew;
}

class LocalImportSnapshot {
  const LocalImportSnapshot({required this.albums, required this.appearance});

  final List<AlbumData> albums;
  final PrototypeAppearance appearance;
}
