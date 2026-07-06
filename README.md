# Ñote（MemorizeSpanish）

个人使用的 **西班牙语背单词** iOS 应用：收录单词、按间隔重复复习、支持教材/DELE 词表导入、动词变位与备注。配套可选的桌面词库同步小服务。

> 内置教材词表为学习用示例，与商业教材全书不一致；扩展词库请自行整理 JSON 并注意版权。

## 功能

- **学习**：今日复习队列、卡片翻面背诵（忘了 / 模糊 / 记得）、7 日复习预览、本地每日提醒
- **词库**：浏览、搜索、编辑；词条含西语、中文、词性、备注、复习进度
- **导入**：手工添加（联网自动译中）、内置走西/现西示例单元、DELE A1–B2 词包、JSON 词表导入
- **西语**：背诵页展示备注；动词各时态变位（规则 + 不规则 JSON）
- **备份**：设置内导出/恢复学习库 JSON（词条 + 复习状态 + 学习计划）
- **内测**：TestFlight 分发 + App 内邀请码识别测试渠道（见 `TesterAccessService`）

## 仓库结构

```
MemorizeSpanish/     # iOS 工程（SwiftUI + SwiftData）
DeskManualSync/      # 可选：浏览器录词 + API，供 App 拉取合并
MemorizeSpanish/Scripts/   # 词表构建、从 .xcappdata 导出备份等脚本
```

## 本地运行（iOS）

**要求**：macOS、完整 Xcode（非仅 Command Line Tools）、iOS 模拟器或真机。

1. 打开 `MemorizeSpanish/MemorizeSpanish.xcodeproj`
2. 选择 Scheme `MemorizeSpanish`，目标为模拟器或已连接的真机
3. **⌘R** 运行

真机调试需在 Xcode **Signing & Capabilities** 中选择你的 Team。TestFlight 流程见 `MemorizeSpanish/RELEASE_TESTFLIGHT.txt`。

若工程位于中文路径且构建偶发签名问题，可将 DerivedData 设到 `/tmp`（见 `AI协作备忘.md`）。

## 桌面词库同步（可选）

```bash
cd DeskManualSync
npm install
# 配置环境变量 NOTE_DESK_SYNC_TOKEN 后
node server.js
```

App **设置** 中填写同步服务 URL 与 Token。部署说明见 `DeskManualSync/`（含 Docker / Railway 配置）。

## 技术栈

| 部分 | 技术 |
|------|------|
| iOS | SwiftUI、SwiftData、UserNotifications |
| 复习算法 | SM-2 风格间隔调度 |
| 同步服务 | Node.js、Express |
| 词表维护 | Python 脚本 + JSON 资源 |

## 文档

- `MemorizeSpanish/RELEASE_TESTFLIGHT.txt` — TestFlight 上传步骤
- `MemorizeSpanish/ACCOUNT_SETUP.txt` — 开发者账号与能力说明
- `AI协作备忘.md` — 本地协作约定

## License

个人学习项目，未指定开源协议；教材与 DELE 相关资源仅供个人学习参考。
