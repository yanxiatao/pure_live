import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/cookie_string.dart';
import 'package:pure_live/modules/account/web_cookie_capture.dart';

void main() {
  group('parseCookiePairs', () {
    test('parses a standard cookie string', () {
      final pairs = parseCookiePairs('a=1; b=2');
      expect(pairs.map((e) => '${e.key}=${e.value}'), ['a=1', 'b=2']);
    });

    test('keeps values that contain equals signs', () {
      final pairs = parseCookiePairs('token=abc==; x=y');
      expect(pairs.first.key, 'token');
      expect(pairs.first.value, 'abc==');
    });

    test('skips empty segments and segments without a name', () {
      final pairs = parseCookiePairs('; a=1;; =2; novalue ;b=3');
      expect(pairs.map((e) => e.key), ['a', 'b']);
    });

    test('returns empty for blank input', () {
      expect(parseCookiePairs(''), isEmpty);
      expect(parseCookiePairs('   '), isEmpty);
    });
  });

  group('cookieDomainMatches', () {
    test('matches exact, dotted and subdomain cookies', () {
      expect(cookieDomainMatches('huya.com', ['huya.com']), isTrue);
      expect(cookieDomainMatches('.huya.com', ['huya.com']), isTrue);
      expect(cookieDomainMatches('www.huya.com', ['huya.com']), isTrue);
      expect(cookieDomainMatches('.twitch.tv', ['twitch.tv']), isTrue);
    });

    test('rejects unrelated and empty domains', () {
      expect(cookieDomainMatches('nothuya.com', ['huya.com']), isFalse);
      expect(cookieDomainMatches('huya.com.evil.com', ['huya.com']), isFalse);
      expect(cookieDomainMatches('', ['huya.com']), isFalse);
    });
  });

  group('assembleCookieString', () {
    test('filters by domain and lets later values win', () {
      final cookie = assembleCookieString(
        [
          Cookie(name: 'a', value: '1', domain: '.huya.com'),
          Cookie(name: 'b', value: '2', domain: 'www.huya.com'),
          Cookie(name: 'a', value: '3', domain: 'huya.com'),
          Cookie(name: 'c', value: '4', domain: 'other.com'),
        ],
        ['huya.com'],
      );
      expect(cookie, 'a=3; b=2');
    });

    test('returns null when nothing matches', () {
      final cookie = assembleCookieString([Cookie(name: 'a', value: '1', domain: 'other.com')], ['huya.com']);
      expect(cookie, isNull);
    });
  });

  test('capture targets cover the auto-capture platforms', () {
    expect(kCookieCaptureTargets.keys, containsAll(['douyin', 'huya', 'kuaishou', 'soop', 'twitch']));
    for (final entry in kCookieCaptureTargets.entries) {
      expect(entry.value.platform, entry.key);
      expect(entry.value.loginUrl, startsWith('https://'));
      expect(entry.value.domains, isNotEmpty);
    }
  });
}
