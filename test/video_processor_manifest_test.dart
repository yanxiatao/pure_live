import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/video_processor_service.dart';

void main() {
  test('concat manifest is explicit and safely escapes portable paths', () {
    final manifest = VideoProcessorService.buildConcatManifest(<String>[
      r'C:\Pure Live\001.ts',
      "/tmp/anchor's/002.ts",
    ]);

    expect(manifest, startsWith('ffconcat version 1.0\n'));
    expect(manifest, contains("file 'C:/Pure Live/001.ts'"));
    expect(manifest, contains(r"file '/tmp/anchor'\''s/002.ts'"));
  });

  test('normal retries never merge segments from an older attempt', () {
    // Relative forward-slash paths resolve to the same base name under both the
    // Windows and POSIX path contexts, so this stays meaningful on any runner.
    final files = <File>[
      File('records/20260827_080000_001_000000.ts'),
      File('records/20260827_080001_002_000000.ts'),
    ];

    expect(
      VideoProcessorService.selectAttemptSegments(
        candidates: files,
        filePrefix: '20260827_080001_002',
      ).map((file) => file.path),
      ['records/20260827_080001_002_000000.ts'],
    );
    expect(VideoProcessorService.selectAttemptSegments(candidates: files, filePrefix: 'missing'), isEmpty);
    expect(
      VideoProcessorService.selectAttemptSegments(candidates: files, filePrefix: 'legacy', allowLegacySegments: true),
      files,
    );
  });
}
