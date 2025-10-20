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
        // Programmatic navigation: use NavigationLink with isActive to push views on NavigationStack
        .background(
            // invisible navigation links
            Group {
                NavigationLink(destination: AnyView(
                    Group {
                        if let sid = activeSessionID, let svc = activeService {
                            WaitingForOpponentView(sessionID: sid, service: svc)
                        } else {
                            EmptyView()
                        }
                    }
                ), isActive: Binding(get: { activeSessionID != nil && battleSessionIDForBattleView == nil && !showBattleSheet }, set: { new in
                    if !new {
                        // if nav is popped, clear waiting state
                        activeSessionID = nil
                        activeService = nil
                    }
                })) {
                    EmptyView()
                }

                NavigationLink(destination: AnyView(
                    Group {
                        if let sid = battleSessionIDForBattleView, let svc = battleServiceForBattleView {
                            BattleView(sessionID: sid, service: svc, motionService: container.motionService, locationService: container.locationService)
                        } else {
                            EmptyView()
                        }
                    }
                ), isActive: $showBattleSheet) {
                    EmptyView()
                }
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .waitingDidResolve)) { notif in
            print("[BattleStageListView] received waitingDidResolve notification object=\(String(describing: notif.object)) activeSessionID=\(String(describing: activeSessionID))")
            guard let sid = notif.object as? String else { return }
            print("[BattleStageListView] waitingDidResolve sid=\(sid)")
            if sid == activeSessionID {
                // when waiting resolves, clear waiting state and push battle
                if let svc = activeService {
                    battleSessionIDForBattleView = sid
                    battleServiceForBattleView = svc
                    // clear the activeSessionID to indicate waiting cleared
                    print("[BattleStageListView] transitioning to battle for sid=\(sid), clearing activeSessionID")
                    activeSessionID = nil
                    activeService = nil
                    showBattleSheet = true
                }
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
                    // immediately show waiting UI, then perform join in background
                    activeSessionID = stage.id
                    print("[BattleStageListView] activeSessionID set to initial stage id=\(String(describing: activeSessionID))")
                    activeService = service

                    Task {
                        do {
                            _ = try await service.join(sessionID: stage.id)
                            // retrieve session id from service
                            let sid = await service.currentSessionId()
                            print("[BattleStageListView] join completed, service.currentSessionId=\(String(describing: sid))")
                            // if opponent already present, go straight to battle
                            if await service.knownOpponentId() != nil {
                                print("[BattleStageListView] opponent already present -> navigating to battle")
                                battleSessionIDForBattleView = sid
                                battleServiceForBattleView = service
                                // clear waiting indicator and push battle
                                activeSessionID = nil
                                activeService = nil
                                showBattleSheet = true
                                return
                            }

                            // Development shortcut: allow skipping waiting screen when flag enabled
                            if AppConfiguration.devSkipWaiting {
                                print("[BattleStageListView] DEV_SKIP_WAITING enabled -> skipping waiting and navigating to battle")
                                battleSessionIDForBattleView = sid
                                battleServiceForBattleView = service
                                activeSessionID = nil
                                activeService = nil
                                showBattleSheet = true
                                return
                            }

                            // otherwise update waiting sheet to show actual session id
                            activeSessionID = sid
                            print("[BattleStageListView] activeSessionID updated to real session id=\(String(describing: activeSessionID))")
                        } catch {
                            // on failure, clear waiting UI and (optionally) show error
                            print("[BattleStageListView] join failed: \(error). clearing waiting")
                            activeSessionID = nil
                            activeService = nil
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
