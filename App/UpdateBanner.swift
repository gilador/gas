import SwiftUI
import UsageCore

struct UpdateBanner: View {
    @ObservedObject var updates: UpdateModel

    var body: some View {
        switch updates.phase {
        case .available(let release):
            HStack {
                Text("gas \(release.version.description) is available").font(.callout.bold())
                Spacer()
                Button("Later") { updates.later() }
                Button("Update") { Task { await updates.update() } }
            }
        case .downloading(let release):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading gas \(release.version.description)…").font(.callout)
            }
        case .failed(_, let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("Update failed: \(message)").font(.callout).foregroundStyle(.orange)
                HStack {
                    Button("Open release page") { updates.openReleasePage() }
                    Spacer()
                    Button("Try again") { Task { await updates.update() } }
                }
            }
        case .idle, .checking, .upToDate, .checkFailed:
            EmptyView()
        }
    }
}
