# IMETA Y1 云端部署 / 本地最小推理环境

这套流程对应：

- 云端 GPU 机器加载 `openpi` checkpoint 并启动 `serve_policy`
- 本地 Y1 控制机只负责相机采集、机械臂状态读取、动作执行
- 本地不安装 `jax`、`torch`、`lerobot` 这类完整训练依赖

## 1. 云端机器

云端机器仍然使用完整 `openpi` 环境。完整 `openpi` 项目要求 Python 3.11：

```bash
conda create -n openpi python=3.11 -y
conda activate openpi
pip install uv
cd /path/to/openpi
GIT_LFS_SKIP_SMUDGE=1 uv sync
GIT_LFS_SKIP_SMUDGE=1 uv pip install -e .
```

启动策略服务：

```bash
cd /path/to/openpi
uv run scripts/serve_policy.py policy:checkpoint \
  --policy.config=pi05_base_full_dual_arm \
  --policy.dir=/path/to/your/checkpoint \
  --port=8000
```

如果是官方基座模型，也可以直接：

```bash
uv run scripts/serve_policy.py --env ALOHA --port=8000
```

## 2. 本地 Y1 控制机

本地 Y1 控制机使用 Python 3.10，只安装这些内容：

- `openpi-client`
- `y1_sdk`
- `numpy<2`
- `opencv-python<4.11`
- `tyro`
- `v4l2`
- `uv`

创建环境：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
bash scripts/inference_remote/setup_local_env.sh
conda activate openpi_local_infer
source /opt/ros/humble/setup.bash
```

## 3. 本地运行远端推理

默认相机映射使用本地 udev 别名：

- `cam_high -> /dev/cam_high`
- `cam_right_wrist -> /dev/cam_right_wrist`
- `cam_left_wrist -> /dev/cam_left_wrist`

如果还没有创建这些别名，可以先运行：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
sudo python scripts/inference_python/utils/set_v4l2_camera_rules.py
```

双臂默认 CAN：

- `left_arm -> can0`
- `right_arm -> can1`

运行双臂远端推理：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
conda activate openpi_local_infer
source /opt/ros/humble/setup.bash
SERVER_HOST=<cloud_ip> \
SERVER_PORT=8000 \
PROMPT="replace_with_your_task" \
bash scripts/inference_remote/eval_real_robot.sh
```

如果是单臂任务：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
conda activate openpi_local_infer
source /opt/ros/humble/setup.bash
SERVER_HOST=<cloud_ip> \
SERVER_PORT=8000 \
PROMPT="replace_with_your_task" \
SINGLE_ARM=1 \
bash scripts/inference_remote/eval_real_robot.sh
```

## 4. 需要改的最少参数

- 云端 `--policy.config`
- 云端 `--policy.dir`
- 本地 `SERVER_HOST`
- 本地 `PROMPT`

如果你的相机名或训练配置不一致，再改：

- `CAM_NAMES`
- `CAMERA_DEVICES="cam_high=/dev/... cam_left_wrist=/dev/..."`
- `ARM_CAN_IDS="left_arm=can0 right_arm=can1"`

## 5. 相关文件

- `scripts/inference_remote/setup_local_env.sh`
- `scripts/inference_remote/eval_real_robot.sh`
- `scripts/inference_remote/eval_real_robot.py`
- `scripts/inference_python/real_robot_env.py`
