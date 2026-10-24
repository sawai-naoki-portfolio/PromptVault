import 'package:flutter/material.dart';

/// アプリ全体で共有する [ScaffoldMessenger]。
///
/// 「画面を閉じた直後に通知を出したい」ケース（編集を保存して一覧に戻る、
/// 課金の結果が非同期で届く、など）では、通知元の Scaffold がもう無い。
/// そのため MaterialApp に1つだけぶら下げた messenger を経由させる。
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 直前の通知を畳んでから新しい通知を出す。
void showAppSnackBar(SnackBar snackBar) {
  appMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(snackBar);
}
