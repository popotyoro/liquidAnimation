# Repository Guidelines

## プロジェクトの目的と構成

SwiftUI の画面に液体を重ね、上端の一か所から斜めに注ぐ iOS アプリ。長方形の容器、2D の流体計算、設定可能な液量と不透明度、60fps を目標とする。要件と数式は `docs/liquid-animation-spec.md` を参照し、仕様を変更した場合は同時に更新する。

- `Package.swift`：Swift tools 6.4によるライブラリとテストの定義。
- `Tests/LiquidFluidTests/`：ライブラリのテスト。
- `LiquidAnimation/LiquidAnimation/Demo/`：デモ専用の画面・設定UI・カレンダー。
- `LiquidAnimation/LiquidAnimation.xcodeproj`：Xcode プロジェクト。
- `LiquidAnimation/LiquidAnimation/ContentView.swift`：サンプル画面と設定 UI。
- `Sources/LiquidFluid/View/`：SwiftUIの入口、modifier、`MTKView`の組み込み。
- `Sources/LiquidFluid/Model/`：設定・操作状態、水滴・気泡などのデータ型。
- `Sources/LiquidFluid/Simulation/`：浅水モデル、注水曲線、数式、再生制御。
- `Sources/LiquidFluid/Rendering/`：Metal描画、共有バッファ、頂点・定数、描画エラー。
- `LiquidAnimation/LiquidAnimation/Assets.xcassets`：色。
- `LiquidAnimation/LiquidAnimation/AppIcon.icon`：Icon Composerのアプリアイコン。

## ビルド・実行は Xcode MCP を使う

**Xcode の操作とビルド・実行・テストには Xcode MCP を使用する。`xcodebuild` を使ったビルドは禁止する。** シェルスクリプトや他のツールを経由して `xcodebuild` を呼び出す方法も使用しない。

1. `XcodeListWorkspaces` で現在の識別子を取得する。識別子を固定値として保存しない。
2. `XcodeListSchemes` と `XcodeListRunDestinations` で `LiquidAnimation` スキームと iOS の実行先を確認する。
3. `BuildProject` でビルドし、`RunProject` で実行する。必要に応じて `GetBuildLog` と `GetConsoleOutput` で原因を調べる。

Metalの処理・起動方式を変更した場合は、描画テストに加えて通常起動後の`GetConsoleOutput`とデバッガの`process status`を確認する。`RunProject`の起動成功だけで検証を終えず、Metal検証エラーによる停止がなく実行を継続していることを確かめる。

設定の確認・変更には `GetTargetBuildSettings` と `UpdateTargetBuildSetting` を使う。`project.pbxproj` を直接編集しない。Metal ツールチェーンなどの環境不足は報告し、無断で別のビルド方式へ切り替えない。

変更後は、先に `LiquidAnimation` スキームで `BuildProject` を実行してパッケージとのリンクを確認する。ライブラリのテストはリポジトリのルートを `XcodeOpenWorkspace` で開き、`LiquidFluid` スキームを使う。デモのテストはプロジェクト側の `LiquidAnimationTests` スキームで実行する。

## コードの書き方

インデントはスペース4つ。型は `UpperCamelCase`、変数・関数は `lowerCamelCase`、Swiftは原則1ファイル1型とし、ファイル名は型名に合わせる。View拡張は `View+LiquidOverlay.swift`、特定の型に属する補助型は `WaterModel+Drop.swift` のように所属を表す。現時点で専用のフォーマッターやリンターは導入していない。

アプリとパッケージはSwift 6モードの完全な並行性チェックを使う。パッケージでもApproachable ConcurrencyとMember Import Visibilityを有効にする。アプリとライブラリは既定の MainActor 隔離を利用し、型への重複した `@MainActor` は省く。UI・水面モデル・描画バッファの変更をこの隔離内に保つ。Metal の完了通知は `@Sendable` とし、値を取り出してから `Task { @MainActor in ... }` で戻す。前のGPUコマンドが完了するまで共有バッファを書き換えない。共有する値型は `Sendable` にする。警告回避のためにチェックを弱めたり、`@unchecked Sendable` を追加したりしない。

SwiftUI は設定と操作、CPU は浅水モデルと液量の計算、Metal は水面と水流の描画を担当する。毎フレームの粒子データを SwiftUI の状態へ流さず、表示する計測値の更新頻度を抑える。Swift と Metal で共有する構造体は、フィールド順序・型・メモリアラインメントを一致させる。

## 設計とリファクタリング

- **単一責任・関心の分離**：操作と時間、物理更新、メッシュ生成、GPU管理、描画設定を役割で分ける。Metalでも水面の形状とライティングを分ける。
- **SLAP**：一つの関数内の抽象度を揃える。上位の関数は処理順を示し、着水処理・流束計算・断面形状などの詳細は意味のある単位の関数に委ねる。
- **DRY**：同じ数式・変換・合成設定は一か所で定義する。注水曲線と積分は `PourEmission`、格子上のガウス分布は `GaussianFootprint` のように、数式のまとまりを名前で表す。
- **KISS・YAGNI**：必要な分割に留め、将来用のプロトコル・設定・汎用基盤を追加しない。

リファクタリングでは既存のテストを振る舞いの基準とし、コミット前に必要なテストを整備して再検証する。物理定数・処理順・描画順を変える場合は、振る舞いの変更として明示する。描画経路の整理では変更前後の画像も比較する。変更の説明には、適用した原則と具体的な改善点を対応づける。

## 物理計算と検証

液量は水流・飛沫を含めた投入総量で管理する。透明なレイヤーは背景の描画内容に依存せず、タッチを遮らない。時間刻み、境界条件、数値的な減衰などの近似はコードと仕様書に残す。

実装と見た目の調整を優先し、テストコードの追加・更新と実行はコミット前にまとめて行う。各調整のたびにテストの作成・実行を必須としない。ビルド・起動確認は調整中も必要に応じて行う。

ただし、描画変更時はコミット前まで待たず、描画テストで時間ごとの画像を出力して実際に目視確認する。ビルド・起動の成功だけで見た目を確認済みとしない。振る舞いのテスト整備と全件実行はコミット前にまとめてよい。

Swift Testingの`LiquidFluidTests`（ライブラリ）と`LiquidAnimationTests`（デモ）を使用する。カバレッジ基準は未設定。コミット前には MCP のビルド確認に加え、0%・50%・100% の投入量、液量の保存、非有限値、波の減衰、一時停止・リセットを確認する。対象のスキームで `RunAllTests` または `RunSomeTests` を使う。実行先は iPhone 18 Pro とし、iPhone Duo およびDuoを選ぶ可能性があるプレビュー経由の検証は使用しない。60fps の達成は実機で測定し、シミュレータの結果と区別する。

テスト設計はt-wadaの重視する振る舞い・再現性・独立性を基準とする。

- **ケースの粒度と名前**：一つの論理的な振る舞いを一ケースにし、`@Test("一時停止中は水の状態が変わらない")` のように日本語で条件と期待結果を書く。関数名は`lowerCamelCase`。private関数の呼び出し回数や分割構造に依存しない。
- **Four Phase Test**：準備・実行・検証・後始末を分ける。前提不足は`#require`で失敗させ、検証を飛ばさない。後始末はスコープ終了・ARCで完結してよい。時刻・日付は固定し、実時間待ちに依存しない。
- **並列実行と独立性**：各ケースがモデルと可変GPU資源を所有する。共有Scene・キーウィンドウ・固定出力ファイルを操作せず、画像は`Attachment.record`で添付する。`.serialized`で共有状態への依存を隠さない。
- **隔離は必要な範囲だけ**：テストの既定隔離は`nonisolated`。対象のモデル・操作状態・描画APIが要求する場合だけ`@MainActor`を付け、純粋計算のSuiteへ一律に付けない。並列化のために本体の隔離やSwift 6のチェックを弱めない。

描画テストは本番の転送・合成経路を使い、画像の生成成功だけでなく画素や描画結果を検証する。詳細は[テストの設計と実行](docs/testing-guide.md)を参照。

## コミットとプルリクエスト

コミットメッセージは変更目的が分かる短い命令形にする。PR には目的、変更内容、MCP での確認結果、未検証事項を記載する。見た目の変更には画像または動画を添え、関連 Issue があればリンクする。

## エージェントの作業範囲

依頼範囲内の軽微で可逆的な改善は進めてよい。目的・範囲・重要な制約を変える場合は、代替案とトレードオフを示して確認する。認証情報や個人用の署名設定をコミットしない。

Computer Use、CUA、ネイティブアプリやブラウザの UI 操作は、ユーザーから明示的な使用指示または事前許可がある場合に限る。「開いて」「実行して」「Xcode で確認して」だけを Computer Use の許可と解釈しない。許可がない場合は専用 MCP/API またはシェルを使う。ただし、ビルドには上記の Xcode MCP の規則を適用する。
