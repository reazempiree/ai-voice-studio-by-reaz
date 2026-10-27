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
      expect(find.textContaining('ফোনে ইংরেজি কণ্ঠ ক্লোনিং'), findsOneWidget);
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.text('আপনার প্রথম কণ্ঠ'), findsOneWidget);
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.text('এখনও অডিও নেই'), findsOneWidget);
      await tester.tap(find.byType(NavigationDestination).at(4));
      await tester.pumpAndSettle();
      expect(find.text('নিজস্ব সার্ভার সংযোগ'), findsOneWidget);
      expect(find.text('ফোনের ইংরেজি মডেল'), findsOneWidget);
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
      controller.inferenceMode = 'server';
      controller.backendUrl = 'https://voice.local';
      controller.token = 'x' * 32;
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

  testWidgets('local English needs no server token or upload checkbox', (
    tester,
  ) async {
    controller.language = 'en';
    controller.pocket.ready = true; // Availability-only UI test, not inference.
    controller.profiles = [
      VoiceProfile(
        id: 'a' * 32,
        name: 'নিজের কণ্ঠ',
        path: '${directory.path}/audio/${'b' * 32}.wav',
        referenceText: 'Hello.',
        createdAt: DateTime(2026),
        durationSeconds: 8,
      ),
    ];
    controller.selectedProfileId = 'a' * 32;
    expect(controller.backendUrl, isEmpty);
    expect(controller.token, isEmpty);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(VoiceStudioApp(controller: controller));
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('generate-button')))
          .onPressed,
      isNotNull,
    );
    expect(
      find.textContaining('কণ্ঠের নমুনা ও লেখা ফোনেই থাকবে'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Bengali is blocked locally with an actionable English alternative',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(VoiceStudioApp(controller: controller));
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('generate-button')))
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('বাংলার জন্য পরীক্ষিত ফোনের মডেল নেই'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('choose-offline-english')),
      );
      await tester.tap(find.byKey(const Key('choose-offline-english')));
      await tester.pumpAndSettle();
      expect(controller.language, 'en');
      expect(controller.error, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('generation-setup')));
      await tester.tap(find.byKey(const Key('generation-setup')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('local-model-manager')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'local model download requires an explicit size and license confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(VoiceStudioApp(controller: controller));
      await tester.tap(find.byType(NavigationDestination).at(4));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('download-local-model')));
      await tester.tap(find.byKey(const Key('download-local-model')));
      await tester.pumpAndSettle();
      expect(find.text('ফোনের মডেল নামাবেন?'), findsOneWidget);
      expect(find.textContaining('98336520'), findsOneWidget);
      expect(find.textContaining('CC-BY-4.0'), findsWidgets);
      expect(controller.pocket.busy, isFalse);
      await tester.tap(find.text('ফিরে যান'));
      await tester.pumpAndSettle();
      expect(controller.pocket.busy, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('reference import is gated by ownership permission', (
    tester,
  ) async {
    controller.inferenceMode = 'server';
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
  testWidgets('local import does not require a reference transcript', (
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
    expect(find.text('রেকর্ডিংয়ের লেখা (ঐচ্ছিক)'), findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('import-select-file')));
    await tester.tap(find.byKey(const Key('import-select-file')));
    await tester.pumpAndSettle();
    expect(find.text('একটি নাম লিখুন।'), findsOneWidget);
    expect(find.text('নমুনার হুবহু লেখা দিন।'), findsNothing);
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
