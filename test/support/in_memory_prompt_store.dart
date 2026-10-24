import 'dart:async';

import 'package:promptvault/data/prompt_repository.dart';
import 'package:promptvault/models/prompt.dart';

/// テスト用のインメモリ [PromptStore]。
///
/// `testWidgets` の本体は擬似非同期ゾーンで実行されるため、
/// 実ファイルI/O（Hive）の Future は完了せずデッドロックする。
/// ウィジェットテストではこの実装を注入して、
/// 保存処理をマイクロタスクだけで完結させる。
///
/// Hive 実装そのものの検証は `prompt_store_test.dart` が
/// 実ファイルを使って行っている。
class InMemoryPromptStore extends PromptStore {
  InMemoryPromptStore([Iterable<Prompt> initial = const <Prompt>[]]) {
    for (final Prompt p in initial) {
      _entries[p.id] = p;
    }
  }

  /// 挿入順を保つ。Hive の box.values と同じ順序特性にするため。
  final Map<String, Prompt> _entries = <String, Prompt>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> watch() => _changes.stream;

  @override
  List<Prompt> getAll() => List<Prompt>.unmodifiable(_entries.values);

  @override
  Prompt? getById(String id) => _entries[id];

  @override
  Future<void> put(Prompt prompt) async {
    _entries[prompt.id] = prompt;
    _changes.add(null);
  }

  @override
  Future<void> putAll(Iterable<Prompt> prompts) async {
    for (final Prompt p in prompts) {
      _entries[p.id] = p;
    }
    if (prompts.isNotEmpty) _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    if (_entries.remove(id) != null) _changes.add(null);
  }

  @override
  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries.clear();
    _changes.add(null);
  }

  void dispose() => _changes.close();
}
