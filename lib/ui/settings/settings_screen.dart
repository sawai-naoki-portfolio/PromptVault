import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/prompt.dart';
import '../../providers/app_providers.dart';
import '../../providers/prompt_providers.dart';
import '../../services/backup_service.dart';
import '../widgets/pro_upsell_sheet.dart';

/// 設定・課金画面。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  // ---- バックアップ ------------------------------------------------------

  /// 書き出しは全プランで使える。データを失わせないことを最優先にする。
  Future<void> _export() async {
    final prompts = ref.read(promptsProvider);
    if (prompts.isEmpty) {
      _toast('書き出すプロンプトがありません');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(backupServiceProvider).exportAndShare(
            prompts,
            sharePositionOrigin: _sharePositionOrigin(),
          );
    } on Object catch (e) {
      _toast('書き出しに失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// iPad の共有ポップオーバーの表示位置。
  /// 渡さないと iPad 実機で例外になるため、画面全体の矩形を基準にする。
  Rect? _sharePositionOrigin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _import() async {
    if (!ref.read(entitlementsProvider).importBackup) {
      await showProUpsellSheet(context, reason: UpsellReason.importBackup);
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final String source;
    try {
      // withData が効かない環境（大きいファイル等）ではパス経由で読む。
      if (file.bytes != null) {
        source = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null) {
        source = await File(file.path!).readAsString();
      } else {
        _toast('ファイルを読み込めませんでした');
        return;
      }
    } on Object catch (e) {
      _toast('ファイルを読み込めませんでした: $e');
      return;
    }

    final List<Prompt> prompts;
    try {
      prompts = ref.read(backupServiceProvider).parseJson(source);
    } on BackupParseException catch (e) {
      _toast(e.message);
      return;
    }

    if (!mounted) return;
    final mode = await _askRestoreMode(prompts.length);
    if (mode == null) return;

    setState(() => _busy = true);
    final written = await ref.read(promptsProvider.notifier).restore(
          prompts,
          merge: mode == _RestoreMode.merge,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    _toast('$written件を復元しました');
  }

  Future<_RestoreMode?> _askRestoreMode(int count) {
    return showDialog<_RestoreMode>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('復元方法を選択'),
        content: Text(
          'ファイルから$count件のプロンプトを読み込みました。\n'
          '既存データをどう扱いますか？',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_RestoreMode.replace),
            child: const Text('置き換え'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_RestoreMode.merge),
            style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
            child: const Text('追加（推奨）'),
          ),
        ],
      ),
    );
  }

  /// 全件削除。取り消せるようにしておく。
  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('すべて削除しますか？'),
        content: const Text('端末内のプロンプトをすべて削除します。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              minimumSize: const Size(88, 40),
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // 消す前に控えておき、取り消しで丸ごと書き戻せるようにする。
    final notifier = ref.read(promptsProvider.notifier);
    final snapshot = ref.read(promptsProvider);
    await notifier.deleteAll();
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${snapshot.length}件を削除しました'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () => notifier.restoreSnapshot(snapshot),
          ),
        ),
      );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPro = ref.watch(isProProvider);
    final entitlements = ref.watch(entitlementsProvider);
    final count = ref.watch(promptCountProvider);
    final purchase = ref.watch(purchaseServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _PlanCard(isPro: isPro, count: count),
          const SizedBox(height: 20),

          if (!isPro) ...<Widget>[
            const _SectionTitle('Proプラン（買い切り）'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const ProBenefitList(),
                    const SizedBox(height: 4),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(purchaseServiceProvider).buyPro(),
                      icon: const Icon(Icons.workspace_premium),
                      label: Text(
                        purchase.proProduct?.price == null
                            ? 'Proプランを購入'
                            : 'Proプランを購入（${purchase.proProduct!.price}）',
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(purchaseServiceProvider).restorePurchases(),
                      child: const Text('購入情報を復元（機種変更した方はこちら）'),
                    ),
                    Text(
                      '月額課金ではありません。1回のお支払いでずっとお使いいただけます。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ] else ...<Widget>[
            const _SectionTitle('購入'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('購入情報を復元'),
                subtitle: const Text('機種変更・再インストール後に実行してください'),
                onTap: () =>
                    ref.read(purchaseServiceProvider).restorePurchases(),
              ),
            ),
            const SizedBox(height: 20),
          ],

          const _SectionTitle('データ'),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('JSONで書き出し'),
                  subtitle: const Text('端末やGoogleドライブへ保存できます'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _export,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('JSONから復元'),
                  subtitle: const Text('書き出したバックアップを読み込みます'),
                  trailing: entitlements.importBackup
                      ? const Icon(Icons.chevron_right)
                      : const _ProBadge(),
                  onTap: _busy ? null : _import,
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      Icon(Icons.delete_forever, color: theme.colorScheme.error),
                  title: Text(
                    'すべてのプロンプトを削除',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: Text('現在 $count 件'),
                  onTap: _busy ? null : _deleteAll,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const _SectionTitle('プライバシー'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.lock_outline,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'プロンプトは端末内のみに保存され、外部サーバーへ送信されることはありません。'
                      '業務で使う機密情報を含むプロンプトも安心して保存できます。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          const _SectionTitle('アプリについて'),
          Card(
            child: Column(
              children: <Widget>[
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('バージョン'),
                  trailing: Text('1.0.0'),
                ),
                if (kDebugMode) ...<Widget>[
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.bug_report_outlined),
                    title: const Text('[デバッグ] Proとして扱う'),
                    subtitle: const Text('デバッグビルドでのみ表示されます'),
                    value: isPro,
                    onChanged: (bool v) =>
                        ref.read(isProProvider.notifier).debugSetPro(v),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _RestoreMode { merge, replace }

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.isPro, required this.count});

  final bool isPro;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isPro ? Icons.workspace_premium : Icons.person_outline,
                  color: isPro
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Text(
                  isPro ? 'Proプラン' : 'Freeプラン',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text('$count 件', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isPro
                  ? '広告なし・変数の選択肢と既定値・コピー履歴・復元がすべて有効です。'
                  : '保存数・ピン留め・書き出しは無制限です。'
                      'Proにすると広告が消え、変数入力がさらに速くなります。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Pro',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
