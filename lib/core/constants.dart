/// アプリ全体で共有する定数。
class AppConstants {
  const AppConstants._();

  static const String appName = 'PromptVault';

  // ---- 広告 --------------------------------------------------------------
  /// コピー / 保存が何回発生するごとにインタースティシャルを出すか。
  /// 連打によるユーザー体験の悪化を避けるため、毎回は表示しない。
  static const int interstitialEveryNActions = 4;

  /// 前回のインタースティシャルからこの時間が経過するまでは再表示しない。
  static const Duration interstitialCooldown = Duration(minutes: 2);

  // ---- 課金 --------------------------------------------------------------
  /// 買い切り（非消費型）Pro プランのプロダクトID。
  /// App Store Connect / Google Play Console 側と一致させること。
  static const String proProductId = 'promptvault_pro';

  // ---- コピー履歴（Pro） --------------------------------------------------
  /// 保持する履歴の最大件数。増やしすぎても遡らないので浅く持つ。
  static const int copyHistoryLimit = 20;

  // ---- 永続化キー --------------------------------------------------------
  static const String prefsIsProUser = 'isProUser';
  static const String prefsActionCounter = 'adActionCounter';
  static const String prefsLastInterstitialAt = 'lastInterstitialAtMs';
  static const String prefsSortMode = 'sortMode';
  static const String prefsCopyHistory = 'copyHistory';

  /// 初回起動時のサンプル投入を済ませたか。
  /// 「サンプルを消したのに再起動で復活する」のを防ぐために立てる。
  static const String prefsSeeded = 'seededStarters';

  // ---- ストレージ --------------------------------------------------------
  static const String promptBoxName = 'prompts';

  /// バックアップJSONのスキーマバージョン。
  static const int backupSchemaVersion = 1;
}

/// 一覧の並び替えモード。
///
/// 以前は5種類あったが、実際に使い分けられるのは
/// 「最近さわった順」と「よく使う順」の2つだけだったため絞った。
/// ピン留めはどちらのモードでも常に最優先で先頭に集まる。
enum SortMode {
  recent('最近使った順'),
  usage('よく使う順');

  const SortMode(this.label);

  final String label;

  static SortMode fromName(String? name) {
    return SortMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => SortMode.recent,
    );
  }
}
