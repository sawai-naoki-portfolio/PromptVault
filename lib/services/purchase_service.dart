import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/constants.dart';

/// 課金フローの結果種別。
enum PurchaseOutcome {
  /// ストアと通信中 / 購入処理中。
  pending,

  /// 新規購入が成立した。
  purchased,

  /// 復元（リストア）で購入済みが確認できた。
  restored,

  /// ユーザーがキャンセルした。
  canceled,

  /// 復元したが購入履歴が見つからなかった。
  nothingToRestore,

  /// エラー。
  error,
}

/// 課金フローからUIへ渡すイベント。
@immutable
class PurchaseEvent {
  const PurchaseEvent(this.outcome, {this.message});

  final PurchaseOutcome outcome;
  final String? message;
}

/// ストア上の商品情報（プラグインの型をUIに漏らさないためのDTO）。
@immutable
class ProProductInfo {
  const ProProductInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  final String id;
  final String title;
  final String description;

  /// ストアがローカライズ済みの価格文字列（例: "¥400"）。
  final String price;
}

/// アプリ内課金のインターフェース。
abstract class PurchaseService {
  Future<void> initialize();

  /// ストアが利用可能か（端末設定・地域・シミュレータ等で false になりうる）。
  bool get isStoreAvailable;

  /// 取得済みの Pro 商品情報。未取得なら null。
  ProProductInfo? get proProduct;

  /// 購入・復元の結果イベント。
  Stream<PurchaseEvent> get events;

  Future<void> buyPro();

  Future<void> restorePurchases();

  void dispose();
}

/// ストアに繋がらない環境（テスト・デスクトップ）向けのスタブ。
class StubPurchaseService implements PurchaseService {
  final StreamController<PurchaseEvent> _controller =
      StreamController<PurchaseEvent>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  bool get isStoreAvailable => false;

  @override
  ProProductInfo? get proProduct => null;

  @override
  Stream<PurchaseEvent> get events => _controller.stream;

  @override
  Future<void> buyPro() async {
    _controller.add(
      const PurchaseEvent(
        PurchaseOutcome.error,
        message: 'この環境ではストアを利用できません。',
      ),
    );
  }

  @override
  Future<void> restorePurchases() async {
    _controller.add(
      const PurchaseEvent(
        PurchaseOutcome.error,
        message: 'この環境ではストアを利用できません。',
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
  }
}

/// in_app_purchase を使う本実装。
///
/// サーバーを持たない構成のため、レシートのサーバー検証は行わず
/// ストアSDKが返す購入状態をそのまま信頼する（0円運用の前提）。
/// 買い切り（非消費型）なので、購入後は `completePurchase` のみ行い
/// consume はしない。
class IapPurchaseService implements PurchaseService {
  IapPurchaseService({InAppPurchase? iap})
      : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  final StreamController<PurchaseEvent> _events =
      StreamController<PurchaseEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _storeAvailable = false;
  ProProductInfo? _proProduct;

  /// restorePurchases 実行中フラグ。
  /// 「復元したが何も無かった」を検出するために使う。
  bool _restoring = false;
  bool _restoredSomething = false;

  @override
  bool get isStoreAvailable => _storeAvailable;

  @override
  ProProductInfo? get proProduct => _proProduct;

  @override
  Stream<PurchaseEvent> get events => _events.stream;

  bool get _platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<void> initialize() async {
    if (!_platformSupported) return;

    _storeAvailable = await _iap.isAvailable();
    if (!_storeAvailable) return;

    // purchaseStream はアプリ起動中ずっと購読し続ける。
    // 中断した決済がアプリ再起動後に流れてくるケースを取りこぼさないため。
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (Object error) {
        _events.add(
          PurchaseEvent(PurchaseOutcome.error, message: error.toString()),
        );
      },
    );

    await _loadProduct();
  }

  Future<void> _loadProduct() async {
    final response =
        await _iap.queryProductDetails(<String>{AppConstants.proProductId});
    if (response.productDetails.isEmpty) return;

    final details = response.productDetails.first;
    _proProduct = ProProductInfo(
      id: details.id,
      title: details.title,
      description: details.description,
      price: details.price,
    );
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      if (purchase.productID != AppConstants.proProductId) {
        // 未知の商品でも完了処理だけはしておく。放置するとストアが再送し続ける。
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          _events.add(const PurchaseEvent(PurchaseOutcome.pending));

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _restoredSomething = true;
          _events.add(
            PurchaseEvent(
              purchase.status == PurchaseStatus.restored
                  ? PurchaseOutcome.restored
                  : PurchaseOutcome.purchased,
            ),
          );

        case PurchaseStatus.canceled:
          _events.add(const PurchaseEvent(PurchaseOutcome.canceled));

        case PurchaseStatus.error:
          _events.add(
            PurchaseEvent(
              PurchaseOutcome.error,
              message: purchase.error?.message ?? '購入処理でエラーが発生しました。',
            ),
          );
      }

      // 完了通知を返さないとストアが購入を保留のまま扱い続けるため必ず呼ぶ。
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  @override
  Future<void> buyPro() async {
    if (!_storeAvailable) {
      _events.add(
        const PurchaseEvent(
          PurchaseOutcome.error,
          message: 'ストアに接続できませんでした。通信環境をご確認ください。',
        ),
      );
      return;
    }

    final response =
        await _iap.queryProductDetails(<String>{AppConstants.proProductId});
    if (response.productDetails.isEmpty) {
      _events.add(
        const PurchaseEvent(
          PurchaseOutcome.error,
          message: '商品情報を取得できませんでした。時間をおいて再度お試しください。',
        ),
      );
      return;
    }

    // 買い切り（非消費型）なので buyNonConsumable を使う。
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: response.productDetails.first,
      ),
    );
  }

  @override
  Future<void> restorePurchases() async {
    if (!_storeAvailable) {
      _events.add(
        const PurchaseEvent(
          PurchaseOutcome.error,
          message: 'ストアに接続できませんでした。通信環境をご確認ください。',
        ),
      );
      return;
    }

    _restoring = true;
    _restoredSomething = false;
    await _iap.restorePurchases();

    // restorePurchases は結果を purchaseStream 経由で返すため、
    // 「何も復元されなかった」場合は無音になる。少し待って判定する。
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_restoring && !_restoredSomething) {
      _events.add(const PurchaseEvent(PurchaseOutcome.nothingToRestore));
    }
    _restoring = false;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _events.close();
  }
}
