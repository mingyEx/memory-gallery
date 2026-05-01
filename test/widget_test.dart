import 'package:album_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home page renders album prototype shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlbumPrototypeApp());
    await tester.pumpAndSettle();

    expect(find.text('电子相册'), findsAtLeastNWidgets(1));
    expect(find.text('记录生活，珍藏回忆'), findsOneWidget);
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

    expect(find.text('图片占位区'), findsOneWidget);
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
