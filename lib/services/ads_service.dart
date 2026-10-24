import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// AdMob の広告ユニットID。
///
/// リリースビルドで `--dart-define=ADMOB_BANNER_ANDROID=...` などを渡すと
/// 本番IDに差し替わる。未指定の場合は Google 公式のテストIDを使う。
/// 「実機デバッグ中に本番広告を叩いてポリシー違反になる」事故を防ぐための既定値。
class AdUnits {
  const AdUnits._();

  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  static const String _bannerAndroid =
      String.fromEnvironment('ADMOB_BANNER_ANDROID');
  static const String _bannerIos = String.fromEnvironment('ADMOB_BANNER_IOS');
  static const String _interstitialAndroid =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID');
  static const String _interstitialIos =
      String.fromEnvironment('ADMOB_INTERSTITIAL_IOS');

  /// dart-define で本番IDが渡され、かつリリースビルドのときだけ本番IDを使う。
  static bool get _useProduction => kReleaseMode;

  static String get banner {
    if (Platform.isAndroid) {
      return _useProduction && _bannerAndroid.isNotEmpty
          ? _bannerAndroid
          : _testBannerAndroid;
    }
    return _useProduction && _bannerIos.isNotEmpty ? _bannerIos : _testBannerIos;
  }

  static String get interstitial {
    if (Platform.isAndroid) {
      return _useProduction && _interstitialAndroid.isNotEmpty
          ? _interstitialAndroid
          : _testInterstitialAndroid;
    }
    return _useProduction && _interstitialIos.isNotEmpty
        ? _interstitialIos
        : _testInterstitialIos;
  }
}

/// インタースティシャルを出すかどうかを決める純粋ロジック。
///
/// 「コピーのたびに全画面広告が出る」のはアプリの価値そのもの（=高速コピペ）を
/// 壊すため、回数と時間の2重のガードをかけている。
@immutable
class InterstitialCadence {
  const InterstitialCadence({
    this.everyNActions = AppConstants.interstitialEveryNActions,
    this.cooldown = AppConstants.interstitialCooldown,
  });

  /// 何回に1回表示するか。
  final int everyNActions;

  /// 直前の表示からの最低間隔。
  final Duration cooldown;

  /// [actionCount] は「今回のアクションを含めた累計回数」。
  bool shouldShow({
    required int actionCount,
    required DateTime? lastShownAt,
    required DateTime now,
  }) {
    if (everyNActions <= 0) return false;
    if (actionCount <= 0 || actionCount % everyNActions != 0) return false;
    if (lastShownAt != null && now.difference(lastShownAt) < cooldown) {
      return false;
    }
    return true;
  }
}

/// 広告の表示を担当するインターフェース。
///
/// 実装を差し替えられるようにしておくことで、
/// Pro ユーザー / テスト / 非対応プラットフォームでは何もしない実装を注入できる。
abstract class AdsService {
  /// SDK の初期化。呼ばれる前に広告を要求しても表示されない。
  Future<void> initialize();

  /// このプラットフォームで広告を出せるか。
  bool get isSupported;

  /// バナー広告ユニットID。
  String get bannerAdUnitId;

  /// 次のインタースティシャルを先読みしておく。
  void preloadInterstitial();

  /// コピー / 保存などのアクション後に呼ぶ。
  /// 条件を満たしたときだけ全画面広告を表示する。
  Future<void> onRewardableAction();

  void dispose();
}

/// 何もしない実装。Pro ユーザー・テスト・デスクトップ等で使う。
class NoopAdsService implements AdsService {
  const NoopAdsService();

  @override
  Future<void> initialize() async {}

  @override
  bool get isSupported => false;

  @override
  String get bannerAdUnitId => '';

  @override
  void preloadInterstitial() {}

  @override
  Future<void> onRewardableAction() async {}

  @override
  void dispose() {}
}

/// Google AdMob を使う本実装。
class AdMobAdsService implements AdsService {
  AdMobAdsService(this._prefs, {InterstitialCadence? cadence})
      : _cadence = cadence ?? const InterstitialCadence();

  final SharedPreferences _prefs;
  final InterstitialCadence _cadence;

  bool _initialized = false;
  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;

  @override
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  String get bannerAdUnitId => isSupported ? AdUnits.banner : '';

  @override
  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    _initialized = true;
    await MobileAds.instance.initialize();
    preloadInterstitial();
  }

  @override
  void preloadInterstitial() {
    if (!isSupported || _interstitial != null || _loadingInterstitial) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: AdUnits.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (LoadAdError error) {
          // 読み込み失敗はユーザーに見せない。次のアクションで再試行する。
          _loadingInterstitial = false;
          _interstitial = null;
          debugPrint('Interstitial load failed: $error');
        },
      ),
    );
  }

  @override
  Future<void> onRewardableAction() async {
    if (!isSupported) return;

    final count = (_prefs.getInt(AppConstants.prefsActionCounter) ?? 0) + 1;
    await _prefs.setInt(AppConstants.prefsActionCounter, count);

    final lastMs = _prefs.getInt(AppConstants.prefsLastInterstitialAt);
    final lastShownAt =
        lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs);

    final shouldShow = _cadence.shouldShow(
      actionCount: count,
      lastShownAt: lastShownAt,
      now: DateTime.now(),
    );
    if (!shouldShow) {
      // 次回に備えて先読みだけ済ませておく。
      preloadInterstitial();
      return;
    }

    final ad = _interstitial;
    if (ad == null) {
      // まだ読めていないなら今回は見送る。コピー体験を止めないことを優先。
      preloadInterstitial();
      return;
    }

    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        ad.dispose();
        preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        ad.dispose();
        preloadInterstitial();
      },
    );
    await _prefs.setInt(
      AppConstants.prefsLastInterstitialAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    await ad.show();
  }

  @override
  void dispose() {
    _interstitial?.dispose();
    _interstitial = null;
  }
}
