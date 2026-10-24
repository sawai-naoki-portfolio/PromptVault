import 'package:hive/hive.dart';

import '../core/constants.dart';
import '../models/prompt.dart';

/// プロンプトの永続化の抽象。
///
/// 保存先は端末内のみ。外部にデータを送る経路をこの層に作らないことで
/// 「完全ローカル管理」という仕様を1箇所で保証する。
///
/// 実装が差し替えられるようにしてあるのは、ウィジェットテストのため。
/// `testWidgets` の本体は擬似非同期ゾーンで動くので、実ファイルI/Oの Future が
/// 完了せずデッドロックする。テストではインメモリ実装を注入する。
abstract class PromptStore {
  // ---- 実装ごとに用意する最小限の操作 ------------------------------------

  /// 変更通知ストリーム。Riverpod 側で購読して一覧を再構築する。
  Stream<void> watch();

  List<Prompt> getAll();

  Prompt? getById(String id);

  /// 新規作成・更新の共通経路。[Prompt.updatedAt] は呼び出し側で設定済みとする。
  Future<void> put(Prompt prompt);

  Future<void> putAll(Iterable<Prompt> prompts);

  Future<void> delete(String id);

  Future<void> clear();

  // ---- 上の操作から導ける共通ロジック ------------------------------------

  int get count => getAll().length;

  int get pinnedCount => getAll().where((Prompt p) => p.isPinned).length;

  /// 端末内に存在する全タグ（重複なし・辞書順）。
  List<String> allTags() {
    final tags = <String>{};
    for (final Prompt p in getAll()) {
      tags.addAll(p.tags);
    }
    final sorted = tags.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  /// バックアップ復元。[merge] が false なら既存データを置き換える。
  ///
  /// merge 時に同一IDが衝突した場合は updatedAt が新しい方を残す。
  /// 「別端末で編集したものを取り込む」ケースで古いデータに巻き戻らないようにする。
  ///
  /// 戻り値は実際に書き込んだ件数。
  Future<int> restore(List<Prompt> incoming, {required bool merge}) async {
    if (!merge) {
      await clear();
      await putAll(incoming);
      return incoming.length;
    }

    final toWrite = <Prompt>[];
    for (final Prompt p in incoming) {
      final existing = getById(p.id);
      if (existing == null || p.updatedAt.isAfter(existing.updatedAt)) {
        toWrite.add(p);
      }
    }
    await putAll(toWrite);
    return toWrite.length;
  }
}

/// Hive を使う本番実装。
class PromptRepository extends PromptStore {
  PromptRepository(this._box);

  final Box<Prompt> _box;

  @override
  Stream<void> watch() => _box.watch().map((_) {});

  @override
  List<Prompt> getAll() => _box.values.toList(growable: false);

  @override
  int get count => _box.length;

  @override
  Prompt? getById(String id) => _box.get(id);

  @override
  Future<void> put(Prompt prompt) => _box.put(prompt.id, prompt);

  @override
  Future<void> putAll(Iterable<Prompt> prompts) {
    return _box.putAll(<String, Prompt>{
      for (final Prompt p in prompts) p.id: p,
    });
  }

  @override
  Future<void> delete(String id) => _box.delete(id);

  @override
  Future<void> clear() => _box.clear();

  /// Hive box を開く。アプリ起動時に1度だけ呼ぶ。
  static Future<Box<Prompt>> openBox() {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(PromptAdapter());
    }
    return Hive.openBox<Prompt>(AppConstants.promptBoxName);
  }
}
