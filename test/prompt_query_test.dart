import 'package:flutter_test/flutter_test.dart';
import 'package:promptvault/core/constants.dart';
import 'package:promptvault/core/prompt_query.dart';
import 'package:promptvault/models/prompt.dart';

Prompt makePrompt({
  required String id,
  String title = '',
  String body = '',
  List<String> tags = const <String>[],
  bool isPinned = false,
  int usageCount = 0,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final base = DateTime(2026, 1, 1);
  return Prompt(
    id: id,
    title: title,
    body: body,
    tags: tags,
    isPinned: isPinned,
    usageCount: usageCount,
    createdAt: createdAt ?? base,
    updatedAt: updatedAt ?? base,
  );
}

void main() {
  group('PromptQuery.filter', () {
    final prompts = <Prompt>[
      makePrompt(
        id: 'a',
        title: '記事の要約',
        body: '以下の文章を要約してください',
        tags: <String>['要約', '定番', 'ライティング'],
      ),
      makePrompt(
        id: 'b',
        title: 'Code Review',
        body: 'Review this Dart code',
        tags: <String>['開発'],
      ),
      makePrompt(
        id: 'c',
        title: '英語メール',
        body: '英語でビジネスメールを書いてください',
        tags: <String>['英語', '定番'],
      ),
    ];

    test('検索語が空なら全件を返す', () {
      expect(PromptQuery.filter(prompts).length, 3);
    });

    test('タイトルに一致する', () {
      expect(
        PromptQuery.filter(prompts, query: '要約').map((Prompt p) => p.id),
        <String>['a'],
      );
    });

    test('本文にも一致する', () {
      expect(
        PromptQuery.filter(prompts, query: 'ビジネスメール').map((Prompt p) => p.id),
        <String>['c'],
      );
    });

    test('タグにも一致する', () {
      expect(
        PromptQuery.filter(prompts, query: '開発').map((Prompt p) => p.id),
        <String>['b'],
      );
    });

    test('大文字小文字を区別しない', () {
      expect(PromptQuery.filter(prompts, query: 'CODE').length, 1);
      expect(PromptQuery.filter(prompts, query: 'dart').length, 1);
    });

    test('空白区切りの複数語は AND 条件', () {
      expect(
        PromptQuery.filter(prompts, query: '英語 メール').map((Prompt p) => p.id),
        <String>['c'],
      );
      expect(PromptQuery.filter(prompts, query: '英語 Dart'), isEmpty);
    });

    test('タグフィルターは選択タグをすべて含むものだけ通す', () {
      expect(
        PromptQuery.filter(prompts, tags: <String>{'定番'})
            .map((Prompt p) => p.id),
        <String>['a', 'c'],
      );
      expect(
        PromptQuery.filter(prompts, tags: <String>{'定番', '英語'})
            .map((Prompt p) => p.id),
        <String>['c'],
      );
    });

    test('検索語とタグフィルターは併用できる', () {
      expect(
        PromptQuery.filter(prompts, query: '要約', tags: <String>{'定番'})
            .map((Prompt p) => p.id),
        <String>['a'],
      );
    });
  });

  group('PromptQuery.sort', () {
    test('ピン留めは並び替えモードに関わらず先頭に集まる', () {
      final prompts = <Prompt>[
        makePrompt(id: 'old-pinned', title: 'A', updatedAt: DateTime(2020)),
        makePrompt(id: 'new', title: 'B', updatedAt: DateTime(2026)),
        makePrompt(
          id: 'pinned',
          title: 'C',
          isPinned: true,
          updatedAt: DateTime(2019),
        ),
      ];
      for (final SortMode mode in SortMode.values) {
        expect(PromptQuery.sort(prompts, mode).first.id, 'pinned',
            reason: mode.name);
      }
    });

    test('recent は更新が新しい順', () {
      final prompts = <Prompt>[
        makePrompt(id: 'old', updatedAt: DateTime(2024)),
        makePrompt(id: 'new', updatedAt: DateTime(2026)),
        makePrompt(id: 'mid', updatedAt: DateTime(2025)),
      ];
      expect(
        PromptQuery.sort(prompts, SortMode.recent).map((Prompt p) => p.id),
        <String>['new', 'mid', 'old'],
      );
    });

    test('usage は使用回数が多い順、同数なら更新が新しい順', () {
      final prompts = <Prompt>[
        makePrompt(id: 'few', usageCount: 1),
        makePrompt(id: 'many', usageCount: 10),
        makePrompt(id: 'tie', usageCount: 10, updatedAt: DateTime(2027)),
      ];
      expect(
        PromptQuery.sort(prompts, SortMode.usage).map((Prompt p) => p.id),
        <String>['tie', 'many', 'few'],
      );
    });

    test('元のリストを破壊しない', () {
      final prompts = <Prompt>[
        makePrompt(id: 'a', updatedAt: DateTime(2024)),
        makePrompt(id: 'b', updatedAt: DateTime(2026)),
      ];
      PromptQuery.sort(prompts, SortMode.recent);
      expect(prompts.map((Prompt p) => p.id), <String>['a', 'b']);
    });
  });

  group('SortMode', () {
    test('未知の名前は recent に落とす', () {
      expect(SortMode.fromName('manual'), SortMode.recent);
      expect(SortMode.fromName(null), SortMode.recent);
    });

    test('保存した名前は復元できる', () {
      for (final SortMode mode in SortMode.values) {
        expect(SortMode.fromName(mode.name), mode);
      }
    });
  });

  group('PromptQuery.parseTags', () {
    test('カンマ・全角カンマ・空白で区切る', () {
      expect(
        PromptQuery.parseTags('要約, 英語　ビジネス、開発'),
        <String>['要約', '英語', 'ビジネス', '開発'],
      );
    });

    test('先頭の # を取り除く', () {
      expect(PromptQuery.parseTags('#要約, #英語'), <String>['要約', '英語']);
    });

    test('重複を除き、入力順を保つ', () {
      expect(PromptQuery.parseTags('a, b, a'), <String>['a', 'b']);
    });

    test('空入力では空リスト', () {
      expect(PromptQuery.parseTags('   ,, '), isEmpty);
    });
  });

  group('Prompt', () {
    test('displayTitle はタイトルが空なら本文の1行目を使う', () {
      expect(makePrompt(id: 'x', body: '最初の行\n2行目').displayTitle, '最初の行');
    });

    test('displayTitle はタイトルも本文も空なら (無題)', () {
      expect(makePrompt(id: 'x').displayTitle, '(無題)');
    });

    test('preview は改行を潰して1行にする', () {
      expect(makePrompt(id: 'x', body: 'a\n\nb   c').preview, 'a b c');
    });

    test('newId は呼び出しごとに異なる', () {
      final ids = <String>{for (int i = 0; i < 200; i++) Prompt.newId()};
      expect(ids.length, 200);
    });
  });

  group('旧カテゴリのタグ移行', () {
    test('カテゴリがタグ末尾に足される', () {
      expect(
        Prompt.mergeLegacyCategory(<String>['要約'], 'ライティング'),
        <String>['要約', 'ライティング'],
      );
    });

    test('同名なら重複させない', () {
      expect(
        Prompt.mergeLegacyCategory(<String>['要約'], '要約'),
        <String>['要約'],
      );
    });

    test('カテゴリが空なら何も足さない', () {
      expect(Prompt.mergeLegacyCategory(<String>['a'], ''), <String>['a']);
      expect(Prompt.mergeLegacyCategory(<String>['a'], null), <String>['a']);
    });

    test('空白だけのタグは捨てる', () {
      expect(Prompt.mergeLegacyCategory(<String>['a', ' ', ''], null),
          <String>['a']);
    });
  });
}
