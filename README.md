# kkk-windows-user-folder-rename

**中文** | [English](#english)

把 Windows 用户配置目录（`C:\Users\旧名`）安全改名的完整工具集：改名前只读盘点 → 注册表/hive 备份 → 生成防呆改名脚本 → 另一管理员账户一键执行 → 残留路径批量修复 → 收尾与回滚方案。典型场景：微软账户登录时用户文件夹名被截断（如取邮箱前 5 个字母）、拼写错误、想把目录改短。

## 为什么不能直接改名

直接重命名 `C:\Users\你的账户` 会在三个地方翻车，本工具集逐一解决：

1. **本人登录时改不动**——`ntuser.dat` 被系统锁定。必须在另一个管理员账户下执行，并同步修改注册表 `ProfileList` 的 `ProfileImagePath`。
2. **有程序占着句柄**——安全软件的后台服务常驻扫描用户目录（如微软电脑管家），资源监视器还搜不到这类服务句柄，需要专门处理。
3. **改完到处是断链**——环境变量、WSL、OneDrive、壁纸、软件协议处理器里写死了几百处旧绝对路径，逐个手改不现实。

## 特性

- **四阶段完整流程**：盘点 → 备份+生成脚本 → 用户 3 分钟手动操作 → 残留修复
- **防呆改名脚本**（自动生成）：提权检查、本人账户拒绝、重复运行自动退出（幂等）、执行前自动停止已知句柄占用服务
- **junction 兜底**：改名后创建 `C:\Users\旧名 → 新名` 目录联接，所有写死旧路径的程序继续可用，观察稳定一周后再删
- **批量残留修复器**：定点修环境变量/WSL/OneDrive 相关键，可选全量扫描 HKCU 所有字符串值（只动 REG_SZ/REG_EXPAND_SZ，不碰二进制）
- **OneDrive 特例处理**：识别其源头是本地 SQLite 设置库、注册表会被写回的机制，给出官方迁移的正确路径，避免无效反复修
- **完整回滚方案**：.reg 导出 + 用户 hive 快照 + 系统还原点三重保险

## 快速开始

环境要求：Windows 10/11、PowerShell 5.1+、一个临时第二管理员入口（内置 Administrator 或临时账户）。

```powershell
# 1. 盘点当前状态（只读）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/scan-old-refs.ps1 -OldName 旧名

# 2. 备份关键注册表键 + 用户 hive + 建还原点（按 SKILL.md Phase 1 清单）

# 3. 生成改名脚本（自动写成 GBK+CRLF，防中文乱码解析错位）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gen-step2-bat.ps1 `
  -OldName 旧名 -NewName 新名 -Sid S-1-5-21-xxxx `
  -OutFile "C:\Users\Public\Desktop\step2-as-admin.bat"

# 4. 重启电脑 → 登录另一管理员账户 → 运行桌面的 step2-as-admin.bat → 登回原账户

# 5. 修复残留路径
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/fix-hkcu-paths.ps1 `
  -OldName 旧名 -NewName 新名 -All
```

详细流程、铁律与坑速查表见 [SKILL.md](SKILL.md)。

## 目录结构

```
├── SKILL.md                 # 完整流程文档（四阶段 + 铁律 + 坑速查表 + 回滚）
├── README.md                # 本文件
└── scripts/
    ├── gen-step2-bat.ps1    # 生成防呆改名 bat（GBK+CRLF，参数化）
    ├── scan-old-refs.ps1    # 改名前只读盘点（SID/账户/硬编码/服务/残留基线）
    └── fix-hkcu-paths.ps1   # 改名后残留路径修复（定点 + -All 全量）
```

## 注意

- 本仓库脚本不包含任何真实机器信息，`旧名/新名/SID` 均为参数，请按自己机器的实际值传入
- 改名有风险，务必先按流程完成备份；出问题时按 SKILL.md 的回滚方案恢复
- OneDrive 用户：删兜底 junction 前必须先完成 OneDrive 官方迁移（取消链接→重登→选新位置）

## 许可证

[MIT](LICENSE)

---

# English

A complete toolkit for safely renaming a Windows user profile folder (`C:\Users\old-name`): read-only inventory → registry/hive backup → generate a foolproof rename script → one-click execution from another admin account → batch residue-path fixing → cleanup and rollback.

## Why not just rename it

1. **You can't rename your own profile while signed in** — `ntuser.dat` is locked. It must be done from another admin account, together with updating `ProfileImagePath` in the registry `ProfileList`.
2. **Background services hold handles** — security suites constantly scan user folders (e.g. Microsoft PC Manager), and Resource Monitor cannot even find those service handles.
3. **Hundreds of hardcoded old paths break** — environment variables, WSL, OneDrive, wallpaper, protocol handlers and more all store absolute paths under the old folder.

## Highlights

- Four-phase workflow: inventory → backup + script generation → 3-minute manual step → residue fixing
- Generated rename script with guards: elevation check, owner-account refusal, idempotent re-runs, auto-stopping known handle-holder services
- Junction fallback (`C:\Users\old → new`) keeps old-path programs working; remove it after a stable week
- Batch fixer for targeted keys plus an optional full HKCU sweep (string values only)
- Documents the OneDrive special case (its source of truth is a local SQLite store — registry edits get rewritten; use the official unlink/relink flow)
- Triple rollback safety: .reg exports + user hive snapshots + system restore point

## Quick start

Requires Windows 10/11, PowerShell 5.1+, and a temporary second admin entry point.

```powershell
# 1. Read-only inventory
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/scan-old-refs.ps1 -OldName old-name

# 2. Back up registry keys + user hives + create a restore point (see SKILL.md Phase 1)

# 3. Generate the rename script (GBK + CRLF, safe under any console codepage)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gen-step2-bat.ps1 `
  -OldName old-name -NewName new-name -Sid S-1-5-21-xxxx `
  -OutFile "C:\Users\Public\Desktop\step2-as-admin.bat"

# 4. Reboot → sign in as another admin → run the generated .bat → sign back in

# 5. Fix residual paths
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/fix-hkcu-paths.ps1 `
  -OldName old-name -NewName new-name -All
```

Full workflow, rules and a pitfall cheat-sheet live in [SKILL.md](SKILL.md).

## Notes

- No real machine data is included; pass your own old/new names and SID as parameters
- Always complete the backups first; see SKILL.md for rollback
- OneDrive users must run the official unlink/relink flow before removing the fallback junction

## License

[MIT](LICENSE)
