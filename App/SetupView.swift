import SwiftUI
import UsageCore

struct SetupView: View {
    @ObservedObject var model: SetupModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up providers")
                .font(.title2.bold())
            Text("Connect the tools gas uses to read your usage.")
                .foregroundStyle(.secondary)
            ForEach(ProviderID.displayOrder, id: \.self) { provider in
                if provider != .claude { Divider() }
                row(provider)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 500, height: 340)
    }

    private func row(_ provider: ProviderID) -> some View {
        let state = model.rows[provider] ?? .readError("Checking…")
        return HStack(alignment: .top, spacing: 12) {
            ProviderIcon(provider: provider, size: 22)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                if state == .ready {
                    Label {
                        Text("\(provider.displayName) — ready")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(.green)
                } else {
                    Text(provider.displayName).font(.headline)
                    Text(statusText(state, provider: provider))
                        .font(.caption)
                        .foregroundStyle(state == .turnedOff ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if state != .ready && state != .turnedOff && !isBusy(state) {
                    Button("Don't use") { model.dontUse(provider) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            Spacer(minLength: 10)
            action(for: state, provider: provider)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func action(for state: SetupState, provider: ProviderID) -> some View {
        switch state {
        case .cliMissing:
            Button("Set up") { model.setUp(provider) }
        case .notLoggedIn, .loginTimedOut:
            Button("Sign in") { model.setUp(provider) }
        case .readError, .installFailed, .binaryNotFound, .loginCheckFailed, .cancelled:
            Button("Try again") { model.tryAgain(provider) }
        case .turnedOff:
            Button("Use") { model.use(provider) }
        case .ready, .rateLimited, .installing, .waitingForSignIn, .readingUsage:
            EmptyView()
        }
    }

    private func isBusy(_ state: SetupState) -> Bool {
        state == .installing || state == .waitingForSignIn || state == .readingUsage
    }

    private func statusText(_ state: SetupState, provider: ProviderID) -> String {
        switch state {
        case .ready: return "Ready"
        case .cliMissing:
            let tool = provider == .claude ? "Claude Code" : "Codex CLI"
            let source = provider == .claude ? "Anthropic's" : "OpenAI's"
            return "\(tool) is not installed. Set up downloads \(source) official installer and opens the sign-in page."
        case .notLoggedIn:
            return "Not logged in. Sign in opens the sign-in page in your browser."
        case .rateLimited(let until):
            return "Server busy — next try at \(until.formatted(date: .omitted, time: .shortened))"
        case .readError(let reason): return "Can't read usage: \(reason)"
        case .turnedOff: return "Not used"
        case .installing: return "Installing…"
        case .waitingForSignIn: return "Waiting for sign-in in your browser…"
        case .readingUsage: return "Reading usage…"
        case .installFailed(let reason): return "Install failed: \(reason)"
        case .binaryNotFound: return "Installed, but gas can't find it"
        case .loginTimedOut: return "Sign-in not finished"
        case .loginCheckFailed: return "Can't check the login"
        case .cancelled: return "Setup stopped"
        }
    }
}
