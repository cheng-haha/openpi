# OpenPI 环境创建

本文根据《PI0、PI0.5 算法训练、推理 (同步推理, RTC推理).pdf》整理 openpi 环境创建流程。这里要严格区分两台机器或两类角色：

- 云端 GPU 机器 / 训练机：处理数据、计算 norm stats、训练模型、加载 checkpoint、启动策略服务，需要完整 openpi 环境。
- 本地 Y1 控制机：只负责相机读取、机械臂状态读取、动作执行、请求云端策略服务，只需要最小推理环境。

本地 Y1 控制机不要安装 `jax`、`torch`、`lerobot` 这些完整训练依赖；这些依赖只应该出现在云端 GPU 机器或训练机上。

## 1. 环境边界

建议按下面的边界安排环境：

| 角色 | 位置 | 环境 | 主要用途 |
| --- | --- | --- | --- |
| 云端 GPU / 训练机 | AutoDL、服务器、本地高显存 GPU | 完整 openpi 环境，Python 3.11 | 数据转换、norm stats、训练、数据集评估、`serve_policy` |
| 本地 Y1 控制机 | 连接机械臂和相机的机器 | 最小推理环境，Python 3.10 | 读取相机和机械臂状态、调用云端 policy、执行动作 |

给 Codex、Claude Code 或其他自动化脚本的执行规则：

- 只要任务涉及数据预处理、LeRobot 数据集、norm stats、训练、数据集评估、checkpoint、`serve_policy`，就在云端 GPU / 训练机使用完整 openpi 环境。
- 只要任务是在本地 Y1 控制机上调用云端策略并执行真机动作，就只使用最小推理环境 `openpi_local_infer`。
- 本地 Y1 控制机默认不要执行 `uv sync`，也不要安装 `jax`、`torch`、`lerobot`。除非明确要求“本机 GPU 直接跑完整 openpi 推理”，否则本地只按最小环境处理。
- 云端 / 训练机不直接连接 Y1 机械臂和相机；本地 Y1 控制机不负责训练和处理大数据集。

PDF 中提到 PI 模型实机推理显存占用约 `9084 MB`。训练显存占用更高，建议使用云端 GPU 或本地高显存 GPU。

## 2. 云端 / 训练机：拉取源码

```bash
git clone https://github.com/IMETA-Robotics/openpi.git
cd openpi
git checkout imeta_robotics
```

如果已经有仓库，只需要确认分支：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
git branch --show-current
```

期望分支：

```text
imeta_robotics
```

## 3. 云端 / 训练机：创建完整 openpi 环境

openpi 要求 Python 3.11：

```bash
conda create -n openpi python=3.11 -y
conda activate openpi
pip install uv
```

同步依赖并安装当前项目：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
GIT_LFS_SKIP_SMUDGE=1 uv sync
GIT_LFS_SKIP_SMUDGE=1 uv pip install -e .
```

`GIT_LFS_SKIP_SMUDGE=1` 用于避免依赖同步时自动拉取大文件。

## 4. 云端 / 训练机：下载慢时切换 PyPI 源

如果整体下载速度很慢，可以临时使用清华源：

```bash
export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
GIT_LFS_SKIP_SMUDGE=1 uv sync
GIT_LFS_SKIP_SMUDGE=1 uv pip install -e .
```

如果后面想恢复默认源，关闭当前终端或取消变量：

```bash
unset UV_DEFAULT_INDEX
```

## 5. 云端 / 训练机：LeRobot 下载慢时使用本地路径

如果安装 LeRobot 依赖特别慢，尤其是在 AutoDL 云服务器上，可以提前下载指定 commit：

```bash
cd /root/autodl-tmp
git clone https://github.com/huggingface/lerobot.git
cd lerobot
git checkout 0cf864870cf29f4738d3ade893e6fd13fbd7cdb5
```

然后修改 openpi 的 `pyproject.toml`：把远程 `lerobot` 依赖注释掉，打开本地路径依赖，并改成实际路径，例如：

```toml
# lerobot = { git = "https://github.com/huggingface/lerobot.git", rev = "0cf864870cf29f4738d3ade893e6fd13fbd7cdb5" }
lerobot = { path = "/root/autodl-tmp/lerobot", editable = true }
```

修改后重新同步：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
GIT_LFS_SKIP_SMUDGE=1 uv sync
GIT_LFS_SKIP_SMUDGE=1 uv pip install -e .
```

## 6. 云端 / 训练机：安装 ffmpeg

LeRobot Dataset 使用视频或解析视频数据时需要 ffmpeg：

```bash
conda install ffmpeg -c conda-forge
```

如果后续解析 LeRobot Dataset 出问题，可以固定版本：

```bash
conda install ffmpeg=7.1.1 -c conda-forge
```

## 7. 云端 / 训练机：AutoDL 路径变量

云端训练建议把源码、预训练模型、数据集和缓存放到数据盘，例如 `/root/autodl-tmp`。当前仓库提供：

```text
scripts/set_env.sh
```

默认内容：

```bash
export OPENPI_DATA_HOME="/root/autodl-tmp/openpi_base_model/openpi"
export XDG_CACHE_HOME="/root/autodl-tmp/.cache"
export HF_HOME="/root/autodl-tmp/.cache/huggingface_hub/"
export HF_LEROBOT_HOME="/root/autodl-tmp/lerobot_dataset/"
```

训练或计算 norm stats 前执行：

```bash
cd /path/to/openpi
source scripts/set_env.sh
```

变量含义：

- `OPENPI_DATA_HOME`: openpi 预训练模型缓存目录。设置后会优先从这里找 `pi0_base`、`pi05_base` 等模型。
- `XDG_CACHE_HOME`: 通用缓存目录。
- `HF_HOME`: HuggingFace Hub 缓存目录。
- `HF_LEROBOT_HOME`: LeRobot Dataset 本地目录。加载数据时会从 `HF_LEROBOT_HOME/<repo_id>` 查找。

## 8. 云端 / 训练机：文件传输

本地已经处理好的 LeRobot 数据集、预训练模型或 checkpoint 可以用 `rclone` 在本地和云端之间传输。

本地数据传到远端示例：

```bash
rclone copy pick_two_water_bottle_20251215/ \
  autodl-rtx-pro-6000://root/autodl-tmp/lerobot_dataset/ \
  -P \
  --sftp-host connect.westd.seetacloud.com \
  --sftp-user root \
  --sftp-port 45696
```

远端文件传回本地示例：

```bash
rclone copy \
  autodl-rtx-pro-6000://root/autodl-tmp/openpi/checkpoints/pi05_base_full_dual_arm/exp/30000 \
  ./checkpoints_from_cloud/ \
  -P \
  --sftp-host connect.westd.seetacloud.com \
  --sftp-user root \
  --sftp-port 45696
```

需要根据自己的服务器修改：

- `autodl-rtx-pro-6000`: rclone 远程配置名称。
- `--sftp-host`: 服务器连接地址。
- `--sftp-user`: 用户名。
- `--sftp-port`: 端口。

## 9. 本地 Y1 控制机：创建最小推理环境

如果使用云端 GPU 启动策略服务，本地 Y1 控制机不需要完整训练环境。不要在本地控制机上跑 `uv sync`，也不要安装 `jax`、`torch`、`lerobot`。当前仓库提供：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
bash scripts/inference_remote/setup_local_env.sh
conda activate openpi_local_infer
source /opt/ros/humble/setup.bash
```

该环境主要包含：

- `openpi-client`
- `y1_sdk`
- ROS2 Humble 提供的 `rclpy`、`cv_bridge`
- `numpy<2`
- `opencv-python<4.11`
- `tyro`
- `v4l2`
- `uv`

远端推理流程见 [05_imeta_y1_remote_inference_min.md](05_imeta_y1_remote_inference_min.md)。

## 10. 环境检查

完整 openpi 环境检查：

```bash
conda activate openpi
python --version
uv --version
python -c "import openpi; print('openpi import ok')"
```

本地最小推理环境检查：

```bash
conda activate openpi_local_infer
python --version
python -c "import openpi_client; print('openpi-client import ok')"
python -c "import cv2, numpy; print(cv2.__version__, numpy.__version__)"
```

如果 `uv: command not found`，先确认已激活对应 conda 环境，并执行：

```bash
pip install uv
```
