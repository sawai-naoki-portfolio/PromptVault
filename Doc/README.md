# PromptVault — 設計ドキュメント

> **「探す・直す・コピペする」を最速にする LLM プロンプト管理アプリ。**
> `{{変数}}` 入りのプロンプトを 1 タップでコピーし、入力フォームで置換まで済ませる。
> データは端末内だけに保存（Flutter / iOS・Android）。

<table>
<tr>
<td width="25%"><img src="screenshots/01_list.png" alt="一覧"></td>
<td width="25%"><img src="screenshots/03_editor.png" alt="編集"></td>
<td width="25%"><img src="screenshots/04_variable_form.png" alt="変数フォーム"></td>
<td width="25%"><img src="screenshots/07_settings.png" alt="設定"></td>
</tr>
<tr>
<td align="center">一覧・1 タップコピー</td>
<td align="center">変数チップで挿入</td>
<td align="center">変数フォームで置換</td>
<td align="center">プラン・バックアップ</td>
</tr>
</table>

## プロジェクト概要

| 項目 | 内容 |
|---|---|
| 種別 | スマートフォンアプリ（個人開発） |
| 対応 OS | Android / iOS（Flutter 3.44.7） |
| 担当 | 企画・要件定義・UI 設計・実装・テストすべて 1 人 |
| 規模 | Dart 約 4,200 行（`lib/`）＋ テスト 143 件 ／ 画面 3 ＋ シート 3 |
| 収益モデル | Free（広告あり）＋ Pro 買い切り（広告非表示・入力の高速化） |

### 技術スタック

| 分類 | 技術 |
|---|---|
| 言語 / フレームワーク | Dart 3.12 / Flutter 3.44.7 |
| 状態管理 | Riverpod 3（Notifier） |
| 永続化 | Hive（`TypeAdapter` を手書き）、SharedPreferences |
| 課金 / 広告 | `in_app_purchase`（非消費型）、`google_mobile_ads`（AdMob） |
| その他 | `share_plus`, `file_picker`, `path_provider` |
| テスト | 単体・結合（実 Hive）・ウィジェットテスト 143 件、golden によるスクリーンショット生成 |

---

## このプロジェクトで伝えたいこと

### 1. 独自の変数記法とパーサを設計した

`{{ターゲット}}`（自由入力）、`{{文字数=200}}`（既定値）、`{{トーン:丁寧|カジュアル}}`（選択肢）の 3 種類の記法を設計し、`PlaceholderParser` で解析・置換・挿入まで実装しました。**記法の解析は Free / Pro に関係なく常に行う**ため、Free で書いたプロンプトが Pro にした瞬間に意味を変えることはありません。パーサの仕様は 34 件の単体テストで固定しています。

### 2. 「ユーザーのデータを人質にしない」課金設計

保存件数・ピン留め・書き出しを Free でも無制限にし、課金の理由を「広告が消える」「入力がさらに速くなる」に置きました。機能差は `Entitlements` クラス 1 か所に集約し、UI からはプロパティを見るだけにしています。

### 3. 広告でコア体験を壊さない

- 広告はクリップボードへ送った**後**に呼ぶ。広告の読み込み状況がコピーの成否に影響しない
- 「4 回に 1 回」かつ「前回から 2 分以上」の二重ガード（`InterstitialCadence` を単体テスト）
- `adsServiceProvider` が `isProProvider` を watch し、**購入した瞬間に Noop 実装へ差し替わる**

### 4. 確認ダイアログより「元に戻す」

削除・編集・全件削除はすべて SnackBar の「元に戻す」で取り消せます。毎回ダイアログを挟むより、1 タップで消して 1 タップで戻せるほうが速いという判断です。

### 5. テストしやすい構造

`PromptStore` / `PurchaseService` / `AdsService` をインターフェースにし、テスト・非対応プラットフォーム・Pro ユーザーで実装を差し替えています。ウィジェットテストでは実ファイル I/O がハングする問題をインメモリ実装の注入で回避し、Hive 実装は**実ファイルを使う結合テスト**で別途検証しています。README とこのドキュメントのスクリーンショットも、テストと同じ経路で本物のウィジェットツリーから生成しています。

### 6. 削る判断

カテゴリとタグの二重管理、5 種類の並び替え、「発見」タブを、使われ方を見直して削りました。既存データのカテゴリは Hive のフィールド番号を据え置いたまま**タグへ自動移行**しています（→ [要件定義書 6 章](requirements.md#6-あえて削ったもの)）。

---

## 技術的な課題と解決

| 課題 | 解決 |
|---|---|
| `share_plus` 13 と `file_picker` 11 が要求する `win32` のメジャーバージョンが衝突 | iOS / Android には影響しない推移的依存のため、`share_plus` を 12 系に固定 |
| `build_runner` なしで Hive を使いたい | `TypeAdapter` を手書き。フィールド番号を据え置き、旧フィールドは読み込み時だけ処理 |
| ウィジェットテストで Hive の I/O が完了せずハングする | `PromptStore` を抽象化し、ウィジェットテストではインメモリ実装を注入 |
| 環境ごとにフォントの描画が変わり golden 比較が不安定 | スクリーンショット生成は `--tags screenshots` で明示実行し、CI の合否から外す |
| 開発中に本番広告を表示してしまうリスク | 既定はテスト広告 ID。本番 ID はリリースビルドかつ `--dart-define` 指定時のみ |

---

## ドキュメント一覧

| ドキュメント | 内容 |
|---|---|
| [要件定義書](requirements.md) | 背景・目的・対象ユーザー・機能要件・非機能要件・削ったもの |
| [画面定義書](screen-definitions.md) | 画面・シート・ダイアログの一覧と、表示項目／操作／入力チェック |
| [設計書](design.md) | システム構成・レイヤー・クラス図・シーケンス図・データ設計・課金と広告 |
| [テスト仕様・結果](test-report.md) | テスト方針・143 件の内訳・代表ケース |
| [diagrams/](diagrams/) | PlantUML ソース（`src/`）と SVG（`svg/`） |
| [screenshots/](screenshots/) | 主要画面（`test/screenshots_test.dart` で生成） |

### 図の一覧

| 図 | PlantUML | SVG |
|---|---|---|
| ユースケース図 | [usecase.puml](diagrams/src/usecase.puml) | [usecase.svg](diagrams/svg/usecase.svg) |
| システム構成図 | [architecture.puml](diagrams/src/architecture.puml) | [architecture.svg](diagrams/svg/architecture.svg) |
| クラス図 | [class.puml](diagrams/src/class.puml) | [class.svg](diagrams/svg/class.svg) |
| シーケンス図① コピー | [seq-copy.puml](diagrams/src/seq-copy.puml) | [seq-copy.svg](diagrams/svg/seq-copy.svg) |
| シーケンス図② 保存と取り消し | [seq-edit-undo.puml](diagrams/src/seq-edit-undo.puml) | [seq-edit-undo.svg](diagrams/svg/seq-edit-undo.svg) |
| シーケンス図③ バックアップ | [seq-backup.puml](diagrams/src/seq-backup.puml) | [seq-backup.svg](diagrams/svg/seq-backup.svg) |
| シーケンス図④ 購入 | [seq-purchase.puml](diagrams/src/seq-purchase.puml) | [seq-purchase.svg](diagrams/svg/seq-purchase.svg) |
| 画面遷移図 | [screen-transition.puml](diagrams/src/screen-transition.puml) | [screen-transition.svg](diagrams/svg/screen-transition.svg) |

SVG の再生成：

```bash
cd Doc/diagrams/src
java -jar plantuml.jar -charset UTF-8 -tsvg -o ../svg *.puml
```
