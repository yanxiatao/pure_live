import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/huya/huya_site.dart';

void main() {
  test('Huya treats only explicit inactive states as authoritative offline', () {
    expect(HuyaSite.isExplicitOfflineState('OFF'), isTrue);
    expect(HuyaSite.isExplicitOfflineState(' offline '), isTrue);
    expect(HuyaSite.isExplicitOfflineState('CLOSED'), isTrue);
    expect(HuyaSite.isExplicitOfflineState('ON'), isFalse);
    expect(HuyaSite.isExplicitOfflineState(null), isFalse);
  });

  HuyaLineModel line(
    HuyaLineType type,
    String base, {
    String flvAntiCode = 'wsSecret=flv-token&wsTime=6a87f351',
    String hlsAntiCode = 'wsSecret=hls-token&wsTime=6a87f351',
  }) {
    return HuyaLineModel(
      line: base,
      lineType: type,
      flvAntiCode: flvAntiCode,
      hlsAntiCode: hlsAntiCode,
      streamName: 'stream-name',
      cdnType: 'AL',
      presenterUid: 123,
    );
  }

  /// v3.0.8 resolves the anti-code through the CDN token API on every call, so the
  /// per-line `flvAntiCode`/`hlsAntiCode` no longer reaches the URL. Seeding keeps
  /// these tests deterministic instead of hitting Huya's token endpoint.
  HuyaSite siteWithToken(String token) {
    final site = HuyaSite();
    site.seedTokenForTest('stream-name', token);
    return site;
  }

  test('Huya FLV URL keeps the advertised base verbatim and appends the quality', () async {
    // v3.0.8 no longer routes the CDN base through secureHuyaCdnBase, and a token
    // without an `fm` parameter is passed through unchanged (legacy fixture path).
    final url = await siteWithToken('wsSecret=fetched&wsTime=6a87f351&u=31488')
        .getPlayUrl(line(HuyaLineType.flv, 'http://al.flv.huya.com/src'), 8000);

    expect(url, startsWith('http://al.flv.huya.com/src/stream-name.flv?'));
    expect(url, contains('wsSecret=fetched'));
    expect(url, isNot(contains('&seqid=')));
    expect(url, endsWith('&codec=264&ratio=8000'));
  });

  test('Huya HLS URL switches only the extension and the requested ratio', () async {
    final url = await siteWithToken('wsSecret=fetched&wsTime=6a87f351&u=31488')
        .getPlayUrl(line(HuyaLineType.hls, 'http://al.hls.huya.com/src'), 2000);

    expect(url, startsWith('http://al.hls.huya.com/src/stream-name.m3u8?'));
    expect(url, endsWith('&codec=264&ratio=2000'));
  });

  test('Huya re-signs a CDN token that carries an fm signature', () async {
    // The re-signing branch needs fm, wsTime and fs together; it reads
    // `mapAnti['fs']!` directly, so a token without all three throws instead of
    // degrading. Build a complete fixture here.
    final fm = base64.encode(utf8.encode('huya-secret-prefix_0_1_2'));
    final url = await siteWithToken(
      'wsSecret=stale&wsTime=6a87f351&fs=gctex&fm=${Uri.encodeComponent(fm)}',
    ).getPlayUrl(line(HuyaLineType.flv, 'https://al.flv.huya.com/src'), 8000);

    expect(url, contains('&seqid='));
    expect(url, contains('ctype=huya_pc_exe'));
    expect(url, isNot(contains('wsSecret=stale')));
    expect(url, endsWith('&codec=264&ratio=8000'));
  });

  test('Huya CDN bases use HTTPS without rewriting unrelated hosts', () {
    expect(HuyaSite.secureHuyaCdnBase('http://tx.flv.huya.com/src'), 'https://tx.flv.huya.com/src');
    expect(HuyaSite.secureHuyaCdnBase('http://example.com/src'), 'http://example.com/src');
  });

  test('Huya appends the requested quality instead of replacing token-carried pairs', () async {
    // Regression surface kept visible: v3.0.7 replaced `codec`/`ratio` inside the
    // anti-code, v3.0.8 appends its own pair, so a token that already carries them
    // yields duplicate query parameters and the CDN sees the first value.
    final url = await siteWithToken('wsSecret=fetched&wsTime=6a87f351&codec=265&ratio=4000')
        .getPlayUrl(line(HuyaLineType.hls, 'https://al.hls.huya.com/src'), 2000);

    final query = Uri.parse(url).query;
    expect(RegExp(r'(^|&)codec=').allMatches(query).length, 2);
    expect(RegExp(r'(^|&)ratio=').allMatches(query).length, 2);
    expect(url, contains('&codec=264'));
    expect(url, contains('&ratio=2000'));
  });

  test('Huya source quality omits the ratio parameter', () async {
    final url = await siteWithToken('wsSecret=fetched&wsTime=6a87f351')
        .getPlayUrl(
          line(
            HuyaLineType.flv,
            'https://tx.flv.huya.com/src',
            flvAntiCode: 'wsSecret=flv-token&wsTime=6a87f351&ratio=500',
          ),
          0,
        );

    expect(Uri.parse(url).queryParameters.containsKey('ratio'), isFalse);
    expect(url, contains('&codec=264'));
    // The per-line antiCode is no longer used at all: the CDN token wins.
    expect(url, isNot(contains('flv-token')));
  });

  test('Huya exposes only server advertised bitrates and has stable selection ids', () {
    final data = HuyaUrlDataModel(
      url: '',
      uid: '',
      lines: [line(HuyaLineType.flv, 'https://tx.flv.huya.com/src')],
      bitRates: [
        HuyaBitRateModel(name: '蓝光4M', bitRate: 0),
        HuyaBitRateModel(name: '超清', bitRate: 2000),
        HuyaBitRateModel(name: '重复超清', bitRate: 2000),
        HuyaBitRateModel(name: '流畅', bitRate: 500),
      ],
      isXingxiu: false,
    );

    final qualities = HuyaSite.parsePlayQualities(data);

    expect(qualities.map((quality) => quality.quality), ['蓝光4M', '超清', '流畅']);
    expect(qualities.map((quality) => quality.selectionId), [0, 2000, 500]);
  });

  test('Huya does not invent an unsupported transcode when no rate list exists', () {
    final qualities = HuyaSite.parsePlayQualities(
      HuyaUrlDataModel(url: '', uid: '', lines: const [], bitRates: const [], isXingxiu: false),
    );

    expect(qualities, hasLength(1));
    expect(qualities.single.selectionId, 0);
  });
}
