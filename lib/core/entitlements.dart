import 'package:flutter/foundation.dart';

/// Free / Pro の機能差を1箇所にまとめたポリシー。
///
/// 方針: **ユーザー自身のデータには制限をかけない**。
/// 保存件数・ピン留め・書き出しを人質に取ると、価値を体験する前に離脱するか
/// 「データを失った」という最悪の体験を生む。
/// 課金の理由は「広告が消える」と「入力がさらに速くなる」に置く。
@immutable
class Entitlements {
  const Entitlements({required this.isPro});

  const Entitlements.free() : isPro = false;

  const Entitlements.pro() : isPro = true;

  final bool isPro;

  // ---- 全員が使える（データに関わるもの） --------------------------------

  /// `{{変数}}` の入力フォーム。
  ///
  /// このアプリの核心的な体験なので Free でも開放する。
  /// ここを閉じると Free ユーザーには「ただのメモ帳」にしか見えない。
  bool get variableForm => true;

  /// バックアップの書き出し。データ喪失だけは絶対に起こさせない。
  bool get exportBackup => true;

  // ---- Pro 限定（速さと快適さ） ------------------------------------------

  /// 広告の表示。Pro は完全非表示。
  bool get showAds => !isPro;

  /// 変数の選択肢 `{{トーン:丁寧|カジュアル}}` と既定値 `{{文字数=200}}`。
  ///
  /// Free でも変数入力自体はできるが、こちらは素のテキスト入力になる。
  bool get advancedVariables => isPro;

  /// コピー履歴の閲覧と再コピー。
  bool get copyHistory => isPro;

  /// バックアップからの復元（取り込み）。
  ///
  /// 書き出しは全員に開放しているのでデータは失われない。
  /// 機種変更で「戻したい」と最も強く思う瞬間を課金ポイントにしている。
  bool get importBackup => isPro;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Entitlements && other.isPro == isPro);

  @override
  int get hashCode => isPro.hashCode;
}

/// プロンプト保存の結果。
enum MutationOutcome {
  ok,

  /// タイトルも本文も空。
  blockedByEmptyContent,
}
