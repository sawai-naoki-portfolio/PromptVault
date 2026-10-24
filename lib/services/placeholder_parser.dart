import 'package:flutter/foundation.dart';

/// 本文から取り出した1つの変数。
@immutable
class PromptVariable {
  const PromptVariable({
    required this.name,
    this.choices = const <String>[],
    this.defaultValue = '',
  });

  /// 変数名。フォームのラベルと置換のキーになる。
  final String name;

  /// 選択肢。空なら自由入力。
  final List<String> choices;

  /// 既定値。空なら未入力で始まる。
  final String defaultValue;

  bool get hasChoices => choices.isNotEmpty;

  /// 編集画面などに表示する正規化した記法。
  String get token {
    final buffer = StringBuffer('{{')..write(name);
    if (hasChoices) buffer.write(':${choices.join('|')}');
    if (defaultValue.isNotEmpty && defaultValue != _implicitDefault) {
      buffer.write('=$defaultValue');
    }
    return (buffer..write('}}')).toString();
  }

  /// 選択肢の先頭を暗黙の既定値にしているかの判定用。
  String get _implicitDefault => hasChoices ? choices.first : '';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PromptVariable &&
          other.name == name &&
          other.defaultValue == defaultValue &&
          listEquals(other.choices, choices));

  @override
  int get hashCode => Object.hash(name, defaultValue, Object.hashAll(choices));

  @override
  String toString() => token;
}

/// `{{変数名}}` プレースホルダの検出と置換。
///
/// 対応する記法:
///
/// | 記法 | 意味 |
/// |---|---|
/// | `{{ターゲット}}` | 自由入力 |
/// | `{{文字数=200}}` | 既定値つきの自由入力 |
/// | `{{トーン:丁寧\|カジュアル}}` | 選択肢（先頭が既定値） |
/// | `{{トーン:丁寧\|カジュアル=カジュアル}}` | 選択肢 + 既定値を明示 |
///
/// 選択肢と既定値は Pro 限定の機能だが、**解析自体は常に行う**。
/// Free で `{{文字数=200}}` を書いたときに変数名が「文字数=200」に
/// なってしまうと、あとで Pro にした瞬間に意味が変わってしまうため。
class PlaceholderParser {
  const PlaceholderParser._();

  /// `{{ ... }}` を拾う正規表現。
  ///
  /// - 中括弧の入れ子は許容しない（`[^{}]`）ので壊れた記法で暴走しない。
  /// - 改行はまたがない。
  static final RegExp pattern = RegExp(r'\{\{\s*([^{}\n]*?)\s*\}\}');

  /// 本文に含まれる変数を「出現順・重複なし」で返す。
  ///
  /// 同じ変数名が複数回出てもフォームの入力欄は1つにまとめる。
  /// 2回目以降に選択肢や既定値が書かれていた場合は、最初の定義を優先する。
  static List<PromptVariable> extract(String text) {
    final seen = <String>{};
    final result = <PromptVariable>[];
    for (final match in pattern.allMatches(text)) {
      final variable = _parseSpec(match.group(1) ?? '');
      if (variable == null) continue;
      if (seen.add(variable.name)) result.add(variable);
    }
    return List<PromptVariable>.unmodifiable(result);
  }

  /// 変数名だけが欲しい場合の簡易版。
  static List<String> extractNames(String text) =>
      extract(text).map((PromptVariable v) => v.name).toList(growable: false);

  /// 変数を含むかどうか。
  static bool hasPlaceholders(String text) => extract(text).isNotEmpty;

  /// フォームの初期値。既定値が書かれていればそれを入れておく。
  static Map<String, String> initialValues(List<PromptVariable> variables) {
    return <String, String>{
      for (final PromptVariable v in variables) v.name: v.defaultValue,
    };
  }

  /// `{{ }}` の中身を解析する。変数として扱えない場合は null。
  ///
  /// 解析順は「まず `:` で選択肢を切り出し、残りの末尾 `=` を既定値とする」。
  /// `:` が無い場合は最初の `=` の前後を名前と既定値に分ける。
  static PromptVariable? _parseSpec(String raw) {
    final spec = raw.trim();
    if (spec.isEmpty) return null;

    final colon = spec.indexOf(':');
    if (colon < 0) {
      // 選択肢なし。`名前=既定値` か、ただの `名前`。
      final equals = spec.indexOf('=');
      if (equals < 0) return PromptVariable(name: spec);

      final name = spec.substring(0, equals).trim();
      if (name.isEmpty) return null;
      return PromptVariable(
        name: name,
        defaultValue: spec.substring(equals + 1).trim(),
      );
    }

    final name = spec.substring(0, colon).trim();
    if (name.isEmpty) return null;

    var rest = spec.substring(colon + 1);
    String explicitDefault = '';

    // 既定値は末尾の `=` 以降。選択肢のほうに `=` が来ることは想定しない。
    final equals = rest.lastIndexOf('=');
    if (equals >= 0) {
      explicitDefault = rest.substring(equals + 1).trim();
      rest = rest.substring(0, equals);
    }

    final choices = rest
        .split('|')
        .map((String c) => c.trim())
        .where((String c) => c.isNotEmpty)
        .toList(growable: false);

    if (choices.isEmpty) {
      // `{{名前:}}` や `{{名前:=既定値}}` は選択肢なしとして扱う。
      return PromptVariable(name: name, defaultValue: explicitDefault);
    }

    return PromptVariable(
      name: name,
      choices: choices,
      // 明示が無ければ先頭の選択肢を既定値にする。
      // そのまま「置換してコピー」を押しても成立する状態にしておきたい。
      defaultValue: explicitDefault.isNotEmpty ? explicitDefault : choices.first,
    );
  }

  /// [values] に従って本文を置換する。
  ///
  /// [values] に無い変数、または空文字が渡された変数は
  /// `{{...}}` の記法をそのまま残す。ユーザーが空欄のまま確定したときに
  /// 「何が埋まっていないか」がコピー後のテキストで分かるようにするため。
  static String fill(String text, Map<String, String> values) {
    return text.replaceAllMapped(pattern, (Match match) {
      final variable = _parseSpec(match.group(1) ?? '');
      if (variable == null) return match.group(0)!;
      final value = values[variable.name];
      if (value == null || value.isEmpty) return match.group(0)!;
      return value;
    });
  }

  /// 本文中の指定位置に `{{name}}` を挿入した結果を返す。
  static InsertionResult insert(String text, int offset, String name) {
    final safeOffset = offset.clamp(0, text.length);
    final token = '{{$name}}';
    return InsertionResult(
      text: text.replaceRange(safeOffset, safeOffset, token),
      caretOffset: safeOffset + token.length,
    );
  }
}

/// [PlaceholderParser.insert] の戻り値。
class InsertionResult {
  const InsertionResult({required this.text, required this.caretOffset});

  final String text;
  final int caretOffset;
}
