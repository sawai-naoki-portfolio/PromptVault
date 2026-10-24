import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../models/prompt.dart';

/// 復元時のバリデーション失敗。
class BackupParseException implements Exception {
  const BackupParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// プロンプトの書き出し / 読み込み。
///
/// 外部サーバーは介さず、端末のファイルとOS標準の共有シート
/// （Googleドライブ・ファイルアプリ等）だけで完結させる。
///
/// 形式は JSON のみ。以前は CSV も出していたが、プロンプト本文には
/// 改行が普通に入るため表計算で開いても1セルに長文が入るだけで、
/// エスケープの実装コストに見合わなかった。
class BackupService {
  const BackupService();

  // ---- 書き出し ---------------------------------------------------------

  /// バックアップJSON文字列を生成する。
  ///
  /// 復元側で世代を判別できるよう [AppConstants.backupSchemaVersion] を含める。
  String buildJson(List<Prompt> prompts) {
    final payload = <String, dynamic>{
      'app': AppConstants.appName,
      'schemaVersion': AppConstants.backupSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'count': prompts.length,
      'prompts': prompts.map((Prompt p) => p.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 一時ディレクトリにファイルを書き出し、OSの共有シートを開く。
  ///
  /// [sharePositionOrigin] は iPad で共有ポップオーバーの表示位置を決めるために
  /// 必要。省略すると iPad で例外になるため、呼び出し側から渡すこと。
  ///
  /// 戻り値は書き出したファイルのパス。
  Future<String> exportAndShare(
    List<Prompt> prompts, {
    Rect? sharePositionOrigin,
  }) async {
    final fileName = buildFileName();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buildJson(prompts), encoding: utf8);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/json')],
        subject: '$fileName（${AppConstants.appName} バックアップ）',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return file.path;
  }

  /// `promptvault-backup-20260727-1830.json` のようなファイル名を組み立てる。
  @visibleForTesting
  static String buildFileName({DateTime? now}) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
    return 'promptvault-backup-$stamp.json';
  }

  // ---- 読み込み ---------------------------------------------------------

  /// バックアップJSONを [Prompt] のリストに変換する。
  ///
  /// 以下の2形式を受け付ける:
  ///  - 本アプリが書き出したラッパー形式 `{"prompts": [...]}`
  ///  - プロンプト配列のみ `[...]`（手書き・他ツールからの移行を想定）
  List<Prompt> parseJson(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const BackupParseException('ファイルが空です。');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (e) {
      throw BackupParseException('JSONとして読み取れませんでした: ${e.message}');
    }

    final List<dynamic> rawList;
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final prompts = decoded['prompts'];
      if (prompts is! List) {
        throw const BackupParseException(
          'バックアップ形式が違います（"prompts" 配列が見つかりません）。',
        );
      }
      rawList = prompts;
    } else {
      throw const BackupParseException('バックアップ形式が違います。');
    }

    final result = <Prompt>[];
    for (final dynamic item in rawList) {
      if (item is! Map) continue;
      final map = item.map<String, dynamic>(
        (Object? k, Object? v) => MapEntry<String, dynamic>(k.toString(), v),
      );
      // タイトルも本文も空の行は復元しても価値がないので捨てる。
      final title = (map['title'] as String? ?? '').trim();
      final body = (map['body'] as String? ?? '').trim();
      if (title.isEmpty && body.isEmpty) continue;
      result.add(Prompt.fromJson(map));
    }

    if (result.isEmpty) {
      throw const BackupParseException('復元できるプロンプトが1件もありませんでした。');
    }
    return result;
  }
}
