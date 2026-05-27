# 中文开发记录

## 2026-05-25 - 从上游新版本恢复 LBTV 分叉功能

### 背景

本轮开发从 `YuGeYu/CS2-Bot-Improver` 当前仓库出发，以 `ed0ard/CS2-Bot-Improver` 的新版本为上游基线，恢复旧 `CS2-Bot-Improver_upstream` 中已经验证过的 LBTV 功能，并适配上游新增的 `NadeSystem`。

上游整包已保存为：

```text
vendor/upstream/CS2BotImprover_upstream_latest.zip
```

### 功能恢复

#### BotTaunt

新增独立插件：

```text
addons/counterstrikesharp/plugins/BotTaunt/
addons/counterstrikesharp/configs/plugins/BotTaunt/BotTaunt.json
```

恢复内容：

- BOT 击杀嘲讽。
- 爆头、刀杀等特殊击杀嘲讽。
- 开局垃圾话。
- 多杀和单回合多杀嘲讽。
- 残局/保枪场景嘲讽。
- MVP AI 嘲讽。
- 玩家聊天触发 BOT AI 回复。
- `lbtv_bot_taunt` 与 `lbtv_bot_chat` 控制命令。
- `IPluginConfig<BotTauntConfig>` 配置读取。

AI 接口支持两种响应格式：

- `{ "reply": "..." }`
- OpenAI 兼容的 `choices[0].message.content`

#### RoundDamageRecap

修改文件：

```text
addons/counterstrikesharp/plugins/RoundDamageRecap/RoundDamageRecap.cs
```

恢复与新增内容：

- 恢复 `lbtv_difficulty` 命令。
- 恢复基于 `overrides/botprofile.vpk` SHA256 的难度识别。
- 当前文件与 `Low/Medium/High` 三个预设 VPK 对比。
- 不匹配时显示 `Custom / Unknown [?/3]`。
- 保留新版回合伤害统计逻辑。
- 新增道具伤害归因：
  - HE 爆炸伤害。
  - Molotov / Incendiary / Inferno 火焰伤害。
  - 闪、烟、雷、火、诱饵、tagrenade 等道具撞击伤害。

归因策略：

1. 优先使用 `player_hurt` 事件自带 attacker。
2. attacker 缺失时，根据最近投掷记录、爆点位置、时间窗口和受害者位置反推投掷者。
3. 反推失败则不记录，避免错误归因。

#### NadeSystem

修改文件：

```text
addons/counterstrikesharp/plugins/NadeSystem/NadeSystem.cs
```

本轮适配点：

- 为 native 创建的 `smoke/he/molotov` projectile 补齐：
  - `Thrower`
  - `OriginalThrower`
  - `OwnerEntity`
  - `InitialPosition`
  - `InitialVelocity`
  - `Elasticity`
- 为循环重建的 decoy-flash 补齐初始位置和速度。
- 增加统一道具使用提交函数 `TryCommitUtilityUse`。
- 统一处理普通投掷、瞬发烟/闪、下包烟、火中逃生烟、反击 HE/火。

新增回合硬上限：

```text
TeamRoundLimit:
  flash = 10
  smoke = 5
  he = 5
  molotov/incgrenade = 5

BotRoundLimit:
  flash = 2
  smoke = 1
  he = 1
  molotov/incgrenade = 1
```

新增经济预算机制：

- `EventRoundFreezeEnd` 时记录每个 BOT 当前经济。
- 使用 `_roundUtilityBudgetByBot` 保存本回合道具预算。
- `_roundSpendPerBot` 记录插件本回合已花费金额。
- 判断条件为 `alreadySpent + cost <= recordedBudget`。
- 杀人加钱不会提高本回合插件道具预算。

#### BotState

修改文件：

```text
addons/counterstrikesharp/plugins/BotState/BotState.cs
addons/counterstrikesharp/plugins/BotState/BotState.csproj
```

平衡性调整：

- `ExpandedValue` 从 `4000f` 降到 `1000f`。
- `RestoreDelay` 从 `1.0f` 降到 `0.35f`。
- 拆包烟循环恢复也使用 `RestoreDelay`。

编译适配：

- 原项目引用缺失的 `Ray-Trace` 子项目。
- 改为引用本地 `libs/RayTraceApi.dll`。
- DLL 来自上游最新整包内的 `addons/counterstrikesharp/shared/RayTraceApi/RayTraceApi.dll`。

### 依赖文件

为支持本地编译，补充以下 DLL：

```text
addons/counterstrikesharp/plugins/BotAimImprover/libs/RayTraceApi.dll
addons/counterstrikesharp/plugins/BotState/libs/RayTraceApi.dll
addons/counterstrikesharp/plugins/NadeSystem/libs/RayTraceApi.dll
```

### 打包脚本

新增：

```text
scripts/Build-FullRelease.ps1
scripts/Rebuild-OverrideVpks.py
```

打包策略：

1. 使用 `vendor/upstream/CS2BotImprover_upstream_latest.zip` 作为基底。
2. 编译并覆盖本分叉修改过的插件：
   - `BotTaunt`
   - `BotState`
   - `NadeSystem`
   - `RoundDamageRecap`
3. 递归复制 `addons/counterstrikesharp/configs`，确保 `BotTaunt.json` 入包。
4. 重建 `overrides/botprofile.vpk` 与 `Low/Medium/High` 三档 VPK。
5. 输出：

```text
dist/CS2BotImprover_fresh_lbtv.zip
```

### 验证记录

已执行：

```powershell
dotnet build addons\counterstrikesharp\plugins\BotTaunt\BotTaunt.csproj -c Release
dotnet build addons\counterstrikesharp\plugins\BotState\BotState.csproj -c Release
dotnet build addons\counterstrikesharp\plugins\NadeSystem\NadeSystem.csproj -c Release
dotnet build addons\counterstrikesharp\plugins\RoundDamageRecap\RoundDamageRecap.csproj -c Release
powershell -ExecutionPolicy Bypass -File scripts\Build-FullRelease.ps1
```

结果：

- `BotTaunt`：0 警告，0 错误。
- `NadeSystem`：0 警告，0 错误。
- `RoundDamageRecap`：0 警告，0 错误。
- `BotState`：1 个既有未使用字段警告，0 错误。
- 完整整包成功生成。

最新本地整包：

```text
dist/CS2BotImprover_fresh_lbtv.zip
```

SHA256：

```text
A6DCD0C80397C968186B26931924A6052B663F77DB3BE11E67D9CC2D208CE5C5
```

### GitHub 同步

已推送到：

```text
https://github.com/YuGeYu/CS2-Bot-Improver
```

提交：

```text
c28c414 Restore LBTV bot enhancements
```

GitHub 对 `vendor/upstream/CS2BotImprover_upstream_latest.zip` 给出大文件提醒。后续如需长期维护，建议改为 Git LFS 或 GitHub Release 资产。
