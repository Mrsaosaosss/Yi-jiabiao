# ============================================================
# Cursor IDE 登录后界面不跳转 - 自动修复脚本
# 适用于 Windows 10/11
# 使用方法: 右键以管理员身份运行 PowerShell，然后执行此脚本
# ============================================================
#Requires -Version 5.1

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "Cursor 登录修复工具"

Write-Host @"
╔══════════════════════════════════════════════════════╗
║     Cursor IDE 登录跳转问题 - 自动修复工具          ║
╚══════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
Write-Host ""

# 检测 Cursor 数据目录
$cursorAppData = "$env:APPDATA\Cursor"
$cursorUserData = "$env:LOCALAPPDATA\Programs\cursor"
$cursorSettingsFile = "$cursorAppData\User\settings.json"

# 备用路径 (Cursor 可能在不同位置存放数据)
$possibleCursorDirs = @(
    "$env:APPDATA\Cursor",
    "$env:LOCALAPPDATA\Cursor",
    "$env:USERPROFILE\.cursor"
)

$actualCursorDir = $null
foreach ($dir in $possibleCursorDirs) {
    if (Test-Path $dir) {
        $actualCursorDir = $dir
        Write-Host "[信息] 检测到 Cursor 数据目录: $dir" -ForegroundColor Gray
        break
    }
}

if (-not $actualCursorDir) {
    Write-Host "[警告] 未检测到 Cursor 数据目录。如果你确实安装了 Cursor，请手动指定路径。" -ForegroundColor Yellow
    $actualCursorDir = "$env:APPDATA\Cursor"
    Write-Host "[信息] 将使用默认路径: $actualCursorDir" -ForegroundColor Gray
}

# ============================================================
# 步骤 1: 检查默认浏览器及协议关联
# ============================================================
Write-Host ""
Write-Host "=" * 60
Write-Host "  步骤 1/3: 检查系统默认浏览器及 HTTP/HTTPS 协议关联" -ForegroundColor Yellow
Write-Host "=" * 60
Write-Host ""

Write-Host "[说明] 如果默认浏览器设置异常，Cursor 完成登录后可能无法正确唤起浏览器回跳。" -ForegroundColor Gray
Write-Host ""

# 检查 HTTP 协议关联
Write-Host ">>> 正在检查 HTTP 协议关联..." -ForegroundColor Gray
$httpAssoc = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" -ErrorAction SilentlyContinue
$httpsAssoc = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice" -ErrorAction SilentlyContinue

# 检查默认浏览器 ProgId
$httpProgId = $httpAssoc.ProgId
$httpsProgId = $httpsAssoc.ProgId

Write-Host "  HTTP 协议关联程序: $httpProgId"
Write-Host "  HTTPS 协议关联程序: $httpsProgId"

if (-not $httpProgId -or -not $httpsProgId) {
    Write-Host "  [异常] HTTP 或 HTTPS 协议未正确关联到任何浏览器！" -ForegroundColor Red
    $httpStatus = "异常"
} else {
    Write-Host "  [正常] HTTP 和 HTTPS 协议均已关联" -ForegroundColor Green
    $httpStatus = "正常"
}

Write-Host ""

# 列出系统中已安装的浏览器
Write-Host ">>> 正在扫描系统中已注册的浏览器..." -ForegroundColor Gray
$browserPaths = @{
    "Chrome" = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    "Edge" = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
    )
    "Firefox" = @(
        "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
    )
    "Brave" = @(
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
}

$foundBrowsers = @()
foreach ($browser in $browserPaths.GetEnumerator()) {
    foreach ($path in $browser.Value) {
        if (Test-Path $path) {
            Write-Host "  [已安装] $($browser.Name): $path"
            $foundBrowsers += @{ Name = $browser.Name; Path = $path }
            break
        }
    }
}

Write-Host ""

# 报告及修复建议
Write-Host "══════════════════ 步骤 1 诊断结果 ══════════════════" -ForegroundColor Cyan
if ($httpStatus -eq "异常") {
    Write-Host "  结论: HTTP/HTTPS 协议关联异常，需要修复。" -ForegroundColor Red
    Write-Host ""
    Write-Host "  建议修复方式 (请手动选择一种):"
    Write-Host "    a) 打开 Windows 设置 -> 应用 -> 默认应用 -> 按协议类型指定默认应用"
    Write-Host "       将 HTTP 和 HTTPS 协议都设置为你的常用浏览器 (如 Chrome/Edge)"
    Write-Host "    b) 直接在浏览器设置中点击「设为默认浏览器」"
} else {
    Write-Host "  结论: 协议关联正常。" -ForegroundColor Green
}

Write-Host ""
Write-Host ">>> 请确认是否继续执行步骤 2 (清理代理设置)? [Y/N] " -ForegroundColor Magenta -NoNewline
$confirm = Read-Host
if ($confirm -notmatch '^[Yy]') {
    Write-Host "用户取消操作，脚本退出。" -ForegroundColor Red
    exit 0
}

# ============================================================
# 步骤 2: 清理代理设置
# ============================================================
Write-Host ""
Write-Host "=" * 60
Write-Host "  步骤 2/3: 清理代理设置" -ForegroundColor Yellow
Write-Host "=" * 60
Write-Host ""

Write-Host "[说明] 某些开发工具 (如代理抓包工具) 会在系统中设置 HTTP_PROXY / HTTPS_PROXY 环境变量，"
Write-Host "        或者 Cursor 的配置文件中残留代理配置。这会干扰 OAuth 登录回调。"
Write-Host ""

$proxyFound = $false
$proxyDetails = @()

# 2a. 检查进程级环境变量
Write-Host ">>> 正在检查当前会话的环境变量..." -ForegroundColor Gray
$envVars = @("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "all_proxy", "NO_PROXY", "no_proxy")
foreach ($varName in $envVars) {
    $val = [Environment]::GetEnvironmentVariable($varName, "Process")
    if ($val) {
        Write-Host "  [发现] 进程级 $varName = $val" -ForegroundColor Yellow
        $proxyFound = $true
        $proxyDetails += "进程级环境变量: $varName = $val"
        # 标记 localhost:18030
        if ($val -match "localhost:18030") {
            Write-Host "    ^^^ 这是典型的抓包代理端口 (如 mitmproxy/Charles/Fiddler)!" -ForegroundColor Red
        }
    }
}

# 2b. 检查用户级环境变量
Write-Host ">>> 正在检查用户级环境变量..." -ForegroundColor Gray
foreach ($varName in $envVars) {
    $val = [Environment]::GetEnvironmentVariable($varName, "User")
    if ($val) {
        Write-Host "  [发现] 用户级 $varName = $val" -ForegroundColor Yellow
        $proxyFound = $true
        $proxyDetails += "用户级环境变量: $varName = $val"
        if ($val -match "localhost:18030") {
            Write-Host "    ^^^ 这是典型的抓包代理端口!" -ForegroundColor Red
        }
    }
}

# 2c. 检查系统级环境变量
Write-Host ">>> 正在检查系统级环境变量..." -ForegroundColor Gray
foreach ($varName in $envVars) {
    $val = [Environment]::GetEnvironmentVariable($varName, "Machine")
    if ($val) {
        Write-Host "  [发现] 系统级 $varName = $val" -ForegroundColor Yellow
        $proxyFound = $true
        $proxyDetails += "系统级环境变量: $varName = $val"
        if ($val -match "localhost:18030") {
            Write-Host "    ^^^ 这是典型的抓包代理端口!" -ForegroundColor Red
        }
    }
}

# 2d. 检查 Cursor 配置文件中的代理设置
Write-Host ">>> 正在检查 Cursor 配置文件中的代理设置..." -ForegroundColor Gray
if (Test-Path $cursorSettingsFile) {
    $settingsContent = Get-Content $cursorSettingsFile -Raw -ErrorAction SilentlyContinue
    if ($settingsContent -match "proxy" -or $settingsContent -match "Proxy") {
        Write-Host "  [发现] Cursor settings.json 中包含 proxy 相关配置" -ForegroundColor Yellow
        $proxyFound = $true
        $proxyDetails += "Cursor settings.json 中包含 proxy 配置"

        # 提取 proxy 相关行
        $proxyLines = ($settingsContent -split "`n") | Where-Object { $_ -match "proxy|Proxy" }
        foreach ($line in $proxyLines) {
            Write-Host "    配置行: $($line.Trim())" -ForegroundColor Yellow
            if ($line -match "18030") {
                Write-Host "    ^^^ 检测到 18030 端口代理!" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  [正常] Cursor settings.json 中未发现代理配置" -ForegroundColor Green
    }
} else {
    Write-Host "  [信息] 未找到 Cursor settings.json ($cursorSettingsFile)" -ForegroundColor Gray
}

Write-Host ""

if (-not $proxyFound) {
    Write-Host "══════════════════ 步骤 2 诊断结果 ══════════════════" -ForegroundColor Cyan
    Write-Host "  结论: 系统中未发现代理设置。" -ForegroundColor Green
} else {
    Write-Host "══════════════════ 步骤 2 诊断结果 ══════════════════" -ForegroundColor Cyan
    Write-Host "  结论: 发现上述代理设置，建议清除。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host ">>> 是否要自动清除这些代理设置? [Y/N] " -ForegroundColor Magenta -NoNewline
    $confirmClean = Read-Host
    if ($confirmClean -match '^[Yy]') {
        Write-Host ""
        Write-Host ">>> 正在清除代理设置..." -ForegroundColor Gray

        # 清除进程级环境变量
        foreach ($varName in $envVars) {
            $val = [Environment]::GetEnvironmentVariable($varName, "Process")
            if ($val) {
                [Environment]::SetEnvironmentVariable($varName, $null, "Process")
                Write-Host "  已清除进程级 $varName"
            }
        }

        # 清除用户级环境变量
        foreach ($varName in $envVars) {
            $val = [Environment]::GetEnvironmentVariable($varName, "User")
            if ($val) {
                [Environment]::SetEnvironmentVariable($varName, $null, "User")
                Write-Host "  已清除用户级 $varName"
            }
        }

        # 清除系统级环境变量 (需要管理员权限)
        $needAdmin = $false
        foreach ($varName in $envVars) {
            $val = [Environment]::GetEnvironmentVariable($varName, "Machine")
            if ($val) {
                $needAdmin = $true
            }
        }

        if ($needAdmin) {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if ($isAdmin) {
                foreach ($varName in $envVars) {
                    $val = [Environment]::GetEnvironmentVariable($varName, "Machine")
                    if ($val) {
                        [Environment]::SetEnvironmentVariable($varName, $null, "Machine")
                        Write-Host "  已清除系统级 $varName"
                    }
                }
            } else {
                Write-Host "  [警告] 清除系统级环境变量需要管理员权限。请以管理员身份重新运行此脚本。" -ForegroundColor Yellow
            }
        }

        # 清理 Cursor 配置文件中的代理
        if (Test-Path $cursorSettingsFile) {
            $settingsContent = Get-Content $cursorSettingsFile -Raw -ErrorAction SilentlyContinue
            if ($settingsContent -match "proxy" -or $settingsContent -match "Proxy") {
                # 备份
                $backupPath = "$cursorSettingsFile.backup-proxy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item $cursorSettingsFile $backupPath -Force
                Write-Host "  已备份 Cursor 配置文件到: $backupPath"

                # 移除 HTTP 代理行 (注释掉而不是删除，方便恢复)
                $lines = Get-Content $cursorSettingsFile
                $newLines = $lines | ForEach-Object {
                    if ($_ -match '"http\.proxy"' -or $_ -match '"https\.proxy"' -or $_ -match '"proxy"' -or $_ -match '"proxyStrictSSL"') {
                        "    // [已注释] 原代理配置: $_"
                    } else {
                        $_
                    }
                }
                # 需要先读取再写入，避免编码问题
                $tempFile = [System.IO.Path]::GetTempFileName()
                $newLines | Out-File -FilePath $tempFile -Encoding UTF8
                Move-Item $tempFile $cursorSettingsFile -Force
                Write-Host "  已注释掉 Cursor 配置文件中的代理设置"
            }
        }

        Write-Host ""
        Write-Host "  [完成] 代理设置已清除。" -ForegroundColor Green
        Write-Host "  [提醒] 修改系统级环境变量后需要注销或重启才能完全生效。" -ForegroundColor Yellow
    } else {
        Write-Host "  [跳过] 保留现有代理设置。" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host ">>> 请确认是否继续执行步骤 3 (重置登录状态)? [Y/N] " -ForegroundColor Magenta -NoNewline
$confirm = Read-Host
if ($confirm -notmatch '^[Yy]') {
    Write-Host "用户取消操作，脚本退出。" -ForegroundColor Red
    exit 0
}

# ============================================================
# 步骤 3: 重置 Cursor 登录状态
# ============================================================
Write-Host ""
Write-Host "=" * 60
Write-Host "  步骤 3/3: 重置 Cursor 本地登录缓存" -ForegroundColor Yellow
Write-Host "=" * 60
Write-Host ""

Write-Host "[说明] Cursor 基于 Electron 构建，其登录会话数据存储在用户数据目录中。"
Write-Host "        清除这些数据可以重置登录状态，强制重新进行完整的 OAuth 流程。"
Write-Host "        你的 Cursor 数据目录: $actualCursorDir"
Write-Host ""

# 列出将要清理的文件/目录
$sessionPaths = @()
$electronDirs = @()

# Electron 标准的会话存储路径
if (Test-Path $actualCursorDir) {
    # 查找所有类似 Electron user data 结构的目录
    $subDirs = Get-ChildItem $actualCursorDir -Directory -ErrorAction SilentlyContinue

    # 需要清理的 Electron 会话文件夹
    $sessionFolderNames = @(
        "Cookies",
        "Cookie-journal",
        "Local Storage",
        "Session Storage",
        "IndexedDB",
        "Cache",
        "Code Cache",
        "Service Worker",
        "GPUCache",
        "DawnCache",
        "WebStorage",
        "blob_storage",
        "shared_proto_db"
    )

    # 需要清理的会话文件
    $sessionFileNames = @(
        "Cookies",
        "Cookies-journal",
        "Network Persistent State",
        "Preferences",
        "TransportSecurity",
        "Trust Tokens",
        "Trust Tokens-journal"
    )

    # 在 Cursor 数据目录下递归查找需要清理的内容
    foreach ($dir in $subDirs) {
        $fullPath = $dir.FullName
        $dirName = $dir.Name

        # 检查是否是 Electron 用户数据目录 (通常包含这些子目录)
        $hasElectronDirs = $false
        foreach ($sessionName in $sessionFolderNames) {
            $sessionPath = Join-Path $fullPath $sessionName
            if (Test-Path $sessionPath) {
                $sessionPaths += $sessionPath
                $hasElectronDirs = $true
            }
        }

        foreach ($sessionName in $sessionFileNames) {
            $sessionFile = Join-Path $fullPath $sessionName
            if (Test-Path $sessionFile) {
                $sessionPaths += $sessionFile
            }
        }

        if ($hasElectronDirs) {
            $electronDirs += $fullPath
        }
    }

    # 也检查子目录下的二级目录 (如 User\Default\ 结构)
    foreach ($dir in $subDirs) {
        $innerDirs = Get-ChildItem $dir.FullName -Directory -ErrorAction SilentlyContinue
        foreach ($innerDir in $innerDirs) {
            foreach ($sessionName in $sessionFolderNames) {
                $sessionPath = Join-Path $innerDir.FullName $sessionName
                if (Test-Path $sessionPath) {
                    $sessionPaths += $sessionPath
                }
            }
            foreach ($sessionName in $sessionFileNames) {
                $sessionFile = Join-Path $innerDir.FullName $sessionName
                if (Test-Path $sessionFile) {
                    $sessionPaths += $sessionFile
                }
            }
        }
    }
}

$sessionPaths = $sessionPaths | Select-Object -Unique

if ($sessionPaths.Count -eq 0) {
    Write-Host "══════════════════ 步骤 3 诊断结果 ══════════════════" -ForegroundColor Cyan
    Write-Host "  结论: 未在 Cursor 数据目录中找到典型的会话文件。" -ForegroundColor Yellow
    Write-Host "        这可能意味着:"
    Write-Host "         - Cursor 尚未安装或从未运行过"
    Write-Host "         - Cursor 使用了非标准的数据存储位置"
    Write-Host ""
    Write-Host "  建议: 请手动检查以下位置是否存在相关文件:" -ForegroundColor Gray
    Write-Host "        - $env:APPDATA\Cursor\" -ForegroundColor Gray
    Write-Host "        - $env:LOCALAPPDATA\Cursor\" -ForegroundColor Gray
    Write-Host "        - $env:USERPROFILE\.cursor\" -ForegroundColor Gray
} else {
    Write-Host ">>> 发现以下会话相关文件/目录 (将被备份后删除):" -ForegroundColor Gray
    Write-Host ""
    foreach ($p in $sessionPaths) {
        $item = Get-Item $p -ErrorAction SilentlyContinue
        if ($item) {
            $sizeInfo = ""
            if ($item -is [System.IO.DirectoryInfo]) {
                $size = (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                if ($size) {
                    $sizeInfo = "  (~{0:N2} MB)" -f ($size / 1MB)
                }
            }
            Write-Host "  - $p$sizeInfo"
        }
    }

    Write-Host ""
    Write-Host "══════════════════ 步骤 3 诊断结果 ══════════════════" -ForegroundColor Cyan
    Write-Host "  共发现 $($sessionPaths.Count) 个会话相关文件/目录" -ForegroundColor Yellow
    Write-Host "  将创建备份后删除这些文件。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [警告] 这将清除 Cursor 中的所有登录状态、Cookie、本地存储等数据。" -ForegroundColor Red
    Write-Host "         你的工作区设置、扩展等应该不受影响，但建议在执行前关闭 Cursor。" -ForegroundColor Red

    Write-Host ""
    Write-Host ">>> 是否要备份并清除这些会话数据? [Y/N] " -ForegroundColor Magenta -NoNewline
    $confirmClean = Read-Host
    if ($confirmClean -match '^[Yy]') {
        Write-Host ""

        # 检查 Cursor 是否正在运行
        $cursorProcess = Get-Process -Name "Cursor" -ErrorAction SilentlyContinue
        if ($cursorProcess) {
            Write-Host "  [警告] 检测到 Cursor 进程正在运行!" -ForegroundColor Red
            Write-Host "         建议先关闭 Cursor 再继续操作。" -ForegroundColor Red
            Write-Host ">>> 是否强制继续 (不推荐)? [Y/N] " -ForegroundColor Magenta -NoNewline
            $forceContinue = Read-Host
            if ($forceContinue -notmatch '^[Yy]') {
                Write-Host "  请先手动关闭 Cursor，然后重新运行此脚本。" -ForegroundColor Yellow
                Write-Host "  终止 Cursor 进程的命令: taskkill /F /IM Cursor.exe" -ForegroundColor Gray
                exit 0
            }
            Write-Host "  正在强制终止 Cursor 进程..." -ForegroundColor Yellow
            Stop-Process -Name "Cursor" -Force -ErrorAction SilentlyContinue
            Write-Host "  Cursor 进程已终止。" -ForegroundColor Gray
        }

        # 创建备份
        $backupRoot = "$env:USERPROFILE\Cursor-Session-Backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Write-Host ">>> 备份目录: $backupRoot" -ForegroundColor Gray
        Write-Host ""

        $backedUpCount = 0
        $deletedCount = 0

        foreach ($p in $sessionPaths) {
            $relativePath = $p.Replace($actualCursorDir, "").TrimStart('\', '/')
            if (-not $relativePath) { $relativePath = (Split-Path $p -Leaf) }

            $backupPath = Join-Path $backupRoot $relativePath

            try {
                # 创建父目录
                $backupParent = Split-Path $backupPath -Parent
                if (-not (Test-Path $backupParent)) {
                    New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
                }

                # 复制到备份
                Copy-Item $p -Destination $backupPath -Recurse -Force -ErrorAction Stop
                $backedUpCount++

                # 删除原文件
                Remove-Item $p -Recurse -Force -ErrorAction Stop
                $deletedCount++

                Write-Host "  [已处理] $relativePath" -ForegroundColor Gray
            } catch {
                Write-Host "  [失败] $relativePath : $_" -ForegroundColor Red
            }
        }

        Write-Host ""
        Write-Host "  [完成] 备份了 $backedUpCount 项，删除了 $deletedCount 项。" -ForegroundColor Green

        # 也检查并清理 shared_proto_db 中的 auth 相关内容
        $sharedProtoDb = "$actualCursorDir\shared_proto_db"
        if (Test-Path $sharedProtoDb) {
            Write-Host "  [信息] 发现 shared_proto_db 目录，建议一并清理。" -ForegroundColor Yellow
            Write-Host "         该目录通常包含账户和认证相关的元数据。" -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "══════════════════ 所有步骤执行完毕 ══════════════════" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  后续操作建议:" -ForegroundColor Green
        Write-Host "  1. 重启计算机 (推荐，确保所有环境变量和缓存完全清除)" -ForegroundColor White
        Write-Host "  2. 如果你清除了系统级环境变量，重启后修改才会生效" -ForegroundColor White
        Write-Host "  3. 重启后打开 Cursor，重新进行登录" -ForegroundColor White
        Write-Host "  4. 登录时确保默认浏览器没有被其他程序占用" -ForegroundColor White
        Write-Host "  5. 如果问题仍然存在，请检查是否有安全软件/防火墙拦截了本地回调" -ForegroundColor White
        Write-Host ""
        Write-Host "  备份文件位于: $backupRoot" -ForegroundColor Gray
        Write-Host "  如需恢复，将备份文件夹中的内容复制回 $actualCursorDir 即可" -ForegroundColor Gray
        Write-Host ""

    } else {
        Write-Host "  [跳过] 保留现有登录缓存。" -ForegroundColor Gray
        Write-Host ""
        Write-Host "══════════════════ 脚本执行完毕 ══════════════════════" -ForegroundColor Cyan
    }
}

# 额外建议: 检查 Windows 防火墙/代理设置
Write-Host ""
Write-Host "══════════════════ 补充诊断建议 ══════════════════════" -ForegroundColor Cyan
Write-Host ""

# 检查 IE 代理 (WinINET 代理，会影响许多应用)
$ieProxy = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
if ($ieProxy.ProxyEnable -eq 1) {
    Write-Host "  [注意] 检测到系统级 Internet 代理已启用：" -ForegroundColor Yellow
    Write-Host "         代理服务器: $($ieProxy.ProxyServer)" -ForegroundColor Yellow
    Write-Host "         这可能会干扰 Cursor 的网络通信。" -ForegroundColor Yellow
    Write-Host "         可在「Internet 选项 -> 连接 -> 局域网设置」中禁用。" -ForegroundColor Gray
} else {
    Write-Host "  [正常] 系统级 Internet 代理未启用。" -ForegroundColor Green
}

Write-Host ""
Write-Host "脚本执行完毕。按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
