import 'package:flutter_test/flutter_test.dart';
import 'package:promptvault/core/entitlements.dart';

void main() {
  const free = Entitlements.free();
  const pro = Entitlements.pro();

  group('データに関わる機能は全プランで使える', () {
    test('変数フォームは Free でも使える', () {
      // ここを閉じると Free ユーザーには「ただのメモ帳」にしか見えないため。
      expect(free.variableForm, isTrue);
      expect(pro.variableForm, isTrue);
    });

    test('バックアップの書き出しは Free でも使える', () {
      expect(free.exportBackup, isTrue);
      expect(pro.exportBackup, isTrue);
    });
  });

  group('Free プラン', () {
    test('広告が表示される', () => expect(free.showAds, isTrue));

    test('変数の選択肢・既定値は使えない', () {
      expect(free.advancedVariables, isFalse);
    });

    test('コピー履歴は使えない', () => expect(free.copyHistory, isFalse));

    test('バックアップからの復元は使えない', () {
      expect(free.importBackup, isFalse);
    });
  });

  group('Pro プラン', () {
    test('広告が消える', () => expect(pro.showAds, isFalse));

    test('変数の選択肢・既定値が使える', () {
      expect(pro.advancedVariables, isTrue);
    });

    test('コピー履歴が使える', () => expect(pro.copyHistory, isTrue));

    test('バックアップからの復元が使える', () {
      expect(pro.importBackup, isTrue);
    });
  });

  test('同じプランどうしは等価', () {
    expect(const Entitlements(isPro: false), free);
    expect(const Entitlements(isPro: true), pro);
    expect(free, isNot(pro));
  });
}
