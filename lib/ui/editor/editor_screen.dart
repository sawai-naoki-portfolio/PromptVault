import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entitlements.dart';
import '../../core/prompt_query.dart';
import '../../models/prompt.dart';
import '../../providers/app_providers.dart';
import '../../providers/prompt_providers.dart';
import '../../services/placeholder_parser.dart';
import '../app_messenger.dart';
import '../widgets/banner_ad_view.dart';
import '../widgets/pro_upsell_sheet.dart';

/// プロンプトの作成・編集画面。
///
/// [prompt] が null なら新規作成。
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, this.prompt});

  final Prompt? prompt;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _tagsController;
  final FocusNode _bodyFocus = FocusNode();

  bool _saving = false;

  /// 変数チップの初期候補。実務で頻出するものを既定で並べる。
  static const List<String> _suggestedVariables = <String>[
    'ターゲット',
    '文字数',
    'トーン',
    '言語',
    '入力テキスト',
    '目的',
  ];

  bool get _isNew => widget.prompt == null;

  @override
  void initState() {
    super.initState();
    final p = widget.prompt;
    _titleController = TextEditingController(text: p?.title ?? '');
    _bodyController = TextEditingController(text: p?.body ?? '');
    _tagsController = TextEditingController(text: p?.tags.join(', ') ?? '');

    // 変数チップの活性状態とプレビューを本文の変更に追従させる。
    _bodyController.addListener(_onBodyChanged);
  }

  void _onBodyChanged() => setState(() {});

  @override
  void dispose() {
    _bodyController.removeListener(_onBodyChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _tagsController.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  /// 本文のカーソル位置に `{{name}}` を挿入する。
  void _insertVariable(String name) {
    final selection = _bodyController.selection;
    // 一度もフォーカスしていないと selection.start は -1 になる。末尾に足す。
    final offset =
        selection.start < 0 ? _bodyController.text.length : selection.start;

    final result = PlaceholderParser.insert(_bodyController.text, offset, name);
    _bodyController.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.caretOffset),
    );
    _bodyFocus.requestFocus();
  }

  Future<void> _insertCustomVariable() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('変数を追加'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '変数名（例: 業界）',
            prefixText: '{{',
            suffixText: '}}',
          ),
          onSubmitted: (String v) => Navigator.of(context).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
            child: const Text('挿入'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    _insertVariable(trimmed);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final notifier = ref.read(promptsProvider.notifier);
    final adsService = ref.read(adsServiceProvider);
    final original = widget.prompt;
    final tags = PromptQuery.parseTags(_tagsController.text);

    final MutationOutcome outcome = _isNew
        ? await notifier.create(
            title: _titleController.text,
            body: _bodyController.text,
            tags: tags,
          )
        : await notifier.update(
            original!,
            title: _titleController.text,
            body: _bodyController.text,
            tags: tags,
          );

    if (!mounted) return;
    setState(() => _saving = false);

    if (outcome == MutationOutcome.blockedByEmptyContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タイトルか本文のどちらかを入力してください')),
      );
      return;
    }

    Navigator.of(context).pop();

    // 画面を閉じた後の通知なので、アプリ全体で共有している messenger を使う。
    if (original != null) {
      showAppSnackBar(
        SnackBar(
          content: const Text('更新しました'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '元に戻す',
            // 編集前のスナップショットをそのまま書き戻す。
            onPressed: () => notifier.restoreSnapshot(<Prompt>[original]),
          ),
        ),
      );
    } else {
      // 新規保存時のみ広告のカウント対象。編集のたびに広告が出るのは煩わしいため。
      await adsService.onRewardableAction();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variables = PlaceholderParser.extract(_bodyController.text);
    final entitlements = ref.watch(entitlementsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新規プロンプト' : 'プロンプトを編集'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      hintText: 'タイトル（例: ブログ記事の要約）',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- 変数の挿入チップ ---
                  Row(
                    children: <Widget>[
                      Icon(Icons.data_object,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text('変数を挿入', style: theme.textTheme.labelLarge),
                      const Spacer(),
                      if (variables.isNotEmpty)
                        Text(
                          '検出: ${variables.length}件',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final String name in _suggestedVariables)
                        ActionChip(
                          label: Text('{{$name}}'),
                          labelStyle: theme.textTheme.labelMedium,
                          onPressed: () => _insertVariable(name),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('カスタム'),
                        labelStyle: theme.textTheme.labelMedium,
                        onPressed: _insertCustomVariable,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // --- 本文エディタ ---
                  TextField(
                    controller: _bodyController,
                    focusNode: _bodyFocus,
                    maxLines: null,
                    minLines: 12,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText:
                          '本文を入力\n\n例: 以下の文章を{{ターゲット}}向けに{{文字数=200}}字で要約してください。',
                    ),
                  ),

                  if (variables.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    _VariableSummary(
                      variables: variables,
                      advanced: entitlements.advancedVariables,
                    ),
                  ],

                  const SizedBox(height: 20),
                  TextField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      hintText: 'タグ（カンマ区切り 例: 要約, 英語）',
                      prefixIcon: Icon(Icons.tag),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const BannerAdView(),
        ],
      ),
    );
  }
}

/// 検出した変数の一覧と、記法のヘルプ。
class _VariableSummary extends StatelessWidget {
  const _VariableSummary({required this.variables, required this.advanced});

  final List<PromptVariable> variables;
  final bool advanced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monoStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Menlo', 'Courier'],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final PromptVariable v in variables)
                Text(v.token, style: monoStyle),
            ],
          ),
          const SizedBox(height: 6),
          if (advanced)
            Text(
              'コピー時に入力フォームが開きます。'
              '{{トーン:丁寧|カジュアル}} で選択肢、{{文字数=200}} で既定値を指定できます。',
              style: theme.textTheme.bodySmall,
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Proにすると {{トーン:丁寧|カジュアル}} の選択肢や '
                    '{{文字数=200}} の既定値が使えます。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => showProUpsellSheet(
                    context,
                    reason: UpsellReason.advancedVariables,
                  ),
                  style:
                      TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('詳細'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
