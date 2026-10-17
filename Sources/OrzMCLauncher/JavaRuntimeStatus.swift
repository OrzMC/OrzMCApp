/// 托管 JRE 状态（`docs/spec/behavior.md` B5）。
///
/// GUI 与 CLI 一样**只用引擎托管的 JRE**（`<root>/java/<major>`，缺失时启动自动安装），
/// 因此判定依据是「该 major 的托管运行时是否已就位」，而不是系统里装了哪个 JDK。
public enum JavaRuntimeStatus: Equatable, Sendable {
    /// 还没选中版本 / 不知道需要哪个 major。
    case unknown
    /// 所需 major 的托管运行时已就位。
    case valid
    /// 所需 major 的托管运行时未安装（启动时会自动下载安装）。
    case missing
}

public struct JavaRuntimeRequirement: Equatable, Sendable {
    public let installedMajorVersions: [Int]
    public let requiredMajorVersion: Int?

    public init(installedMajorVersions: [Int], requiredMajorVersion: Int?) {
        self.installedMajorVersions = installedMajorVersions
        self.requiredMajorVersion = requiredMajorVersion
    }
}

public struct JavaRuntimePolicy: Sendable {
    public init() {}

    public func status(for requirement: JavaRuntimeRequirement) -> JavaRuntimeStatus {
        guard let requiredMajorVersion = requirement.requiredMajorVersion
        else {
            return .unknown
        }
        return requirement.installedMajorVersions.contains(requiredMajorVersion) ? .valid : .missing
    }
}
