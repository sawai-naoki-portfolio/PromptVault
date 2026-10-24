import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/copy_history_store.dart';
import '../models/prompt.dart';
import '../providers/app_providers.dart';
import '../providers/prompt_providers.dart';
import '../services/placeholder_parser.dart';
import 'widgets/pro_upsell_sheet.dart';
import 'widgets/variable_fill_sheet.dart';

/// このアプリの中核体験である「コピー」の一連の流れ。
///
///  1. `{{変数}}` があれば入力フォームを出して置換する（全プラン）
///  2. クリップボードへ送る
///  3. 使用回数を加算し、Pro なら履歴に積む
///  4. Free なら一定条件でインタースティシャル広告
///
/// 広告は「クリップボードへ送った後」に呼ぶ。
/// 広告の読み込み状況にコピーの成否が左右されないようにするため。
Future<void> copyPromptToClipboard(
  BuildContext context,
  WidgetRef ref,
  Prompt prompt,
) async {
  final entitlements = ref.read(entitlementsProvider);
  final variables = PlaceholderParser.extract(prompt.body);

  String text = prompt.body;
  bool replaced = false;

  if (variables.isNotEmpty) {
    final values = await showVariableFillSheet(
      context,
      body: prompt.body,
      variables: variables,
      advanced: entitlements.advancedVariables,
    );
    // シートをキャンセルしたらコピーごと中止する。
    if (values == null) return;
    text = PlaceholderParser.fill(prompt.body, values);
    replaced = true;
  }

  // シートを閉じている間に画面が破棄されている可能性がある。
  if (!context.mounted) return;

  await copyTextToClipboard(
    context,
    ref,
    text: text,
    sourceTitle: prompt.displayTitle,
    message: replaced ? '変数を置換してコピーしました' : 'コピーしました',
  );

  if (!context.mounted) return;
  await ref.read(promptsProvider.notifier).markUsed(prompt);
}

/// テキストをクリップボードへ送り、履歴と広告の後処理まで行う。
///
/// コピー履歴からの再コピーでも同じ経路を通す。
Future<void> copyTextToClipboard(
  BuildContext context,
  WidgetRef ref, {
  required String text,
  required String sourceTitle,
  String message = 'コピーしました',
}) async {
  await Clipboard.setData(ClipboardData(text: text));

  final entitlements = ref.read(entitlementsProvider);
  if (entitlements.copyHistory) {
    await ref.read(copyHistoryProvider.notifier).add(
          CopyHistoryEntry(
            text: text,
            sourceTitle: sourceTitle,
            copiedAt: DateTime.now(),
          ),
        );
  }

  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
      // 履歴は Pro 限定なので、コピーした直後にだけ軽く案内する。
      action: entitlements.copyHistory
          ? null
          : SnackBarAction(
              label: '履歴に残す',
              onPressed: () => showProUpsellSheet(
                context,
                reason: UpsellReason.copyHistory,
              ),
            ),
    ),
  );

  await ref.read(adsServiceProvider).onRewardableAction();
}
