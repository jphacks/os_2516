import SwiftUI

struct BattleStageListView: View {
    @StateObject private var viewModel: BattleStageListViewModel
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var activeSessionID: String? = nil
    @State private var activeService: BattleService? = nil
    @State private var showBattleSheet: Bool = false
    @State private var battleSessionIDForBattleView: String? = nil
    @State private var battleServiceForBattleView: BattleService? = nil

    init(mapService: MapService, locationService: LocationService? = nil) {
        _viewModel = StateObject(wrappedValue: BattleStageListViewModel(mapService: mapService,
                                                                        locationService: locationService))
    }

    var body: some View {
        List {
            switch viewModel.stagesState {
            case .idle, .loading:
                loadingSection
            case .empty:
                emptySection
            case .failure(let error):
                errorSection(error)
            case .success(let stages):
                stagesSection(stages)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("ステージ")
        .task { triggerInitialLoadIfNeeded() }
        .refreshable { viewModel.loadStages(force: true) }
        .sheet(isPresented: Binding(get: { activeSessionID != nil }, set: { new in
            if !new {
                activeSessionID = nil
                activeService = nil
            }
        })) {
            if let sessionId = activeSessionID {
                if let service = activeService {
                    WaitingForOpponentView(sessionID: sessionId, service: service)
                } else {
                    Text("セッションを開始できませんでした")
                }
            } else {
                // defensively show empty view if sessionId became nil
                EmptyView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .waitingDidResolve)) { notif in
            guard let sid = notif.object as? String else { return }
            if sid == activeSessionID {
                activeSessionID = nil
                if let svc = activeService {
                    battleSessionIDForBattleView = sid
                    battleServiceForBattleView = svc
                    showBattleSheet = true
                }
            }
        }
        .sheet(isPresented: $showBattleSheet, onDismiss: {
            battleSessionIDForBattleView = nil
            battleServiceForBattleView = nil
            showBattleSheet = false
        }) {
            if let sid = battleSessionIDForBattleView, let service = battleServiceForBattleView {
                BattleView(sessionID: sid, service: service, motionService: container.motionService, locationService: container.locationService)
            } else {
                Text("セッションを開始できませんでした")
            }
        }
    }

    private func triggerInitialLoadIfNeeded() {
        if case .idle = viewModel.stagesState {
            viewModel.loadStages()
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        Section {
            HStack {
                Spacer(minLength: 0)
                ProgressView("読み込み中…")
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var emptySection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("周辺にステージが見つかりませんでした")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func errorSection(_ error: Error) -> some View {
        Section {
            VStack(spacing: 12) {
                Text("ステージ情報の取得に失敗しました")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("再読み込み") {
                    viewModel.loadStages(force: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func stagesSection(_ stages: [BattleStageListViewModel.Stage]) -> some View {
        Section("付近のステージ") {
            ForEach(stages, id: \.id) { stage in
                let service = battleService(for: stage)
                Button {
                    // create session then navigate to waiting view if needed
                    Task {
                        do {
                            _ = try await service.join(sessionID: stage.id)
                            // retrieve session id from service
                            let sid = await service.currentSessionId()
                            // check opponent via protocol method
                            if await service.knownOpponentId() != nil {
                                battleSessionIDForBattleView = sid
                                battleServiceForBattleView = service
                                showBattleSheet = true
                                return
                            }
                            // otherwise show waiting UI sheet
                            activeSessionID = sid
                            activeService = service
                        } catch {
                            // ignore for now - real app should show error
                        }
                    }
                } label: {
                    stageRow(stage)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stageRow(_ stage: BattleStageListViewModel.Stage) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stage.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                if let text = distanceText(for: stage) {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("参加")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.name) に参加")
        .accessibilityHint("バトル画面へ移動します")
    }

    private func distanceText(for stage: BattleStageListViewModel.Stage) -> String? {
        guard let meters = stage.distanceMeters else { return nil }
        if meters >= 1000 {
            return String(format: "約 %.1f km", meters / 1000)
        } else {
            return "約 \(Int(meters)) m"
        }
    }
}

private extension BattleStageListView {
    func battleService(for stage: BattleStageListViewModel.Stage) -> BattleService {
        if container.useMock {
            return ServiceFactory.makeBattleService()
        }

        if let token = authViewModel.session?.token {
            return RemoteBattleService(baseURL: container.apiBaseURL, token: token)
        }

        return ServiceFactory.makeBattleService()
    }
}

// programmatic navigation handling: when WaitingForOpponent posts that it resolved, navigate to BattleView
extension BattleStageListView {
    // Use NavigationStack's new .navigationDestination via environment when needed - keep simple: observe notification and push
}

#if DEBUG
struct BattleStageListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BattleStageListView(mapService: MockMapService(mode: .success, latencyMs: 0, failureRate: 0, useFixture: true),
                                locationService: MockLocationService())
        }
        .environmentObject(AppContainer(useMock: true))
        .environmentObject(AuthViewModel())
    }
}
#endif
