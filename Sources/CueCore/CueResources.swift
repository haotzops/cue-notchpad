import Foundation

enum CueResources {
    static let bundle: Bundle = {
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()

        if executableDirectory.lastPathComponent == "MacOS" {
            let appURL = executableDirectory
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            if appURL.pathExtension == "app", let appBundle = Bundle(url: appURL) {
                return appBundle
            }
        }

        if Bundle.main.bundleURL.pathExtension == "app" {
            return .main
        }

        for name in ["CueNotchpad_CueCore.bundle", "CueNotchpad_CueCore.resources"] {
            if let bundle = Bundle(url: executableDirectory.appendingPathComponent(name)) {
                return bundle
            }
        }

        return .main
    }()
}
