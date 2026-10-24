import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/starter_prompts.dart';
import '../../models/prompt.dart';
import '../../providers/app_providers.dart';
import '../../providers/prompt_providers.dart';
import '../copy_flow.dart';
import '../editor/editor_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/banner_ad_view.dart';
import '../widgets/copy_history_sheet.dart';
import '../widgets/pro_upsell_sheet.dart';
import 'prompt_card.dart';

/// プロンプト一覧（アプリのホーム）。
class PromptListScreen extends ConsumerStatefulWidget {
  const PromptListScreen({super.key});

  @override
  ConsumerState<PromptListScreen> createState() => _PromptListScreenState();
}

class _PromptListScreenState extends ConsumerState<PromptListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor({Prompt? prompt}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => EditorScreen(prompt: prompt),
      ),
    );
  }

  Future<void> _openSettings() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SettingsScreen(),
      ),
    );
  }

  Future<void> _openHistory() {
    if (!ref.read(entitlementsProvider).copyHistory) {
      return showProUpsellSheet(context, reason: UpsellReason.copyHistory);
    }
    return showCopyHistorySheet(context);
  }

  Future<void> _duplicate(Prompt prompt) async {
    await ref.read(promptsProvider.notifier).create(
          title: '${prompt.displayTitle} のコピー',
          body: prompt.body,
          tags: prompt.tags,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('複製しました')),
    );
  }

  /// 削除。確認ダイアログは出さず、取り消せるようにする。
  ///
  /// 1タップで消せて1タップで戻せるほうが、毎回ダイアログを挟むより速い。
  Future<void> _delete(Prompt prompt) async {
    final notifier = ref.read(promptsProvider.notifier);
    await notifier.delete(prompt.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('「${prompt.displayTitle}」を削除しました'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () => notifier.restoreSnapshot(<Prompt>[prompt]),
          ),
        ),
      );
  }

  Future<void> _addSamples() async {
    final added =
        await ref.read(promptsProvider.notifier).addStarters(StarterPrompts.all);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('サンプルを$added件追加しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompts = ref.watch(visiblePromptsProvider);
    final totalCount = ref.watch(promptCountProvider);
    final tags = ref.watch(allTagsProvider);
    final selectedTags = ref.watch(selectedTagsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: <Widget>[
          IconButton(
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
            tooltip: 'コピー履歴',
          ),
          const _SortMenuButton(),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新規'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (String value) =>
                  ref.read(searchQueryProvider.notifier).set(value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'タイトル・本文・タグを検索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).clear();
                        },
                      ),
              ),
            ),
          ),
          if (tags.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  if (selectedTags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.filter_alt_off, size: 16),
                        label: const Text('解除'),
                        onPressed: () =>
                            ref.read(selectedTagsProvider.notifier).clear(),
                      ),
                    ),
                  for (final String tag in tags)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('#$tag'),
                        selected: selectedTags.contains(tag),
                        onSelected: (_) =>
                            ref.read(selectedTagsProvider.notifier).toggle(tag),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: prompts.isEmpty
                ? _EmptyState(
                    isFiltered: totalCount > 0,
                    onCreate: () => _openEditor(),
                    onAddSamples: _addSamples,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: prompts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final prompt = prompts[index];
                      return PromptCard(
                        prompt: prompt,
                        onCopy: () =>
                            copyPromptToClipboard(context, ref, prompt),
                        onEdit: () => _openEditor(prompt: prompt),
                        onTogglePin: () =>
                            ref.read(promptsProvider.notifier).togglePin(prompt),
                        onDuplicate: () => _duplicate(prompt),
                        onDelete: () => _delete(prompt),
                      );
                    },
                  ),
          ),
          if (prompts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${prompts.length}件表示中',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          const BannerAdView(),
        ],
      ),
    );
  }
}

class _SortMenuButton extends ConsumerWidget {
  const _SortMenuButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(sortModeProvider);
    return PopupMenuButton<SortMode>(
      icon: const Icon(Icons.sort),
      tooltip: '並び替え',
      initialValue: current,
      onSelected: (SortMode mode) =>
          ref.read(sortModeProvider.notifier).set(mode),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<SortMode>>[
        for (final SortMode mode in SortMode.values)
          PopupMenuItem<SortMode>(value: mode, child: Text(mode.label)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isFiltered,
    required this.onCreate,
    required this.onAddSamples,
  });

  /// 保存済みは存在するが、検索・フィルターの結果0件なのかどうか。
  final bool isFiltered;
  final VoidCallback onCreate;
  final VoidCallback onAddSamples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isFiltered ? Icons.search_off : Icons.inbox_outlined,
              size: 56,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered ? '条件に合うプロンプトがありません' : 'まだプロンプトがありません',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? '検索語やタグフィルターを変更してみてください。'
                  : 'よく使うプロンプトを登録して、1タップでコピーできるようにしましょう。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            if (!isFiltered) ...<Widget>[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('最初のプロンプトを作る'),
                style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onAddSamples,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('サンプルを追加する'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
