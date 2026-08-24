---
name: lcron-exp-dev-machine
description: 连接 LCRON_EXP 的 KML 开发机，用于公开数据集实验
version: 1.0.0
---

# LCRON_EXP 开发机连接

这个 skill 用于连接并复用以下 KML 开发机，适合运行公开数据集实验：

- Web 入口：[KML machine terminal](https://kml.corp.kuaishou.com/#/system/project/10049/machine-terminal/100000920?fullScreen=1&originPid=10049&provider=Ailurus)
- Pod：`kml-dtmachine-100000920-prod-worker-0`
- Container：`worker`
- Namespace：`kubekml`
- Cluster：`kce-aip-wlf1-hb2az1`
- Server：`kml.corp.kuaishou.com`

## Token 安全配置

不要把 KML Token 写进 Git 仓库、脚本或命令历史。首次使用时，在本机安全保存一份权限为 `600` 的环境文件：

```bash
mkdir -p "$HOME/.config/lcron-exp"
read -rsp 'KML token: ' KML_TOKEN
printf '\n'
printf 'export KML_TOKEN=%q\n' "$KML_TOKEN" > "$HOME/.config/lcron-exp/kml.env"
chmod 600 "$HOME/.config/lcron-exp/kml.env"
unset KML_TOKEN
```

每次连接前加载：

```bash
source "$HOME/.config/lcron-exp/kml.env"
test -n "$KML_TOKEN" || { echo 'KML_TOKEN 未设置'; return 1 2>/dev/null || exit 1; }
```

Token 过期时，按 `magic/kaiworks_webshell/获取kml_token.md` 的流程重新生成并覆盖本机文件。

## 一键连接脚本

当前目录的 `connect.sh` 已把“SSH → KIM → Relay → kml_login → 持久 tmux”串起来：

```bash
cd /Users/zz/Desktop/code/LCRON_EXP
./connect.sh
```

首次连接时，脚本会打开 tmux 并等待 KIM 确认；批准后会自动执行 `kml_login`。脚本默认读取 `~/.config/lcron-exp/kml.env`，文件不存在时会安全地交互式询问 Token。

```bash
# 重新进入已有会话
./connect.sh attach

# 停止会话（会终止其中仍在前台运行的命令）
./connect.sh stop
```

## 第一跳：登录跳板机

本机先通过 SSH 登录跳板机，KIM 确认是 SSH 登录流程的一部分：

```bash
ssh zhangzhen24@relay.corp.kuaishou.com
```

本机已检测到默认私钥 `/Users/zz/.ssh/id_rsa`（权限为 `600`），SSH 会自动优先尝试它；无需把私钥内容复制到仓库或发送出来。如需显式指定：

```bash
ssh -i /Users/zz/.ssh/id_rsa zhangzhen24@relay.corp.kuaishou.com
```

收到 KIM 确认后批准登录，进入跳板机 shell。`kml_login` 应在跳板机上执行，而不是在本机执行。

## 第二跳：登录 KML 开发机

在跳板机 shell 中执行：

```bash
kml_login \
  --pod=kml-dtmachine-100000920-prod-worker-0 \
  --container=worker \
  --namespace=kubekml \
  --cluster=kce-aip-wlf1-hb2az1 \
  --token='REPLACE_WITH_KML_TOKEN' \
  --server=kml.corp.kuaishou.com
```

上面的 `REPLACE_WITH_KML_TOKEN` 由本机生成的完整命令替换；不要在跳板机上假定存在本机的 `kml.env` 文件。

## 持久连接（推荐）

建议在本机用 `tmux` 保持 SSH 会话；本机终端断开后，跳板机和开发机里的实验仍会继续运行。

```bash
SESSION='lcron-exp-kml'

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux attach -t "$SESSION"
else
  tmux new-session -d -s "$SESSION"
  tmux send-keys -t "$SESSION" 'ssh zhangzhen24@relay.corp.kuaishou.com' C-m
  tmux attach -t "$SESSION"
fi
```

进入 tmux 后，先完成 KIM 确认；进入跳板机 shell 后，再执行上面的 `kml_login` 命令。

由于 `kml.env` 在本机，跳板机不会自动拥有这个文件。可在本机加载 Token 后生成一条临时命令，再复制到跳板机执行：

```bash
source "$HOME/.config/lcron-exp/kml.env"
printf 'kml_login --pod=kml-dtmachine-100000920-prod-worker-0 --container=worker --namespace=kubekml --cluster=kce-aip-wlf1-hb2az1 --token=%q --server=kml.corp.kuaishou.com\n' "$KML_TOKEN"
```

常用会话操作：

```bash
# 重新连接已有会话
tmux attach -t lcron-exp-kml

# 从会话中退出但不停止实验：按 Ctrl-b，再按 d

# 查看会话是否还在
tmux has-session -t lcron-exp-kml && echo 'session alive'

# 结束会话（会停止其中仍在前台运行的命令）
tmux kill-session -t lcron-exp-kml
```

## 通过 magic 的自动登录脚本

如果本机没有 `kml_login`，可使用 magic 中的堡垒机转发脚本。该脚本会创建自己的 `tmux` 会话，并执行 `ssh relay`。先在本机 `~/.ssh/config` 中配置 SSH 别名（不写入仓库）：

`config.ini` 只负责提供脚本参数和会话配置，不会绕过 Relay 的 SSH/KIM 认证。首次建立 SSH 会话时仍需要你在 KIM 中确认；如果 Relay 会话已经复用或 KIM 已自动放行，才可能不再出现确认。

```sshconfig
Host relay
  HostName relay.corp.kuaishou.com
  User zhangzhen24
```

然后运行：

> 该脚本会把展开后的登录命令显示在本机输出中，因此只在本机可信、且确认不会共享终端日志时使用。Token 仍不会写入本文件。

```bash
cd /Users/zz/Desktop/code/phoenix/magic/k8s_login
read -rsp 'KML token: ' KML_TOKEN
printf '\n'
sh auto-k8s-login.sh "kml_login --pod=kml-dtmachine-100000920-prod-worker-0 --container=worker --namespace=kubekml --cluster=kce-aip-wlf1-hb2az1 --token=$KML_TOKEN --server=kml.corp.kuaishou.com"
unset KML_TOKEN
```

脚本会先 SSH 到 `relay`，KIM 确认后再执行 `kml_login`。

脚本输出会话名后，可用以下命令重新进入：

```bash
tmux attach -t '<脚本输出的会话名>'
```

## 实验建议

- 登录后先执行 `pwd`、`nvidia-smi`、`df -h` 和 `python3 --version` 检查环境。
- 长时间实验放在 `tmux` 中运行，并把 stdout/stderr 重定向到日志文件。
- 不要在日志、提交记录或截图中暴露 `KML_TOKEN`。

# 访问外网需要添加
export http_proxy=http://10.66.81.222:11080 https_proxy=http://10.66.81.222:11080 no_proxy=localhost,127.0.0.1,localaddress,localdomain.com,internal,corp.kuaishou.com,test.gifshow.com,staging.kuaishou.com

# 上传下载文件与本地交互
wget -O csc_linux_amd64.tar.gz https://halo.corp.kuaishou.com/api/cloud-storage/v1/public-objects/devcloud-product/cloud-storage%2Fcsc_linux_amd64_1.0.tar.gz && tar -xzvf csc_linux_amd64.tar.gz 
上传命令：
./csc upload filepath zz_carm_test/filepath
下载命令：
./csc get zz_carm_test/filename filepath

## 公开数据集实验路径

开发机上的 RecFlow 数据已经准备在：

```text
/share/ad/zhangzhen24/recflow/data/
```

开发机仓库建议将 `data` 链接到该目录，避免复制 224GB 数据：

```bash
cd /home/zhangzhen24/experiments/LCRON_EXP
ln -sfn /share/ad/zhangzhen24/recflow/data data
```

运行 LCRON 两阶段实验时，需要同时加入仓库根目录和 `deep_components` 到 `PYTHONPATH`：

```bash
cd /home/zhangzhen24/experiments/LCRON_EXP
CUDA_VISIBLE_DEVICES=0 \
PYTHONPATH="$PWD:$PWD/deep_components" \
bash two_stage/run_x2.sh all lcron 0 50 30 .
```

后台运行并查看日志：

```bash
nohup env CUDA_VISIBLE_DEVICES=0 \
  PYTHONPATH="$PWD:$PWD/deep_components" \
  bash two_stage/run_x2.sh all lcron 0 50 30 . \
  > logs/launcher_lcron_E30.log 2>&1 &

tail -f logs/TRAIN_bs-1024_lr-1e-2_tau50_lcron-1st_E30_S2.log
```
