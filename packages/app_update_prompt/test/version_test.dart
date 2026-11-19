import 'package:app_update_prompt/app_update_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('orders numerically, not as strings', () {
      expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('2.0.0', '10.0.0'), lessThan(0));
    });
    test('missing parts are zero', () {
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1', '1.0.1'), lessThan(0));
    });
    test('ignores build suffix, prerelease tag and a leading v', () {
      expect(compareVersions('v1.0.5+19', '1.0.5'), 0);
      expect(compareVersions('1.0.5-beta', '1.0.5'), 0);
    });
    test('garbage never throws', () {
      expect(compareVersions('', '1.0.0'), lessThan(0));
      expect(compareVersions('abc', '0.0.0'), 0);
      expect(compareVersions('1.x.3', '1.0.3'), 0);
    });
  });

  group('isNewerRelease', () {
    bool newer(String? v, int? b, String iv, int? ib) => isNewerRelease(
      latestVersion: v,
      latestBuild: b,
      installedVersion: iv,
      installedBuild: ib,
    );
    test('the version name decides first', () {
      expect(newer('1.0.6', 1, '1.0.5', 99), isTrue);
      expect(newer('1.0.4', 99, '1.0.5', 1), isFalse);
    });
    test('same version: the build decides', () {
      expect(newer('1.0.5', 20, '1.0.5', 19), isTrue);
      expect(newer('1.0.5', 19, '1.0.5', 19), isFalse);
      expect(newer('1.0.5', 18, '1.0.5', 19), isFalse);
    });
    test('unknown build on either side is not newer', () {
      expect(newer('1.0.5', null, '1.0.5', 19), isFalse);
      expect(newer('1.0.5', 20, '1.0.5', null), isFalse);
      expect(newer(null, 20, '1.0.5', 19), isTrue);
    });
  });

  group('android build offset', () {
    test('strips the per-ABI offset Flutter adds', () {
      expect(normalizeAndroidBuild(2504), 504); // arm64-v8a
      expect(normalizeAndroidBuild(1504), 504); // armeabi-v7a
      expect(normalizeAndroidBuild(4504), 504); // x86_64
      expect(normalizeAndroidBuild(504), 504); // universal
    });
    test('parseBuild', () {
      expect(parseBuild('19'), 19);
      expect(parseBuild(' 19 '), 19);
      expect(parseBuild(''), isNull);
      expect(parseBuild(null), isNull);
      expect(parseBuild('1.2'), isNull);
    });
  });

  group('UpdatePolicy', () {
    test('reads top-level fields and the platform override', () {
      final json = {
        'latestVersion': '1.0.5',
        'latestBuild': 504,
        'minSupportedBuild': 400,
        'message_en': 'Please update.',
        'message_vi': 'Vui lòng cập nhật.',
        'downloadUrl': 'https://x.test/r',
        'ios': {'latestBuild': 19, 'minSupportedBuild': 12},
      };
      final a = UpdatePolicy.fromJson(json, 'android');
      expect(a.latestBuild, 504);
      expect(a.minSupportedBuild, 400);
      final i = UpdatePolicy.fromJson(json, 'ios');
      expect(i.latestBuild, 19);
      expect(i.minSupportedBuild, 12);
      expect(i.latestVersion, '1.0.5');
      expect(i.downloadUrl, 'https://x.test/r');
    });
    test('accepts numbers as strings and ignores junk', () {
      final p = UpdatePolicy.fromJson({
        'latestBuild': '12',
        'minSupportedBuild': 'x',
        'message_en': 7,
      }, 'android');
      expect(p.latestBuild, 12);
      expect(p.minSupportedBuild, 0);
      expect(p.messageEn, isNull);
    });
    test('a malformed document is empty (fail-open)', () {
      expect(UpdatePolicy.fromJson(null, 'ios').minSupportedBuild, 0);
      expect(UpdatePolicy.fromJson([1, 2], 'ios').latestVersion, isNull);
      expect(UpdatePolicy.fromJson('x', 'ios').latestBuild, isNull);
    });
    test('messageFor: vi, en, other languages use built-in copy', () {
      const p = UpdatePolicy(messageEn: 'en!', messageVi: 'vi!');
      expect(p.messageFor('vi'), 'vi!');
      expect(p.messageFor('en'), 'en!');
      expect(p.messageFor('ja'), isNull);
      expect(const UpdatePolicy(messageEn: 'e').messageFor('vi'), 'e');
    });
  });

  group('UpdateCopy', () {
    test('every language is filled and the banner stays short', () {
      for (final l in UpdateCopy.languages) {
        final c = UpdateCopy.forLanguage(l);
        for (final s in [
          c.title,
          c.update,
          c.later,
          c.dismissLabel,
          c.downloadedTitle,
          c.restart,
          c.requiredTitle,
          c.requiredBody,
          c.requiredBodyForParents,
        ]) {
          expect(s.trim(), isNotEmpty, reason: l);
        }
        final words = '${c.title} ${c.update}'.split(' ').length;
        expect(words, lessThanOrEqualTo(12), reason: l);
      }
    });
    test('unknown language falls back to English', () {
      expect(UpdateCopy.forLanguage('fr').update, 'Update');
    });
  });
}
