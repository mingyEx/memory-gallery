// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:album_app/main.dart';

void main() {
  testWidgets('Album home page renders basic controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        repository: InMemoryAlbumRepository(
          initialEntries: <AlbumEntry>[
            AlbumEntry(
              imagePath: 'missing-file.jpg',
              note: '测试备注',
              createdAt: DateTime(2026, 4, 26, 14, 30),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('电子相册'), findsAtLeastNWidgets(1));
    expect(find.text('工作区'), findsOneWidget);
    expect(find.text('选择图片'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('清空输入'), findsOneWidget);
  });

  testWidgets('App uses dark theme mode from settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        repository: InMemoryAlbumRepository(
          initialSettings: const AppSettings(
            themeMode: AlbumThemeMode.dark,
            backgroundColorValue: 0xFF5B8DEF,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final MaterialApp app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
