import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:promptvault/core/constants.dart';
import 'package:promptvault/core/entitlements.dart';
import 'package:promptvault/data/copy_history_store.dart';
import 'package:promptvault/data/prompt_repository.dart';
import 'package:promptvault/data/starter_prompts.dart';
import 'package:promptvault/models/prompt.dart';
import 'package:promptvault/providers/app_providers.dart';
import 'package:promptvault/providers/prompt_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 実際の Hive box と Riverpod を通した結合テスト。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<Prompt> box;
  late ProviderContainer container;

  Future<ProviderContainer> makeContainer({
    bool isPro = false,
    bool seeded = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppConstants.prefsIsProUser: isPro,
      AppConstants.prefsSeeded: seeded,
    });
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        promptRepositoryProvider.overrideWithValue(PromptRepository(box)),
      ],
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('promptvault_test');
    Hive.init(tempDir.path);
    box = await PromptRepository.openBox();
  });

  tearDown(() async {
    container.dispose();
    await box.clear();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('作成と更新', () {
    test('保存件数に上限はない', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);

      for (int i = 0; i < 50; i++) {
        expect(
          await notifier.create(title: 'p$i', body: 'body $i'),
          MutationOutcome.ok,
          reason: '${i + 1}件目',
        );
      }
      expect(container.read(promptCountProvider), 50);
    });

    test('タイトルも本文も空なら保存しない', () async {
      container = await makeContainer();
      expect(
        await container
            .read(promptsProvider.notifier)
            .create(title: '   ', body: ''),
        MutationOutcome.blockedByEmptyContent,
      );
      expect(container.read(promptCountProvider), 0);
    });

    test('更新しても件数は増えない', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: '編集前', body: 'body');

      final target = container.read(promptsProvider).single;
      expect(
        await notifier.update(target, title: '編集後', body: '新しい本文'),
        MutationOutcome.ok,
      );

      final updated = container.read(promptsProvider).single;
      expect(updated.title, '編集後');
      expect(updated.body, '新しい本文');
      expect(container.read(promptCountProvider), 1);
    });
  });

  group('ピン留め', () {
    test('件数に上限はなく、updatedAt も変わらない', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      for (int i = 0; i < 5; i++) {
        await notifier.create(title: 'p$i', body: 'body');
      }

      final before = container.read(promptsProvider);
      for (final Prompt p in before) {
        await notifier.togglePin(p);
      }
      expect(container.read(pinnedCountProvider), 5);

      final after = container.read(promptsProvider);
      for (final Prompt p in after) {
        final original = before.firstWhere((Prompt o) => o.id == p.id);
        expect(p.updatedAt, original.updatedAt,
            reason: 'ピン留めで並び順を乱さない');
      }
    });

    test('解除もできる', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: 'p', body: 'body');

      await notifier.togglePin(container.read(promptsProvider).single);
      expect(container.read(pinnedCountProvider), 1);

      await notifier.togglePin(container.read(promptsProvider).single);
      expect(container.read(pinnedCountProvider), 0);
    });
  });

  group('使用回数', () {
    test('markUsed で加算され、updatedAt は変わらない', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: 'p', body: 'b');

      final before = container.read(promptsProvider).single;
      await notifier.markUsed(before);

      final after = container.read(promptsProvider).single;
      expect(after.usageCount, 1);
      expect(after.updatedAt, before.updatedAt, reason: 'コピーで並び順を乱さない');
    });
  });

  group('削除と取り消し', () {
    test('指定したプロンプトだけ削除される', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: 'a', body: 'b');
      await notifier.create(title: 'c', body: 'd');

      final target = container.read(promptsProvider).first;
      await notifier.delete(target.id);

      expect(container.read(promptCountProvider), 1);
      expect(
        container.read(promptsProvider).any((Prompt p) => p.id == target.id),
        isFalse,
      );
    });

    test('削除したプロンプトを元に戻せる', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: '消すやつ', body: 'body');

      final target = container.read(promptsProvider).single;
      await notifier.delete(target.id);
      expect(container.read(promptCountProvider), 0);

      await notifier.restoreSnapshot(<Prompt>[target]);
      final restored = container.read(promptsProvider).single;
      expect(restored.id, target.id);
      expect(restored.title, '消すやつ');
      expect(restored.updatedAt, target.updatedAt, reason: '並び順も元に戻る');
    });

    test('編集を元に戻すと編集前の内容に戻る', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: '編集前', body: '元の本文');

      final original = container.read(promptsProvider).single;
      await notifier.update(original, title: '編集後', body: '新しい本文');
      expect(container.read(promptsProvider).single.title, '編集後');

      await notifier.restoreSnapshot(<Prompt>[original]);
      final reverted = container.read(promptsProvider).single;
      expect(reverted.title, '編集前');
      expect(reverted.body, '元の本文');
    });

    test('全件削除も元に戻せる', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: 'a', body: 'x');
      await notifier.create(title: 'b', body: 'y');

      final snapshot = container.read(promptsProvider);
      await notifier.deleteAll();
      expect(container.read(promptCountProvider), 0);

      await notifier.restoreSnapshot(snapshot);
      expect(container.read(promptCountProvider), 2);
    });
  });

  group('サンプルの投入', () {
    test('初回起動なら自動で投入される', () async {
      container = await makeContainer(seeded: false);
      await container.read(promptsProvider.notifier).seedIfFirstLaunch();

      expect(
        container.read(promptCountProvider),
        StarterPrompts.autoSeedCount,
      );
      // 変数の使い方を最初から体験させたいので、変数入りが含まれること。
      expect(
        container.read(promptsProvider).any((Prompt p) => p.body.contains('{{')),
        isTrue,
      );
    });

    test('2回目以降は投入しない', () async {
      container = await makeContainer(seeded: false);
      final notifier = container.read(promptsProvider.notifier);
      await notifier.seedIfFirstLaunch();
      await notifier.seedIfFirstLaunch();

      expect(
        container.read(promptCountProvider),
        StarterPrompts.autoSeedCount,
      );
    });

    test('投入済みフラグが立っていれば何もしない', () async {
      container = await makeContainer();
      await container.read(promptsProvider.notifier).seedIfFirstLaunch();
      expect(container.read(promptCountProvider), 0);
    });

    test('既にプロンプトがあるなら投入しない', () async {
      container = await makeContainer(seeded: false);
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: '既存', body: 'body');
      await notifier.seedIfFirstLaunch();

      expect(container.read(promptCountProvider), 1);
    });

    test('サンプルを手動で全件追加できる', () async {
      container = await makeContainer();
      final added = await container
          .read(promptsProvider.notifier)
          .addStarters(StarterPrompts.all);

      expect(added, StarterPrompts.all.length);
      expect(container.read(promptCountProvider), StarterPrompts.all.length);
    });
  });

  group('コピー履歴', () {
    test('新しい順に積まれ、上限で打ち切られる', () async {
      container = await makeContainer(isPro: true);
      final notifier = container.read(copyHistoryProvider.notifier);

      for (int i = 0; i < AppConstants.copyHistoryLimit + 5; i++) {
        await notifier.add(
          CopyHistoryEntry(
            text: 'text $i',
            sourceTitle: 'p$i',
            copiedAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }

      final history = container.read(copyHistoryProvider);
      expect(history.length, AppConstants.copyHistoryLimit);
      expect(history.first.text, 'text ${AppConstants.copyHistoryLimit + 4}');
    });

    test('同じテキストは1件にまとめる', () async {
      container = await makeContainer(isPro: true);
      final notifier = container.read(copyHistoryProvider.notifier);
      final entry = CopyHistoryEntry(
        text: '同じ本文',
        sourceTitle: 'p',
        copiedAt: DateTime(2026),
      );

      await notifier.add(entry);
      await notifier.add(
        CopyHistoryEntry(
          text: 'ほかの本文',
          sourceTitle: 'q',
          copiedAt: DateTime(2026),
        ),
      );
      await notifier.add(entry);

      final history = container.read(copyHistoryProvider);
      expect(history.length, 2);
      expect(history.first.text, '同じ本文', reason: '再コピーで先頭に来る');
    });

    test('消去できる', () async {
      container = await makeContainer(isPro: true);
      final notifier = container.read(copyHistoryProvider.notifier);
      await notifier.add(
        CopyHistoryEntry(
          text: 'x',
          sourceTitle: 'p',
          copiedAt: DateTime(2026),
        ),
      );
      await notifier.clear();
      expect(container.read(copyHistoryProvider), isEmpty);
    });

    test('保存した履歴は読み直せる', () async {
      container = await makeContainer(isPro: true);
      await container.read(copyHistoryProvider.notifier).add(
            CopyHistoryEntry(
              text: '残る本文',
              sourceTitle: 'p',
              copiedAt: DateTime(2026, 5, 1),
            ),
          );

      final reloaded = container.read(copyHistoryStoreProvider).load();
      expect(reloaded.single.text, '残る本文');
      expect(reloaded.single.sourceTitle, 'p');
      expect(reloaded.single.copiedAt, DateTime(2026, 5, 1));
    });
  });

  group('Pro プラン', () {
    test('広告は表示されない', () async {
      container = await makeContainer(isPro: true);
      expect(container.read(entitlementsProvider).showAds, isFalse);
      expect(container.read(adsServiceProvider).isSupported, isFalse);
    });
  });

  group('バックアップ復元', () {
    test('merge=false は既存を置き換える', () async {
      container = await makeContainer(isPro: true);
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: '既存', body: 'x');

      final incoming = <Prompt>[
        Prompt(
          id: 'imported-1',
          title: '復元',
          body: 'y',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
      expect(await notifier.restore(incoming, merge: false), 1);
      expect(container.read(promptsProvider).single.title, '復元');
    });

    test('merge=true は既存を残しつつ追加する', () async {
      container = await makeContainer(isPro: true);
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: '既存', body: 'x');

      expect(
        await notifier.restore(
          <Prompt>[
            Prompt(
              id: 'imported-1',
              title: '復元',
              body: 'y',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
          merge: true,
        ),
        1,
      );
      expect(container.read(promptCountProvider), 2);
    });

    test('merge 時、同一IDは updatedAt が新しい方を残す', () async {
      container = await makeContainer(isPro: true);
      final notifier = container.read(promptsProvider.notifier);

      await container.read(promptRepositoryProvider).put(
            Prompt(
              id: 'same',
              title: '新しいローカル版',
              body: 'local',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026, 12),
            ),
          );

      // 取り込むデータの方が古いので、ローカルが優先されるべき。
      expect(
        await notifier.restore(
          <Prompt>[
            Prompt(
              id: 'same',
              title: '古いバックアップ版',
              body: 'backup',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026, 1),
            ),
          ],
          merge: true,
        ),
        0,
      );
      expect(container.read(promptsProvider).single.title, '新しいローカル版');

      // 逆に新しいデータなら上書きされる。
      expect(
        await notifier.restore(
          <Prompt>[
            Prompt(
              id: 'same',
              title: '新しいバックアップ版',
              body: 'backup',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2027),
            ),
          ],
          merge: true,
        ),
        1,
      );
      expect(container.read(promptsProvider).single.title, '新しいバックアップ版');
    });
  });

  group('永続化', () {
    test('Hive に保存され、box を開き直しても残る', () async {
      container = await makeContainer();
      await container.read(promptsProvider.notifier).create(
            title: '永続化テスト',
            body: '{{変数}}入り',
            tags: <String>['要約', '定番'],
          );

      await box.close();
      box = await PromptRepository.openBox();

      final reopened = PromptRepository(box).getAll();
      expect(reopened.single.title, '永続化テスト');
      expect(reopened.single.body, '{{変数}}入り');
      expect(reopened.single.tags, <String>['要約', '定番']);
    });

    test('ピン留めと使用回数も往復する', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: 'p', body: 'b');

      await notifier.togglePin(container.read(promptsProvider).single);
      await notifier.markUsed(container.read(promptsProvider).single);

      await box.close();
      box = await PromptRepository.openBox();

      final reopened = PromptRepository(box).getAll().single;
      expect(reopened.isPinned, isTrue);
      expect(reopened.usageCount, 1);
    });
  });

  group('検索・タグ', () {
    test('検索語とタグの状態が一覧に反映される', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: '要約プロンプト', body: 'x', tags: <String>['要約']);
      await notifier.create(title: 'メール作成', body: 'y', tags: <String>['メール']);

      container.read(searchQueryProvider.notifier).set('要約');
      expect(container.read(visiblePromptsProvider).length, 1);

      container.read(searchQueryProvider.notifier).clear();
      container.read(selectedTagsProvider.notifier).toggle('メール');
      expect(container.read(visiblePromptsProvider).single.title, 'メール作成');

      container.read(selectedTagsProvider.notifier).clear();
      expect(container.read(visiblePromptsProvider).length, 2);
    });

    test('allTagsProvider が全タグを重複なく返す', () async {
      container = await makeContainer();
      final notifier = container.read(promptsProvider.notifier);
      await notifier.create(title: 'a', body: 'x', tags: <String>['要約', '定番']);
      await notifier.create(title: 'b', body: 'y', tags: <String>['定番', '英語']);

      expect(container.read(allTagsProvider), <String>['定番', '英語', '要約']);
    });
  });
}
