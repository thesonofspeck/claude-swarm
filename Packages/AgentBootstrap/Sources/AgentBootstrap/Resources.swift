import Foundation

public enum BootstrapResources {
    public static func notifyScript() throws -> URL {
        guard let url = Bundle.module.url(
            forResource: "notify",
            withExtension: "sh",
            subdirectory: "Resources/Hooks"
        ) else {
            throw InstallerError.missingResource("notify.sh")
        }
        return url
    }

    public static func agentTemplate(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "md",
            subdirectory: "Resources/Agents"
        ) else {
            throw InstallerError.missingResource("\(name).md")
        }
        return url
    }
}
