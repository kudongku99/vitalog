import SwiftUI
import UIKit

struct BackfillView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine = BackfillEngine()
    @State private var syncState = SyncStateStore.load()
    @State private var isSyncing = false
    @State private var isCharging = true
    @State private var message: String?
    private let expiry = ProvisioningExpiry.date

    private var doneMonths: Int { engine.statuses.reduce(0) { $0 + $1.doneMonths } }
    private var totalMonths: Int { engine.statuses.reduce(0) { $0 + $1.totalMonths } }
    private var uploaded: Int { engine.statuses.reduce(0) { $0 + $1.uploaded } }

    var body: some View {
        NavigationStack {
            List {
                Section(header: SectionHeader("상태")) {
                    LabeledContent("마지막 동기화", value: lastSyncText)
                    LabeledContent("앱 만료일", value: expiryText)
                    if let warning = expiryWarning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.alert)
                    }
                }
                Section(header: SectionHeader("새 기록 동기화")) {
                    if let error = syncState.lastError {
                        Text("오류: \(error)")
                            .font(.footnote)
                            .foregroundStyle(Theme.alert)
                    }
                    Button(isSyncing ? "동기화 중" : "지금 동기화") {
                        Task { await syncNow() }
                    }
                    .disabled(isSyncing)
                }
                if !syncState.recentChanges.isEmpty {
                    Section(header: SectionHeader("최근 변경")) {
                        ForEach(syncState.recentChanges) { change in
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("\(change.at.formatted(date: .abbreviated, time: .shortened)) (\(modeName(change.mode)))")
                                    Spacer()
                                    Text("+\(change.inserted) / -\(change.deleted)")
                                        .monospacedDigit()
                                }
                                Text(change.types.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .font(.footnote)
                        }
                    }
                }
                if let finishedAt = engine.finishedAt, !engine.isRunning {
                    Section(header: SectionHeader("최초 동기화")) {
                        LabeledContent("완료", value: finishedAt.formatted(date: .abbreviated, time: .shortened))
                        DisclosureGroup("다시 실행, 권한 요청") {
                            Button("최초 동기화 다시 실행") { engine.start() }
                            perObjectAccessButton
                        }
                    }
                } else {
                    Section(header: SectionHeader("최초 동기화")) {
                        Text(phaseText)
                        if totalMonths > 0 {
                            ProgressView(value: Double(doneMonths), total: Double(totalMonths))
                            LabeledContent("완료한 구간", value: "\(doneMonths) / \(totalMonths)")
                            LabeledContent("남은 달", value: "\(engine.remainingMonths)")
                            LabeledContent("이번 실행에서 올린 행", value: "\(uploaded)")
                        }
                        if engine.isRunning {
                            Button("정지", role: .destructive) { engine.stop() }
                        } else {
                            Button("최초 동기화 시작") { engine.start() }
                        }
                    }
                    if engine.isRunning && !isCharging {
                        Section {
                            Label("충전기에 꽂고 화면을 켜 둔 채로 두세요. 기기가 잠기면 최초 동기화가 멈추고, 잠금을 풀면 이어서 진행합니다.", systemImage: "bolt.batteryblock")
                                .font(.footnote)
                        }
                    }
                    Section {
                        perObjectAccessButton
                    } footer: {
                        Text("이 두 유형은 항목별로 따로 허용해야 합니다. 허용한 뒤 최초 동기화를 시작하면 함께 올립니다.")
                    }
                    Section(header: SectionHeader("유형별 진행")) {
                        ForEach(engine.statuses) { status in
                            HStack {
                                Text(status.name)
                                    .font(.footnote)
                                Spacer()
                                Text("\(status.doneMonths)/\(status.totalMonths)달")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(status.isDone ? .green : .secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Vitalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.teal, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        LogoMark(size: 24)
                        Text("Vitalog")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("로그아웃") {
                        Task { await signOut() }
                    }
                    .disabled(engine.isRunning)
                }
            }
            .alert("알림", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("확인") { message = nil }
            } message: {
                Text(message ?? "")
            }
            .onAppear {
                UIDevice.current.isBatteryMonitoringEnabled = true
                updateCharging()
            }
            .onChange(of: scenePhase, initial: true) {
                if scenePhase == .active {
                    Task { await syncNow() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncStateDidChange)) { _ in
                syncState = SyncStateStore.load()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
                updateCharging()
            }
        }
    }

    private var perObjectAccessButton: some View {
        Button("복약, 시력 처방 권한 요청") {
            Task { message = await engine.requestPerObjectAccess() }
        }
        .disabled(engine.isRunning)
    }

    private var phaseText: String {
        switch engine.phase {
        case .idle:
            return "최초 동기화를 시작할 수 있습니다."
        case .preparing:
            return "유형별 데이터 기간을 확인하는 중입니다."
        case .running(let month):
            return "\(BackfillProgress.monthFormatter.string(from: month)) 처리 중"
        case .stopped:
            return "정지했습니다. 다시 시작하면 이어서 진행합니다."
        case .waitingForUnlock:
            return "기기가 잠겨 멈췄습니다. 잠금을 풀면 이어서 진행합니다."
        case .paused(let reason):
            return "오류로 멈췄습니다: \(reason)\n다시 시작하면 이어서 진행합니다."
        case .finished:
            return "최초 동기화를 모두 마쳤습니다."
        }
    }

    private var lastSyncText: String {
        guard let date = syncState.lastSyncAt else { return "없음" }
        return "\(date.formatted(date: .abbreviated, time: .shortened)) (\(modeName(syncState.lastMode)))"
    }

    private var expiryText: String {
        guard let expiry else { return "알 수 없음" }
        let date = expiry.formatted(date: .abbreviated, time: .shortened)
        if expiry <= Date() { return "\(date) (만료됨)" }
        return "\(date) (\(ProvisioningExpiry.daysLeft(until: expiry))일 남음)"
    }

    private var expiryWarning: String? {
        guard let expiry else { return nil }
        if expiry <= Date() { return "앱이 만료되었습니다. Mac에서 scripts/reinstall.sh로 덮어 설치하세요." }
        let days = ProvisioningExpiry.daysLeft(until: expiry)
        return days <= 2 ? "\(days)일 안에 만료됩니다. Mac에서 scripts/reinstall.sh로 덮어 설치하세요." : nil
    }

    private func modeName(_ mode: String?) -> String {
        switch mode {
        case "observer": "옵저버"
        case "background_task": "백그라운드 작업"
        default: "수동"
        }
    }

    private func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncState = await SyncService.shared.sync(mode: .manual, budget: 120)
        isSyncing = false
    }

    private func updateCharging() {
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full
    }

    private func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            message = "로그아웃 실패: \(error.localizedDescription)"
        }
    }
}

#Preview {
    BackfillView()
}
