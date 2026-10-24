import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';

/// Pro 訴求を出すきっかけ。見出しの文言を切り替えるために使う。
enum UpsellReason {
  advancedVariables,
  copyHistory,
  importBackup,
  removeAds,
  generic;

  String get headline => switch (this) {
        UpsellReason.advancedVariables => '変数の選択肢と既定値はProプラン限定です',
        UpsellReason.copyHistory => 'コピー履歴はProプラン限定です',
        UpsellReason.importBackup => 'バックアップからの復元はProプラン限定です',
        UpsellReason.removeAds => '広告を消してもっと快適に',
        UpsellReason.generic => 'Proプランでもっと速く',
      };
}

/// Pro プランの案内シート。買い切りのため「一度きりの支払い」を明示する。
Future<void> showProUpsellSheet(
  BuildContext context, {
  UpsellReason reason = UpsellReason.generic,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => _ProUpsellSheet(reason: reason),
  );
}

class _ProUpsellSheet extends ConsumerWidget {
  const _ProUpsellSheet({required this.reason});

  final UpsellReason reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final purchase = ref.watch(purchaseServiceProvider);
    final price = purchase.proProduct?.price;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.workspace_premium,
                    color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    reason.headline,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const ProBenefitList(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.check_circle_outline,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '買い切り（1回のお支払い）。月額課金はありません。\n'
                      '保存数・ピン留め・書き出しはFreeでも無制限です。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(purchaseServiceProvider).buyPro();
              },
              icon: const Icon(Icons.lock_open),
              label: Text(price == null ? 'Proプランを購入' : 'Proプランを購入（$price）'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(purchaseServiceProvider).restorePurchases();
              },
              child: const Text('購入情報を復元する'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pro プランの特典一覧。設定画面と訴求シートで同じ内容を使う。
class ProBenefitList extends StatelessWidget {
  const ProBenefitList({super.key});

  static const List<(IconData, String, String)> _benefits =
      <(IconData, String, String)>[
    (Icons.block, '広告が完全非表示', 'バナーもコピー時の全画面広告も消えます'),
    (Icons.tune, '変数の選択肢と既定値', '{{トーン:丁寧|カジュアル}} をタップで選べます'),
    (Icons.history, 'コピー履歴', '変数を埋めた結果を遡って再コピーできます'),
    (Icons.download, 'バックアップからの復元', '機種変更のときに丸ごと戻せます'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final (IconData icon, String title, String desc) b in _benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(b.$1, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        b.$2,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        b.$3,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
