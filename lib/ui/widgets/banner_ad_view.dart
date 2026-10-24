import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../providers/app_providers.dart';

/// Free ユーザー向けのバナー広告枠。
///
/// Pro ユーザー・非対応プラットフォーム・読み込み失敗時は
/// 高さ0の [SizedBox] を返すため、レイアウトに一切影響しない。
class BannerAdView extends ConsumerStatefulWidget {
  const BannerAdView({super.key});

  @override
  ConsumerState<BannerAdView> createState() => _BannerAdViewState();
}

class _BannerAdViewState extends ConsumerState<BannerAdView> {
  BannerAd? _ad;
  bool _loaded = false;

  /// 画面幅に依存する広告サイズを決めるため、load は didChangeDependencies で行う。
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;

    final showAds = ref.read(entitlementsProvider).showAds;
    final ads = ref.read(adsServiceProvider);
    if (!showAds || !ads.isSupported) return;

    _requested = true;
    _load(ads.bannerAdUnitId);
  }

  Future<void> _load(String adUnitId) async {
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;

    final ad = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          // 広告が出ないこと自体はユーザーに伝える必要がないので黙って畳む。
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _ad = null;
            _loaded = false;
          });
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pro を購入した瞬間にバナーを消すため、ここでも entitlements を監視する。
    final showAds = ref.watch(entitlementsProvider).showAds;
    final ad = _ad;
    if (!showAds || !_loaded || ad == null) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
