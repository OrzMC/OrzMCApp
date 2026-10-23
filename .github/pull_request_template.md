## 为什么改（问题 / 需求）

<!-- 用户能看到的现象，或要解决的具体问题。避免只写"优化了一下"。 -->

## 改了什么

<!-- 分点写；涉及界面就说是哪个窗口/页面。 -->

## 验证

- [ ] `./scripts/dev/check.sh`（或 `--full`）通过
- [ ] 涉及界面：贴快照（`--snapshot-watch`）或说明怎么看
- [ ] 涉及新文案：`zh-Hans` 已补（`check-localization.py` 会查）
- [ ] 新增 `.swift` 已登记进工程（`check-pbxproj.py` 会查）
- [ ] 涉及协议/网络：`ORZMC_LIVE_*` 真 socket 联调跑过（CI `protocol-live` 也会跑）

## 用户需要做什么

<!-- 需要手动操作（自升级/迁移/改配置）、破坏性变更、已知问题与 workaround。
     发版时这些会进 CHANGELOG 与 Release notes。没有就写"无"。 -->
