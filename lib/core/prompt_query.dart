import '../models/prompt.dart';
import 'constants.dart';

/// 一覧の絞り込み・並び替えを行う純粋関数群。
///
/// UI や Riverpod から切り離しておくことで、
/// 検索の当たり判定やピン優先の並びをユニットテストで固定できる。
class PromptQuery {
  const PromptQuery._();

  /// 絞り込み → 並び替え を一括で適用する。
  static List<Prompt> apply(
    List<Prompt> prompts, {
    String query = '',
    Set<String> tags = const <String>{},
    SortMode sortMode = SortMode.recent,
  }) {
    return sort(filter(prompts, query: query, tags: tags), sortMode);
  }

  /// インクリメンタルサーチ用の絞り込み。
  ///
  /// - 検索語は空白区切りの AND 条件（「要約 英語」で両方含むものだけ）
  /// - 大文字小文字を区別しない
  /// - タイトル / 本文 / タグを横断して探す
  /// - タグフィルターは選択タグを「すべて含む」AND 条件
  static List<Prompt> filter(
    List<Prompt> prompts, {
    String query = '',
    Set<String> tags = const <String>{},
  }) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((String t) => t.isNotEmpty)
        .toList(growable: false);

    return prompts.where((Prompt p) {
      if (tags.isNotEmpty && !tags.every(p.tags.contains)) return false;
      if (terms.isEmpty) return true;

      final haystack =
          <String>[p.title, p.body, ...p.tags].join('\n').toLowerCase();
      return terms.every(haystack.contains);
    }).toList(growable: false);
  }

  /// 並び替え。ピン留めは常に最優先で先頭に集める。
  static List<Prompt> sort(List<Prompt> prompts, SortMode mode) {
    final sorted = List<Prompt>.of(prompts);
    sorted.sort((Prompt a, Prompt b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return switch (mode) {
        SortMode.recent => b.updatedAt.compareTo(a.updatedAt),
        SortMode.usage => _compareUsage(a, b),
      };
    });
    return List<Prompt>.unmodifiable(sorted);
  }

  static int _compareUsage(Prompt a, Prompt b) {
    final result = b.usageCount.compareTo(a.usageCount);
    // 使用回数が同じなら「最近さわったもの」を上に。
    return result != 0 ? result : b.updatedAt.compareTo(a.updatedAt);
  }

  /// タグ入力欄の文字列（カンマ / 全角カンマ / 空白区切り）を正規化する。
  static List<String> parseTags(String raw) {
    final parts = raw.split(RegExp(r'[,、\s]+'));
    final seen = <String>{};
    final result = <String>[];
    for (final String part in parts) {
      final tag = part.trim().replaceFirst(RegExp(r'^#'), '');
      if (tag.isEmpty) continue;
      if (seen.add(tag)) result.add(tag);
    }
    return List<String>.unmodifiable(result);
  }
}
