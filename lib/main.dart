import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp(repository: LocalAlbumRepository()));
}

class MyApp extends StatefulWidget {
  const MyApp({required this.repository, super.key});

  final AlbumRepository repository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppSettings _settings = AppSettings.defaults();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final AppSettings settings = await widget.repository.loadSettings();
    if (!mounted) {
      return;
    }

    setState(() {
      _settings = settings;
    });
  }

  Future<void> _updateSettings(AppSettings settings) async {
    final AppSettings savedSettings = await widget.repository.saveSettings(
      settings,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _settings = savedSettings;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '电子相册',
      debugShowCheckedModeBanner: false,
      themeMode: _settings.themeMode.themeMode,
      theme: _buildTheme(Brightness.light, _settings.backgroundColor),
      darkTheme: _buildTheme(Brightness.dark, _settings.backgroundColor),
      home: AlbumHomePage(
        repository: widget.repository,
        settings: _settings,
        onSettingsChanged: _updateSettings,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness, Color accentColor) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme colorScheme = ColorScheme(
      brightness: brightness,
      primary: accentColor,
      onPrimary: Colors.white,
      secondary: accentColor.withValues(alpha: isDark ? 0.86 : 0.72),
      onSecondary: Colors.white,
      error: const Color(0xFFD13438),
      onError: Colors.white,
      surface: isDark ? const Color(0xFF202020) : const Color(0xFFF6F6F6),
      onSurface: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1F1F1F),
      surfaceContainerHighest:
          isDark ? const Color(0xFF2B2B2B) : const Color(0xFFEAEAEA),
      onSurfaceVariant:
          isDark ? const Color(0xFFD0D0D0) : const Color(0xFF5E5E5E),
      outline: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFD0D0D0),
      outlineVariant:
          isDark ? const Color(0xFF323232) : const Color(0xFFE2E2E2),
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: isDark ? Colors.white : const Color(0xFF1F1F1F),
      onInverseSurface: isDark ? const Color(0xFF1F1F1F) : Colors.white,
      inversePrimary: accentColor.withValues(alpha: 0.7),
    );
    final Color cardColor =
        isDark ? const Color(0xCC2A2A2A) : const Color(0xEFFFFFFF);
    final Color inputFillColor =
        isDark ? const Color(0xFF262626) : const Color(0xFFF9F9F9);

    return ThemeData(
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: !kIsWeb && Platform.isWindows ? 'Segoe UI' : null,
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: cardColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerColor: colorScheme.outlineVariant,
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accentColor, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(44),
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFF222222),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }
}

class AlbumHomePage extends StatefulWidget {
  const AlbumHomePage({
    required this.repository,
    required this.settings,
    required this.onSettingsChanged,
    super.key,
  });

  final AlbumRepository repository;
  final AppSettings settings;
  final Future<void> Function(AppSettings settings) onSettingsChanged;

  @override
  State<AlbumHomePage> createState() => _AlbumHomePageState();
}

String _formatCreatedAt(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

class _AlbumHomePageState extends State<AlbumHomePage> {
  static const List<ThemeColorOption> _themeColors = <ThemeColorOption>[
    ThemeColorOption('海盐蓝', Color(0xFF5B8DEF)),
    ThemeColorOption('奶油杏', Color(0xFFE4A972)),
    ThemeColorOption('森林绿', Color(0xFF4F8A5B)),
    ThemeColorOption('玫瑰粉', Color(0xFFD96C8D)),
    ThemeColorOption('石墨灰', Color(0xFF607D8B)),
  ];

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _noteController = TextEditingController();
  final List<AlbumEntry> _entries = <AlbumEntry>[];

  XFile? _selectedImage;
  String? _selectedEntryPath;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUpdatingAppearance = false;
  String? _deletingImagePath;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final List<AlbumEntry> entries = await widget.repository.loadEntries();
    if (!mounted) {
      return;
    }

    setState(() {
      _entries
        ..clear()
        ..addAll(entries);
      _selectedEntryPath = _resolveSelectedEntryPath(entries);
      _isLoading = false;
    });
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted || image == null) {
      return;
    }

    setState(() {
      _selectedImage = image;
    });
  }

  Future<void> _saveEntry() async {
    final String note = _noteController.text.trim();
    if (_selectedImage == null || note.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择图片并填写备注。')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final AlbumEntry entry = await widget.repository.createEntry(
      sourceImagePath: _selectedImage!.path,
      note: note,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _entries.insert(0, entry);
      _selectedEntryPath = entry.imagePath;
      _clearInput();
      _isSaving = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('保存成功。')));
  }

  Future<void> _deleteEntry(AlbumEntry entry) async {
    setState(() {
      _deletingImagePath = entry.imagePath;
    });

    await widget.repository.deleteEntry(entry);

    if (!mounted) {
      return;
    }

    setState(() {
      _entries.removeWhere(
        (AlbumEntry item) => item.imagePath == entry.imagePath,
      );
      _selectedEntryPath = _resolveSelectedEntryPath(_entries);
      _deletingImagePath = null;
    });
  }

  Future<void> _setThemeMode(AlbumThemeMode mode) async {
    await _saveAppearance(widget.settings.copyWith(themeMode: mode));
  }

  Future<void> _setBackgroundColor(Color color) async {
    await _saveAppearance(
      widget.settings.copyWith(backgroundColorValue: color.toARGB32()),
    );
  }

  Future<void> _pickWallpaper() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      return;
    }

    final String storedPath = await widget.repository.storeWallpaperImage(
      sourceImagePath: image.path,
      previousImagePath: widget.settings.wallpaperPath,
    );
    await _saveAppearance(widget.settings.copyWith(wallpaperPath: storedPath));
  }

  Future<void> _clearWallpaper() async {
    final String? wallpaperPath = widget.settings.wallpaperPath;
    if (wallpaperPath != null) {
      await widget.repository.deleteWallpaperImage(wallpaperPath);
    }
    await _saveAppearance(widget.settings.copyWith(clearWallpaper: true));
  }

  Future<void> _saveAppearance(AppSettings settings) async {
    setState(() {
      _isUpdatingAppearance = true;
    });

    await widget.onSettingsChanged(settings);

    if (!mounted) {
      return;
    }

    setState(() {
      _isUpdatingAppearance = false;
    });
  }

  void _clearInput() {
    _selectedImage = null;
    _noteController.clear();
  }

  String? _resolveSelectedEntryPath(List<AlbumEntry> entries) {
    if (entries.isEmpty) {
      return null;
    }

    final String? current = _selectedEntryPath;
    if (current != null &&
        entries.any((AlbumEntry entry) => entry.imagePath == current)) {
      return current;
    }

    return entries.first.imagePath;
  }

  AlbumEntry? _selectedEntry() {
    final String? selectedPath = _selectedEntryPath;
    if (selectedPath == null) {
      return null;
    }

    for (final AlbumEntry entry in _entries) {
      if (entry.imagePath == selectedPath) {
        return entry;
      }
    }
    return _entries.isEmpty ? null : _entries.first;
  }

  Future<void> _openAppearanceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('界面外观', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _SegmentedSelection<AlbumThemeMode>(
                    value: widget.settings.themeMode,
                    options: AlbumThemeMode.values
                        .map(
                          (AlbumThemeMode mode) => SegmentedOption<AlbumThemeMode>(
                            value: mode,
                            label: mode.label,
                          ),
                        )
                        .toList(),
                    onChanged: _isUpdatingAppearance ? null : _setThemeMode,
                  ),
                  const SizedBox(height: 20),
                  Text('背景主色', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _ColorPaletteGrid(
                    options: _themeColors,
                    selectedColorValue: widget.settings.backgroundColorValue,
                    enabled: !_isUpdatingAppearance,
                    onSelected: _setBackgroundColor,
                  ),
                  const SizedBox(height: 20),
                  Text('背景壁纸', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _SettingsPreviewCard(
                    title: widget.settings.wallpaperPath == null
                        ? '当前未设置壁纸'
                        : '已选择自定义壁纸',
                    subtitle: '壁纸会铺满应用背景，并保留上层内容可读性。',
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: _WallpaperPreview(
                          imagePath: widget.settings.wallpaperPath,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isUpdatingAppearance ? null : _pickWallpaper,
                          icon: const Icon(Icons.wallpaper_outlined),
                          label: const Text('选择壁纸'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _isUpdatingAppearance ||
                                  widget.settings.wallpaperPath == null
                              ? null
                              : _clearWallpaper,
                          icon: const Icon(Icons.layers_clear_outlined),
                          label: const Text('清除壁纸'),
                        ),
                      ),
                    ],
                  ),
                  if (_isUpdatingAppearance) ...<Widget>[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color overlayColor = Theme.of(context).colorScheme.surface.withValues(
      alpha: widget.settings.wallpaperPath == null ? 0.82 : 0.72,
    );
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AlbumEntry? selectedEntry = _selectedEntry();

    return Scaffold(
      appBar: AppBar(
        title: const Text('电子相册'),
        actions: <Widget>[
          IconButton(
            tooltip: '外观设置',
            onPressed: _openAppearanceSheet,
            icon: const Icon(Icons.palette_outlined),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: widget.settings.backgroundColor,
          image: kIsWeb || widget.settings.wallpaperPath == null
              ? null
              : DecorationImage(
                  image: FileImage(File(widget.settings.wallpaperPath!)),
                  fit: BoxFit.cover,
                ),
        ),
        child: Container(
          color: overlayColor,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '工作区',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '电子相册',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '本地保存图片与备注，保留桌面应用式的浏览体验。',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colorScheme.outlineVariant),
                            ),
                            child: Text(
                              _isLoading ? '正在加载' : '共 ${_entries.length} 条记录',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            '内容录入',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '添加新内容',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '从本地选择一张图片，并附上一段备注。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: _isSaving ? null : _pickImage,
                            child: const Text('选择图片'),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 180,
                            child: _ImagePreview(imagePath: _selectedImage?.path),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _noteController,
                            decoration: const InputDecoration(
                              labelText: '备注',
                              border: OutlineInputBorder(),
                            ),
                            minLines: 1,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isSaving ? null : _saveEntry,
                                  child: Text(_isSaving ? '保存中...' : '保存'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isSaving
                                      ? null
                                      : () {
                                          setState(_clearInput);
                                        },
                                  child: const Text('清空输入'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '内容浏览',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '相册记录',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '左侧切换缩略图，右侧查看大图与备注详情。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_entries.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: Text('还没有保存的相册内容。')),
                            )
                          else
                            _PresentationWorkspace(
                              entries: _entries,
                              selectedEntryPath: _selectedEntryPath,
                              onSelectEntry: (AlbumEntry entry) {
                                setState(() {
                                  _selectedEntryPath = entry.imagePath;
                                });
                              },
                              deletingImagePath: _deletingImagePath,
                              onDeleteEntry: _deleteEntry,
                              selectedEntry: selectedEntry,
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
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

class _PresentationWorkspace extends StatelessWidget {
  const _PresentationWorkspace({
    required this.entries,
    required this.selectedEntryPath,
    required this.onSelectEntry,
    required this.deletingImagePath,
    required this.onDeleteEntry,
    required this.selectedEntry,
  });

  final List<AlbumEntry> entries;
  final String? selectedEntryPath;
  final ValueChanged<AlbumEntry> onSelectEntry;
  final String? deletingImagePath;
  final Future<void> Function(AlbumEntry entry) onDeleteEntry;
  final AlbumEntry? selectedEntry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stacked = constraints.maxWidth < 860;

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ThumbnailRail(
                entries: entries,
                selectedEntryPath: selectedEntryPath,
                onSelectEntry: onSelectEntry,
                deletingImagePath: deletingImagePath,
              ),
              const SizedBox(height: 16),
              _DetailStage(
                entry: selectedEntry,
                isDeleting: deletingImagePath == selectedEntry?.imagePath,
                onDelete: selectedEntry == null
                    ? null
                    : () => onDeleteEntry(selectedEntry!),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 250,
              child: _ThumbnailRail(
                entries: entries,
                selectedEntryPath: selectedEntryPath,
                onSelectEntry: onSelectEntry,
                deletingImagePath: deletingImagePath,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _DetailStage(
                entry: selectedEntry,
                isDeleting: deletingImagePath == selectedEntry?.imagePath,
                onDelete: selectedEntry == null
                    ? null
                    : () => onDeleteEntry(selectedEntry!),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThumbnailRail extends StatelessWidget {
  const _ThumbnailRail({
    required this.entries,
    required this.selectedEntryPath,
    required this.onSelectEntry,
    required this.deletingImagePath,
  });

  final List<AlbumEntry> entries;
  final String? selectedEntryPath;
  final ValueChanged<AlbumEntry> onSelectEntry;
  final String? deletingImagePath;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('缩略图', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              final AlbumEntry entry = entries[index];
              final bool selected = entry.imagePath == selectedEntryPath;
              final bool isDeleting = entry.imagePath == deletingImagePath;
              return _ThumbnailTile(
                entry: entry,
                selected: selected,
                isDeleting: isDeleting,
                onTap: () => onSelectEntry(entry),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ThumbnailTile extends StatelessWidget {
  const _ThumbnailTile({
    required this.entry,
    required this.selected,
    required this.isDeleting,
    required this.onTap,
  });

  final AlbumEntry entry;
  final bool selected;
  final bool isDeleting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.16)
          : colorScheme.surface.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? colorScheme.primary : colorScheme.outlineVariant,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 68,
                height: 68,
                child: _ImagePreview(imagePath: entry.imagePath),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatCreatedAt(entry.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (isDeleting) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '删除中...',
                        style: TextStyle(color: colorScheme.primary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailStage extends StatelessWidget {
  const _DetailStage({
    required this.entry,
    required this.isDeleting,
    this.onDelete,
  });

  final AlbumEntry? entry;
  final bool isDeleting;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    if (entry == null) {
      return Container(
        height: 420,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: const Text('请选择一条记录查看内容'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('主画布', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      _formatCreatedAt(entry!.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onDelete,
                child: Text(isDeleting ? '删除中...' : '删除'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _ImagePreview(imagePath: entry!.imagePath),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('备注内容', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                Text(
                  entry!.note,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorPaletteGrid extends StatelessWidget {
  const _ColorPaletteGrid({
    required this.options,
    required this.selectedColorValue,
    required this.enabled,
    required this.onSelected,
  });

  final List<ThemeColorOption> options;
  final int selectedColorValue;
  final bool enabled;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: options.map((ThemeColorOption option) {
        final bool selected = option.color.toARGB32() == selectedColorValue;
        return _ColorSwatchButton(
          option: option,
          selected: selected,
          enabled: enabled,
          onTap: () => onSelected(option.color),
        );
      }).toList(),
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ThemeColorOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool darkChip =
        ThemeData.estimateBrightnessForColor(option.color) == Brightness.dark;

    return SizedBox(
      width: 112,
      child: Material(
        color: enabled
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? colorScheme.primary : colorScheme.outlineVariant,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: option.color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: selected
                      ? Icon(
                          Icons.check,
                          color: darkChip ? Colors.white : Colors.black87,
                        )
                      : null,
                ),
                const SizedBox(height: 10),
                Text(option.label, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPreviewCard extends StatelessWidget {
  const _SettingsPreviewCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class SegmentedOption<T> {
  const SegmentedOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _SegmentedSelection<T> extends StatelessWidget {
  const _SegmentedSelection({
    required this.value,
    required this.options,
    this.onChanged,
  });

  final T value;
  final List<SegmentedOption<T>> options;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: options.map((SegmentedOption<T> option) {
          final bool selected = option.value == value;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: selected ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onChanged == null ? null : () => onChanged!(option.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      option.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WallpaperPreview extends StatelessWidget {
  const _WallpaperPreview({required this.imagePath});

  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    if (imagePath == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Text('当前未设置壁纸')),
      );
    }

    if (kIsWeb) {
      return const ColoredBox(
        color: Color(0xFFE0E0E0),
        child: Center(child: Text('Web 端壁纸预览未启用')),
      );
    }

    return Image.file(
      File(imagePath!),
      fit: BoxFit.cover,
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Text('壁纸文件不可用')),
        );
      },
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({this.imagePath});

  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    if (imagePath == null) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('尚未选择图片'),
      );
    }

    if (kIsWeb) {
      return const ColoredBox(
        color: Color(0xFFE0E0E0),
        child: Center(child: Text('Web 端预览未启用')),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(imagePath!),
        fit: BoxFit.cover,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) {
              return Container(
                alignment: Alignment.center,
                color: const Color(0xFFF3F3F3),
                child: const Text('图片已失效或不存在'),
              );
            },
      ),
    );
  }
}

class ThemeColorOption {
  const ThemeColorOption(this.label, this.color);

  final String label;
  final Color color;
}

enum AlbumThemeMode {
  system('跟随系统', ThemeMode.system),
  light('浅色', ThemeMode.light),
  dark('深色', ThemeMode.dark);

  const AlbumThemeMode(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;

  static AlbumThemeMode fromName(String? value) {
    return AlbumThemeMode.values.firstWhere(
      (AlbumThemeMode mode) => mode.name == value,
      orElse: () => AlbumThemeMode.system,
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.backgroundColorValue,
    this.wallpaperPath,
  });

  final AlbumThemeMode themeMode;
  final int backgroundColorValue;
  final String? wallpaperPath;

  Color get backgroundColor => Color(backgroundColorValue);

  factory AppSettings.defaults() {
    return const AppSettings(
      themeMode: AlbumThemeMode.system,
      backgroundColorValue: 0xFF5B8DEF,
    );
  }

  AppSettings copyWith({
    AlbumThemeMode? themeMode,
    int? backgroundColorValue,
    String? wallpaperPath,
    bool clearWallpaper = false,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
      wallpaperPath: clearWallpaper ? null : (wallpaperPath ?? this.wallpaperPath),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeMode': themeMode.name,
      'backgroundColorValue': backgroundColorValue,
      'wallpaperPath': wallpaperPath,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: AlbumThemeMode.fromName(json['themeMode'] as String?),
      backgroundColorValue:
          (json['backgroundColorValue'] as num?)?.toInt() ?? 0xFF5B8DEF,
      wallpaperPath: json['wallpaperPath'] as String?,
    );
  }
}

class AlbumEntry {
  const AlbumEntry({
    required this.imagePath,
    required this.note,
    required this.createdAt,
  });

  final String imagePath;
  final String note;
  final DateTime createdAt;

  Map<String, String> toJson() {
    return <String, String>{
      'imagePath': imagePath,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AlbumEntry.fromJson(Map<String, dynamic> json) {
    return AlbumEntry(
      imagePath: json['imagePath'] as String,
      note: json['note'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

abstract class AlbumRepository {
  Future<List<AlbumEntry>> loadEntries();

  Future<AlbumEntry> createEntry({
    required String sourceImagePath,
    required String note,
  });

  Future<void> deleteEntry(AlbumEntry entry);

  Future<AppSettings> loadSettings();

  Future<AppSettings> saveSettings(AppSettings settings);

  Future<String> storeWallpaperImage({
    required String sourceImagePath,
    String? previousImagePath,
  });

  Future<void> deleteWallpaperImage(String imagePath);
}

class LocalAlbumRepository implements AlbumRepository {
  static const String _entriesFileName = 'entries.json';
  static const String _settingsFileName = 'settings.json';
  static const String _imagesDirectoryName = 'album_images';
  static const String _wallpaperDirectoryName = 'wallpaper';

  @override
  Future<List<AlbumEntry>> loadEntries() async {
    final File entriesFile = await _entriesFile();
    if (!await entriesFile.exists()) {
      return <AlbumEntry>[];
    }

    final String content = await entriesFile.readAsString();
    if (content.trim().isEmpty) {
      return <AlbumEntry>[];
    }

    final List<dynamic> decoded = jsonDecode(content) as List<dynamic>;
    return decoded
        .map(
          (dynamic item) => AlbumEntry.fromJson(item as Map<String, dynamic>),
        )
        .where((AlbumEntry entry) => File(entry.imagePath).existsSync())
        .toList();
  }

  @override
  Future<AlbumEntry> createEntry({
    required String sourceImagePath,
    required String note,
  }) async {
    final Directory imagesDirectory = await _imagesDirectory();
    final String extension = _fileExtension(sourceImagePath);
    final String fileName =
        '${DateTime.now().microsecondsSinceEpoch}${extension.isEmpty ? '.jpg' : extension}';
    final String targetPath =
        '${imagesDirectory.path}${Platform.pathSeparator}$fileName';

    await File(sourceImagePath).copy(targetPath);

    final AlbumEntry newEntry = AlbumEntry(
      imagePath: targetPath,
      note: note,
      createdAt: DateTime.now(),
    );
    final List<AlbumEntry> currentEntries = await loadEntries();
    final List<AlbumEntry> updatedEntries = <AlbumEntry>[
      newEntry,
      ...currentEntries,
    ];
    await _writeEntries(updatedEntries);
    return newEntry;
  }

  @override
  Future<void> deleteEntry(AlbumEntry entry) async {
    final List<AlbumEntry> currentEntries = await loadEntries();
    final List<AlbumEntry> updatedEntries = currentEntries
        .where((AlbumEntry item) => item.imagePath != entry.imagePath)
        .toList();

    await _writeEntries(updatedEntries);

    final File imageFile = File(entry.imagePath);
    if (await imageFile.exists()) {
      await imageFile.delete();
    }
  }

  @override
  Future<AppSettings> loadSettings() async {
    final File settingsFile = await _settingsFile();
    if (!await settingsFile.exists()) {
      return AppSettings.defaults();
    }

    final String content = await settingsFile.readAsString();
    if (content.trim().isEmpty) {
      return AppSettings.defaults();
    }

    final AppSettings settings = AppSettings.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );
    final String? wallpaperPath = settings.wallpaperPath;
    if (wallpaperPath != null && !File(wallpaperPath).existsSync()) {
      return settings.copyWith(clearWallpaper: true);
    }
    return settings;
  }

  @override
  Future<AppSettings> saveSettings(AppSettings settings) async {
    final File settingsFile = await _settingsFile();
    await settingsFile.writeAsString(jsonEncode(settings.toJson()));
    return settings;
  }

  @override
  Future<String> storeWallpaperImage({
    required String sourceImagePath,
    String? previousImagePath,
  }) async {
    final Directory wallpaperDirectory = await _wallpaperDirectory();
    final String extension = _fileExtension(sourceImagePath);
    final String targetPath =
        '${wallpaperDirectory.path}${Platform.pathSeparator}background${extension.isEmpty ? '.jpg' : extension}';

    if (previousImagePath != null && previousImagePath != targetPath) {
      await deleteWallpaperImage(previousImagePath);
    }

    await File(sourceImagePath).copy(targetPath);
    return targetPath;
  }

  @override
  Future<void> deleteWallpaperImage(String imagePath) async {
    final File imageFile = File(imagePath);
    if (await imageFile.exists()) {
      await imageFile.delete();
    }
  }

  Future<void> _writeEntries(List<AlbumEntry> entries) async {
    final File entriesFile = await _entriesFile();
    final String content = jsonEncode(
      entries.map((AlbumEntry entry) => entry.toJson()).toList(),
    );
    await entriesFile.writeAsString(content);
  }

  Future<File> _entriesFile() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_entriesFileName');
  }

  Future<File> _settingsFile() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_settingsFileName');
  }

  Future<Directory> _imagesDirectory() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final Directory imagesDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}$_imagesDirectoryName',
    );
    if (!await imagesDirectory.exists()) {
      await imagesDirectory.create(recursive: true);
    }
    return imagesDirectory;
  }

  Future<Directory> _wallpaperDirectory() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final Directory wallpaperDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}$_wallpaperDirectoryName',
    );
    if (!await wallpaperDirectory.exists()) {
      await wallpaperDirectory.create(recursive: true);
    }
    return wallpaperDirectory;
  }

  String _fileExtension(String path) {
    final int index = path.lastIndexOf('.');
    if (index < 0 || index == path.length - 1) {
      return '';
    }
    return path.substring(index);
  }
}

class InMemoryAlbumRepository implements AlbumRepository {
  InMemoryAlbumRepository({
    List<AlbumEntry>? initialEntries,
    AppSettings? initialSettings,
  }) : _entries = List<AlbumEntry>.from(initialEntries ?? <AlbumEntry>[]),
       _settings = initialSettings ?? AppSettings.defaults();

  final List<AlbumEntry> _entries;
  AppSettings _settings;

  @override
  Future<List<AlbumEntry>> loadEntries() async {
    return List<AlbumEntry>.from(_entries);
  }

  @override
  Future<AlbumEntry> createEntry({
    required String sourceImagePath,
    required String note,
  }) async {
    final AlbumEntry entry = AlbumEntry(
      imagePath: sourceImagePath,
      note: note,
      createdAt: DateTime.now(),
    );
    _entries.insert(0, entry);
    return entry;
  }

  @override
  Future<void> deleteEntry(AlbumEntry entry) async {
    _entries.removeWhere(
      (AlbumEntry item) => item.imagePath == entry.imagePath,
    );
  }

  @override
  Future<AppSettings> loadSettings() async {
    return _settings;
  }

  @override
  Future<AppSettings> saveSettings(AppSettings settings) async {
    _settings = settings;
    return _settings;
  }

  @override
  Future<String> storeWallpaperImage({
    required String sourceImagePath,
    String? previousImagePath,
  }) async {
    return sourceImagePath;
  }

  @override
  Future<void> deleteWallpaperImage(String imagePath) async {}
}
