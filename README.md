# CameraMediaSort

Windows 相机照片、视频与 RAW 文件整理脚本，使用 PowerShell、Windows Shell 元数据和可选的 robocopy，无需 Python。

详细用法见 [使用说明](使用说明.md)。保持 BAT 和 PS1 文件在同一文件夹。

## 快速开始

把源文件夹拖到 `Drop-SortMediaByDate.bat`，选择目标位置，检查预览后操作：

| 输入 | 操作 |
| --- | --- |
| 回车 / M | 移动（默认，会移走源文件） |
| C | 复制 |
| R | robocopy 暂存后移动归档 |
| RC | robocopy 复制到暂存区后归档，保留源文件 |
| 其他 | 取消 |

也可以在 PowerShell 中运行：

```powershell
# 先预览
.\Sort-MediaByDate.ps1 -Source "E:\DCIM" -Destination "D:\Media" -Recurse -Preview

# 复制；省略 -Mode Copy 时默认移动
.\Sort-MediaByDate.ps1 -Source "E:\DCIM" -Destination "D:\Media" -Recurse -Mode Copy
```

输出目录默认形如 `2026-05-01`，精度到天。日期整理工具遇到重名会追加 `(1)` 等后缀，不进行内容去重。

## 运行环境与限制

- 面向 Windows 桌面环境，BAT 调用 Windows PowerShell；其他操作系统不支持 Shell COM 日期读取。
- 连续编号会按首尾日期及二分探测推断中间日期，假设拍摄日期随编号顺序排列。改过相机时间、混合设备或日期乱序可能导致误分类；当前没有逐文件严格验证开关。
- Shell 日期读取使用列索引，识别结果受 Windows 版本、语言和已安装的格式处理程序影响；不能保证每种 RAW 都能读到拍摄日期，读不到时回退文件修改时间。
- 同编号的 JPG/RAW 等可能共享推断日期；XML 也被纳入处理，但没有独立的伴随文件配对算法。
- 预览可能创建空目标目录；普通传输目前没有总体进度和速度显示。
- robocopy 模式不保证比普通模式快；失败或中断时可能留下暂存文件。移动模式部分文件可能已离开源目录，应检查源、暂存和日期目录后恢复。不要直接删除尚有文件的暂存目录。
- 重复扫描已整理目录可能产生重复副本。建议源和目标使用分开的目录。
- `Copy-MediaRange.ps1` 是较早的独立工具，支持格式、默认复制和重名行为与日期整理工具不同，不能套用日期整理工具的重名保护规则。

## 隐私与公开代码

整理脚本没有上传媒体或联网逻辑，公开脚本本身不会公开本地照片。发布仓库时只纳入源代码和文档，排除真实素材、日志、凭据与临时目录。
