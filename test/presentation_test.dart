import 'dart:io';

import 'package:ai_voice_studio/application/app_controller.dart';
import 'package:ai_voice_studio/data/local_store.dart';
import 'package:ai_voice_studio/domain/models.dart';
import 'package:ai_voice_studio/presentation/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late AppController controller;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('studio_ui_');
    controller = AppController(LocalStore(directory));
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'dashboard and all navigation destinations show honest empty states',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(VoiceStudioApp(controller: controller));
      expect(find.text('আপনার কণ্ঠ, আপনার গল্প'), findsOneWidget);
      expect(
        find.textContaining('ফোনের ভেতরে কণ্ঠ ক্লোনিং চালু নেই'),
        findsOneWidget,
      );
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.text('আপনার প্রথম কণ্ঠ'), findsOneWidget);
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.text('এখনও অডিও নেই'), findsOneWidget);
      await tester.tap(find.byType(NavigationDestination).at(4));
      await tester.pumpAndSettle();
      expect(find.text('নিজস্ব সার্ভার সংযোগ'), findsOneWidget);
      expect(
        find.textContaining('ফোনের ভেতরে ক্লোনিং মডেল নেই'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Bengali editor preserves Unicode text across navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(VoiceStudioApp(controller: controller));
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('generation-text')),
      'আমার সোনার বাংলা। Hello!',
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'আমার সোনার বাংলা। Hello!');
    await tester.tap(find.byType(NavigationDestination).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(
      find.byKey(const Key('generation-text')),
    );
    expect(editor.controller!.text, 'আমার সোনার বাংলা। Hello!');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'generation requires separate permission to upload a saved reference',
    (tester) async {
      controller.profiles = [
        VoiceProfile(
          id: 'a' * 32,
          name: 'নিজের কণ্ঠ',
          path: '${directory.path}/audio/${'b' * 32}.wav',
          referenceText: 'নমুনা কথা',
          createdAt: DateTime(2026),
          durationSeconds: 8,
        ),
      ];
      controller.selectedProfileId = 'a' * 32;
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(VoiceStudioApp(controller: controller));
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      var button = tester.widget<FilledButton>(
        find.byKey(const Key('generate-button')),
      );
      expect(button.onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      button = tester.widget<FilledButton>(
        find.byKey(const Key('generate-button')),
      );
      expect(button.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('reference import is gated by ownership permission', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(VoiceStudioApp(controller: controller));
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('রেকর্ডিং বাছুন'));
    await tester.pumpAndSettle();
    final buttonFinder = find.byKey(const Key('import-select-file'));
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
    expect(find.text('একটি নাম লিখুন।'), findsOneWidget);
    expect(find.text('নমুনার হুবহু লেখা দিন।'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('all destinations fit a small Android screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(VoiceStudioApp(controller: controller));
    for (var tab = 0; tab < 5; tab++) {
      await tester.tap(find.byType(NavigationDestination).at(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
