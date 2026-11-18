#Requires -Version 5.1
<#
.SYNOPSIS
    推送代码 → 触发 GitHub Actions → 轮询状态 → 下载产物（Windows）
.DESCRIPTION
    凭据策略：
      * push 走 SSH（不需要任何 token）
      * 触发/查询优先用 gh CLI（token 由 gh 自己托管）
      * 没有 gh 时退化为 $env:GH_TOKEN（只在本进程内存里，不写文件、不打印）
    安全护栏：
      * remote URL 里若含 token 直接中止
      * GH_TOKEN 永不写入命令回显
.EXAMPLE
    $env:GH_TOKEN = Read-Host "PAT"
    .\scripts\ci\push-and-run.ps1 -Repo "me/sagit-skyward" -KernelUrl "https://x/Image.gz-dtb"
.EXAMPLE
    # 走 SSH + gh（推荐，全程无 token 环境变量）
    gh auth login
    .\scripts\ci\push-and-run.ps1 -Repo "me/sagit-skyward" -KernelMode source -Download
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$Ref = 'main',
    [string]$Message = 'ci: rebuild',
    [ValidateSet('prebuilt', 'source')][string]$KernelMode = 'prebuilt',
    [string]$KernelUrl = '',
    [string]$RootfsSizeMb = '2560',
    [switch]$MakeRelease,
    [switch]$SkipPush,
    [switch]$Download,
    [string]$OutDir = 'out\ci',
    [int]$PollSeconds = 30,
    [int]$TimeoutMinutes = 200
)

$ErrorActionPreference = 'Stop'

function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Fail($t) { Write-Host "!! $t" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- 定位仓库根
$gitRoot = (& git rev-parse --show-toplevel 2>$null)
if (-not $gitRoot) { Fail "当前目录不在 git 仓库里" }
Set-Location $gitRoot
Write-Host "仓库根：$gitRoot"

# ---------------------------------------------------------------- 护栏 1：remote 不含 token
$remote = (& git remote get-url origin 2>$null)
if ($remote -match 'ghp_|github_pat_|x-access-token|:[^/]+@github\.com') {
    Fail "remote URL 里带了凭据，先执行：git remote set-url origin git@github.com:$Repo.git"
}
Write-Host "remote：$remote"

# ---------------------------------------------------------------- 护栏 2：拒绝硬编码 token
$bad = Get-ChildItem -Recurse -File -Include *.ps1, *.sh, *.yml, *.yaml, *.mk, *.md -ErrorAction SilentlyContinue |
       Where-Object { $_.FullName -notmatch '\\out\\|\\.git\\' } |
       Select-String -Pattern 'ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}' -List
if ($bad) {
    Write-Host "!! 仓库里发现疑似硬编码 token：" -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "   $($_.Path):$($_.LineNumber)" }
    Fail "清掉它们（并立即吊销该 token）再重试"
}

# ---------------------------------------------------------------- 1. 推送
if (-not $SkipPush) {
    Step "1/4 推送代码"
    & git add -A
    $dirty = (& git status --porcelain)
    if ($dirty) {
        & git commit -m $Message | Out-Host
    } else {
        Write-Host "工作区干净，跳过 commit"
    }
    & git push origin "HEAD:$Ref"
    if ($LASTEXITCODE -ne 0) { Fail "push 失败（SSH key 是否已加载？ssh -T git@github.com）" }
} else {
    Step "1/4 跳过推送（-SkipPush）"
}

# ---------------------------------------------------------------- 2. 触发
Step "2/4 触发 workflow"
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
$useGh = [bool]$ghCmd

if ($KernelMode -eq 'prebuilt' -and -not $KernelUrl) {
    Write-Host "提示：kernel_mode=prebuilt 需要 -KernelUrl，否则该 job 会明确报错退出。" -ForegroundColor Yellow
}

$inputs = @{
    kernel_mode     = $KernelMode
    prebuilt_kernel_url = $KernelUrl
    rootfs_size_mb  = $RootfsSizeMb
    make_release    = ($(if ($MakeRelease) { 'true' } else { 'false' }))
}

if ($useGh) {
    Write-Host "使用 gh CLI 触发"
    $ghArgs = @('workflow', 'run', 'build.yml', '--ref', $Ref)
    foreach ($k in $inputs.Keys) { $ghArgs += @('-f', "$k=$($inputs[$k])") }
    & gh @ghArgs
    if ($LASTEXITCODE -ne 0) { Fail "gh workflow run 失败（分支上是否已有 build.yml？）" }
}
elseif ($env:GH_TOKEN) {
    Write-Host "使用 REST + `$env:GH_TOKEN 触发"
    $body = @{ ref = $Ref; inputs = $inputs } | ConvertTo-Json -Depth 6
    $headers = @{ Authorization = "Bearer $($env:GH_TOKEN)"; Accept = 'application/vnd.github+json' }
    try {
        Invoke-RestMethod -Method Post -Body $body -Headers $headers `
            -Uri "https://api.github.com/repos/$Repo/actions/workflows/build.yml/dispatches" | Out-Null
    } catch {
        Fail "dispatch 失败：$($_.Exception.Message)（PAT 需要 repo+workflow，或 fine-grained 的 Actions:write）"
    }
}
else {
    Fail "既没有 gh CLI 也没有 `$env:GH_TOKEN。任一即可：winget install GitHub.cli; gh auth login"
}

# ---------------------------------------------------------------- 3. 轮询
Step "3/4 等待构建"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$runId = $null

if ($useGh) {
    # 等新 run 出现
    for ($i = 0; $i -lt 20 -and -not $runId; $i++) {
        Start-Sleep -Seconds 6
        $j = & gh run list --workflow build.yml --branch $Ref --limit 1 --json databaseId,status,conclusion,url,createdAt 2>$null
        if ($j) {
            $r = ($j | ConvertFrom-Json)[0]
            if ($r) { $runId = $r.databaseId; $runUrl = $r.url }
        }
    }
    if (-not $runId) { Fail "没等到新的 run（Actions 是否被禁用？）" }
    Write-Host "run id=$runId  $runUrl"

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $PollSeconds
        $s = (& gh run view $runId --json status,conclusion | ConvertFrom-Json)
        Write-Host ("  {0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $s.status)
        if ($s.status -eq 'completed') {
            if ($s.conclusion -ne 'success') { Fail "构建结论：$($s.conclusion)（$runUrl）" }
            Write-Host "构建成功" -ForegroundColor Green
            break
        }
    }
} else {
    $headers = @{ Authorization = "Bearer $($env:GH_TOKEN)"; Accept = 'application/vnd.github+json' }
    for ($i = 0; $i -lt 20 -and -not $runId; $i++) {
        Start-Sleep -Seconds 6
        $resp = Invoke-RestMethod -Headers $headers `
            -Uri "https://api.github.com/repos/$Repo/actions/workflows/build.yml/runs?branch=$Ref&per_page=1"
        if ($resp.workflow_runs.Count -gt 0) { $runId = $resp.workflow_runs[0].id; $runUrl = $resp.workflow_runs[0].html_url }
    }
    if (-not $runId) { Fail "没等到新的 run" }
    Write-Host "run id=$runId  $runUrl"

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $PollSeconds
        $run = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/actions/runs/$runId"
        Write-Host ("  {0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $run.status)
        if ($run.status -eq 'completed') {
            if ($run.conclusion -ne 'success') { Fail "构建结论：$($run.conclusion)（$runUrl）" }
            Write-Host "构建成功" -ForegroundColor Green
            break
        }
    }
}

# ---------------------------------------------------------------- 4. 下载
if ($Download) {
    Step "4/4 下载产物"
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    if ($useGh) {
        & gh run download $runId -D $OutDir
        if ($LASTEXITCODE -ne 0) { Fail "gh run download 失败" }
    } else {
        $headers = @{ Authorization = "Bearer $($env:GH_TOKEN)"; Accept = 'application/vnd.github+json' }
        $arts = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/actions/runs/$runId/artifacts"
        foreach ($a in $arts.artifacts) {
            $zip = Join-Path $OutDir "$($a.name).zip"
            Write-Host "  ↓ $($a.name) ($([math]::Round($a.size_in_bytes/1MB,1)) MB)"
            Invoke-WebRequest -Headers $headers -Uri $a.archive_download_url -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath (Join-Path $OutDir $a.name) -Force
            Remove-Item $zip
        }
    }
    Get-ChildItem -Recurse $OutDir | Where-Object { -not $_.PSIsContainer } |
        Select-Object FullName, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table -AutoSize
    Write-Host "还原大镜像：cat rootfs-sagit.img.part-* > rootfs.img" -ForegroundColor Yellow
}
else {
    Step "4/4 跳过下载（加 -Download 自动取产物）"
    Write-Host "网页查看：$runUrl"
}
