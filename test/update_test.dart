import 'package:ai_voice_studio/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stable versions compare major, minor and patch in order', () {
    expect(isNewerVersion('v1.0.0', '0.9.9'), isTrue);
    expect(isNewerVersion('0.2.0', '0.1.9'), isTrue);
    expect(isNewerVersion('0.1.1', '0.1.0+4'), isTrue);
    expect(isNewerVersion('0.1.0', '0.1.0'), isFalse);
    expect(isNewerVersion('0.9.9', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
  });
  test('untrusted malformed and prerelease tags are ignored', () {
    for (final tag in ['next', '2.0', '1.0.0-beta', '-1.2.0', 'https://evil']) {
      expect(isNewerVersion(tag, '0.1.0'), isFalse);
    }
  });
}
