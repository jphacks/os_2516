# Requirements Document

## Introduction

リアル版格闘ゲームは、UWB 技術を活用して現実空間で行う位置情報ベースの対戦ゲームです。プレイヤーは魔法少女として、実際に移動しながら相手と戦闘を行います。スマートフォンは補助的な役割を担い、攻撃判定、HP 管理、魔素回収などのゲームメカニクスを提供します。

## Requirements

### Requirement 1

**User Story:** プレイヤーとして、相手の現在位置を把握したいので、戦略的な攻撃や回避行動を取ることができる

#### Acceptance Criteria

1. WHEN ゲームが開始されたとき THEN システムは UWB 技術を使用して相手プレイヤーの位置を検出する SHALL
2. WHEN 相手プレイヤーが移動したとき THEN システムは リアルタイムで位置情報を更新する SHALL
3. IF UWB 技術が利用できない場合 THEN システムは 代替の位置検出方法を使用する SHALL
4. WHEN 位置情報が取得できたとき THEN システムは プレイヤーに相手の方向と距離を表示する SHALL

### Requirement 2

**User Story:** プレイヤーとして、攻撃を実行したいので、相手にダメージを与えることができる

#### Acceptance Criteria

1. WHEN プレイヤーが攻撃アクションを実行したとき THEN システムは スマートフォンの向きと相手の位置から攻撃判定を行う SHALL
2. WHEN 攻撃が命中したとき THEN システムは 相手の HP を減少させる SHALL
3. WHEN 攻撃時に詠唱が必要なとき THEN システムは プレイヤーに詠唱を促す SHALL
4. WHEN 攻撃判定が複雑な場合 THEN システムは サーバーに判定処理を委託する SHALL
5. WHEN 攻撃が実行されたとき THEN システムは 振動でプレイヤーに攻撃実行を通知する SHALL

### Requirement 3

**User Story:** プレイヤーとして、魔素を回収したいので、継続的に攻撃を行うことができる

#### Acceptance Criteria

1. WHEN プレイヤーが走って移動したとき THEN システムは 移動距離に応じて魔素を回収する SHALL
2. WHEN 魔素が回収されたとき THEN システムは プレイヤーの魔素量を増加させる SHALL
3. WHEN 散歩モードで移動したとき THEN システムは 薄い魔素を回収する SHALL
4. WHEN 魔素量が変化したとき THEN システムは プレイヤーに現在の魔素量を表示する SHALL
5. WHEN 攻撃に必要な魔素が不足しているとき THEN システムは 攻撃を実行できないことを通知する SHALL

### Requirement 4

**User Story:** プレイヤーとして、自分と相手の HP を把握したいので、戦闘状況を理解できる

#### Acceptance Criteria

1. WHEN ゲームが開始されたとき THEN システムは 両プレイヤーの HP を初期値に設定する SHALL
2. WHEN ダメージを受けたとき THEN システムは HP を減少させ振動で通知する SHALL
3. WHEN HP が変化したとき THEN システムは リアルタイムで両プレイヤーの HP 状況を表示する SHALL
4. WHEN プレイヤーの HP が 0 になったとき THEN システムは ゲーム終了を宣言する SHALL

### Requirement 5

**User Story:** プレイヤーとして、公正な対戦を行いたいので、裁定システムによる管理を受けたい

#### Acceptance Criteria

1. WHEN 知らないプレイヤー同士が対戦するとき THEN システムは 裁定人機能を提供する SHALL
2. WHEN ルール違反や不正行為が検出されたとき THEN システムは 適切な処罰を実行する SHALL
3. WHEN 対戦が開始されるとき THEN システムは 妖精協会のルールを両プレイヤーに提示する SHALL
4. WHEN 判定に争いが生じたとき THEN システムは 自動的に裁定を行う SHALL

### Requirement 6

**User Story:** プレイヤーとして、iOS デバイスでゲームを楽しみたいので、ネイティブアプリとして動作する

#### Acceptance Criteria

1. WHEN アプリが起動されたとき THEN システムは iOS 固有の機能を活用する SHALL
2. WHEN 位置情報が必要なとき THEN システムは Core Location を使用する SHALL
3. WHEN 振動通知が必要なとき THEN システムは Haptic Feedback を使用する SHALL
4. WHEN リアルタイム通信が必要なとき THEN システムは サーバーとの通信を確立する SHALL

### Requirement 7

**User Story:** 開発者として、サーバーサイドの処理を効率的に実装したいので、適切な技術スタックを使用する

#### Acceptance Criteria

1. WHEN サーバーをデプロイするとき THEN システムは Cloudflare Workers または GCP Cloud Run を使用する SHALL
2. WHEN サーバーサイドロジックを実装するとき THEN システムは Hono または Go を使用する SHALL
3. WHEN リアルタイム通信が必要なとき THEN システムは WebSocket または類似技術を使用する SHALL
4. WHEN 攻撃判定処理を行うとき THEN システムは サーバーサイドで計算を実行する SHALL
