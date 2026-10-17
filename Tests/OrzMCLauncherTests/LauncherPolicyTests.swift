import XCTest
import OrzMCFoundation
@testable import OrzMCLauncher

private struct TestVersion: MinecraftVersionSummary, Equatable {
    let minecraftVersionId: String
    let minecraftVersionKind: MinecraftVersionKind
}

final class LauncherPolicyTests: XCTestCase {
    func testJavaRuntimeStatus() {
        let policy = JavaRuntimePolicy()

        // 只认引擎托管的 JRE（`<root>/java/<major>`），不再比较系统 JDK 版本高低。
        XCTAssertEqual(policy.status(for: .init(installedMajorVersions: [17], requiredMajorVersion: nil)), .unknown)
        XCTAssertEqual(policy.status(for: .init(installedMajorVersions: [], requiredMajorVersion: 21)), .missing)
        XCTAssertEqual(policy.status(for: .init(installedMajorVersions: [17], requiredMajorVersion: 21)), .missing)
        XCTAssertEqual(policy.status(for: .init(installedMajorVersions: [21], requiredMajorVersion: 21)), .valid)
        XCTAssertEqual(policy.status(for: .init(installedMajorVersions: [17, 21], requiredMajorVersion: 21)), .valid)
    }

    func testVersionListFiltering() {
        let versions = [
            TestVersion(minecraftVersionId: "1.21.1", minecraftVersionKind: .release),
            TestVersion(minecraftVersionId: "25w20a", minecraftVersionKind: .snapshot),
            TestVersion(minecraftVersionId: "1.20.6", minecraftVersionKind: .release)
        ]
        let filter = VersionListFilter()

        XCTAssertEqual(
            filter.filter(versions: versions, searchText: "1.2", releaseOnly: true),
            [
                TestVersion(minecraftVersionId: "1.21.1", minecraftVersionKind: .release),
                TestVersion(minecraftVersionId: "1.20.6", minecraftVersionKind: .release)
            ]
        )
        XCTAssertEqual(
            filter.filter(versions: versions, searchText: "25W", releaseOnly: false),
            [TestVersion(minecraftVersionId: "25w20a", minecraftVersionKind: .snapshot)]
        )
    }

    func testServerProcessRegistryFiltersManagedProcesses() {
        let registry = ServerProcessRegistry()
        let processes: [ManagedServerKey: ProcessIdentifier] = [
            ManagedServerKey(versionId: "1.21.1", softwareId: "vanilla"): ProcessIdentifier("101"),
            ManagedServerKey(versionId: "1.20.6", softwareId: "paper"): ProcessIdentifier("202")
        ]

        let filtered = registry.filtered(processes, runningProcessIds: [ProcessIdentifier("202")])

        XCTAssertEqual(filtered, [
            ManagedServerKey(versionId: "1.20.6", softwareId: "paper"): ProcessIdentifier("202")
        ])
        XCTAssertTrue(registry.hasManagedRunningServers(filtered))
        XCTAssertEqual(registry.processIds(from: filtered), [ProcessIdentifier("202")])
        XCTAssertFalse(registry.hasManagedRunningServers([:]))
    }

    func testManagedServerProcessStoreTracksAndRefreshesProcesses() {
        let vanillaKey = ManagedServerKey(versionId: "1.21.1", softwareId: "vanilla")
        let paperKey = ManagedServerKey(versionId: "1.20.6", softwareId: "paper")
        var store = ManagedServerProcessStore()

        store.record(ProcessIdentifier("101"), for: vanillaKey)
        store.record(ProcessIdentifier("202"), for: paperKey)

        XCTAssertTrue(store.hasManagedRunningServers)
        XCTAssertEqual(store.processId(for: vanillaKey), ProcessIdentifier("101"))

        store.refresh(runningProcessIds: [ProcessIdentifier("202")])

        XCTAssertNil(store.processId(for: vanillaKey))
        XCTAssertEqual(store.processId(for: paperKey), ProcessIdentifier("202"))

        store.removeProcess(for: paperKey)

        XCTAssertFalse(store.hasManagedRunningServers)
    }
}
