import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptvault/models/prompt.dart';
import 'package:promptvault/services/backup_service.dart';

Prompt sample({
  String id = 'p1',
  String title = 'タイトル',
  String body = '本文',
  List<String> tags = const <String>['要約'],
}) {
  return Prompt(
    id: id,
    title: title,
    body: body,
    tags: tags,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 2, 1),
  );
}

void main() {
  const service = BackupService();

  group('JSON 書き出し', () {
    test('スキーマバージョンと件数を含む', () {
      final json = jsonDecode(service.buildJson(<Prompt>[sample()]))
          as Map<String, dynamic>;
      expect(json['schemaVersion'], 1);
      expect(json['count'], 1);
      expect((json['prompts'] as List<dynamic>).length, 1);
    });

    test('書き出したJSONをそのまま読み戻せる（往復）', () {
      final original = <Prompt>[
        sample(id: 'a', title: 'A', body: '{{変数}}を含む本文'),
        sample(id: 'b', title: 'B', body: '改行\nを含む本文'),
      ];
      final restored = service.parseJson(service.buildJson(original));

      expect(restored.length, 2);
      expect(restored[0].id, 'a');
      expect(restored[0].body, '{{変数}}を含む本文');
      expect(restored[1].body, '改行\nを含む本文');
      expect(restored[0].tags, <String>['要約']);
      expect(restored[0].createdAt, DateTime(2026, 1, 1));
    });
  });

  group('JSON 読み込み', () {
    test('プロンプト配列だけのJSONも受け付ける', () {
      const source = '[{"title":"t","body":"b"}]';
      final result = service.parseJson(source);
      expect(result.length, 1);
      expect(result.first.title, 't');
    });

    test('IDが無い場合は自動採番する', () {
      final result = service.parseJson('[{"title":"t","body":"b"}]');
      expect(result.first.id, isNotEmpty);
    });

    test('タイトルも本文も空の項目は取り込まない', () {
      final result = service.parseJson(
        '[{"title":"","body":""},{"title":"ok","body":""}]',
      );
      expect(result.length, 1);
      expect(result.first.title, 'ok');
    });

    test('壊れたJSONは BackupParseException', () {
      expect(
        () => service.parseJson('{ not json'),
        throwsA(isA<BackupParseException>()),
      );
    });

    test('空ファイルは BackupParseException', () {
      expect(
        () => service.parseJson('   '),
        throwsA(isA<BackupParseException>()),
      );
    });

    test('prompts 配列を持たないオブジェクトは BackupParseException', () {
      expect(
        () => service.parseJson('{"foo":1}'),
        throwsA(isA<BackupParseException>()),
      );
    });

    test('有効な項目が1件も無ければ BackupParseException', () {
      expect(
        () => service.parseJson('[]'),
        throwsA(isA<BackupParseException>()),
      );
    });

    test('欠損フィールドは既定値で埋めて例外にしない', () {
      final result = service.parseJson('[{"title":"t"}]');
      expect(result.first.body, '');
      expect(result.first.tags, isEmpty);
      expect(result.first.isPinned, isFalse);
      expect(result.first.usageCount, 0);
    });
  });

  test('ファイル名に日時が入る', () {
    expect(
      BackupService.buildFileName(now: DateTime(2026, 7, 27, 18, 5)),
      'promptvault-backup-20260727-1805.json',
    );
  });

  group('旧形式との互換', () {
    test('旧 category はタグとして取り込む', () {
      final result = service.parseJson(
        '[{"title":"t","body":"b","tags":["要約"],"category":"ライティング"}]',
      );
      expect(result.single.tags, <String>['要約', 'ライティング']);
    });

    test('タグと同名の category は重複させない', () {
      final result = service.parseJson(
        '[{"title":"t","body":"b","tags":["要約"],"category":"要約"}]',
      );
      expect(result.single.tags, <String>['要約']);
    });

    test('旧 sortOrder は無視して読み込める', () {
      final result =
          service.parseJson('[{"title":"t","body":"b","sortOrder":5}]');
      expect(result.single.title, 't');
    });
  });
}
