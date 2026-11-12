import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Open ShareMount at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { wanted in
                        LoginItem.setEnabled(wanted)
                        // Only re-read the approval state: re-reading the toggle here
                        // would re-fire onChange and could save the wrong choice.
                        needsApproval = LoginItem.needsApproval
                    }
                if needsApproval {
                    HStack {
                        Text("macOS needs you to allow ShareMount in Login Items.")
                            .foregroundColor(Color(nsColor: .systemOrange))
                        Spacer()
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if !LoginItem.isInstalledCopy {
                    Text("This copy isn’t in /Applications. Run ./install.sh so the installed copy is the one that opens at login.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } footer: {
                Text("With this on, drives set to Keep connected are connected as soon as you log in, and retried every minute while they’re unavailable.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Location") {
                    Text(Bundle.main.bundlePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        launchAtLogin = LoginItem.isEnabled
        needsApproval = LoginItem.needsApproval
    }
}
