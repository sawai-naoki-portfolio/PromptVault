import 'package:hive/hive.dart';

/// 1件のプロンプトを表すドメインモデル。
///
/// Hive の TypeAdapter は build_runner を使わず手書きしている（[PromptAdapter]）。
/// 生成コードを持たないぶんフィールド追加時は
/// [PromptAdapter.read] / [PromptAdapter.write] の更新が必須になる点に注意。
class Prompt {
  const Prompt({
    required this.id,
    required this.title,
    required this.body,
    this.tags = const <String>[],
    this.isPinned = false,
    this.usageCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;

  /// 分類はタグ1本に統一している。
  /// 以前はカテゴリと併存していたが、入力欄が2つあると保存が億劫になり
  /// 「素早く貯める」という目的と噛み合わなかった。
  final List<String> tags;

  final bool isPinned;

  /// コピーされた回数。「よく使う順」の並び替えに利用する。
  final int usageCount;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 一覧カードに出す本文プレビュー（改行を潰して1行にする）。
  String get preview {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 120 ? flat : '${flat.substring(0, 120)}…';
  }

  /// タイトルが空のときに一覧で表示する見出し。
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body.trim().split('\n').first.trim();
    if (firstLine.isEmpty) return '(無題)';
    return firstLine.length <= 40 ? firstLine : '${firstLine.substring(0, 40)}…';
  }

  Prompt copyWith({
    String? id,
    String? title,
    String? body,
    List<String>? tags,
    bool? isPinned,
    int? usageCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Prompt(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      tags: tags ?? this.tags,
      isPinned: isPinned ?? this.isPinned,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// バックアップ用のJSON表現。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'tags': tags,
        'isPinned': isPinned,
        'usageCount': usageCount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// バックアップJSONからの復元。
  ///
  /// 手で編集されたファイルを読み込む可能性があるため、
  /// 欠損フィールドは既定値で埋めて例外にしない。
  /// 旧形式の `category` はタグとして取り込む。
  factory Prompt.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Prompt(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : newId(),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      tags: mergeLegacyCategory(
        (json['tags'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => e.toString()),
        json['category'] as String?,
      ),
      isPinned: json['isPinned'] as bool? ?? false,
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  /// 旧「カテゴリ」をタグ列に畳み込む。
  ///
  /// カテゴリ廃止前に保存されたデータでも分類情報を失わないようにするため、
  /// 読み込み経路（Hive アダプタ / バックアップJSON）の両方から通す。
  static List<String> mergeLegacyCategory(
    Iterable<String> tags,
    String? category,
  ) {
    final seen = <String>{};
    final result = <String>[];
    for (final String tag in tags) {
      final t = tag.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) result.add(t);
    }
    final c = category?.trim() ?? '';
    if (c.isNotEmpty && seen.add(c)) result.add(c);
    return List<String>.unmodifiable(result);
  }

  /// 端末内で一意なIDを作る。
  ///
  /// 完全ローカル運用なので衝突耐性はマイクロ秒 + カウンタで十分。
  static int _seq = 0;
  static String newId() {
    _seq = (_seq + 1) & 0xffff;
    final ms = DateTime.now().microsecondsSinceEpoch;
    return '$ms-${_seq.toRadixString(16).padLeft(4, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Prompt && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// [Prompt] の手書き Hive アダプタ。
///
/// フィールド番号は互換のため据え置き。
/// 3 = 旧 category、6 = 旧 sortOrder は書き出さないが、
/// 既存データを読むときだけ面倒を見る。
class PromptAdapter extends TypeAdapter<Prompt> {
  @override
  final int typeId = 1;

  static const int _fieldLegacyCategory = 3;

  @override
  Prompt read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };
    return Prompt(
      id: fields[0] as String? ?? Prompt.newId(),
      title: fields[1] as String? ?? '',
      body: fields[2] as String? ?? '',
      tags: Prompt.mergeLegacyCategory(
        (fields[4] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => e.toString()),
        fields[_fieldLegacyCategory] as String?,
      ),
      isPinned: fields[5] as bool? ?? false,
      usageCount: fields[7] as int? ?? 0,
      createdAt: fields[8] as DateTime? ?? DateTime.now(),
      updatedAt: fields[9] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, Prompt obj) {
    writer
      // フィールド数。下で書く writeByte/write の組の数と必ず一致させること。
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.body)
      ..writeByte(4)
      ..write(obj.tags)
      ..writeByte(5)
      ..write(obj.isPinned)
      ..writeByte(7)
      ..write(obj.usageCount)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.updatedAt);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PromptAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId);

  @override
  int get hashCode => typeId.hashCode;
}
