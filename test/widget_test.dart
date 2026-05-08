import 'package:album_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home page renders album prototype shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    expect(find.text('创建相册'), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsWidgets);
    expect(find.text('创建相册'), findsOneWidget);
    expect(find.text('2024 川西之旅'), findsWidgets);
  });

  testWidgets('mobile home uses focused album stage layout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('mobile-focused-album-stage')),
      findsWidgets,
    );
  });

  testWidgets('mobile home shows sidebar sections as top navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('mobile-home-section-bar')),
      findsOneWidget,
    );
    expect(find.text('单相册'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    expect(find.text('当前还没有收藏照片。'), findsOneWidget);
  });

  testWidgets('mobile album button cycles through three view modes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    expect(find.text('单相册'), findsOneWidget);

    await tester.tap(find.text('单相册'));
    await tester.pumpAndSettle();
    expect(find.text('六宫格'), findsOneWidget);

    await tester.tap(find.text('六宫格'));
    await tester.pumpAndSettle();
    expect(find.text('书脊墙'), findsOneWidget);

    await tester.tap(find.text('书脊墙'));
    await tester.pumpAndSettle();
    expect(find.text('单相册'), findsOneWidget);
  });

  testWidgets('album detail shows add photo import action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-focused-album-stage')).first,
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('album detail supports entering multi-select mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-focused-album-stage')).first,
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(PhotoVisual).first);
    await tester.pumpAndSettle();

    expect(find.text('已选择 1 张'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsWidgets);
  });

  testWidgets('album detail supports select all in multi-select mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-focused-album-stage')).first,
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(PhotoVisual).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    expect(find.text('取消全选'), findsOneWidget);
  });

  testWidgets('photo detail supports editing and saving title body and date', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mobile-focused-album-stage')).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PhotoVisual).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('照片标题'), findsOneWidget);
    expect(find.text('照片日期'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '新的照片标题');
    await tester.enterText(find.byType(TextField).at(1), '2026年5月4日');
    await tester.enterText(find.byType(TextField).at(2), '新的正文内容');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('新的照片标题'), findsOneWidget);
    expect(find.text('2026年5月4日'), findsOneWidget);
    expect(find.text('新的正文内容'), findsOneWidget);
  });

  testWidgets('photo detail renders note content as markdown', (
    WidgetTester tester,
  ) async {
    final AlbumData album = buildDemoAlbums().first;
    final List<PhotoData> photos = <PhotoData>[
      album.photos.first.copyWith(note: '# 小标题\n\n**加粗正文**'),
      ...album.photos.skip(1),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoDetailPage(
          album: album.copyWith(photos: photos),
          photos: photos,
          initialIndex: 0,
          onAlbumChanged: (_) {},
          onPhotosTrashed: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('小标题'), findsOneWidget);
    expect(find.text('加粗正文'), findsOneWidget);
  });

  testWidgets('photo detail uses stacked layout on mobile width', (
    WidgetTester tester,
  ) async {
    final AlbumData album = buildDemoAlbums().first;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(430, 932)),
        child: MaterialApp(
          home: PhotoDetailPage(
            album: album,
            photos: album.photos,
            initialIndex: 0,
            onAlbumChanged: (_) {},
            onPhotosTrashed: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('mobile-photo-detail-layout')),
      findsOneWidget,
    );
  });

  testWidgets('photo detail switches photos with keyboard arrow keys', (
    WidgetTester tester,
  ) async {
    final AlbumData album = buildDemoAlbums().first;

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoDetailPage(
          album: album,
          photos: album.photos,
          initialIndex: 0,
          onAlbumChanged: (_) {},
          onPhotosTrashed: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 6'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.text('2 / 6'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.text('1 / 6'), findsOneWidget);
  });

  testWidgets('photo detail shows first photo edge message on left arrow', (
    WidgetTester tester,
  ) async {
    final AlbumData album = buildDemoAlbums().first;

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoDetailPage(
          album: album,
          photos: album.photos,
          initialIndex: 0,
          onAlbumChanged: (_) {},
          onPhotosTrashed: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(find.text('已经是第一张照片'), findsOneWidget);
  });

  testWidgets('photo detail shows last photo edge message on right arrow', (
    WidgetTester tester,
  ) async {
    final AlbumData album = buildDemoAlbums().first;

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoDetailPage(
          album: album,
          photos: album.photos,
          initialIndex: album.photos.length - 1,
          onAlbumChanged: (_) {},
          onPhotosTrashed: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('6 / 6'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(find.text('已经是最后一张照片'), findsOneWidget);
  });

  testWidgets('album detail shows photo title under each photo', (
    WidgetTester tester,
  ) async {
    final AlbumData album = buildDemoAlbums().first;

    await tester.pumpWidget(
      MaterialApp(
        home: AlbumDetailPage(
          album: album,
          albums: <AlbumData>[album],
          onAlbumChanged: (_) {},
          onAlbumsChanged: (_) {},
          onPhotosTrashed: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('在四姑娘山的清晨'), findsOneWidget);
  });

  testWidgets('album editor persists cover framing controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('封面缩放'), findsOneWidget);
    expect(find.text('水平位置'), findsOneWidget);
    expect(find.text('垂直位置'), findsOneWidget);

    final Slider scaleSlider = tester.widget<Slider>(find.byType(Slider).at(0));
    final Slider offsetXSlider = tester.widget<Slider>(
      find.byType(Slider).at(1),
    );
    final Slider offsetYSlider = tester.widget<Slider>(
      find.byType(Slider).at(2),
    );

    scaleSlider.onChanged?.call(1.6);
    offsetXSlider.onChanged?.call(0.4);
    offsetYSlider.onChanged?.call(-0.3);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    final bool hasAdjustedCover = tester
        .widgetList<AlbumCoverVisual>(find.byType(AlbumCoverVisual))
        .any((AlbumCoverVisual widget) {
          return widget.album.coverScale > 1 ||
              widget.album.coverOffsetX != 0 ||
              widget.album.coverOffsetY != 0;
        });
    expect(hasAdjustedCover, isTrue);
  });

  testWidgets('desktop search closes when tapping outside panel', (
    WidgetTester tester,
  ) async {
    const PrototypeAppearance appearance = PrototypeAppearance(
      themeMode: ThemeMode.light,
      themeStyle: PrototypeThemeStyle.warm,
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1400, 900)),
        child: MaterialApp(
          home: AlbumHomePage(
            albums: buildDemoAlbums(),
            recycleBin: const <TrashPhotoEntry>[],
            onAlbumChanged: (_) {},
            onAlbumsChanged: (_) {},
            onAlbumDeleted: (_) {},
            onPhotosTrashed: (_) {},
            onTrashPhotoRestored: (_) => '测试相册',
            onTrashPhotoDeleted: (_) {},
            onTrashEmptied: () {},
            appearance: appearance,
            onAppearanceChanged: (_) {},
            onAlbumCreated: (_) {},
            onExportDataPressed: () async {},
            onImportDataPressed: () async {},
            onCustomBackgroundPressed: () async {},
            onClearBackgroundPressed: () async {},
            onAboutSoftwarePressed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-search-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('desktop-search-panel')),
      findsOneWidget,
    );
    expect(find.text('搜索相册'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-search-dismiss-layer')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('desktop-search-panel')),
      findsNothing,
    );
    expect(find.text('搜索相册'), findsNothing);
  });

  testWidgets('trash scene can restore photo from desktop sidebar', (
    WidgetTester tester,
  ) async {
    const PrototypeAppearance appearance = PrototypeAppearance(
      themeMode: ThemeMode.light,
      themeStyle: PrototypeThemeStyle.warm,
    );
    final AlbumData sourceAlbum = buildDemoAlbums().first;
    final TrashPhotoEntry entry = TrashPhotoEntry(
      id: 'trash-1',
      albumId: sourceAlbum.id,
      albumTitle: sourceAlbum.title,
      photo: sourceAlbum.photos.first,
      originalPhotoIndex: 0,
      deletedAt: '2026-05-05T10:00:00.000',
    );
    bool restored = false;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1400, 900)),
        child: MaterialApp(
          home: AlbumHomePage(
            albums: buildDemoAlbums(),
            recycleBin: <TrashPhotoEntry>[entry],
            onAlbumChanged: (_) {},
            onAlbumsChanged: (_) {},
            onAlbumDeleted: (_) {},
            onPhotosTrashed: (_) {},
            onTrashPhotoRestored: (TrashPhotoEntry restoredEntry) {
              restored = restoredEntry.id == entry.id;
              return restoredEntry.albumTitle;
            },
            onTrashPhotoDeleted: (_) {},
            onTrashEmptied: () {},
            appearance: appearance,
            onAppearanceChanged: (_) {},
            onAlbumCreated: (_) {},
            onExportDataPressed: () async {},
            onImportDataPressed: () async {},
            onCustomBackgroundPressed: () async {},
            onClearBackgroundPressed: () async {},
            onAboutSoftwarePressed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复'));
    await tester.pump();

    expect(restored, isTrue);
    expect(find.text('已恢复到“2024 川西之旅”'), findsOneWidget);
  });

  testWidgets('trash scene can empty recycle bin', (WidgetTester tester) async {
    const PrototypeAppearance appearance = PrototypeAppearance(
      themeMode: ThemeMode.light,
      themeStyle: PrototypeThemeStyle.warm,
    );
    final AlbumData sourceAlbum = buildDemoAlbums().first;
    final TrashPhotoEntry entry = TrashPhotoEntry(
      id: 'trash-1',
      albumId: sourceAlbum.id,
      albumTitle: sourceAlbum.title,
      photo: sourceAlbum.photos.first,
      originalPhotoIndex: 0,
      deletedAt: '2026-05-05T10:00:00.000',
    );
    bool emptied = false;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1400, 900)),
        child: MaterialApp(
          home: AlbumHomePage(
            albums: buildDemoAlbums(),
            recycleBin: <TrashPhotoEntry>[entry],
            onAlbumChanged: (_) {},
            onAlbumsChanged: (_) {},
            onAlbumDeleted: (_) {},
            onPhotosTrashed: (_) {},
            onTrashPhotoRestored: (_) => '测试相册',
            onTrashPhotoDeleted: (_) {},
            onTrashEmptied: () {
              emptied = true;
            },
            appearance: appearance,
            onAppearanceChanged: (_) {},
            onAlbumCreated: (_) {},
            onExportDataPressed: () async {},
            onImportDataPressed: () async {},
            onCustomBackgroundPressed: () async {},
            onClearBackgroundPressed: () async {},
            onAboutSoftwarePressed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空回收站'));
    await tester.pumpAndSettle();

    expect(find.text('清空回收站'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pump();

    expect(emptied, isTrue);
    expect(find.text('已清空回收站'), findsOneWidget);
  });

  test('album json preserves cover framing values', () {
    const String timestamp = '2026-05-04T10:30:00.000';
    const AlbumData album = AlbumData(
      id: 'album-1',
      title: '封面测试',
      subtitle: '1 张照片 · 2026年5月',
      createdAt: timestamp,
      updatedAt: timestamp,
      description: 'desc',
      style: PhotoStyle.sunlitRoom,
      photos: <PhotoData>[
        PhotoData(
          id: 'photo-1',
          title: '封面',
          date: '2026年5月4日',
          note: 'note',
          orientation: PhotoOrientation.landscape,
          style: PhotoStyle.sunlitRoom,
        ),
      ],
      coverPhotoId: 'photo-1',
      coverScale: 1.6,
      coverOffsetX: 0.35,
      coverOffsetY: -0.25,
    );

    final AlbumData restored = AlbumData.fromJson(album.toJson());

    expect(restored.coverScale, 1.6);
    expect(restored.coverOffsetX, 0.35);
    expect(restored.coverOffsetY, -0.25);
  });

  testWidgets('material app keeps warm seed theme', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    final MaterialApp app = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(app.theme?.colorScheme.primary, const Color(0xFF8E6847));
  });
}
