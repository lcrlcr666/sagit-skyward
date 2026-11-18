# 凭据手册（Windows 本地 + GitHub Actions）

本项目会用到**四种完全不同的"key"**，别混：

| # | 凭据 | 干什么 | 存在哪 | 会过期吗 |
|---|---|---|---|---|
| 1 | **SSH key** | `git push` 代码 | `~/.ssh/id_ed25519` + GitHub 账号 | 不会 |
| 2 | **PAT**（classic/fine-grained） | 调 API：触发 workflow、读构建状态、下载 artifact | 系统凭据管理器 / `gh` | 会（必须设） |
| 3 | **`GITHUB_TOKEN`** | CI 里发 Release、拉 artifact | GitHub 自动注入，**你不需要创建** | 6 小时，自动 |
| 4 | **Android 签名密钥** | 给 `recovery.img` 签名 | 仓库 secret（base64）/ 本地 `security/` | 不会（但泄露=别人能伪造你的包） |

**日常推代码只要 #1**。#2 只在你想命令行触发构建时用。#4 是可选的（不签也能用，只是 `ro.build.tags` 是 test-keys）。

---

## 1. SSH key（推荐，零泄露面）

```powershell
# 生成（一路回车，passphrase 建议设一个）
ssh-keygen -t ed25519 -C "sagit-skyward@$(hostname)" -f "$env:USERPROFILE\.ssh\id_ed25519"

# 启动 agent 并加载（Windows 自带的 ssh-agent 服务需先开）
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"

# 复制公钥 → 打开 https://github.com/settings/keys → New SSH key → 粘贴
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
```

挂好之后验证并把 remote 换成 SSH：

```powershell
ssh -T git@github.com
# 期望：Hi <用户名>! You've successfully authenticated, but GitHub does not provide shell access.

cd C:\Users\l1212\Desktop\sagit-skyward
git remote set-url origin git@github.com:<你的用户名>/sagit-skyward.git
git remote -v
```

> 组织仓库需要 SSO 时，去 https://github.com/settings/keys 对应 key 旁点 **Configure SSO** → Authorize。

---

## 2. PAT（只在你需要命令行触发构建时）

创建：https://github.com/settings/personal-access-tokens/new （fine-grained，推荐）
或 classic 预填：https://github.com/settings/tokens/new?scopes=repo,workflow&description=sagit-skyward

**fine-grained 最小权限**（Repository access 只选 `sagit-skyward`）：

| 权限 | 级别 | 用途 |
|---|---|---|
| Contents | Read and write | push、发 Release |
| Workflows | Read and write | 改 `.github/workflows/**` |
| Actions | Read | 读 run 状态、下载 artifact |
| Metadata | Read | 自动带，必选 |

**存起来（不要贴聊天、不要进 remote URL）**：

```powershell
# 方式 A：gh CLI 托管（推荐）
winget install --id GitHub.cli -e
gh auth login      # 选 HTTPS → Paste an authentication token
gh auth status
gh auth token      # 需要时取回

# 方式 B：直接进当前会话，不落盘
$env:GH_TOKEN = Read-Host "粘贴 PAT"      # 不回显

# 方式 C：持久化到用户环境变量（会被同用户所有进程读到，谨慎）
[Environment]::SetEnvironmentVariable("GH_TOKEN", (Read-Host "PAT"), "User")
```

⚠️ 自查有没有踩过坑：

```powershell
git remote -v | Select-String 'ghp_|github_pat_|x-access-token'   # 有输出=泄露在 .git/config
```

---

## 3. `GITHUB_TOKEN`：CI 里的 key，不用你管

`.github/workflows/build.yml` 已经写好：

```yaml
permissions:
  contents: write        # 发 Release 需要
```

`release` job 里 `softprops/action-gh-release` 读的就是自动注入的 `secrets.GITHUB_TOKEN`。
**你什么都不用配**，网页点 `Run workflow` 即可。

限制（记住这两条就够了）：
- 只能访问**当前仓库**，读不到别的仓库（所以要拉私有内核仓库得用 #1 的 deploy key）；
- 用它做的事件**不会触发新的 workflow**（防递归），所以"用 CI 触发 CI"必须用 PAT。

---

## 4. Android 签名密钥（可选但建议）

### 4.1 生成（AOSP 标准三件套）

```bash
mkdir -p keys && cd keys
openssl genrsa -out releasekey.key 2048
openssl req -new -x509 -key releasekey.key -out releasekey.x509.pem -days 10000 \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=skyward/OU=sagit/CN=skyward-sagit"
openssl pkcs8 -topk8 -inform PEM -outform DER -in releasekey.key -out releasekey.pk8 -nocrypt
```

`recovery.img` 只需要这一对 `releasekey.pk8` + `releasekey.x509.pem`。

### 4.2 本地构建直接用

```makefile
# device/xiaomi/sagit/BoardConfig.mk（把最后一行取消注释）
PRODUCT_DEFAULT_DEV_CERTIFICATE := device/xiaomi/sagit/security/releasekey
```

把 `releasekey.pk8` / `releasekey.x509.pem` 放到 `device/xiaomi/sagit/security/`，
并**确保 `security/` 在 `.gitignore` 里**（`.gitignore` 已含 `*.img`，请手动加 `device/xiaomi/sagit/security/`）。

### 4.3 注入 CI（base64 → secret）

```powershell
# 本地打包成 secret（base64 单行）
cd C:\Users\l1212\Desktop\sagit-skyward\device\xiaomi\sagit
Compress-Archive -Path security\* -DestinationPath $env:TEMP\keys.zip -Force
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:TEMP\keys.zip"))
$b64 | Set-Clipboard      # 粘到仓库 Settings → Secrets → New secret: SIGNING_KEY_B64
Remove-Item "$env:TEMP\keys.zip"
```

workflow 里加一步（放在编译之前）：

```yaml
      - name: 注入签名密钥
        if: ${{ secrets.SIGNING_KEY_B64 != '' }}
        env:
          SIGNING_KEY_B64: ${{ secrets.SIGNING_KEY_B64 }}
        run: |
          mkdir -p device/xiaomi/sagit/security
          echo "$SIGNING_KEY_B64" | base64 -d > /tmp/keys.zip
          unzip -o -q /tmp/keys.zip -d device/xiaomi/sagit/security
          rm -f /tmp/keys.zip
```

⚠️ **BL 锁的现实**：Mi6 锁着 BL 时，boot/recovery 走 AVB 校验，自己签的 `recovery.img` 刷进去会
`FAILED (remote: 'partition table doesn't exist')` 或直接不进系统。**解锁 BL 之后自签名才有效**，
且解锁会清数据。

---

## 5. 私有内核仓库（deploy key，别用 PAT）

`kernel_mode=source` 且内核仓库是私有时：

```bash
ssh-keygen -t ed25519 -f ~/.ssh/sagit_kernel_deploy -N ""
# 把 .pub 加到内核仓库 Settings → Deploy keys（勾 Allow write? 不需要，只读）
# 私钥全文存成 secret: KERNEL_DEPLOY_KEY
```

workflow 片段：

```yaml
      - name: 配置内核仓库 deploy key
        if: ${{ env.KERNEL_MODE == 'source' }}
        run: |
          mkdir -p ~/.ssh && chmod 700 ~/.ssh
          echo "${{ secrets.KERNEL_DEPLOY_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan github.com >> ~/.ssh/known_hosts
          git config --global url."git@github.com:".insteadOf "https://github.com/"
```

---

## 6. 红线清单

1. 凭据**不进**：聊天、issue、commit、Actions 日志、remote URL、`.env` 被跟踪文件。
2. PAT **必须设过期**（30 天），用完 `Delete` 而不是留着。
3. 只给最小 scope；`workflow` 是提权关键项，能给细粒度就别给 classic `repo`。
4. 泄露后顺序：**先吊销** → 查 security log → 查 Actions 异常运行 → 轮换所有 `secrets.*`。
5. 签名私钥泄露比 PAT 更严重（能伪造你的 ROM），发现即重新生成并重新发版。

## 7. 排错表

| 现象 | 原因 | 处理 |
|---|---|---|
| `Permission denied (publickey)` | key 没加载 / 没挂到账号 | `ssh-add -l` 看列表；`ssh -T git@github.com` 复测 |
| `refusing to allow a PAT to create or update workflow` | PAT 缺 `workflow` scope | 重新生成，勾 `workflow` |
| `Bad credentials` | token 过期/抄错/已被吊销 | `gh auth status`；重新生成 |
| `Resource not accessible by integration` | 用了 `GITHUB_TOKEN` 干越权的事（跨仓库/触发 CI） | 换 PAT 或 deploy key |
| `gh: workflow not found` | 分支上还没有 `build.yml` | 先 push 再 `gh workflow run` |
| artifact 下载 404 | run 还没结束 / retention 过期 | 等 `conclusion=success`，retention 14 天 |
