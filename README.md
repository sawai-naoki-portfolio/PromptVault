# PromptVault

[![Test](https://github.com/sawai-naoki-portfolio/PromptVault/actions/workflows/test.yml/badge.svg)](https://github.com/sawai-naoki-portfolio/PromptVault/actions/workflows/test.yml)

> **ポートフォリオ作品**（[作品一覧へ](https://github.com/sawai-naoki-portfolio)）。設計資料（要件定義書・画面定義書・設計書・テスト結果・UML 図）は [`Doc/`](Doc/README.md) にあります。
>
> | 項目 | 内容 |
> |---|---|
> | 開発 | 個人開発。企画・仕様決め・設計の判断・レビュー・テストでの検証は自分で行い、実装とドキュメント作成には生成 AI（Claude Code）を活用 |
> | 開発時期 | 2026 年 7 月（コミットの記録: 7/28） |
> | 公開状況 | 未公開 |

「探す・直す・コピペする」を最速化する、**オフライン完結型**の LLM プロンプト管理アプリ（Flutter / iOS・Android）。

ChatGPT・Claude・Gemini などを日常業務で使う人が、スマホから**1 タップでプロンプトをコピー**し、
`{{変数}}` の差し替えまで済ませて貼り付けられることを目指しています。

プロンプトは端末内の Hive にのみ保存され、外部サーバーへ送信する経路をアプリ内に持ちません。
運用コストが発生する外部サービスを使わない構成です（サーバー費 0 円）。

> **設計ドキュメント** — 要件定義書・画面定義書・設計書（クラス図／シーケンス図／画面遷移図）・テスト仕様は
> [`Doc/`](Doc/README.md) にまとめています。

---

## スクリーンショット

| プロンプト一覧 | 検索で絞り込み | 作成・編集 |
|:---:|:---:|:---:|
| ![プロンプト一覧](Doc/screenshots/01_list.png) | ![検索](Doc/screenshots/02_search.png) | ![編集](Doc/screenshots/03_editor.png) |
| ピン留めを上部に固定。カードを 1 タップでコピー | タイトル・本文・タグを横断するインクリメンタルサーチ | 全画面エディタと `{{変数}}` 挿入チップ |

| 変数フォーム（Pro） | コピー履歴（Pro） | 設定・課金 |
|:---:|:---:|:---:|
| ![変数フォーム](Doc/screenshots/04_variable_form.png) | ![コピー履歴](Doc/screenshots/05_copy_history.png) | ![設定](Doc/screenshots/07_settings.png) |
| 選択肢はタップで切り替え、既定値は最初から入っている状態でコピーできる | 変数を埋めた結果を遡って再コピーできる | プラン状態、購入 / 復元、バックアップ、プライバシーの説明 |

<p align="center">
  <img src="Doc/screenshots/06_pro_upsell.png" width="320" alt="Pro訴求">
</p>
<p align="center">
  Pro 訴求 — 保存数やピン留めではなく「広告が消える・入力が速くなる」で売る
</p>

> スクリーンショットは実機ではなく、ウィジェットテストと同じ経路で本物のウィジェットツリーを
> 描画して生成しています（`test/screenshots_test.dart`）。生成方法は[後述](#スクリーンショットの再生成)。

---

## 機能

### Free / Pro の違い

**ユーザー自身のデータには制限をかけない**方針です。保存件数やピン留めを人質に取ると、
価値を体験する前に離脱するか「データを失った」という最悪の体験を生みます。
課金の理由は「広告が消える」と「入力がさらに速くなる」に置いています。

| 機能 | Free | Pro（買い切り） |
|---|:---:|:---:|
| 保存件数 | **無制限** | 無制限 |
| ピン留め | **無制限** | 無制限 |
| `{{変数}}` の入力フォーム | **使える** | 使える |
| バックアップの書き出し | **使える** | 使える |
| 広告表示 | あり | **なし** |
| 変数の選択肢・既定値 | なし | **あり** |
| コピー履歴 | なし | **あり** |
| バックアップからの復元 | なし | **あり** |

判定ロジックは `lib/core/entitlements.dart` に集約しています。

### 主な画面

- **プロンプト一覧**（ホーム） — インクリメンタルサーチ（タイトル/本文/タグ横断、空白区切りは AND）、タグフィルター、並び替え、ピン留め、カード 1 タップでコピー、コピー履歴
- **作成・編集** — 全画面エディタ、`{{変数}}` 挿入チップ、タグ
- **設定・課金** — プラン状態、Pro 購入 / 復元、バックアップの書き出しと復元、全削除

### 変数の記法

| 記法 | 動作 | プラン |
|---|---|:---:|
| `{{ターゲット}}` | 自由入力 | Free / Pro |
| `{{文字数=200}}` | 既定値つきの自由入力 | Pro |
| `{{トーン:丁寧\|カジュアル}}` | 選択肢（先頭が既定値） | Pro |
| `{{トーン:丁寧\|カジュアル=カジュアル}}` | 選択肢 + 既定値を明示 | Pro |

解析は常に行うため、Free で書いた `{{文字数=200}}` は変数名「文字数」として扱われ、
Pro にした瞬間に意味が変わることはありません。Free では選択肢と既定値が無視され、
素のテキスト入力欄になります。

### コピー体験

1. `{{変数}}` があれば入力フォームを自動生成 → 置換（**全プラン**）
2. クリップボードへ送信
3. 使用回数を加算（「よく使う順」に反映）し、Pro なら履歴に積む
4. Free なら一定条件でインタースティシャル広告

広告はクリップボードへ送った**後**に呼ぶため、広告の読み込み状況がコピーの成否に影響しません。
また「4 回に 1 回」かつ「前回表示から 2 分以上」の二重のガードをかけ、連打で広告が連続しないようにしています。

`updatedAt` はコピーやピン留めでは更新しません。並び順が勝手に変わると、
ユーザーが覚えている位置が壊れるためです。

### 取り消し

削除・編集・全件削除はすべて SnackBar の「元に戻す」で取り消せます。
削除に確認ダイアログは出しません。1 タップで消せて 1 タップで戻せるほうが、
毎回ダイアログを挟むより速いためです。

### オンボーディング

初回起動時に変数入りのサンプルを 3 件自動投入します。
空のリストから始まると、このアプリの価値が何も伝わらないためです。
一度実行したらフラグを立てるので、サンプルを消したのに再起動で復活することはありません。
空状態の「サンプルを追加する」から全件まとめて入れることもできます。

---

## 必要な環境

| | バージョン |
|---|---|
| Flutter | **3.44.7**（stable） |
| Dart | 3.12.2（Flutter 3.44.7 同梱） |
| Android | AGP 9.0.1 / Gradle 9.1.0 / JDK 17 |

Android・iOS のプロジェクトファイルは Flutter 3.44.7 のテンプレートで生成しています。

## 技術スタック

| 役割 | パッケージ | バージョン |
|---|---|---|
| 状態管理 | `flutter_riverpod` | ^3.4.1 |
| ローカル DB | `hive` / `hive_flutter` | ^2.2.3 / ^1.1.0 |
| アプリ内課金 | `in_app_purchase` | ^3.3.0 |
| 広告 | `google_mobile_ads` | ^9.0.0 |
| フラグ保存 | `shared_preferences` | ^2.3.5 |
| ファイル共有 | `share_plus` + `path_provider` | ^12.0.2 / ^2.1.6 |
| ファイル選択（復元用） | `file_picker` | ^11.0.2 |

> `share_plus` は 13 系ではなく **12 系**に固定しています。
> `share_plus` 13 は `win32 ^6` を、`file_picker` 11 は `win32 ^5` を要求しており、
> 同時に解決できないためです（`win32` は Windows 専用の推移的依存で、
> 本アプリの対象である iOS / Android には影響しません）。
> `file_picker` 12（win32 6 対応）が stable になれば両方を上げられます。

Hive の `TypeAdapter` は `build_runner` を使わず手書きです（`lib/models/prompt.dart`）。
コード生成が無いぶん、**フィールドを追加したら `PromptAdapter.read` / `write` の更新が必須**です。

---

## ディレクトリ構成

```
lib/
├── main.dart                     起動。Hive / SharedPreferences を初期化して DI
├── app.dart                      MaterialApp と起動時の副作用（課金購読・初回投入）
├── core/
│   ├── constants.dart            プロダクトID・永続化キー・広告の頻度
│   ├── entitlements.dart         Free/Pro の機能差ポリシー
│   ├── prompt_query.dart         絞り込み・並び替え（純粋関数）
│   └── theme.dart
├── models/prompt.dart            ドメインモデル + 手書き Hive アダプタ
├── data/
│   ├── prompt_repository.dart    PromptStore（抽象）と Hive 実装
│   ├── copy_history_store.dart   コピー履歴（Pro）
│   └── starter_prompts.dart      初回投入・サンプル用テンプレート
├── providers/                    Riverpod のプロバイダ定義
├── services/
│   ├── placeholder_parser.dart   {{変数}} の検出・置換・挿入
│   ├── ads_service.dart          AdMob + 表示頻度の制御
│   ├── purchase_service.dart     in_app_purchase ラッパー
│   └── backup_service.dart       JSON の書き出し・読み込み
└── ui/                           画面とウィジェット
```

`AdsService` / `PurchaseService` / `PromptStore` はインターフェースになっており、
非対応プラットフォームやテストでは何もしない実装・インメモリ実装に差し替わります。

---

## 開発

```bash
flutter --version   # 3.44.7 であることを確認
flutter pub get
flutter run
flutter test        # 143 tests（screenshots 用の 7 件は skip）
flutter analyze
```

デバッグビルドの設定画面には「[デバッグ] Proとして扱う」トグルがあり、
決済を通さずに Pro 限定機能を確認できます。

### テスト方針

- ロジック（変数の検出・置換、検索、並び替え、CSV エスケープ、広告頻度、Free/Pro 判定）はユニットテスト
- 保存制限・ピン制限・バックアップ復元は**実際の Hive ファイル**を使った結合テスト（`test/prompt_store_test.dart`）
- 画面の描画、コピー体験、取り消し、課金導線はウィジェットテスト（`test/app_flow_test.dart`）

> ウィジェットテストでは Hive ではなく `InMemoryPromptStore` を注入しています。
> `testWidgets` の本体は擬似非同期ゾーンで動くため、実ファイル I/O の Future が
> 完了せずテストがハングするためです。Hive 実装自体は結合テスト側で検証しています。

### スクリーンショットの再生成

```bash
flutter test --update-goldens --tags screenshots --run-skipped
```

`Doc/screenshots/` の PNG が上書きされます。通常の `flutter test` では実行されません
（`dart_test.yaml` で skip 指定）。フォントの描画結果は環境によって微妙に変わるため、
golden 比較を CI の合否には含めていません。

生成には日本語フォントが必要です。`test/screenshots_test.dart` が
IPAGothic（`fonts-ipafont-gothic`）や Noto Sans CJK などを自動で探し、
見つからない場合は文字が豆腐（□）になります。Debian / Ubuntu なら:

```bash
sudo apt-get install fonts-ipafont-gothic
```

---

## リリース前チェックリスト

### 1. AdMob

**既定ではテスト用の広告ユニット ID が使われます。** 開発中に本番広告を叩いて
ポリシー違反になる事故を防ぐための既定値なので、**このままリリースしても収益は発生しません。**

- [ ] `android/app/src/main/AndroidManifest.xml` の `com.google.android.gms.ads.APPLICATION_ID` を本番アプリ ID に差し替え
- [ ] `ios/Runner/Info.plist` の `GADApplicationIdentifier` を本番アプリ ID に差し替え
- [ ] 広告ユニット ID をビルド時に注入する:

```bash
flutter build appbundle --release \
  --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-xxx/yyy \
  --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-xxx/zzz
```

（iOS は `ADMOB_BANNER_IOS` / `ADMOB_INTERSTITIAL_IOS`）
本番 ID はリリースビルドかつ dart-define 指定時のみ使われます（`lib/services/ads_service.dart`）。

- [ ] `ios/Runner/Info.plist` の `SKAdNetworkItems` に AdMob 公式一覧の識別子を追記

### 2. アプリ内課金

- [ ] App Store Connect / Google Play Console で**非消費型（買い切り）**アイテムを作成
- [ ] プロダクト ID を `AppConstants.proProductId`（既定 `promptvault_pro`）と一致させる
- [ ] 価格を設定（想定 320〜480 円）
- [ ] Sandbox / ライセンステストアカウントで購入・復元を確認

> サーバーを持たない構成のため、レシートのサーバー検証は行わず、
> ストア SDK が返す購入状態をそのまま信頼しています。

### 3. アプリ設定

- [ ] `applicationId` / Bundle ID を実際に登録するものへ変更（現在 `com.promptvault.promptvault`）
- [ ] リリース用の署名設定（現状は debug キーのまま）
- [ ] アイコン・スプラッシュの差し替え

### 4. ストア申請

- [ ] プライバシーポリシー（広告 SDK が識別子を利用する旨を含む）
- [ ] データ収集の申告（AdMob の利用を申告。プロンプト本文は収集しない）
