# IMETA Y1 云端部署 / 本地最小远程推理

这套流程对应：

- 云端 GPU 机器加载 `openpi` checkpoint 并启动 `serve_policy`
- 本地 Y1 控制机只负责相机采集、机械臂状态读取、动作执行
- 本地不安装 `jax`、`torch`、`lerobot` 这类完整训练依赖

完整环境创建见 [01_openpi_environment_setup.md](01_openpi_environment_setup.md)。同步推理、RTC 推理、相机和 ROS1 部署细节见 [06_imeta_y1_real_robot_inference.md](06_imeta_y1_real_robot_inference.md)。

安全提示：真机调试模型有风险。启动推理前确认急停可用，人和电脑远离机械臂运动范围。

## 1. 机器职责

远程推理必须明确分成两边：

| 机器 | 环境 | 负责内容 |
| --- | --- | --- |
| 云端 GPU / 训练机 | 完整 openpi，Python 3.11 | 加载 checkpoint，启动 `serve_policy`，执行模型前向推理 |
| 本地 Y1 控制机 | 最小推理环境，Python 3.10 | 读取 ROS2 `usb_cam` topic 或 V4L2 相机、读取 Y1 状态、请求云端策略、向机械臂发送 action |

不要在本地 Y1 控制机上跑 `uv sync`，也不要为了远程推理安装 `jax`、`torch`、`lerobot`。本地只需要 `scripts/inference_remote/setup_local_env.sh` 创建的最小环境。

## 2. 云端 GPU / 训练机

云端机器使用完整 `openpi` 环境。完整 `openpi` 项目要求 Python 3.11：

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

PDF 中提到 PI 模型实机推理显存占用约 `9084 MB`。云端机器显存应至少覆盖该需求，并预留系统和图像处理开销。

云端服务启动后，确认本地 Y1 控制机能访问：

```bash
nc -vz <cloud_ip> 8000
```

如果不通，先检查云服务器安全组、防火墙、端口转发和 `serve_policy` 监听地址。

## 3. 本地 Y1 控制机：最小环境

本地 Y1 控制机使用 Python 3.10，只安装这些内容：

- `openpi-client`
- `y1_sdk`
- ROS2 Humble 提供的 `rclpy`、`cv_bridge`
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

这个环境只用于 `scripts/inference_remote/eval_real_robot.sh` 和 `scripts/inference_remote/eval_real_robot.py`。它不包含完整训练依赖。

## 4. 本地 Y1 控制链路准备

远程推理前，先停掉旧的 Y1 tmux 会话，避免还停在数据采集或旧控制模式：

```bash
bash /home/ubuntu/projects/y1_robot/stop_y1_tmux.sh
```

再启动普通双臂控制链路：

```bash
AUTO_ATTACH=0 bash /home/ubuntu/projects/y1_robot/start_y1_dual_arm_inference_tmux.sh
tmux attach -t y1_dual_arm_inference
```

这个脚本会初始化：

- `can0`
- `can1`
- `ros2 launch y1_controller two_arm_control.launch.py`

这对应 `data_collection/doc/0. 先看这里：现在应该启动哪个脚本.md` 里说的“推理 / 回放数据 / 发送控制指令 / 普通双臂控制”模式。不要把数据采集模式 `two_master.launch.py` 留在后台。

注意：当前 `scripts/inference_remote/eval_real_robot.py` 通过 `scripts/inference_python/real_robot_env.py` 使用 Python SDK 直接读写 Y1，并默认使用 `can0`、`can1`。如果运行远程推理时出现 SDK 初始化失败、CAN 被占用或动作异常，先在 tmux 里确认 `can0/can1` 已经 up，然后关闭可能同时发送控制指令的进程，只保留 CAN 接口可用，再重新运行 openpi 远程推理客户端。

调试 ROS2 话题或 tmux 控制链路时，另开终端加载完整 ROS2 环境：

```bash
source /opt/ros/humble/setup.bash
source /home/ubuntu/projects/y1_robot/y1_sdk_python/y1_ros2/install/setup.bash
```

`scripts/inference_remote/eval_real_robot.sh` 自己只会 source `/opt/ros/humble/setup.bash`；它不会自动 source `y1_ros2/install/setup.bash`。

## 5. 本地相机模式

推荐推理时复用数据采集时的 ROS2 `usb_cam` topic 链路。原因是当前训练数据就是按这条链路采集的：

```text
start_y1_cameras_tmux.sh
  -> ros2 run usb_cam usb_cam_node_exe
  -> /camera_right/color/image_raw
  -> /camera_left/color/image_raw
  -> /camera_high/color/image_raw
  -> data_collection 订阅 topic，转 rgb8，再 JPEG 压缩写入 HDF5
```

`start_y1_cameras_tmux.sh` 还会设置相机参数：

```text
FRAMERATE=60.0
IMAGE_WIDTH=640
IMAGE_HEIGHT=480
PIXEL_FORMAT=yuyv
AUTOEXPOSURE=true
AUTO_WHITE_BALANCE=true
BRIGHTNESS=0
POWER_LINE_FREQUENCY=1
```

这些参数会影响亮度、对比度、白平衡、颜色和运动模糊。为了避免训推图像不一致，使用 `data_collection` 采集出来的数据训练的模型，远程推理默认应启动同一套 ROS2 相机：

```bash
bash /home/ubuntu/projects/y1_robot/start_y1_cameras_tmux.sh
tmux attach -t y1_cameras
```

检查 topic：

```bash
source /opt/ros/humble/setup.bash
ros2 topic hz /camera_right/color/image_raw
ros2 topic hz /camera_left/color/image_raw
ros2 topic hz /camera_high/color/image_raw
```

远程推理脚本默认使用 `CAMERA_TYPE=ros2`，topic 映射来自 `scripts/inference_python/real_robot_env.py`：

```text
cam_high -> /camera_high/color/image_raw
cam_left_wrist -> /camera_left/color/image_raw
cam_right_wrist -> /camera_right/color/image_raw
```

如果你的 topic 名不同，用 `CAMERA_TOPICS` 覆盖：

```bash
CAMERA_TYPE=ros2 \
CAMERA_TOPICS="cam_high=/camera_high/color/image_raw cam_left_wrist=/camera_left/color/image_raw cam_right_wrist=/camera_right/color/image_raw" \
bash scripts/inference_remote/eval_real_robot.sh
```

### V4L2 直连只作为备选

openpi 里也保留了 V4L2 直连模式：

```text
cam_high -> /dev/cam_high
cam_left_wrist -> /dev/cam_left_wrist
cam_right_wrist -> /dev/cam_right_wrist
```

如果直接用 V4L2，要注意它和采集链路不同：

- 当前 `scripts/inference_python/camera/v4l2_camera.py` 强制使用 MJPEG，而采集脚本默认使用 `pixel_format=yuyv`。
- V4L2 直连类没有自动复用 `start_y1_cameras_tmux.sh` 里的曝光、白平衡、亮度、电源频率等 `v4l2-ctl` 参数。
- 如果没有先对齐这些参数，推理图像可能在亮度、对比度、色温、压缩伪影和运动模糊上和训练图像不同。
- 同一个 `/dev/video*` 设备如果已经被 ROS2 `usb_cam` 占用，V4L2 直连可能打不开。

因此，只有在你明确复现了采集时的设备路径、分辨率、像素格式和 V4L2 控制参数后，才建议用 V4L2 直连。

如果仍然要用 V4L2 直连，可以创建 udev 别名：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
conda activate openpi_local_infer
sudo env "PATH=$PATH" python scripts/inference_python/utils/set_v4l2_camera_rules.py
```

这里用 `sudo env "PATH=$PATH"` 是为了让 `sudo` 使用当前 conda 环境里的 `python`，避免退回系统 Python。

也可以直接把 `data_collection` 里整理好的 `/dev/v4l/by-path` 设备路径传给远程推理脚本。实际路径以 `start_y1_cameras_tmux.sh` 启动时打印的 `Current device mapping` 为准：

```bash
CAMERA_DEVICES="cam_high=<high_by_path> cam_left_wrist=<left_by_path> cam_right_wrist=<right_by_path>"
```

## 6. 本地运行远程推理

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
CAMERA_TYPE=ros2 \
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
CAMERA_TYPE=ros2 \
bash scripts/inference_remote/eval_real_robot.sh
```

如果要覆盖相机路径或 CAN 名称：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
conda activate openpi_local_infer
SERVER_HOST=<cloud_ip> \
SERVER_PORT=8000 \
PROMPT="replace_with_your_task" \
CAMERA_TYPE=ros2 \
CAMERA_TOPICS="cam_high=/camera_high/color/image_raw cam_left_wrist=/camera_left/color/image_raw cam_right_wrist=/camera_right/color/image_raw" \
ARM_CAN_IDS="left_arm=can0 right_arm=can1" \
bash scripts/inference_remote/eval_real_robot.sh
```

## 7. 需要改的最少参数

- 云端 `--policy.config`
- 云端 `--policy.dir`
- 本地 `SERVER_HOST`
- 本地 `PROMPT`

如果你的相机名或训练配置不一致，再改：

- `CAM_NAMES`
- `CAMERA_TYPE=ros2`
- `CAMERA_TOPICS="cam_high=/camera_high/color/image_raw ..."`
- V4L2 备选：`CAMERA_DEVICES="cam_high=/dev/... cam_left_wrist=/dev/..."`
- `ARM_CAN_IDS="left_arm=can0 right_arm=can1"`

`PROMPT` 要和训练数据里的任务语义一致，例如训练时是“pick up the bottle”，推理时不要换成含义不同的任务描述。

## 8. 运行前检查清单

启动真机前逐项确认：

- 云端 `serve_policy` 已启动，本地能访问 `<cloud_ip>:8000`。
- 本地已经激活 `openpi_local_infer`，没有切到完整训练环境。
- 旧的 Y1 tmux 会话已通过 `stop_y1_tmux.sh` 停掉。
- `can0`、`can1` 已经初始化，且没有停留在数据采集 `two_master.launch.py` 模式。
- 相机优先使用 `CAMERA_TYPE=ros2`，并复用 `start_y1_cameras_tmux.sh` 启动的 ROS2 `usb_cam` topic。
- `/camera_right`、`/camera_left`、`/camera_high` 的真实画面和训练时相机顺序一致。
- 如果改用 V4L2 直连，已经确认设备路径、分辨率、像素格式和曝光/白平衡等参数与采集时一致。
- `PROMPT`、单臂/双臂、`CAM_NAMES` 和训练配置一致。
- 急停可用，人和电脑离开机械臂运动范围。

## 9. 相关文件

- `scripts/inference_remote/setup_local_env.sh`
- `scripts/inference_remote/eval_real_robot.sh`
- `scripts/inference_remote/eval_real_robot.py`
- `scripts/inference_python/real_robot_env.py`
- `/home/ubuntu/projects/y1_robot/start_y1_dual_arm_inference_tmux.sh`
- `/home/ubuntu/projects/y1_robot/stop_y1_tmux.sh`
- `/home/ubuntu/projects/y1_robot/start_y1_cameras_tmux.sh`
