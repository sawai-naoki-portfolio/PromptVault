# テスト仕様・結果 — PromptVault

## 1. 方針

| 種類 | 対象 | ねらい |
|---|---|---|
| 単体テスト | 変数の解析・置換、検索、並び替え、JSON、広告頻度、Free / Pro 判定 | 純粋関数として切り出したロジックの仕様を固定する |
| 結合テスト | `PromptRepository`（**実際の Hive ファイル**） | 保存・取り消し・復元・永続化が実ストレージで動くことを確認する |
| ウィジェットテスト | 一覧・コピー・編集・設定の画面操作 | 「Free でも変数フォームが開く」「Pro では選択肢がチップになる」など、ユーザーから見える振る舞いを固定する |
| スクリーンショット | README・本ドキュメントの画像 | 本物のウィジェットツリーを描画して生成（golden 比較は CI の合否に含めない） |

> ウィジェットテストでは Hive ではなく `InMemoryPromptStore` を注入しています。`testWidgets` の本体は擬似非同期ゾーンで動くため、実ファイル I/O の Future が完了せずハングするためです。Hive 実装そのものは結合テスト側で検証しています。

## 2. 実行方法

```bash
flutter pub get
flutter analyze
flutter test                                                    # 143 件（screenshots タグの 7 件は skip）
flutter test --update-goldens --tags screenshots --run-skipped  # スクリーンショット再生成
```

## 3. テストケース一覧

| ファイル | 種類 | 件数 | 主な観点 |
|---|---|---|---|
| `test/placeholder_parser_test.dart` | 単体 | 34 | 基本記法、既定値 `{{名前=値}}`、選択肢 `{{名前:A\|B}}`、重複と混在、初期値、正規化表示、置換、カーソル位置への挿入 |
| `test/prompt_query_test.dart` | 単体 | 26 | AND 検索、大文字小文字、タグ AND、ピン優先の並び替え、タグ文字列の正規化、旧カテゴリのタグ移行 |
| `test/backup_service_test.dart` | 単体 | 14 | JSON 書き出し、ラッパー形式／配列形式の読み込み、欠損フィールド、旧形式との互換 |
| `test/entitlements_test.dart` | 単体 | 11 | データに関わる機能は全プランで使える、Free / Pro の機能差 |
| `test/interstitial_cadence_test.dart` | 単体 | 6 | 4 回に 1 回、クールダウン中は出さない、0 以下の設定で広告オフ、Noop 実装 |
| `test/prompt_store_test.dart` | 結合（実 Hive） | 27 | 件数無制限、空保存の拒否、ピン留めで `updatedAt` が変わらない、削除・編集・全件削除の取り消し、初回サンプル投入、コピー履歴の上限と重複統合、マージ復元、box を開き直しても残る |
| `test/app_flow_test.dart` | ウィジェット | 25 | 空状態、検索、ピン留め、変数なし／あり（Free・Pro）のコピー、キャンセル、コピー履歴、作成・編集・取り消し、設定の購入導線、下部タブが存在しないこと |
| **合計** | | **143** | |
| `test/screenshots_test.dart` | 画像生成 | 7 | 通常実行では skip（`dart_test.yaml`） |

### 代表的なテストケース（抜粋）

| No | ケース | 期待結果 |
|---|---|---|
| 1 | Free で変数入りプロンプトをタップ | 変数フォームが開き、置換してコピーできる |
| 2 | Free で `{{トーン:丁寧\|カジュアル}}` を含むプロンプトをコピー | 選択肢も既定値も効かず、素の入力欄になる |
| 3 | Pro で同じプロンプトをコピー | 選択肢がチップになり、既定値が入った状態で始まる |
| 4 | 変数フォームをキャンセル | クリップボードに何も送らない |
| 5 | プロンプトを削除 | 確認なしで削除され、「元に戻す」で復活する |
| 6 | 編集を保存して「元に戻す」 | 編集前の内容に戻る |
| 7 | サンプルを消して再起動 | サンプルは再投入されない |
| 8 | 同じテキストを 2 回コピー（Pro） | 履歴は 1 件にまとまる |
| 9 | 同一 ID を含むバックアップをマージ復元 | `updatedAt` が新しい方を残す |
| 10 | Hive の box を閉じて開き直す | ピン留め・使用回数を含めて残っている |

## 4. 結果

| 項目 | 結果 |
|---|---|
| `flutter test` | 143 件 pass（GitHub Actions・Flutter 3.44.7、`flutter test --reporter expanded` の最終行 `+143 ~1: All tests passed!`）。`test/` の `test(`/`testWidgets(` は静的に数えて 150 件で、差の 7 件は `screenshots_test.dart`（`dart_test.yaml` で skip、スイート単位で `~1`） |
| スクリーンショット | `test/screenshots_test.dart` で生成（本ドキュメントの `screenshots/`） |

## 5. 既知の課題

| 課題 | 対応方針 |
|---|---|
| リリース署名が debug キーのまま | 公開前に release 署名を設定 |
| 広告ユニット ID がテスト用 | `--dart-define` で本番 ID を注入してビルド |
| `applicationId` が仮（`com.promptvault.promptvault`） | ストア登録前に変更 |
