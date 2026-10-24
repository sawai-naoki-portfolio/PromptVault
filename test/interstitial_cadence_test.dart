import 'package:flutter_test/flutter_test.dart';
import 'package:promptvault/services/ads_service.dart';

void main() {
  final now = DateTime(2026, 7, 27, 12, 0);

  group('InterstitialCadence', () {
    const cadence = InterstitialCadence(
      everyNActions: 4,
      cooldown: Duration(minutes: 2),
    );

    test('4回に1回だけ表示する', () {
      final shown = <int>[
        for (int i = 1; i <= 12; i++)
          if (cadence.shouldShow(
            actionCount: i,
            lastShownAt: null,
            now: now,
          ))
            i,
      ];
      expect(shown, <int>[4, 8, 12]);
    });

    test('クールダウン中は回数条件を満たしても表示しない', () {
      expect(
        cadence.shouldShow(
          actionCount: 4,
          lastShownAt: now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        isFalse,
      );
    });

    test('クールダウンを過ぎていれば表示する', () {
      expect(
        cadence.shouldShow(
          actionCount: 4,
          lastShownAt: now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        isTrue,
      );
    });

    test('カウントが0以下なら表示しない', () {
      expect(
        cadence.shouldShow(actionCount: 0, lastShownAt: null, now: now),
        isFalse,
      );
    });

    test('everyNActions が0以下なら常に表示しない（広告オフ相当）', () {
      const off = InterstitialCadence(everyNActions: 0);
      expect(
        off.shouldShow(actionCount: 100, lastShownAt: null, now: now),
        isFalse,
      );
    });
  });

  test('NoopAdsService は常に非対応として振る舞う', () async {
    const service = NoopAdsService();
    expect(service.isSupported, isFalse);
    expect(service.bannerAdUnitId, isEmpty);
    // 例外を投げずに黙って何もしないことを確認する。
    await service.initialize();
    await service.onRewardableAction();
    service.preloadInterstitial();
    service.dispose();
  });
}
