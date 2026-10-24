import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/entitlements.dart';
import '../data/copy_history_store.dart';
import '../data/prompt_repository.dart';
import '../services/ads_service.dart';
import '../services/backup_service.dart';
import '../services/purchase_service.dart';

/// このプラットフォームで広告・課金プラグインが動作するか。
bool get isMobilePlatform {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
}

/// 起動時に main() から override する。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (Ref ref) => throw UnimplementedError(
    'sharedPreferencesProvider は main() で override してください',
  ),
);

/// 起動時に main() から override する。
final promptRepositoryProvider = Provider<PromptStore>(
  (Ref ref) => throw UnimplementedError(
    'promptRepositoryProvider は main() で override してください',
  ),
);

final backupServiceProvider = Provider<BackupService>(
  (Ref ref) => const BackupService(),
);

final copyHistoryStoreProvider = Provider<CopyHistoryStore>(
  (Ref ref) => CopyHistoryStore(ref.watch(sharedPreferencesProvider)),
);

/// 課金サービス。非対応プラットフォームではスタブを返す。
final purchaseServiceProvider = Provider<PurchaseService>((Ref ref) {
  final PurchaseService service =
      isMobilePlatform ? IapPurchaseService() : StubPurchaseService();
  ref.onDispose(service.dispose);
  return service;
});

/// 広告サービス。
///
/// Pro ユーザーには [NoopAdsService] を返すため、
/// Pro に切り替わった瞬間にバナーもインタースティシャルも即座に止まる。
final adsServiceProvider = Provider<AdsService>((Ref ref) {
  final isPro = ref.watch(isProProvider);
  if (isPro || !isMobilePlatform) return const NoopAdsService();

  final service = AdMobAdsService(ref.watch(sharedPreferencesProvider));
  unawaited(service.initialize());
  ref.onDispose(service.dispose);
  return service;
});

/// Pro 購入済みフラグ。
///
/// 実体は SharedPreferences の `isProUser`。
/// 購入 / 復元イベントを購読して自動的に true へ更新する。
final isProProvider = NotifierProvider<ProNotifier, bool>(ProNotifier.new);

class ProNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);

    // ストアからの購入・復元通知を常時監視する。
    // 決済完了直後だけでなく、中断した決済が起動時に流れてくる場合も拾える。
    final subscription =
        ref.watch(purchaseServiceProvider).events.listen((PurchaseEvent event) {
      if (event.outcome == PurchaseOutcome.purchased ||
          event.outcome == PurchaseOutcome.restored) {
        unawaited(_persist(true));
      }
    });
    ref.onDispose(subscription.cancel);

    return prefs.getBool(AppConstants.prefsIsProUser) ?? false;
  }

  Future<void> _persist(bool value) async {
    if (state == value) return;
    state = value;
    await ref.read(sharedPreferencesProvider).setBool(
          AppConstants.prefsIsProUser,
          value,
        );
  }

  /// デバッグビルド専用の切り替え。
  /// 決済を通さずに Pro 画面を確認するために使う。
  Future<void> debugSetPro(bool value) async {
    assert(() {
      unawaited(_persist(value));
      return true;
    }());
  }
}

/// Free / Pro の機能差ポリシー。
final entitlementsProvider = Provider<Entitlements>(
  (Ref ref) => Entitlements(isPro: ref.watch(isProProvider)),
);

/// 一覧の並び替えモード（永続化あり）。
final sortModeProvider =
    NotifierProvider<SortModeNotifier, SortMode>(SortModeNotifier.new);

class SortModeNotifier extends Notifier<SortMode> {
  @override
  SortMode build() {
    return SortMode.fromName(
      ref.watch(sharedPreferencesProvider).getString(AppConstants.prefsSortMode),
    );
  }

  Future<void> set(SortMode mode) async {
    state = mode;
    await ref
        .read(sharedPreferencesProvider)
        .setString(AppConstants.prefsSortMode, mode.name);
  }
}
