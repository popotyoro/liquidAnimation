# LiquidFluid

SwiftUIの画面に液体を重ねるiOS向けライブラリ。Metalによる注水と、日付セルなどに使える軽量な水位アニメーションを提供する。

## 構成

```text
Package.swift      Swift Packageの定義
LiquidFluid/       ライブラリのSources・Tests
LiquidAnimation/   パッケージを利用するデモアプリ
docs/              仕様・開発方針
```

## 動作条件

- iOS 27.0以降
- Swift 6.4以降
- Metalが利用できる環境（注水表示）

Swift 6モードの完全な並行性チェックを使う。ライブラリの既定隔離はMainActor、テストはnonisolated。Approachable ConcurrencyのうちSwift 6で標準有効でない機能と、Member Import Visibilityを有効にする。

## パッケージの利用

Xcodeの「Add Package Dependencies」でGitHubのリポジトリURLを指定し、アプリのターゲットに`LiquidFluid`をリンクする。ローカルで使う場合は「Add Local Package」でこのリポジトリのルートを選ぶ。別のSwift Packageからローカル参照する場合は`.package(path: "../liquidAnimation")`を依存関係に追加し、対象ターゲットで`.product(name: "LiquidFluid", package: "liquidAnimation")`を指定する。

デモは`LiquidAnimation/LiquidAnimation.xcodeproj`を開く。`LiquidAnimation`スキームはリポジトリのルートを相対パスで参照する。デモアプリはSwift Packageのターゲットに含めない。Metalシェーダーはパッケージに同梱され、利用側でコピーする必要はない。

`LiquidAnimation/Package.swift`は、Xcodeのルートパッケージ表示からデモを除外するための空の定義。表示が残っている場合はXcodeプロジェクトを開き直す。

## 注水する

```swift
import LiquidFluid
import SwiftUI

struct DrinkView: View {
    @State private var controls = FluidControls(initialFraction: 0.25)

    var body: some View {
        VStack {
            Text("今日の水分")
            Button("合計40%まで注ぐ") { controls.pour(to: 0.4) }
            Button("空にする") { controls.reset() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidOverlay(controls: controls)
    }
}
```

`show(fraction:)`は指定量を静止状態で表示し、`pour(to:)`は現在量から合計割合まで差分を注ぐ。`pour()`は`configuration.fill`の量を空から注ぎ直す。割合は0〜1。一つの容器で別種類の液体を混ぜることは扱わない。mlからの換算や記録の保存は利用側で行う。

`controls.configuration`で種類・色・不透明度・注ぐ位置・角度・流量を設定する。`isPaused`で一時停止し、画面を休止する場合はmodifierの`isActive`へ`false`を渡す。液体レイヤーはタッチ操作を妨げない。

`feedback`は注水開始・初回着水・完了を通知する。触覚の適用例はデモの`FluidControlBar`を参照。

## 水位だけをアニメーションする

```swift
Text("今日の達成率")
    .frame(width: 100, height: 100)
    .liquidFill(fraction: progress, color: .cyan.opacity(0.3))
    .clipShape(RoundedRectangle(cornerRadius: 16))
```

呼び出し側で`progress`を`withAnimation`により変更する。物理モデルやMetalの更新ループは使わず、水位の変化に短い減衰波を重ねる。水位とは別の値で波を開始する場合は`animationTrigger`を指定する。設定と同じ色を使う場合は`Color.liquidFill(for: controls.configuration)`を渡す。

## テスト

ライブラリのテストは、リポジトリのルートをXcodeでパッケージとして開き、`LiquidFluid`スキームで実行する。デモのテストはXcodeプロジェクトの`LiquidAnimationTests`スキームを使う。実行先はiPhone 18 Proシミュレータ。

仕様は[液体注入アニメーション仕様書](docs/liquid-animation-spec.md)、テスト方針は[テストの設計と実行](docs/testing-guide.md)、残作業は[配布までの残作業](docs/future-features.md)を参照。
