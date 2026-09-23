# 更新日志

## 1.1.0（2026-09-23）

- 修复：`fix-hkcu-paths.ps1` 以只读句柄写注册表导致修复恒失败（`TOTAL_FIXED` 恒为 0）；现以可写句柄重开，写入前自动把每个原值落盘为 undo 脚本，支持 `-WhatIf` 干跑
- 新增：`scan-old-refs.ps1` 盘点计划任务运行身份；内置 Administrator 改按 RID 500 SID 识别（不再依赖固定账户名）
- 加固：`gen-step2-bat.ps1` 生成前校验 SID 存在且与旧名匹配；生成的 bat 在改注册表前自动导出 ProfileList 备份；bat 编码改用 `GetEncoding(0)`（PS 5.1 与 pwsh 7 下均为系统 ANSI 码页）
- 文档：OneDrive 自定义位置用户重登选回原路径的说明、handle.exe 下载链接、双语 README 逐节对齐、阶段数口径统一为五阶段；SKILL.md 元数据按规范重塑（author 收进 metadata、移除冗余键）

## 1.0.0（2026-08-22）

- 首次发布
