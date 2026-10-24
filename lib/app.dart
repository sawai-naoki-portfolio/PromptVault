import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'providers/app_providers.dart';
import 'providers/prompt_providers.dart';
import 'services/purchase_service.dart';
import 'ui/app_messenger.dart';
import 'ui/home/prompt_list_screen.dart';

class PromptVaultApp extends StatelessWidget {
  const PromptVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AppBootstrap(child: PromptListScreen()),
    );
  }
}

/// 起動時に一度だけ必要な副作用をまとめる層。
///
/// 以前は下部タブの外枠（一覧 / 発見 / 設定）がこの役割を兼ねていたが、
/// 「発見」タブを畳んで設定を通常の画面遷移に変えたため、
/// タブ自体をやめて一覧を直接ホームにしている。
/// 縦の表示領域がタブバー1本ぶん広くなる。
class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  StreamSubscription<PurchaseEvent>? _purchaseSubscription;

  @override
  void initState() {
    super.initState();
    // ストア接続と広告SDKの初期化は起動をブロックしないよう非同期で走らせる。
    // 失敗しても各サービス側が「利用不可」として扱うため、アプリは通常どおり動く。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final purchase = ref.read(purchaseServiceProvider);
      _purchaseSubscription = purchase.events.listen(_showPurchaseFeedback);
      unawaited(purchase.initialize());
      ref.read(adsServiceProvider).preloadInterstitial();

      // 初回起動なら空の一覧ではなくサンプル入りで始める。
      unawaited(ref.read(promptsProvider.notifier).seedIfFirstLaunch());
    });
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  /// 購入・復元の結果をアプリ全体で1箇所にまとめて通知する。
  ///
  /// Pro フラグ自体の更新は [isProProvider] が同じイベントを購読して行うので、
  /// ここは表示だけに徹する。
  void _showPurchaseFeedback(PurchaseEvent event) {
    final String message = switch (event.outcome) {
      PurchaseOutcome.pending => '購入処理中です…',
      PurchaseOutcome.purchased => 'Proプランを購入しました。ありがとうございます！',
      PurchaseOutcome.restored => '購入情報を復元しました。Proプランが有効です。',
      PurchaseOutcome.canceled => '購入をキャンセルしました',
      PurchaseOutcome.nothingToRestore => '復元できる購入履歴が見つかりませんでした',
      PurchaseOutcome.error => event.message ?? '購入処理でエラーが発生しました',
    };
    showAppSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
