import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/prompt_providers.dart';
import '../copy_flow.dart';

/// コピー履歴（Pro）。変数を埋めた結果を遡って再コピーできる。
Future<void> showCopyHistorySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => const _CopyHistorySheet(),
  );
}

class _CopyHistorySheet extends ConsumerWidget {
  const _CopyHistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(copyHistoryProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (BuildContext context, ScrollController controller) {
        return Column(
          children: <Widget>[
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.history, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'コピー履歴',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (entries.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          ref.read(copyHistoryProvider.notifier).clear(),
                      child: const Text('消去'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'まだ履歴がありません。\nプロンプトをコピーするとここに残ります。',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final entry = entries[index];
                        return Card(
                          child: ListTile(
                            title: Text(
                              entry.preview,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${entry.sourceTitle} ・ ${_formatTime(entry.copiedAt)}',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: theme.colorScheme.outline),
                              ),
                            ),
                            trailing: const Icon(Icons.content_copy, size: 18),
                            onTap: () async {
                              await copyTextToClipboard(
                                context,
                                ref,
                                text: entry.text,
                                sourceTitle: entry.sourceTitle,
                              );
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// 「3分前」「2時間前」程度のざっくり表示。
  /// 履歴は浅いので日付まで出す必要はない。
  static String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inHours < 1) return '${diff.inMinutes}分前';
    if (diff.inDays < 1) return '${diff.inHours}時間前';
    return '${diff.inDays}日前';
  }
}
