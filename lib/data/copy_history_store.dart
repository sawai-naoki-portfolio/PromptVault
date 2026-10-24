import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// コピーした結果の1件。
@immutable
class CopyHistoryEntry {
  const CopyHistoryEntry({
    required this.text,
    required this.sourceTitle,
    required this.copiedAt,
  });

  /// 実際にクリップボードへ送ったテキスト（変数置換済み）。
  final String text;

  /// 元になったプロンプトの見出し。
  final String sourceTitle;

  final DateTime copiedAt;

  /// 一覧に出す1行プレビュー。
  String get preview {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 100 ? flat : '${flat.substring(0, 100)}…';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'sourceTitle': sourceTitle,
        'copiedAt': copiedAt.toIso8601String(),
      };

  static CopyHistoryEntry? fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String? ?? '';
    if (text.isEmpty) return null;
    return CopyHistoryEntry(
      text: text,
      sourceTitle: json['sourceTitle'] as String? ?? '',
      copiedAt:
          DateTime.tryParse(json['copiedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// コピー履歴の保存先（Pro 機能）。
///
/// 件数が浅く構造も単純なので、Hive の box を増やさず
/// SharedPreferences に JSON 文字列として持つ。
class CopyHistoryStore {
  CopyHistoryStore(this._prefs);

  final SharedPreferences _prefs;

  List<CopyHistoryEntry> load() {
    final raw = _prefs.getString(AppConstants.prefsCopyHistory);
    if (raw == null || raw.isEmpty) return const <CopyHistoryEntry>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <CopyHistoryEntry>[];
      return <CopyHistoryEntry>[
        for (final dynamic item in decoded)
          if (item is Map<String, dynamic>)
            if (CopyHistoryEntry.fromJson(item) case final CopyHistoryEntry e)
              e,
      ];
    } on FormatException {
      // 壊れていたら履歴なしとして扱う。ここで落とす価値はない。
      return const <CopyHistoryEntry>[];
    }
  }

  /// 新しい履歴を先頭に積む。
  ///
  /// 同じテキストが連続した場合は古いほうを消して1件にまとめる。
  /// 同じプロンプトを続けてコピーしたときに履歴が埋まるのを防ぐ。
  Future<List<CopyHistoryEntry>> add(CopyHistoryEntry entry) async {
    final next = <CopyHistoryEntry>[
      entry,
      ...load().where((CopyHistoryEntry e) => e.text != entry.text),
    ].take(AppConstants.copyHistoryLimit).toList(growable: false);

    await _save(next);
    return next;
  }

  Future<void> clear() => _prefs.remove(AppConstants.prefsCopyHistory);

  Future<void> _save(List<CopyHistoryEntry> entries) {
    return _prefs.setString(
      AppConstants.prefsCopyHistory,
      jsonEncode(
        entries.map((CopyHistoryEntry e) => e.toJson()).toList(growable: false),
      ),
    );
  }
}
