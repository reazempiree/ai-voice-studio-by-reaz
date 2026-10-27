import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'application/app_controller.dart';
import 'data/local_store.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Serif Bengali',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final directory = await getApplicationSupportDirectory();
  final controller = AppController(LocalStore(directory));
  await controller.initialize();
  runApp(VoiceStudioApp(controller: controller));
}
