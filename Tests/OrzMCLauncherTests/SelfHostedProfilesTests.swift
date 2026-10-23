import Foundation
import XCTest

@testable import OrzMCLauncher

/// 自建服务器档案：`upsert` / `remove` / 选中规则，以及旧格式迁移。
final class SelfHostedProfilesTests: XCTestCase {

    private func profile(_ name: String, host: String = "127.0.0.1") -> SelfHostedServerProfile {
        SelfHostedServerProfile(name: name, host: host)
    }

    func testUpsertAppendsAndSelects() {
        var profiles = SelfHostedProfiles()
        let first = profile("A")
        profiles.upsert(first)
        XCTAssertEqual(profiles.servers.count, 1)
        XCTAssertEqual(profiles.selectedID, first.id)

        let second = profile("B")
        profiles.upsert(second)
        XCTAssertEqual(profiles.servers.map(\.name), ["A", "B"])
        XCTAssertEqual(profiles.selected?.name, "B")
    }

    func testUpsertReplacesSameID() {
        var profiles = SelfHostedProfiles()
        var item = profile("A")
        profiles.upsert(item)
        item.name = "A renamed"
        profiles.upsert(item)
        XCTAssertEqual(profiles.servers.count, 1)
        XCTAssertEqual(profiles.servers.first?.name, "A renamed")
    }

    func testRemoveFallsBackToFirstRemaining() {
        var profiles = SelfHostedProfiles()
        let first = profile("A")
        let second = profile("B")
        profiles.upsert(first)
        profiles.upsert(second)
        profiles.remove(id: second.id)
        XCTAssertEqual(profiles.servers.map(\.name), ["A"])
        XCTAssertEqual(profiles.selectedID, first.id, "删掉当前选中的要落回第一台")
    }

    func testRemoveLastLeavesNothingSelected() {
        var profiles = SelfHostedProfiles()
        let only = profile("A")
        profiles.upsert(only)
        profiles.remove(id: only.id)
        XCTAssertTrue(profiles.servers.isEmpty)
        XCTAssertNil(profiles.selected)
    }

    func testDisplayNameAndAddress() {
        var item = profile("家里的", host: "mc.example.com")
        XCTAssertEqual(item.displayName, "家里的")
        XCTAssertEqual(item.address, "mc.example.com", "默认端口不显示")

        item.port = 25566
        XCTAssertEqual(item.address, "mc.example.com:25566")

        item.name = "   "
        XCTAssertEqual(item.displayName, "mc.example.com", "没填名字就用地址")
    }

    // MARK: - 存储与迁移

    private func makeDefaults() -> UserDefaults {
        let suite = "SelfHostedProfilesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testSaveAndLoadRoundTrip() {
        let defaults = makeDefaults()
        var profiles = SelfHostedProfiles()
        profiles.upsert(profile("A", host: "mc.example.com"))
        SelfHostedProfilesStore.save(profiles, defaults: defaults)
        XCTAssertEqual(SelfHostedProfilesStore.load(defaults: defaults), profiles)
    }

    /// 老版本只存了一台（没有 id 字段）；升级后应当变成一台档案，旧键被清掉。
    func testMigratesLegacySingleProfile() {
        let defaults = makeDefaults()
        let legacy = #"{"name":"本地","host":"127.0.0.1","port":25565,"rconPort":25575,"rconEnabled":false}"#
        defaults.set(Data(legacy.utf8), forKey: SelfHostedProfilesStore.legacyKey)

        let loaded = SelfHostedProfilesStore.load(defaults: defaults)
        XCTAssertEqual(loaded.servers.count, 1)
        XCTAssertEqual(loaded.servers.first?.host, "127.0.0.1")
        XCTAssertEqual(loaded.servers.first?.name, "本地")
        XCTAssertNil(defaults.data(forKey: SelfHostedProfilesStore.legacyKey), "迁移后旧键要删掉")
        XCTAssertNotNil(defaults.data(forKey: SelfHostedProfilesStore.storageKey))
    }

    /// 旧记录里地址为空（用户从没配过）→ 不迁移出空档案。
    func testDoesNotMigrateEmptyLegacyProfile() {
        let defaults = makeDefaults()
        let legacy = #"{"name":"","host":"","port":25565,"rconPort":25575,"rconEnabled":false}"#
        defaults.set(Data(legacy.utf8), forKey: SelfHostedProfilesStore.legacyKey)
        XCTAssertTrue(SelfHostedProfilesStore.load(defaults: defaults).servers.isEmpty)
    }

    func testCorruptLegacyIsIgnored() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: SelfHostedProfilesStore.legacyKey)
        XCTAssertTrue(SelfHostedProfilesStore.load(defaults: defaults).servers.isEmpty)
    }
}
