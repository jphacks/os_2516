**状態管理設計（iOS/SwiftUI, MVVM）**

- 目的
  - 画面ごとのUI状態とドメイン状態を分離し、API呼び出しや非同期処理を安全・可読・テスト容易にする。

- 基本方針
  - アーキテクチャ: MVVM（View = 表示、ViewModel = 状態とロジック、Model/Service = データアクセス）
  - データフロー: 単方向（Action → ViewModel → Service/API → ViewModel更新 → View反映）
  - スレッド: 画面更新は `@MainActor`、I/Oはバックグラウンド。`async/await` を基本、必要に応じてCombine。

- 状態の粒度
  - Viewローカル: `@State` と `@Binding`（一時的入力やトグルなど）
  - 画面単位共有: `ObservableObject` + `@StateObject`（各画面のViewModel）
  - 画面間共有: `@EnvironmentObject` あるいはDIで注入（セッション、ユーザ、設定など）
  - グローバル化は最小限に。必要階層へ明示的に渡す。

- ViewModelの標準形
  - 役割: API呼び出し、入力検証、ローディング/エラー管理、結果の正規化
  - 公開状態: `@Published` でUIが必要とする最小集合のみ
  - 代表パターン（ViewState集約）
    ```swift
    enum ViewState<Data> {
      case idle
      case loading
      case success(Data)
      case failure(Error)
    }
    ```
  - 例（Map画面の骨子）
    ```swift
    import MapKit
    @MainActor
    final class MapViewModel: ObservableObject {
      @Published var region: MKCoordinateRegion = .defaultRegion
      @Published var pins: [MapPin] = []
      @Published var state: ViewState<[MapPin]> = .idle
      private let service: MapService
      private var task: Task<Void, Never>?

      init(service: MapService) { self.service = service }

      func loadPins() {
        task?.cancel()
        state = .loading
        task = Task {
          do {
            let result = try await service.fetchPins(center: region.center)
            guard !Task.isCancelled else { return }
            self.pins = result
            self.state = .success(result)
          } catch {
            guard !Task.isCancelled else { return }
            self.state = .failure(error)
          }
        }
      }
    }
    ```

- API層と依存性注入
  - プロトコルで抽象化しテスト容易性を確保
    ```swift
    protocol MapService {
      func fetchPins(center: CLLocationCoordinate2D) async throws -> [MapPin]
    }
    ```
  - 実装は `real-fighting-server` に合わせてHTTPクライアント（`URLSession`）やキャッシュ層を用意
  - ViewModelへはコンストラクタ注入（画面エントリで組み立て）

- エラー/ローディング表現（View側）
  - `switch state` で分岐し、`ProgressView`・リトライボタン・エラーメッセージを表示
  - 軽量ケースは `@Published var isLoading` 等でも可だが、状態が増える場合は `ViewState` 集約が有効

- 非同期・キャンセル
  - `Task {}` + `task?.cancel()` で最新要求のみ有効化（タイプアヘッド等に有効）
  - 位置更新に応じて再取得する場合は、リージョン変更をデバウンスしてAPI呼び出しを抑制

- キャッシュ/永続化（必要に応じて）
  - 短期: メモリキャッシュ（座標キー＋TTL）
  - 中長期: `FileManager`/`URLCache`、将来はSQLite/CoreDataなどに拡張

- テスト戦略
  - ViewModel: モック `MapService` で成功/失敗・キャンセルを網羅（`RealFightingGameTests/`）
  - UI: スナップショット/UITestで状態ごとの表示確認
  - Go側: ビジネスルールは `real-fighting-server` でテーブル駆動テスト

- 命名・配置（本リポジトリ方針）
  - ViewModel: `RealFightingGame/Presentation/ViewModels/`（例: `MapViewModel.swift`）
  - View: `RealFightingGame/Presentation/Views/...`
  - Service/Repository（iOS側再利用コード）: `RealFightingGame/Domain` または `RealFightingGame/Data` 等で分離
  - 仕様・計画: ルートの `design.md` / `requirements.md` / `tasks.md`、図は `docs/`

- Map画面のポイント（iOS 17以降）
  - `Map(position:content:)` + `MapCameraPosition` を使用し、`region` は ViewModel に保持
  - ピンは `Marker` とし、API結果（`pins`）反映で更新

