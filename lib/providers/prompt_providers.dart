import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/entitlements.dart';
import '../core/prompt_query.dart';
import '../data/copy_history_store.dart';
import '../data/starter_prompts.dart';
import '../models/prompt.dart';
import 'app_providers.dart';

/// 端末に保存されている全プロンプト（並び替え・絞り込み前）。
final promptsProvider =
    NotifierProvider<PromptsNotifier, List<Prompt>>(PromptsNotifier.new);

class PromptsNotifier extends Notifier<List<Prompt>> {
  @override
  List<Prompt> build() {
    final repo = ref.watch(promptRepositoryProvider);

    // Hive の変更通知を購読し、どこから書き換えても一覧が追従するようにする。
    final subscription = repo.watch().listen((_) => state = repo.getAll());
    ref.onDispose(subscription.cancel);

    return repo.getAll();
  }

  /// 自分で書き込んだ直後に state を最新化する。
  ///
  /// Hive の変更通知は非同期に届くため（特に `clear()` は1マイクロタスク遅れる）、
  /// これが無いと「await したのに state が古い」状態が生まれる。
  /// 通知が後から届いても同じ内容を代入するだけなので二重更新にはならない。
  void _refresh() => state = ref.read(promptRepositoryProvider).getAll();

  /// 新規作成。
  ///
  /// 保存件数の上限は設けていない。ユーザー自身のデータを人質に取らない方針。
  Future<MutationOutcome> create({
    required String title,
    required String body,
    List<String> tags = const <String>[],
  }) async {
    if (title.trim().isEmpty && body.trim().isEmpty) {
      return MutationOutcome.blockedByEmptyContent;
    }

    final now = DateTime.now();
    await ref.read(promptRepositoryProvider).put(
          Prompt(
            id: Prompt.newId(),
            title: title.trim(),
            body: body,
            tags: tags,
            createdAt: now,
            updatedAt: now,
          ),
        );
    _refresh();
    return MutationOutcome.ok;
  }

  /// 既存プロンプトの更新。
  Future<MutationOutcome> update(
    Prompt original, {
    required String title,
    required String body,
    List<String> tags = const <String>[],
  }) async {
    if (title.trim().isEmpty && body.trim().isEmpty) {
      return MutationOutcome.blockedByEmptyContent;
    }

    await ref.read(promptRepositoryProvider).put(
          original.copyWith(
            title: title.trim(),
            body: body,
            tags: tags,
            updatedAt: DateTime.now(),
          ),
        );
    _refresh();
    return MutationOutcome.ok;
  }

  Future<void> delete(String id) async {
    await ref.read(promptRepositoryProvider).delete(id);
    _refresh();
  }

  /// 取り消し用の書き戻し。
  ///
  /// 削除や編集を「元に戻す」ときに使う。updatedAt を含めてそのまま復元するので、
  /// 一覧の並び順も取り消し前の状態に戻る。
  Future<void> restoreSnapshot(Iterable<Prompt> prompts) async {
    await ref.read(promptRepositoryProvider).putAll(prompts);
    _refresh();
  }

  /// ピン留めの切り替え。件数の上限は設けていない。
  ///
  /// updatedAt は更新しない。ピン留めのつもりで一覧の並びが変わると
  /// ユーザーの記憶している位置が壊れるため。
  Future<void> togglePin(Prompt prompt) async {
    await ref.read(promptRepositoryProvider).put(
          prompt.copyWith(isPinned: !prompt.isPinned),
        );
    _refresh();
  }

  /// コピー時に使用回数を加算する。「よく使う順」の並び替えに使う。
  ///
  /// updatedAt は更新しない（理由は [togglePin] と同じ）。
  Future<void> markUsed(Prompt prompt) async {
    await ref.read(promptRepositoryProvider).put(
          prompt.copyWith(usageCount: prompt.usageCount + 1),
        );
    _refresh();
  }

  /// バックアップからの復元。書き込んだ件数を返す。
  Future<int> restore(List<Prompt> prompts, {required bool merge}) async {
    final written = await ref
        .read(promptRepositoryProvider)
        .restore(prompts, merge: merge);
    _refresh();
    return written;
  }

  Future<void> deleteAll() async {
    await ref.read(promptRepositoryProvider).clear();
    _refresh();
  }

  /// テンプレートを取り込む。追加した件数を返す。
  Future<int> addStarters(Iterable<StarterPrompt> starters) async {
    final now = DateTime.now();
    final prompts = <Prompt>[];
    int offset = 0;
    for (final StarterPrompt s in starters) {
      // 追加順がそのまま一覧の並びになるよう、わずかに時刻をずらす。
      final t = now.subtract(Duration(milliseconds: offset++));
      prompts.add(
        Prompt(
          id: Prompt.newId(),
          title: s.title,
          body: s.body,
          tags: s.tags,
          createdAt: t,
          updatedAt: t,
        ),
      );
    }
    if (prompts.isEmpty) return 0;

    await ref.read(promptRepositoryProvider).putAll(prompts);
    _refresh();
    return prompts.length;
  }

  /// 初回起動時にサンプルを投入する。
  ///
  /// 空リストから始まると、このアプリの価値（変数つきプロンプトの即コピー）が
  /// 何も伝わらないため。一度実行したらフラグを立て、
  /// ユーザーがサンプルを消したのに再起動で復活する、という事態を防ぐ。
  Future<void> seedIfFirstLaunch() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(AppConstants.prefsSeeded) ?? false) return;
    await prefs.setBool(AppConstants.prefsSeeded, true);

    if (ref.read(promptRepositoryProvider).count > 0) return;
    await addStarters(
      StarterPrompts.all.take(StarterPrompts.autoSeedCount),
    );
  }
}

// ---- コピー履歴（Pro） -----------------------------------------------------

final copyHistoryProvider =
    NotifierProvider<CopyHistoryNotifier, List<CopyHistoryEntry>>(
  CopyHistoryNotifier.new,
);

class CopyHistoryNotifier extends Notifier<List<CopyHistoryEntry>> {
  @override
  List<CopyHistoryEntry> build() =>
      ref.watch(copyHistoryStoreProvider).load();

  Future<void> add(CopyHistoryEntry entry) async {
    state = await ref.read(copyHistoryStoreProvider).add(entry);
  }

  Future<void> clear() async {
    await ref.read(copyHistoryStoreProvider).clear();
    state = const <CopyHistoryEntry>[];
  }
}

// ---- 検索・絞り込みの状態 -------------------------------------------------

/// 検索バーの入力（インクリメンタルサーチ）。
final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;

  void clear() => state = '';
}

/// 選択中のタグフィルター（AND 条件）。
final selectedTagsProvider =
    NotifierProvider<SelectedTagsNotifier, Set<String>>(
  SelectedTagsNotifier.new,
);

class SelectedTagsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void toggle(String tag) {
    final next = Set<String>.of(state);
    if (!next.remove(tag)) next.add(tag);
    state = Set<String>.unmodifiable(next);
  }

  void clear() => state = const <String>{};
}

/// 絞り込み・並び替え後の、実際に一覧へ描画するリスト。
final visiblePromptsProvider = Provider<List<Prompt>>((Ref ref) {
  return PromptQuery.apply(
    ref.watch(promptsProvider),
    query: ref.watch(searchQueryProvider),
    tags: ref.watch(selectedTagsProvider),
    sortMode: ref.watch(sortModeProvider),
  );
});

/// タグフィルター用の、端末内に存在する全タグ。
final allTagsProvider = Provider<List<String>>((Ref ref) {
  final tags = <String>{};
  for (final Prompt p in ref.watch(promptsProvider)) {
    tags.addAll(p.tags);
  }
  final sorted = tags.toList()..sort();
  return List<String>.unmodifiable(sorted);
});

/// 保存件数。
final promptCountProvider =
    Provider<int>((Ref ref) => ref.watch(promptsProvider).length);

/// ピン留め件数。
final pinnedCountProvider = Provider<int>(
  (Ref ref) => ref.watch(promptsProvider).where((Prompt p) => p.isPinned).length,
);
