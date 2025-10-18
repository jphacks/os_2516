# iOS アプリ開発タスク一覧

目的: SwiftUI + MVVM 構成でMap/Battle機能をモック先行で実装し、API準備後は最小差分で切替可能にする。

## P0: MVP 優先タスク（今スプリントで完了）
- [ ] 共通/モック基盤
  - [ ] `MapService` 定義（`RealFightingGame/Data/Map/MapService.swift`）
  - [ ] `MockMapService` 実装（`mode/latencyMs` 付き）
  - [ ] DI 切替（`#if DEBUG` または `USE_MOCK=1`）
  - [ ] （任意）`Resources/Fixtures/pins.json` を用意
- [ ] 通信（WebSocket）最小
  - [ ] `WebSocketClient`（`RealFightingGame/Data/Network/WebSocketClient.swift`）接続/送受信/再接続（1s→2s→4s）
  - [ ] 心拍 `ping` 送信（例: 15s 間隔）と `pong` 検知で接続健全性判定
  - [ ] DTO 定義（`RealFightingGame/Data/Battle/Events.swift`）：`join`/`action`/`state`/`ping`
  - [ ] `BattleService` 最小実装でWS経由の `join`・`action`・`state` を仲介
  - [ ] ログ最小化（OSLog）とデバッグトグル
- [ ] Map（表示/状態/参加導線）
  - [ ] `Map(position:content:)` と `Binding<MapCameraPosition>` の同期（`MapView.swift`）
  - [ ] `Marker` でピン表示（`MapViewModel.destinations`）
  - [ ] `ViewState<[MapPin]>` による `loading/success/failure` 切替
  - [ ] `loadPins()` 実装（`async/await`、キャンセル安全）
  - [ ] リージョン変更のデバウンス（目安 500ms）
  - [ ] 位置権限/現在地表示（`Info.plist` 文言追加）
  - [ ] `LocationService` プロトコル＋`MockLocationService`（東京駅近傍を返す）
  - [ ] 参加可能距離の判定＋「参加」ボタン表示（例: 100m 以内）
  - [ ] 参加ボタン→`BattleView` へ遷移（同時に `WebSocketClient` へ `join`）
- [ ] Battle（最小フロー）
  - [ ] `BattleView` 最小レイアウト（HP/行動ボタン）
  - [ ] `BattleViewModel`（攻撃1種・HP減算・ターン進行の最小実装）
  - [ ] `MockBattleService`（ローカル進行）＋`BattleService`（WS受信 `state` を反映）
  - [ ] 結果画面（勝敗/再戦ボタン）
- [ ] テスト
  - [ ] `MapViewModelTests`（success/empty/error/キャンセル）
  - [ ] `BattleViewModelTests`（ダメージ計算と進行）
  - [ ] `WebSocketClientTests`（再接続バックオフ、`join/action/state/ping` マッピング）
  - [ ] 簡易スナップショット or UITest（主要分岐）

### MVP 受け入れ条件
- [ ] `USE_MOCK=1` で起動し、近畿大学付近に初期フォーカス＋ピン表示
- [ ] 現在地が参加距離内になると「参加」ボタンが表示される
- [ ] 2台（実機またはシミュレータ）で同一セッションに `join` できる
- [ ] 片方の `action` がもう一方の画面状態に反映される（`state` 受信）
- [ ] 参加→バトル→結果表示まで一連の流れが成立
- [ ] エラー時にメッセージとリトライが機能
- [ ] `xcodebuild test` がグリーン

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

---

## P1: 計画同期タスク（plan.md 反映・MVP後）

### 認証基盤
- [ ] Sign in with Apple 実装（`AuthenticationServices`）
- [ ] トークン取得・保存（Keychain）・更新ポリシー
- [ ] API/WS へのトークン添付、失効時の再認証フロー

### ネットワーク/WS 基盤
- [ ] `NetworkService` プロトコルと `APIClient` 強化（タイムアウト/リトライ/バックオフ/ログ）
- [ ] WebSocket クライアント（接続/送受信/再接続・バックオフ/心拍）
- [ ] `game-event` / `result` の DTO とスキーマ定義（送受マッピング）

### センサー・測位
- [ ] CoreMotion + Pedometer で走行判定（まずはモック→実機検証）
- [ ] Nearby Interaction（UWB）検証コードと権限ハンドリング
- [ ] 非対応端末向け fallback（GPS + コンパス）調査と実装
- [ ] 位置権限のフロー・エラーハンドリング見直し

### マップ/参加導線の強化
- [ ] 参加可能距離の閾値確定（例: 100m）とテレメトリ取得
- [ ] 参加ボタンの状態管理（距離外/権限未許可/通信エラー）
- [ ] レーダー UI プロトタイプ（Battle への誘導）

### リザルト/フロー
- [ ] `/result` DTO と API 連携（結果取得・再戦導線）
- [ ] End フラグ送信失敗時のリトライポリシー

### 演出
- [ ] ハプティクスプリセット（攻撃/被弾/詠唱完了）の適用
- [ ] サウンド再生インフラ（`AVAudioSession` 設定、効果音の再生）

### ログ/テスト強化
- [ ] デバッグ用イベントログ保存（OSLog/ファイル）
- [ ] `NetworkService` / WebSocket のテストダブルと結合テスト
- [ ] 距離計算・認証・権限フローのユニット/UITest 追加
