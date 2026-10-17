# Repository Guidelines

## プロジェクトの目的と構成

SwiftUI の画面に液体を重ね、上端の一か所から斜めに注ぐ iOS アプリ。長方形の容器、2D の流体計算、設定可能な液量と不透明度、60fps を目標とする。要件と数式は `docs/liquid-animation-spec.md` を参照し、仕様を変更した場合は同時に更新する。

- `LiquidAnimation/LiquidAnimation.xcodeproj`：Xcode プロジェクト。
- `LiquidAnimation/LiquidAnimation/ContentView.swift`：試作画面と設定 UI。
- `LiquidAnimation/LiquidAnimation/Fluid/`：設定モデル、浅水ソルバー、Metal の計算・描画、SwiftUI への組み込み。
- `LiquidAnimation/LiquidAnimation/Assets.xcassets`：色とアプリアイコン。

## ビルド・実行は Xcode MCP を使う

**Xcode の操作とビルド・実行・テストには Xcode MCP を使用する。`xcodebuild` を使ったビルドは禁止する。** シェルスクリプトや他のツールを経由して `xcodebuild` を呼び出す方法も使用しない。

1. `XcodeListWorkspaces` で現在の識別子を取得する。識別子を固定値として保存しない。
2. `XcodeListSchemes` と `XcodeListRunDestinations` で `LiquidAnimation` スキームと iOS の実行先を確認する。
3. `BuildProject` でビルドし、`RunProject` で実行する。必要に応じて `GetBuildLog` と `GetConsoleOutput` で原因を調べる。

設定の確認・変更には `GetTargetBuildSettings` と `UpdateTargetBuildSetting` を使う。`project.pbxproj` を直接編集しない。Metal ツールチェーンなどの環境不足は報告し、無断で別のビルド方式へ切り替えない。

## コードの書き方

インデントはスペース4つ。型は `UpperCamelCase`、変数・関数は `lowerCamelCase`、ファイル名は主な型に合わせる。現時点で専用のフォーマッターやリンターは導入していない。

SwiftUI は設定と操作、CPU は浅水モデルと液量の計算、Metal は水面と水流の描画を担当する。毎フレームの粒子データを SwiftUI の状態へ流さず、表示する計測値の更新頻度を抑える。Swift と Metal で共有する構造体は、フィールド順序・型・メモリアラインメントを一致させる。

## 物理計算と検証

液量は水流・飛沫を含めた投入総量で管理する。透明なレイヤーは背景の描画内容に依存せず、タッチを遮らない。時間刻み、境界条件、数値的な減衰などの近似はコードと仕様書に残す。

Swift Testing の `LiquidAnimationTests` ターゲットを使用する。カバレッジ基準は未設定。変更時は MCP のビルド確認に加え、0%・50%・100% の投入量、液量の保存、非有限値、波の減衰、一時停止・リセットを確認する。`LiquidAnimationTests` スキームで `RunAllTests` または `RunSomeTests` を使い、テスト名に条件と期待結果を含める。実行先は iPhone 18 Pro とし、iPhone Duo およびDuoを選ぶ可能性があるプレビュー経由の検証は使用しない。60fps の達成は実機で測定し、シミュレータの結果と区別する。

## コミットとプルリクエスト

既存のコミットは `Add SwiftUI liquid simulation prototype` のような短い命令形。新しいコミットも変更目的が分かる表現にする。PR には目的、変更内容、MCP での確認結果、未検証事項を記載する。見た目の変更には画像または動画を添え、関連 Issue があればリンクする。

## エージェントの作業範囲

依頼範囲内の軽微で可逆的な改善は進めてよい。目的・範囲・重要な制約を変える場合は、代替案とトレードオフを示して確認する。認証情報や個人用の署名設定をコミットしない。

Computer Use、CUA、ネイティブアプリやブラウザの UI 操作は、ユーザーから明示的な使用指示または事前許可がある場合に限る。「開いて」「実行して」「Xcode で確認して」だけを Computer Use の許可と解釈しない。許可がない場合は専用 MCP/API またはシェルを使う。ただし、ビルドには上記の Xcode MCP の規則を適用する。
