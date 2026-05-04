import 'package:album_app/main.dart';
import 'package:flutter/material.dart';
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

  testWidgets('can open album detail and add photo page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PageView));
    await tester.pumpAndSettle();

    expect(find.text('添加照片'), findsOneWidget);

    await tester.tap(find.text('添加照片'));
    await tester.pumpAndSettle();

    expect(find.text('点击选择图片'), findsOneWidget);
    expect(find.text('照片日期'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('album detail supports entering multi-select mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PageView));
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

    await tester.tap(find.byType(PageView));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(PhotoVisual).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    expect(find.text('取消全选'), findsOneWidget);
  });

  testWidgets('photo detail supports editing and saving photo date', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PageView));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PhotoVisual).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('照片日期'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '2026年5月4日');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('2026年5月4日'), findsOneWidget);
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
            onAlbumChanged: (_) {},
            onAlbumDeleted: (_) {},
            appearance: appearance,
            onAppearanceChanged: (_) {},
            onAlbumCreated: (_) {},
            onExportDataPressed: () async {},
            onImportDataPressed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('desktop-search-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('desktop-search-panel')), findsOneWidget);
    expect(find.text('搜索相册'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-search-dismiss-layer')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('desktop-search-panel')), findsNothing);
    expect(find.text('搜索相册'), findsNothing);
  });

  test('album json preserves cover framing values', () {
    const AlbumData album = AlbumData(
      id: 'album-1',
      title: '封面测试',
      subtitle: '1 张照片 · 2026年5月',
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
