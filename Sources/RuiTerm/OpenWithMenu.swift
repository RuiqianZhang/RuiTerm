import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OpenWithMenu: View {
    let entry: BrowserEntry
    let host: SSHHost
    let remotePath: String
    let password: String?
    
    @State private var apps: [URL] = []
    
    var body: some View {
        Menu {
            if apps.isEmpty {
                Text("未找到应用程序")
                    .disabled(true)
            } else {
                ForEach(apps, id: \.self) { appURL in
                    Button {
                        openWithApp(appURL)
                    } label: {
                        Label {
                            Text(appURL.deletingPathExtension().lastPathComponent)
                        } icon: {
                            AppIconView(appURL: appURL)
                        }
                    }
                }
            }
            
            Divider()
            
            Button {
                chooseApp()
            } label: {
                Label("其他...", systemImage: "folder")
            }
        } label: {
            Label("打开方式...", systemImage: "macwindow")
        }
        .onAppear {
            loadApps()
        }
    }
    
    private func loadApps() {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RuiTerm_Probe")
            .appendingPathComponent(entry.name)
        
        try? FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: tempURL.path) {
            try? "".write(to: tempURL, atomically: true, encoding: .utf8)
        }
        
        let foundApps = NSWorkspace.shared.urlsForApplications(toOpen: tempURL)
        
        // Collect unique apps from system discovery
        var uniqueApps: [URL] = []
        var seenBundles: Set<String> = []
        for app in foundApps {
            let bundleID = Bundle(url: app)?.bundleIdentifier ?? app.lastPathComponent
            if !seenBundles.contains(bundleID) {
                seenBundles.insert(bundleID)
                uniqueApps.append(app)
            }
        }
        
        // Well-known text editors to always include if installed (lookup by Bundle ID only)
        let extraEditorBundleIDs = [
            "com.sublimetext.4",
            "com.sublimetext.3",
            "com.sublimetext.2",
            "com.microsoft.VSCode",
            "com.jetbrains.intellij",
            "com.jetbrains.intellij.ce",
            "com.jetbrains.WebStorm",
            "com.jetbrains.pycharm",
            "com.jetbrains.pycharm.ce",
            "com.jetbrains.goland",
            "com.jetbrains.CLion",
            "com.jetbrains.rider",
            "com.jetbrains.PhpStorm",
            "com.jetbrains.rubymine",
            "com.todesktop.230313mzl4w4u92",  // Cursor
            "dev.zed.Zed",
            "com.barebones.bbedit",
            "com.coteditor.CotEditor",
            "com.macromates.TextMate",
            "com.github.atom",
            "abnerworks.Typora",
            "com.apple.dt.Xcode",
        ]
        
        for bundleID in extraEditorBundleIDs {
            if seenBundles.contains(bundleID) { continue }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                seenBundles.insert(bundleID)
                uniqueApps.append(url)
            }
        }
        
        self.apps = uniqueApps.sorted(by: {
            $0.deletingPathExtension().lastPathComponent
            < $1.deletingPathExtension().lastPathComponent
        })
    }
    
    private func openWithApp(_ appURL: URL) {
        let localURL = SFTPFileCoordinator.shared.getLocalURL(hostID: host.id, remotePath: remotePath + "/" + entry.name)
        
        Task {
            let taskID = SFTPTransferManager.shared.startTask(hostID: host.id, type: .download, remotePath: remotePath + "/" + entry.name, localURL: localURL)
            SFTPTransferManager.shared.updateProgress(id: taskID, progress: 0.1)
            
            let success = await SFTPFileCoordinator.shared.downloadAndWatch(
                remotePath: remotePath + "/" + entry.name,
                localURL: localURL,
                host: host,
                password: password
            )
            
            if success {
                SFTPTransferManager.shared.updateProgress(id: taskID, progress: 1.0)
                SFTPTransferManager.shared.completeTask(id: taskID, success: true)
                
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([localURL], withApplicationAt: appURL, configuration: config, completionHandler: nil)
            } else {
                SFTPTransferManager.shared.completeTask(id: taskID, success: false, error: "Download failed")
            }
        }
    }
    
    /// Open a Finder panel for the user to pick any .app
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "选择应用程序"
        panel.message = "选择要打开 \"\(entry.name)\" 的应用程序"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.treatsFilePackagesAsDirectories = false
        
        if panel.runModal() == .OK, let appURL = panel.url {
            openWithApp(appURL)
        }
    }
}

/// Display the actual app icon from the .app bundle
struct AppIconView: View {
    let appURL: URL
    
    var body: some View {
        let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
        Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
