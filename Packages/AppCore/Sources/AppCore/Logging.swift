import Foundation
import os

/// Subsystem for app-level os.Logger instances. Use a per-category logger
/// so users can filter in Console.app: subsystem == com.claudeswarm,
/// category == hook | janitor | library | remote | session.
public enum SwarmLog {
    public static let subsystem = "com.claudeswarm"

    public static let hook = Logger(subsystem: subsystem, category: "hook")
    public static let janitor = Logger(subsystem: subsystem, category: "janitor")
    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let remote = Logger(subsystem: subsystem, category: "remote")
    public static let session = Logger(subsystem: subsystem, category: "session")
    public static let bootstrap = Logger(subsystem: subsystem, category: "bootstrap")
}
