@Tags(<String>['screenshots'])
library;

import 'dart:io';

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

/// README 用のスクリーンショットを生成する。
///
/// 実機ではなく、ウィジェットテストと同じ経路で本物のウィジェットツリーを
/// 描画して PNG に書き出す。エミュレータが無い CI でも生成できる。
///
/// 生成コマンド:
/// ```
/// flutter test --update-goldens --tags screenshots --run-skipped
/// ```
///
/// 通常の `flutter test` では実行されない（`dart_test.yaml` で skip 指定）。
/// フォントのレンダリングは環境差が出るため、
/// 「差分が出たら失敗するテスト」としては運用しない。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryPromptStore store;

  setUpAll(() async {
    // 既定のテストフォントは全グリフが四角なので、実フォントを読み込む。

    // 本文用。Material のテキストテーマが参照する 'Roboto' として登録し、
    // アプリ側のコードを変えずに描画だけ差し替える。
    final japanese = _findJapaneseFont();
    if (japanese != null) {
      await _loadFont('Roboto', japanese);
      // 変数チップが指定する等幅書体。テスト環境には存在しないので同じ実体を割り当てる。
      await _loadFont('monospace', japanese);
    }

    // アイコン用。これが無いと Icon がすべて豆腐になる。
    final icons = _findMaterialIconsFont();
    if (icons != null) await _loadFont('MaterialIcons', icons);
  });

  setUp(() {
    store = InMemoryPromptStore(_samplePrompts());

    // クリップボードのチャンネルを塞いでおく。
    // モックしないと Clipboard.setData が MissingPluginException になり、
    // コピー後の処理（履歴への追加など）がそこで止まってしまう。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    store.dispose();
  });

  /// スマートフォン相当のサイズで起動する。DPR 2 で高解像度の PNG を得る。
  Future<void> pumpApp(WidgetTester tester, {bool isPro = false}) async {
    // 実機に近い見た目にするため、テスト既定の影無効化を解除する。
    // 各テストの終わり（capture）で必ず戻す。戻さないとフレームワークの
    // 「描画デバッグ変数が変更されたまま」という検証に引っかかる。
    debugDisableShadows = false;

    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{
      AppConstants.prefsIsProUser: isPro,
      AppConstants.prefsSeeded: true,
    });
    final prefs = await SharedPreferences.getInstance();

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

  Future<void> capture(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../Doc/screenshots/$name.png'),
    );
    debugDisableShadows = true;
  }

  testWidgets('01 プロンプト一覧（Free）', (WidgetTester tester) async {
    await pumpApp(tester);
    await capture(tester, '01_list');
  });

  testWidgets('02 検索で絞り込み', (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField).first, '要約');
    await tester.pumpAndSettle();
    await capture(tester, '02_search');
  });

  testWidgets('03 作成・編集画面', (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.longPress(find.text('記事をSNS向けに要約').first);
    await tester.pumpAndSettle();
    await capture(tester, '03_editor');
  });

  testWidgets('04 変数フォーム（Pro）', (WidgetTester tester) async {
    await pumpApp(tester, isPro: true);
    await tester.tap(find.text('記事をSNS向けに要約').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'ターゲット を入力'),
      '20代のエンジニア',
    );
    await tester.pumpAndSettle();
    // 選択肢はタップで切り替わることを見せる。
    await tester.tap(find.widgetWithText(ChoiceChip, 'カジュアル'));
    await tester.pumpAndSettle();
    await capture(tester, '04_variable_form');
  });

  testWidgets('05 コピー履歴（Pro）', (WidgetTester tester) async {
    await pumpApp(tester, isPro: true);

    // 履歴を1件作ってから開く。
    await tester.tap(find.text('英文メールの下書き'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '相手 を入力'), '取引先の田中様');
    await tester.enterText(find.widgetWithText(TextField, '目的 を入力'), '納期の相談');
    await tester.pumpAndSettle();
    await tester.tap(find.text('置換してコピー'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await capture(tester, '05_copy_history');
  });

  testWidgets('06 Pro訴求', (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await capture(tester, '06_pro_upsell');
  });

  testWidgets('07 設定・課金画面（Free）', (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await capture(tester, '07_settings');
  });
}

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// Flutter SDK に同梱されている Material Icons を探す。
String? _findMaterialIconsFont() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (root != null) '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ];
  for (final String path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// 日本語グリフを持つフォントを探す。見つからなければ null。
String? _findJapaneseFont() {
  const candidates = <String>[
    // Debian/Ubuntu
    '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/fonts-japanese-gothic.ttf',
    // macOS
    '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc',
    '/Library/Fonts/Arial Unicode.ttf',
  ];
  for (final String path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// スクリーンショットに写すサンプルデータ。
List<Prompt> _samplePrompts() {
  Prompt make({
    required String id,
    required String title,
    required String body,
    required List<String> tags,
    bool isPinned = false,
    int usageCount = 0,
    required int daysAgo,
  }) {
    final t = DateTime(2026, 7, 27).subtract(Duration(days: daysAgo));
    return Prompt(
      id: id,
      title: title,
      body: body,
      tags: tags,
      isPinned: isPinned,
      usageCount: usageCount,
      createdAt: t,
      updatedAt: t,
    );
  }

  return <Prompt>[
    make(
      id: 'p1',
      title: '記事をSNS向けに要約',
      body: '以下の記事を{{ターゲット}}向けに{{文字数=140}}字で要約してください。\n'
          'トーンは{{トーン:丁寧|カジュアル|硬め}}で、結論を最初に書いてください。',
      tags: <String>['要約', '定番', 'ライティング'],
      isPinned: true,
      usageCount: 42,
      daysAgo: 1,
    ),
    make(
      id: 'p2',
      title: 'コードレビュー依頼',
      body: '以下の{{言語}}のコードをレビューしてください。\n'
          '観点: バグ・可読性・パフォーマンス・命名。',
      tags: <String>['開発', '定番'],
      isPinned: true,
      usageCount: 31,
      daysAgo: 2,
    ),
    make(
      id: 'p3',
      title: '英文メールの下書き',
      body: '{{相手}}宛に、{{目的}}を伝える英文メールを書いてください。トーンは丁寧に。',
      tags: <String>['英語', 'メール'],
      usageCount: 18,
      daysAgo: 4,
    ),
    make(
      id: 'p4',
      title: '企画のブレスト',
      body: '{{テーマ}}についてアイデアを{{個数=10}}個出してください。'
          'それぞれに狙いと想定される反論を添えてください。',
      tags: <String>['ブレスト', '企画'],
      usageCount: 9,
      daysAgo: 6,
    ),
    make(
      id: 'p5',
      title: '議事録の整形',
      body: '以下のメモを議事録の形式に整えてください。決定事項とToDoを分けて記載。',
      tags: <String>['議事録', 'ビジネス'],
      usageCount: 5,
      daysAgo: 9,
    ),
  ];
}
