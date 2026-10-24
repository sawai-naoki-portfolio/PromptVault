import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptvault/app.dart';
import 'package:promptvault/core/constants.dart';
import 'package:promptvault/models/prompt.dart';
import 'package:promptvault/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_prompt_store.dart';

/// 画面を実際に描画して、コピー体験と課金導線を確認するウィジェットテスト。
///
/// 広告・課金プラグインはホスト（Linux）では非対応判定になるため、
/// NoopAdsService / StubPurchaseService が自動的に使われる。
///
/// 保存先は [InMemoryPromptStore]。`testWidgets` の本体は擬似非同期ゾーンで
/// 動くため、実ファイルI/O を伴う Hive をそのまま使うと保存処理の Future が
/// 完了せずテストがハングする。Hive 実装自体は prompt_store_test.dart で検証している。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryPromptStore store;

  /// クリップボードに送られた最後のテキスト。
  String? lastCopied;

  setUp(() {
    store = InMemoryPromptStore();
    lastCopied = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        lastCopied =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    store.dispose();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    bool isPro = false,
    List<Prompt> seed = const <Prompt>[],
  }) async {
    // 既定の 800x600 はスマホより横長で、FAB が一覧の末尾カードに重なって
    // タップを奪ってしまう。実機に近い縦長サイズで検証する。
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{
      AppConstants.prefsIsProUser: isPro,
      // 初回投入は seeding のテストでだけ確認したいので既定では抑止する。
      AppConstants.prefsSeeded: true,
    });
    final prefs = await SharedPreferences.getInstance();
    await store.putAll(seed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          promptRepositoryProvider.overrideWithValue(store),
        ],
        child: const PromptVaultApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Prompt seedPrompt({
    String id = 's1',
    String title = 'テストプロンプト',
    String body = '本文です',
    List<String> tags = const <String>[],
    bool isPinned = false,
  }) {
    final now = DateTime(2026, 1, 1);
    return Prompt(
      id: id,
      title: title,
      body: body,
      tags: tags,
      isPinned: isPinned,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('一覧画面', () {
    testWidgets('プロンプトが無いときは空状態を出す', (WidgetTester tester) async {
      await pumpApp(tester);
      expect(find.text('まだプロンプトがありません'), findsOneWidget);
      expect(find.text('最初のプロンプトを作る'), findsOneWidget);
      expect(find.text('サンプルを追加する'), findsOneWidget);
    });

    testWidgets('空状態からサンプルをまとめて追加できる', (WidgetTester tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('サンプルを追加する'));
      await tester.pumpAndSettle();

      expect(store.count, greaterThan(0));
      expect(find.text('文章の要約'), findsOneWidget);
    });

    testWidgets('保存済みプロンプトが一覧に並ぶ', (WidgetTester tester) async {
      await pumpApp(tester, seed: <Prompt>[seedPrompt(title: '要約プロンプト')]);
      expect(find.text('要約プロンプト'), findsOneWidget);
    });

    testWidgets('保存件数の制限バーは表示されない', (WidgetTester tester) async {
      await pumpApp(tester, seed: <Prompt>[seedPrompt()]);
      expect(find.textContaining('Freeプラン'), findsNothing);
      expect(find.textContaining('/ 10 件'), findsNothing);
    });

    testWidgets('検索でリアルタイムに絞り込まれる', (WidgetTester tester) async {
      await pumpApp(
        tester,
        seed: <Prompt>[
          seedPrompt(id: 'a', title: '要約プロンプト'),
          seedPrompt(id: 'b', title: 'メール作成'),
        ],
      );
      expect(find.text('要約プロンプト'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'メール');
      await tester.pumpAndSettle();

      expect(find.text('要約プロンプト'), findsNothing);
      expect(find.text('メール作成'), findsOneWidget);
    });

    testWidgets('ピン留めは何件でもできる', (WidgetTester tester) async {
      await pumpApp(
        tester,
        seed: <Prompt>[
          seedPrompt(id: 'a', title: 'A'),
          seedPrompt(id: 'b', title: 'B'),
          seedPrompt(id: 'c', title: 'C'),
        ],
      );

      for (final String title in <String>['A', 'B', 'C']) {
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text(title),
              matching: find.byType(Card),
            ),
            matching: find.byIcon(Icons.push_pin_outlined),
          ),
        );
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('上限'), findsNothing);
      expect(store.pinnedCount, 3);
    });
  });

  group('コピー', () {
    testWidgets('変数が無ければそのままクリップボードへ送られる',
        (WidgetTester tester) async {
      await pumpApp(
        tester,
        seed: <Prompt>[seedPrompt(title: 'コピー対象', body: 'コピーされる本文')],
      );

      await tester.tap(find.text('コピー対象'));
      await tester.pumpAndSettle();

      expect(lastCopied, 'コピーされる本文');
      expect(find.text('コピーしました'), findsOneWidget);
    });

    testWidgets('Freeでも変数フォームが開き、置換してコピーできる',
        (WidgetTester tester) async {
      await pumpApp(
        tester,
        seed: <Prompt>[
          seedPrompt(title: '変数入り', body: '{{ターゲット}}向けに{{文字数}}字で要約'),
        ],
      );

      await tester.tap(find.text('変数入り'));
      await tester.pumpAndSettle();

      expect(find.text('{{ターゲット}}'), findsOneWidget);
      expect(find.text('{{文字数}}'), findsOneWidget);
      expect(lastCopied, isNull, reason: 'フォーム確定前はコピーしない');

      await tester.enterText(
          find.widgetWithText(TextField, 'ターゲット を入力'), '中学生');
      await tester.enterText(find.widgetWithText(TextField, '文字数 を入力'), '200');
      await tester.pumpAndSettle();

      await tester.tap(find.text('置換してコピー'));
      await tester.pumpAndSettle();

      expect(lastCopied, '中学生向けに200字で要約');
    });

    testWidgets('Freeでは選択肢も既定値も効かず素の入力欄になる',
        (WidgetTester tester) async {
      await pumpApp(
        tester,
        seed: <Prompt>[
          seedPrompt(
            title: '高度な変数',
            body: 'トーンは{{トーン:丁寧|カジュアル}}、{{文字数=200}}字で',
          ),
        ],
      );

      await tester.tap(find.text('高度な変数'));
      await tester.pumpAndSettle();

      // 選択肢のチップは出ず、テキスト入力に落ちる。
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.widgetWithText(TextField, 'トーン を入力'), findsOneWidget);
      expect(find.widgetWithText(TextField, '文字数 を入力'), findsOneWidget);

      // 既定値も入っていないので、そのまま確定すると記法が残る。
      await tester.tap(find.text('置換してコピー'));
      await tester.pumpAndSettle();
      expect(lastCopied, 'トーンは{{トーン:丁寧|カジュアル}}、{{文字数=200}}字で');
    });

    testWidgets('Proでは選択肢がチップになり、既定値が入る',
        (WidgetTester tester) async {
      await pumpApp(
        tester,
        isPro: true,
        seed: <Prompt>[
          seedPrompt(
            title: '高度な変数',
            body: 'トーンは{{トーン:丁寧|カジュアル}}、{{文字数=200}}字で',
          ),
        ],
      );

      await tester.tap(find.text('高度な変数'));
      await tester.pumpAndSettle();

      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.widgetWithText(TextField, '文字数 を入力'), findsOneWidget);

      // 既定値が入っているので、何も触らず確定しても文章として成立する。
      await tester.tap(find.text('置換してコピー'));
      await tester.pumpAndSettle();
      expect(lastCopied, 'トーンは丁寧、200字で');
    });

    testWidgets('Proで選択肢をタップすると置換内容が変わる',
        (WidgetTester tester) async {
      await pumpApp(
        tester,
        isPro: true,
        seed: <Prompt>[
          seedPrompt(title: 'トーン', body: '{{トーン:丁寧|カジュアル}}で書いて'),
        ],
      );

      await tester.tap(find.text('トーン').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'カジュアル'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置換してコピー'));
      await tester.pumpAndSettle();

      expect(lastCopied, 'カジュアルで書いて');
    });

    testWidgets('変数フォームをキャンセルするとコピーしない',
        (WidgetTester tester) async {
      await pumpApp(
        tester,
        seed: <Prompt>[seedPrompt(title: '変数入り', body: '{{a}}')],
      );

      await tester.tap(find.text('変数入り'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(lastCopied, isNull);
    });
  });

  group('コピー履歴', () {
    testWidgets('FreeではPro案内が出る', (WidgetTester tester) async {
      await pumpApp(tester, seed: <Prompt>[seedPrompt()]);

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.text('コピー履歴はProプラン限定です'), findsOneWidget);
    });

    testWidgets('Proではコピーした内容が履歴に残り、再コピーできる',
        (WidgetTester tester) async {
      await pumpApp(
        tester,
        isPro: true,
        seed: <Prompt>[seedPrompt(title: '対象', body: '履歴に残る本文')],
      );

      await tester.tap(find.text('対象'));
      await tester.pumpAndSettle();
      expect(lastCopied, '履歴に残る本文');

      lastCopied = null;
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.text('コピー履歴'), findsOneWidget);
      // 背後の一覧カードにも同じ文字列が出るので、履歴の行に絞って押す。
      await tester.tap(find.widgetWithText(ListTile, '履歴に残る本文'));
      await tester.pumpAndSettle();

      expect(lastCopied, '履歴に残る本文', reason: '履歴から再コピーできる');
    });
  });

  group('作成・編集', () {
    testWidgets('新規作成してリストに反映される', (WidgetTester tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('新規'));
      await tester.pumpAndSettle();
      expect(find.text('新規プロンプト'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'タイトル（例: ブログ記事の要約）'),
        '作成したプロンプト',
      );
      await tester.enterText(find.byType(TextField).at(1), '本文の中身');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('作成したプロンプト'), findsOneWidget);
      expect(store.count, 1);
    });

    testWidgets('変数チップをタップすると本文に {{変数}} が挿入される',
        (WidgetTester tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('新規'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('{{ターゲット}}'));
      await tester.pumpAndSettle();

      expect(find.text('検出: 1件'), findsOneWidget);
    });

    testWidgets('タイトルも本文も空だと保存できない', (WidgetTester tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('新規'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('タイトルか本文のどちらかを入力してください'), findsOneWidget);
      expect(store.count, 0);
    });

    testWidgets('編集して保存すると取り消しを提示する', (WidgetTester tester) async {
      await pumpApp(tester, seed: <Prompt>[seedPrompt(title: '編集前')]);

      await tester.longPress(find.text('編集前'));
      await tester.pumpAndSettle();
      expect(find.text('プロンプトを編集'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '編集後');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('編集後'), findsOneWidget);
      expect(find.text('更新しました'), findsOneWidget);

      await tester.tap(find.text('元に戻す'));
      await tester.pumpAndSettle();

      expect(find.text('編集前'), findsOneWidget);
      expect(store.count, 1);
    });
  });

  group('削除と取り消し', () {
    testWidgets('削除は確認なしで実行され、元に戻せる', (WidgetTester tester) async {
      await pumpApp(tester, seed: <Prompt>[seedPrompt(title: '消すやつ')]);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();

      expect(store.count, 0);
      expect(find.text('「消すやつ」を削除しました'), findsOneWidget);

      await tester.tap(find.text('元に戻す'));
      await tester.pumpAndSettle();

      expect(store.count, 1);
      expect(find.text('消すやつ'), findsOneWidget);
    });
  });

  group('設定画面', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
    }

    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(target, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    testWidgets('Freeでは購入導線が出る', (WidgetTester tester) async {
      await pumpApp(tester);
      await openSettings(tester);

      expect(find.text('Freeプラン'), findsOneWidget);
      expect(find.text('Proプランを購入'), findsOneWidget);
    });

    testWidgets('書き出しは Free でも Pro バッジが付かない',
        (WidgetTester tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      await scrollTo(tester, find.text('JSONから復元'));

      // 書き出しは全員に開放。Pro バッジが付くのは復元だけ。
      expect(find.text('JSONで書き出し'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
    });

    testWidgets('Freeで復元を押すとPro案内が出る', (WidgetTester tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      await scrollTo(tester, find.text('JSONから復元'));

      await tester.tap(find.text('JSONから復元'));
      await tester.pumpAndSettle();

      expect(find.text('バックアップからの復元はProプラン限定です'), findsOneWidget);
    });

    testWidgets('Proでは購入導線が消えバッジも出ない', (WidgetTester tester) async {
      await pumpApp(tester, isPro: true);
      await openSettings(tester);

      expect(find.text('Proプラン'), findsOneWidget);
      expect(find.text('Proプランを購入'), findsNothing);

      await scrollTo(tester, find.text('JSONから復元'));
      expect(find.text('Pro'), findsNothing);
    });

    testWidgets('全件削除も取り消せる', (WidgetTester tester) async {
      await pumpApp(
        tester,
        seed: <Prompt>[
          seedPrompt(id: 'a', title: 'A'),
          seedPrompt(id: 'b', title: 'B'),
        ],
      );
      await openSettings(tester);
      await scrollTo(tester, find.text('すべてのプロンプトを削除'));

      await tester.tap(find.text('すべてのプロンプトを削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '削除'));
      await tester.pumpAndSettle();

      expect(store.count, 0);
      await tester.tap(find.text('元に戻す'));
      await tester.pumpAndSettle();
      expect(store.count, 2);
    });
  });

  group('発見タブの廃止', () {
    testWidgets('下部タブは存在しない', (WidgetTester tester) async {
      await pumpApp(tester);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('発見'), findsNothing);
    });
  });
}
