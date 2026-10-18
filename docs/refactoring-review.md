# FluidのリファクタリングとSwift記法レビュー

確認日：2026年10月18日。対象はFluid内の本体と関連テスト。インストール済みのSwift 6.4コンパイラ、Xcode MCPの設定情報、AppleのSwiftUIガイダンスを基準に確認した。

## 適用した原則

| 原則 | 変更と理由 |
| --- | --- |
| 単一責任・関心の分離 | `BeerFoam`へ泡の保持液量・白濁の計算を移し、`WaterModel`は更新順序と総液量を管理する。`WaterParticleMeshBuilder`へ気泡・飛沫の描画用変換を移した。 |
| DRY | 気泡・飛沫の四角形の頂点配置を共有し、水流を含む座標変換も一か所へ集約した。 |
| 依存の明示・テスト容易性 | `FrameRateMeter`は時刻を引数で受け取り、実際に待機せずに通知境界・次の集計期間・遅延時のFPSを検証できる。 |
| 変更の局所化 | `FluidMetricsView`だけが計測プロパティを読み、計測値だけの更新を局所化した。投入率や再生状態が変わるときは、従来どおり操作バーも更新する。 |
| KISS・YAGNI | 既存の具体型と値型で整理した。将来用のプロトコル・並列処理・汎用描画基盤は導入していない。 |

物理係数・演算順序・粒子上限・水面の式・描画順序は変更していない。水流の断面生成は落下軌道や投入履歴と密接なため、今回は`WaterModel`に残した。

## SwiftとSwiftUIの確認結果

- `@Observable`を画面側の`@State`で所有する構成を維持。Bindingを作らない`FluidControlBar`は`@Bindable`から通常の`let`へ変更し、設定画面では`@Bindable`を維持した。
- 設定項目のタイトルを`String`から`LocalizedStringKey`へ変更し、SwiftUIの静的ラベルとして扱うようにした。
- 既定のMainActor隔離に重複する型注釈は追加していない。独立した計算値型には`nonisolated`と`Sendable`を指定した。
- Metal完了通知の`@Sendable`、値を取り出した後の`Task { @MainActor in ... }`、共有バッファの使用完了待ちは維持した。
- `NavigationStack`、`.foregroundStyle`、安定した識別子を持つ`ForEach`、Swift Testingは導入済み。置き換えが必要な旧式の状態管理は見つからなかった。
- `@concurrent`などは追加していない。同期の物理更新を別の実行領域へ移すことは、記法の整理とは異なる設計変更になるため。

## 検証

泡の生成・排液・時間分割、FPSの集計境界、座標変換、炭酸気泡の最小直径、飛沫の面積保存を、日本語の仕様名を持つSwift Testingのケースで追加した。iPhone 18 Proシミュレータで全116件が成功。変更前後の水・ビール13時点の画像はピクセル単位で完全一致し、操作バーの通常文字・拡大文字の画像も目視確認した。実機性能の改善は今回の検証対象としていない。

通常起動でも空・注水中・50%まで注水した後のスクリーンショットを確認した。背景の文字・図形・ボタン、液体、操作バーと計測値が表示され、Metal検証エラーによる停止はなかった。拡大文字では「注ぐ」が折り返す既存の表示が残るため、すべての文字サイズにおける操作バーの最適化まで完了したとは扱わない。

## 参照

- [Apple：Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app/)
- [Swift：Data Race Safety](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/dataracesafety/)
