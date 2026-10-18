# Repository Guidelines

## プロジェクトの目的と構成

SwiftUI の画面に液体を重ね、上端の一か所から斜めに注ぐ iOS アプリ。長方形の容器、2D の流体計算、設定可能な液量と不透明度、60fps を目標とする。要件と数式は `docs/liquid-animation-spec.md` を参照し、仕様を変更した場合は同時に更新する。

- `LiquidAnimation/LiquidAnimation.xcodeproj`：Xcode プロジェクト。
- `LiquidAnimation/LiquidAnimation/ContentView.swift`：試作画面と設定 UI。
- `LiquidAnimation/LiquidAnimation/Fluid/View/`：SwiftUIの入口、modifier、`MTKView`の組み込み。
- `LiquidAnimation/LiquidAnimation/Fluid/Model/`：設定・操作状態、水滴・気泡などのデータ型。
- `LiquidAnimation/LiquidAnimation/Fluid/Simulation/`：浅水モデル、注水曲線、数式、再生制御。
- `LiquidAnimation/LiquidAnimation/Fluid/Rendering/`：Metal描画、共有バッファ、頂点・定数、描画エラー。
- `LiquidAnimation/LiquidAnimation/Assets.xcassets`：色とアプリアイコン。

## ビルド・実行は Xcode MCP を使う

**Xcode の操作とビルド・実行・テストには Xcode MCP を使用する。`xcodebuild` を使ったビルドは禁止する。** シェルスクリプトや他のツールを経由して `xcodebuild` を呼び出す方法も使用しない。

1. `XcodeListWorkspaces` で現在の識別子を取得する。識別子を固定値として保存しない。
2. `XcodeListSchemes` と `XcodeListRunDestinations` で `LiquidAnimation` スキームと iOS の実行先を確認する。
3. `BuildProject` でビルドし、`RunProject` で実行する。必要に応じて `GetBuildLog` と `GetConsoleOutput` で原因を調べる。

設定の確認・変更には `GetTargetBuildSettings` と `UpdateTargetBuildSetting` を使う。`project.pbxproj` を直接編集しない。Metal ツールチェーンなどの環境不足は報告し、無断で別のビルド方式へ切り替えない。

本体を変更した後は、先に `LiquidAnimation` スキームで `BuildProject` を実行し、続いて `LiquidAnimationTests` スキームでテストする。現在のテストホストの依存関係は自動解決されず、テストだけの実行では古い本体を参照し得る。

## コードの書き方

インデントはスペース4つ。型は `UpperCamelCase`、変数・関数は `lowerCamelCase`、Swiftは原則1ファイル1型とし、ファイル名は型名に合わせる。View拡張は `View+LiquidOverlay.swift`、特定の型に属する補助型は `WaterModel+Drop.swift` のように所属を表す。現時点で専用のフォーマッターやリンターは導入していない。

アプリとテストは Swift 6、`SWIFT_STRICT_CONCURRENCY = complete` を使用する。アプリは既定の MainActor 隔離を利用し、型への重複した `@MainActor` は省く。UI・水面モデル・描画バッファの変更をこの隔離内に保つ。Metal の完了通知は `@Sendable` とし、値を取り出してから `Task { @MainActor in ... }` で戻す。前のGPUコマンドが完了するまで共有バッファを書き換えない。共有する値型は `Sendable` にする。警告回避のためにチェックを弱めたり、`@unchecked Sendable` を追加したりしない。

SwiftUI は設定と操作、CPU は浅水モデルと液量の計算、Metal は水面と水流の描画を担当する。毎フレームの粒子データを SwiftUI の状態へ流さず、表示する計測値の更新頻度を抑える。Swift と Metal で共有する構造体は、フィールド順序・型・メモリアラインメントを一致させる。

## 設計とリファクタリング

- **単一責任・関心の分離**：操作と時間、物理更新、メッシュ生成、GPU管理、描画設定を役割で分ける。Metalでも水面の形状とライティングを分ける。
- **SLAP**：一つの関数内の抽象度を揃える。上位の関数は処理順を示し、着水処理・流束計算・断面形状などの詳細は意味のある単位の関数に委ねる。
- **DRY**：同じ数式・変換・合成設定は一か所で定義する。注水曲線と積分は `PourEmission`、格子上のガウス分布は `GaussianFootprint` のように、数式のまとまりを名前で表す。
- **KISS・YAGNI**：必要な分割に留め、将来用のプロトコル・設定・汎用基盤を追加しない。

リファクタリングでは先に既存の振る舞いをテストで押さえ、分割後に再検証する。物理定数・処理順・描画順を変える場合は、振る舞いの変更として明示する。描画経路の整理では変更前後の画像も比較する。変更の説明には、適用した原則と具体的な改善点を対応づける。

## 物理計算と検証

液量は水流・飛沫を含めた投入総量で管理する。透明なレイヤーは背景の描画内容に依存せず、タッチを遮らない。時間刻み、境界条件、数値的な減衰などの近似はコードと仕様書に残す。

Swift Testing の `LiquidAnimationTests` ターゲットを使用する。カバレッジ基準は未設定。変更時は MCP のビルド確認に加え、0%・50%・100% の投入量、液量の保存、非有限値、波の減衰、一時停止・リセットを確認する。`LiquidAnimationTests` スキームで `RunAllTests` または `RunSomeTests` を使う。実行先は iPhone 18 Pro とし、iPhone Duo およびDuoを選ぶ可能性があるプレビュー経由の検証は使用しない。60fps の達成は実機で測定し、シミュレータの結果と区別する。

ケース名は `@Test("一時停止中は水の状態が変わらない")` のように日本語で条件と期待結果を表し、関数名は通常の `lowerCamelCase` にする。一つのテストは一つの振る舞いに焦点を当て、テスト間でモデルや変更可能なGPU資源を共有しない。private関数の呼び出し回数や分割方法に依存せず、操作と観測できる結果を検証する。描画テストは本番の転送・合成経路を使う。

テストの既定隔離は `nonisolated`。モデル・操作状態・描画のテストには `@MainActor` を付け、`nonisolated` な設定値・共有構造体だけのテストには付けない。

## コミットとプルリクエスト

既存のコミットは `Add SwiftUI liquid simulation prototype` のような短い命令形。新しいコミットも変更目的が分かる表現にする。PR には目的、変更内容、MCP での確認結果、未検証事項を記載する。見た目の変更には画像または動画を添え、関連 Issue があればリンクする。

## エージェントの作業範囲

依頼範囲内の軽微で可逆的な改善は進めてよい。目的・範囲・重要な制約を変える場合は、代替案とトレードオフを示して確認する。認証情報や個人用の署名設定をコミットしない。

Computer Use、CUA、ネイティブアプリやブラウザの UI 操作は、ユーザーから明示的な使用指示または事前許可がある場合に限る。「開いて」「実行して」「Xcode で確認して」だけを Computer Use の許可と解釈しない。許可がない場合は専用 MCP/API またはシェルを使う。ただし、ビルドには上記の Xcode MCP の規則を適用する。
