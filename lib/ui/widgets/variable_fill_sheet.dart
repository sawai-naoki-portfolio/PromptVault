import 'package:flutter/material.dart';

import '../../services/placeholder_parser.dart';

/// `{{変数}}` の入力フォーム。
///
/// 入力が確定したら変数名→値のマップを返す。
/// キャンセル時は null を返し、呼び出し側はコピーを中止する。
///
/// [advanced] が false（Free）のときは選択肢と既定値を無視して
/// すべて素のテキスト入力にする。変数入力自体は全プランで使える。
Future<Map<String, String>?> showVariableFillSheet(
  BuildContext context, {
  required String body,
  required List<PromptVariable> variables,
  required bool advanced,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => _VariableFillSheet(
      body: body,
      variables: variables,
      advanced: advanced,
    ),
  );
}

class _VariableFillSheet extends StatefulWidget {
  const _VariableFillSheet({
    required this.body,
    required this.variables,
    required this.advanced,
  });

  final String body;
  final List<PromptVariable> variables;
  final bool advanced;

  @override
  State<_VariableFillSheet> createState() => _VariableFillSheetState();
}

class _VariableFillSheetState extends State<_VariableFillSheet> {
  late final Map<String, TextEditingController> _controllers;

  /// 選択肢つき変数の選択状態。
  late final Map<String, String> _selections;

  @override
  void initState() {
    super.initState();
    _controllers = <String, TextEditingController>{};
    _selections = <String, String>{};

    for (final PromptVariable v in widget.variables) {
      if (widget.advanced && v.hasChoices) {
        _selections[v.name] = v.defaultValue;
      } else {
        _controllers[v.name] = TextEditingController(
          text: widget.advanced ? v.defaultValue : '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _values => <String, String>{
        for (final MapEntry<String, TextEditingController> e
            in _controllers.entries)
          e.key: e.value.text,
        ..._selections,
      };

  int get _blankCount =>
      _values.values.where((String v) => v.trim().isEmpty).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = PlaceholderParser.fill(widget.body, _values);

    return Padding(
      // キーボードに入力欄が隠れないよう、ビューインセット分だけ持ち上げる。
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (BuildContext context, ScrollController scrollController) {
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.edit_note, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '変数を入力',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${widget.variables.length}件',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: <Widget>[
                    for (final PromptVariable v in widget.variables)
                      _VariableField(
                        variable: v,
                        controller: _controllers[v.name],
                        selected: _selections[v.name],
                        onSelected: (String value) =>
                            setState(() => _selections[v.name] = value),
                        onChanged: () => setState(() {}),
                      ),
                    const SizedBox(height: 20),
                    Text('プレビュー', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(preview, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (_blankCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '未入力の変数が$_blankCount件あります。空欄のままなら {{変数名}} が残ります。',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(_values),
                        icon: const Icon(Icons.content_copy),
                        label: const Text('置換してコピー'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 変数1件ぶんの入力欄。選択肢つきならチップ、なければテキスト入力。
class _VariableField extends StatelessWidget {
  const _VariableField({
    required this.variable,
    required this.controller,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
  });

  final PromptVariable variable;
  final TextEditingController? controller;
  final String? selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 10),
          child: Text(
            '{{${variable.name}}}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              // 'monospace' は Android の総称名。
              // iOS には存在しないので実在する等幅書体を後ろに並べる。
              fontFamily: 'monospace',
              fontFamilyFallback: const <String>['Menlo', 'Courier'],
            ),
          ),
        ),
        if (controller == null)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String choice in variable.choices)
                ChoiceChip(
                  label: Text(choice),
                  selected: selected == choice,
                  onSelected: (_) => onSelected(choice),
                ),
            ],
          )
        else
          TextField(
            controller: controller,
            decoration: InputDecoration(hintText: '${variable.name} を入力'),
            textInputAction: TextInputAction.next,
            onChanged: (_) => onChanged(),
          ),
      ],
    );
  }
}
