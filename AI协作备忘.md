# AI 协作备忘（背单词 / MemorizeSpanish）

本文记录与 Eve 合作时的约定，便于后续会话保持一致。

## 1. 有代码改动时在模拟器里跑一遍

- **期望**：每次对 **MemorizeSpanish（iOS）工程** 做了实质修改后，在 **模拟器** 上 **编译、安装并启动** App，便于直接看到最新界面与交互。
- **Cursor**：同一约定写在 **`.cursor/rules/memorize-spanish-collaboration.mdc`**（`alwaysApply: true`），助手在**有实质工程改动时应在当轮自动执行** build + install + launch，无需你再单独说「跑模拟器」。
- **适用**：Swift / 资源 / `project.pbxproj` 等会影响 App 行为的变更。
- **可跳过**：仅改文档、与本 App 无关的文件、或纯说明性回复且无工程变更时，不必强行跑模拟器。

### 推荐命令（本机已验证可用）

工程路径：

`MemorizeSpanish/MemorizeSpanish.xcodeproj`

为避免工程在「桌面」路径下偶发的 **CodeSign / resource fork** 问题，建议 **DerivedData 放在 `/tmp`**：

```bash
cd "/Users/eve/Desktop/桌面 - Eve的MacBook Pro/背单词/MemorizeSpanish"

xcrun simctl boot "iPhone 17" 2>/dev/null || true
open -a Simulator

xcodebuild -scheme MemorizeSpanish \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  -derivedDataPath "/tmp/MemorizeSpanishDerivedData" \
  build

UDID=$(xcrun simctl list devices booted | grep -oE '[A-F0-9-]{36}' | head -1)
xcrun simctl install "$UDID" \
  "/tmp/MemorizeSpanishDerivedData/Build/Products/Debug-iphonesimulator/MemorizeSpanish.app"
xcrun simctl launch "$UDID" com.example.MemorizeSpanish
```

- **Scheme**：`MemorizeSpanish`
- **Bundle ID**：`com.example.MemorizeSpanish`
- 模拟器名称若变更，将 `iPhone 17` / `booted` 的 UDID 逻辑按 `xcrun simctl list devices` 调整即可。

## 2. 其他（可选补充）

- 用户偏好 **中文** 回复。
- 内置教材词表为 **学习用示例**，与商业教材全书词表一致时需自行整理版权合规数据或通过 JSON 导入补充。

---

*文件由协作约定整理，可随项目演进继续增删条目。*
