---
name: kkk-windows-user-folder-rename
description: >-
  Windows 用户配置目录（C:\Users\旧名）整体安全改名的完整技能：只读盘点 → 注册表/hive 备份 →
  生成 GBK 防呆改名脚本 → 另一管理员账户执行（ren 文件夹 + ProfileImagePath + junction 兜底）→
  残留路径修复（环境变量/WSL/OneDrive/注册表全量替换）→ 收尾与回滚。Use whenever 用户想把
  C:\Users 下的用户文件夹改名/换名/改短、账户目录被微软账户截断想修正、提到 ProfileImagePath、
  user profile folder rename，或目录改名后出现 OneDrive/WSL/环境变量/软件路径失效需要修复。
---

# Windows 用户目录改名（C:\Users\旧名 → 新名）

适用于 Windows 10/11 + PowerShell 5.1+，不依赖特定 Agent 工具。典型场景：微软账户登录时
文件夹名被截断（如邮箱前 5 个字母）、拼写错误、想把目录改短。**不适用**：只想改"账户名/
显示名"——那与文件夹无关，在 控制面板→用户账户 改即可，不必动文件夹。

## 铁律（动手前先读完）

1. **ren 必须在另一个管理员账户下执行**。本人登录时 `ntuser.dat` 被锁定，改名必失败。
   常用第二入口：启用内置 Administrator（`net user administrator /active:yes`，空密码可
   控制台登录；用完禁用回去）或临时建一个本地管理员账户。
2. **junction 兜底是标配，不是可选项**。改完立刻 `mklink /J C:\Users\旧名 C:\Users\新名`，
   所有还写死旧路径的程序继续可用。junction 生命周期：创建 → 稳定观察约 1 周 → 管理员
   cmd `rmdir C:\Users\旧名` 删除（rmdir 只删链接，不动数据）。**删 junction 前必须**：
   ① OneDrive 已走官方迁移（见铁律 3）；② 桌面壁纸重新设置一次（WallPaper 键受系统保护
   改不动，删链接后壁纸会丢）。
3. **OneDrive 是唯一"修注册表没用"的东西**。它的路径源头是本地 SQLite 设置库
   （`~\AppData\Local\Microsoft\OneDrive\settings\Personal\*.db`），注册表只是展示层——
   修了会被 OneDrive 重启后写回，别反复修这些键：`HKCU\Environment` 的 OneDrive/OneDriveConsumer、
   `SyncEngines\...\MountPoint`、`OneDrive\Accounts\...\UserFolder`、User Shell Folders 里被
   接管的 Documents/Pictures。唯一正解（删 junction 的前提）：OneDrive 托盘图标 → 设置 →
   账户 → **取消链接此电脑** → 重新登录 → 位置选 `C:\Users\新名\OneDrive`。文件已在本地，
   只对账不重下载。junction 在，旧路径同步完全正常，不着急可延后做。
4. **含中文的 .bat 必须 GBK(ANSI) 编码 + CRLF**。UTF-8 + `chcp 65001` 会让 cmd 解析
   `if(...)` 括号块时错位（症状：`'试。'`、`'smon'` 之类把中文提示切成"命令"的乱码报错）。
   Agent 的 Write 工具只能写 UTF-8，所以**改名 bat 一律用 `scripts/gen-step2-bat.ps1` 生成**
   （英文提示 + GBK，跨系统 codepage 最稳）。
5. **活跃数据不动**：正在使用的 sqlite db、运行中程序的状态文件里的旧路径靠 junction 兜，
   不做二进制替换；新数据自然写新路径。
6. **改前必须备份**：关键键 `.reg` 导出（普通权限）+ `reg save` 完整用户 hive（需提权）+
   系统还原点。回滚时这是唯一的救命稻草。

## 流程

### Phase 0 盘点（本人登录下，全部只读）

跑 `scripts/scan-old-refs.ps1`（默认从当前 `%USERPROFILE%` 推导旧名；也可 `-OldName xxx`
指定）。产出报告包含：

- 用户的 SID 与 `ProfileList` 状态（有无 `.bak`/临时配置文件）
- 启用的账户、内置 Administrator 状态、有无第二管理员入口
- 硬编码旧路径：HKCU\Environment（含 Path）、WSL `Lxss\*\BasePath`、OneDrive 各键
- 以该用户运行的服务（`Win32_Service` StartName）、计划任务运行身份
- HKCU / HKLM\SOFTWARE 的 `Users\旧名` 数据值计数（残留基线，修复后对比用）

注意事项：Agent 若处于计划模式，只读命令也会被拦，可派只读子代理代跑；
`reg` 命令带 `/v /s /y` 开关在 Git Bash 里要前置 `MSYS_NO_PATHCONV=1`；
对 reg 重定向产物做统计时 grep 可能静默吞输出，用 awk。

### Phase 1 备份 + 生成脚本（本人登录下）

1. 建备份目录（建议非用户目录，如 `C:\Backup\profile-rename-backup\`）：
   - `reg export`：ProfileList 整键、HKCU\Environment、Lxss、OneDrive\Accounts（/y 覆盖）
   - 提权部分打包成一个 bat（建还原点 + `reg save HKCU` + `reg save HKCU\Software\Classes`
     + 启用 Administrator），用 `powershell Start-Process -Verb RunAs` 弹 UAC 执行，
     bat 写完成 flag 文件，轮询确认（Agent Shell 通常未提权时的标准做法）
   - `wsl --shutdown`
2. 生成改名脚本：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gen-step2-bat.ps1 `
     -OldName 旧名 -NewName 新名 -Sid S-1-5-21-xxxx `
     -OutFile "C:\Users\Public\Desktop\step2-as-admin.bat"
   ```
   生成器内置防呆：提权检查、本人账户拒绝、junction 已存在自动退出（幂等）、
   ren 前杀已知占用服务（默认微软电脑管家 `MSPCManagerService`，可 `-KillServices`/`-KillProcesses` 增删）。

### Phase 2 用户手动（约 3 分钟，明确告知步骤）

1. **重启电脑**（保证旧账户会话完全注销，别用"切换用户"）
2. 登录另一管理员账户（内置 Administrator 双击即全权限；自建普通管理员账户必须
   **右键 → 以管理员身份运行**，双击不提权会被脚本拒绝）
3. 运行 step2-as-admin.bat，看到 `Done` 后注销，登回原账户
4. 若 ren 报 Access denied：资源监视器（resmon）**搜不到服务类句柄**，要用 Sysinternals
   `handle.exe` 全量扫 `Users\旧名` 找占用进程（服务类常见；结束/停服务后重跑 bat，幂等）

### Phase 3 残留修复（登回原账户后）

1. 验证：`%USERPROFILE%` = 新路径、Git Bash `$HOME`、junction 存在
2. 跑修复器（定点 + 可选全量）：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/fix-hkcu-paths.ps1 `
     -OldName 旧名 -NewName 新名 -All
   ```
   覆盖：HKCU\Environment、Shell Folders/User Shell Folders、Lxss、OneDrive 相关键、
   SyncEngines；`-All` 再全量扫 HKCU 所有 REG_SZ/REG_EXPAND_SZ 字符串值替换（壁纸、主题、
   协议处理器、卸载信息、托盘缓存等一次清完）。只动字符串值类型，MULTI_SZ/BINARY 不碰。
3. 实测 WSL：`wsl -d <发行版> -e echo ok`（BasePath 修好应能启动）
4. 重启 OneDrive 一次，观察注册表是否被写回旧路径——写回属正常（见铁律 3），转官方迁移，
   **不要**再修那几个键
5. 文件层 grep：`.gitconfig`、`.ssh/config`、`.bashrc`、技能/脚本目录、各工具 config.json
   中的旧绝对路径。Git Bash 里 `sed -i 's/C:\\Users\\X/.../'` 这类含双反斜杠的模式会
   **静默不生效**，改用不含反斜杠的简单模式（如 `s/旧名/新名/`）
6. 残留重扫对比基线：剩几十处属正常——系统保护键（MSI Installer 源缓存、开始菜单备份、
   `\\?\Volume{...}` 推送缓存、UFH 的 MULTI_SZ）改不动也不必改，junction 全兜住

### Phase 4 收尾

- `net user administrator /active:no`；临时管理员账户让用户在 设置→账户 自行删（或留作急救入口）
- 提醒用户完成 OneDrive 官方迁移（若未做）
- 约一周稳定后：重设壁纸 → `rmdir C:\Users\旧名` 删 junction → 备份目录观察一个月后可清理

## 回滚（出问题时）

登录另一管理员账户 → `rmdir C:\Users\旧名`（只删 junction）→ `ren C:\Users\新名 旧名` →
双击备份的 profilelist.reg（或 `reg load` 恢复 hive 快照）→ 重启。或直接用系统还原点。

## 坑速查表

| 症状 | 原因与解法 |
|---|---|
| bat 报 `'试。'`/`'smon'` 之类乱码"命令" | UTF-8+chcp 解析括号块错位；换 GBK+CRLF 生成 |
| ren 拒绝访问，resmon 查无果 | 服务类句柄 resmon 搜不到；用 `handle.exe`；惯犯：微软电脑管家（`sc stop MSPCManagerService` + `taskkill`） |
| PowerShell `.SetValue()` 报"无法写入到注册表键" | `Get-Item`/`Get-ChildItem` 给的是**只读句柄**；`[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($rel,$true)` 重开 |
| OneDrive 注册表修完又变回旧路径 | 源头是 SQLite 设置库；走官方取消链接/重新登录流程 |
| 部分键（WallPaper、Installer、AppListBackup）改不动 | 系统保护键，junction 兜底，放弃即可 |
| `setx` 改 Path 报截断 | Path 超 1024 字符；直接改注册表值（保留 REG_SZ/EXPAND_SZ 原类型） |
| HKCU 残留清不干净 | 保护缓存类正常残留；用 `reg query HKCU /f "Users\旧名" /s /d` 计数对比即可，不追杀 |
