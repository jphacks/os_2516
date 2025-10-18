# iOS アプリ開発タスク一覧

目的: SwiftUI + MVVM 構成でMap/Battle機能をモック先行で実装し、API準備後は最小差分で切替可能にする。

## M0: モック先行セットアップ（共通）
- [ ] プロトコル定義で抽象化
  - [ ] `MapService` / `BattleService` をそれぞれ `RealFightingGame/Data/...` に作成
- [ ] モック実装
  - [ ] `MockMapService`（`mode: success/empty/error`, `latencyMs`, `failureRate`）
  - [ ] `MockBattleService`（マッチング/行動解決をローカルシミュレーション）
- [ ] フィクスチャ
  - [ ] `RealFightingGame/Resources/Fixtures/pins.json`（任意。擬似生成でも可）
- [ ] 依存性注入（DI）
  - [ ] `#if DEBUG` でモック、`#else` でリモート（後日）
  - [ ] `xcconfig` or Scheme で `USE_MOCK=1` 切替（Debug/Preview用）
- [ ] プレビュー/テスト
  - [ ] Preview は常にモックを注入
  - [ ] ユニットテストで `mode` を切替し各状態を再現

## M1: Map 画面 MVP（表示と基本操作）
- [ ] 初期描画
  - [ ] `Map(position:content:)` へ統一（iOS17+）
  - [ ] `Binding<MapCameraPosition>` と `MKCoordinateRegion` の相互同期実装確認（`MapView.swift`）
  - [ ] 初期リージョンを `MapViewModel.region` の `defaultRegion` に揃える
- [ ] ピン描画
  - [ ] `Marker` で `MapPin` をループ表示（`MapViewModel.destinations`）
  - [ ] テキスト/色/アクセシビリティラベル設定
- [ ] ユーザ操作
  - [ ] ズーム/スクロールの感度確認、標準スタイル (`.standard`) 適用
  - [ ] オーバーレイ（タイトル/サブタイトル）のレイアウト最終化
- [ ] 現在地
  - [ ] 位置権限ダイアログ文言（`Info.plist: NSLocationWhenInUseUsageDescription`）
  - [ ] 現在地表示トグル／追従モード（必要なら）

## M2a: データ取得（モック実装で接続）
- [ ] `MapService` プロトコル定義（`Data/Map/MapService.swift`）
- [ ] `MockMapService` 実装（擬似生成 or `pins.json` ロード）
- [ ] `MapViewModel.loadPins()` 実装（`async/await`、`state` 更新、キャンセル安全）
- [ ] リージョン変更のデバウンス（500ms 目安）

## M2b: データ取得（リモート実装・API準備後）
- [ ] DTO/エンドポイント定義（`Data/Map/DTOs.swift`）
- [ ] `RemoteMapService` 実装（`URLSession`/`JSONDecoder`）
- [ ] エラー種別のマッピング（ネットワーク/HTTP/デコード）
- [ ] `AppConfig` に `baseURL`/`timeout` 追加（`Data/Config/AppConfig.swift`）
- [ ] DI 切替（`USE_MOCK` = 0 でリモート利用）

## M3: エラー・ローディング・詳細UI
- [ ] 状態設計
  - [ ] `ViewState<[MapPin]>` 採用（`idle/loading/success/failure`）
  - [ ] 空状態（ピン0件）の表示
- [ ] UI実装
  - [ ] `ProgressView` 表示/非表示
  - [ ] エラー表示＋リトライ
  - [ ] ピン選択→詳細シート（タイトル/距離/説明/アクション）

## M4: 共通基盤・品質
- [ ] 共通 `APIClient`（再利用可能な送受信/エラーハンドリング）
- [ ] 簡易メモリキャッシュ（座標キー＋TTL）（任意）
- [ ] ログ/トレース最小実装
- [ ] SwiftFormat 設定・スクリプト追加

## テスト（`RealFightingGameTests/`）
- [ ] `MapViewModelTests.swift`
  - [ ] 成功/失敗/空/キャンセルのユニットテスト（`MockMapService`）
  - [ ] デバウンス挙動（スロットルと区別、連打耐性）
  - [ ] レイテンシ/失敗率のシミュレーションでUI状態を検証
- [ ] UI テスト
  - [ ] `ViewState` ごとのスナップショット
  - [ ] ピン選択→詳細シート表示

## 受け入れ条件（抜粋）
- [ ] `USE_MOCK=1`（Debug）でモックデータにより全フローが確認できる
- [ ] アプリ起動で東京駅付近に初期フォーカス、ピンが表示される
- [ ] 地図操作で過剰なAPI呼び出しが発生しない（デバウンス有効）
- [ ] オフライン/エラー時にユーザへ明確な案内とリトライ手段を提供
- [ ] `xcodebuild test` がローカルでグリーン

## 実行コマンド（リポジトリ規約）
- ビルド: `cd RealFightingGame && xcodebuild -scheme RealFightingGame -destination "platform=iOS Simulator,name=iPhone 15" build`
- テスト: `cd RealFightingGame && xcodebuild test -scheme RealFightingGame -destination "platform=iOS Simulator,name=iPhone 15"`

## 備考
- 設計ポリシー・詳細は `docs/state-management.md` を参照
- 仕様整合は `design.md` / `requirements.md`、フォローアップは `tasks.md` を適宜更新

---

## B0: モック先行セットアップ（Battle）
- [ ] `BattleService` プロトコル定義（`Data/Battle/BattleService.swift`）
- [ ] `MockBattleService` 実装（マッチング/行動/結果をローカルで決定、シード可）
- [ ] DI 切替（Debug=モック、Release=リモート予定）

## B1: Battle 画面 MVP（UI/操作）
- [ ] レイアウト
  - [ ] `BattleView.swift` の構造（上: ステータス/中央: アリーナ/下: 操作）
  - [ ] 縦横/小画面対応（Size Class）
- [ ] コンポーネント
  - [ ] HP/ガード/必殺ゲージ表示
  - [ ] 行動ボタン（タップ/長押し）と無効化状態
  - [ ] ターゲット選択UI（単体/全体の切替）
- [ ] アクセシビリティ
  - [ ] VoiceOver ラベル/ヒント
  - [ ] Dynamic Type 対応

## B2: 状態管理/ロジック
- [ ] `BattleViewModel` 追加（`Presentation/ViewModels/BattleViewModel.swift`）
- [ ] `ViewState`/`Action` 設計（待機/入力中/解決中/結果）
- [ ] 行動キュー/クールダウン/ターン or 同期タイマー
- [ ] ダメージ計算・クリティカル・属性相性の関数分離

## B3: 演出/入力フィードバック
- [ ] 攻撃/被弾/スキル演出（アニメ/ハプティクス）
- [ ] 連続入力・キャンセル時のUI/状態反映
- [ ] 成功/失敗/クールダウンの視覚フィードバック

## B4: ネットワーク連携
- [ ] `BattleService` 定義（`Data/Battle/BattleService.swift`）
- [ ] マッチング開始/終了API、ルーム参加/離脱
- [ ] イベント同期（ポーリング or WebSocket）
- [ ] 切断時の再接続/リトライ方針

## B5: テスト（`RealFightingGameTests/Battle/`）
- [ ] `BattleViewModelTests.swift`
  - [ ] ダメージ計算（境界値/属性相性）
  - [ ] クールダウン（時間経過/キャンセル）
  - [ ] 同期待ち/遅延下の挙動
- [ ] UI テスト（主要分岐の表示確認）

## 受け入れ条件（Battle抜粋）
- [ ] 対戦開始→行動選択→結果反映の一連が破綻なく動作
- [ ] レイテンシ/切断発生時でもリトライ・再同期が可能
