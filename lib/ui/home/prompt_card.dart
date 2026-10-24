import 'package:flutter/material.dart';

import '../../models/prompt.dart';
import '../../services/placeholder_parser.dart';

/// 一覧に並ぶプロンプトカード。
///
/// カード本体のタップ = コピー。編集は長押しかメニューから行う。
/// 「探す・直す・コピペする」のうち最頻の "コピペ" を最短の操作に割り当てている。
class PromptCard extends StatelessWidget {
  const PromptCard({
    super.key,
    required this.prompt,
    required this.onCopy,
    required this.onEdit,
    required this.onTogglePin,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Prompt prompt;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onTogglePin;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variableCount = PlaceholderParser.extract(prompt.body).length;

    return Card(
      child: InkWell(
        onTap: onCopy,
        onLongPress: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (prompt.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 2),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      prompt.displayTitle,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: onTogglePin,
                    visualDensity: VisualDensity.compact,
                    tooltip: prompt.isPinned ? 'ピン留めを解除' : 'ピン留め',
                    icon: Icon(
                      prompt.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 20,
                      color: prompt.isPinned
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                  ),
                  PopupMenuButton<_CardAction>(
                    tooltip: 'その他',
                    icon: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: theme.colorScheme.outline,
                    ),
                    onSelected: (_CardAction action) => switch (action) {
                      _CardAction.edit => onEdit(),
                      _CardAction.duplicate => onDuplicate(),
                      _CardAction.delete => onDelete(),
                    },
                    itemBuilder: (BuildContext context) =>
                        const <PopupMenuEntry<_CardAction>>[
                      PopupMenuItem<_CardAction>(
                        value: _CardAction.edit,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('編集'),
                        ),
                      ),
                      PopupMenuItem<_CardAction>(
                        value: _CardAction.duplicate,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.copy_all_outlined),
                          title: Text('複製'),
                        ),
                      ),
                      PopupMenuItem<_CardAction>(
                        value: _CardAction.delete,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('削除'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Text(
                  prompt.preview,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final String tag in prompt.tags.take(3))
                          _MiniChip(label: '#$tag'),
                        if (variableCount > 0)
                          _MiniChip(
                            icon: Icons.data_object,
                            label: '変数$variableCount',
                            emphasized: true,
                          ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: onCopy,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'コピー',
                    icon: const Icon(Icons.content_copy, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CardAction { edit, duplicate, delete }

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    this.icon,
    this.emphasized = false,
  });

  final String label;
  final IconData? icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg =
        emphasized ? theme.colorScheme.primary : theme.colorScheme.outline;
    final bg = emphasized
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
