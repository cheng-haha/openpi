# IMETA Y1 真机推理部署

本文根据《PI0、PI0.5 算法训练、推理 (同步推理, RTC推理).pdf》整理完整真机推理流程。最小远端推理流程见 [05_imeta_y1_remote_inference_min.md](05_imeta_y1_remote_inference_min.md)；本文补充数据集评估、ROS1 部署、纯 Python SDK 部署、相机配置、同步推理和 RTC 推理。

安全提示：真机调试模型有风险。启动推理前确认急停可用，人和电脑远离机械臂运动范围。

## 1. 先做数据集评估

模型训练完成后，先在数据集上评估，确认预测 action 曲线和真实 action 大体一致，再上真机。

修改：

```text
scripts/eval_dataset.sh
```

至少改这两个参数：

```bash
--policy.config=<your_config_name>
--policy.dir=checkpoints/<your_config_name>/<experiment_name>/<step>
```

运行：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
bash scripts/eval_dataset.sh
```

评估完成后会生成：

```text
eval_dataset.png
```

如果预测曲线和真实 action 差异很大，优先检查：

- 数据预处理是否选错单臂/双臂。
- `config.py` 里的 `repo_id` 和 `images` 映射是否正确。
- `norm_stats.json` 是否来自同一个数据集。
- 推理 checkpoint 是否选错 step 或实验目录。

## 2. Ubuntu 20.04 ROS1 Noetic 部署

ROS1 部署使用：

```text
scripts/inference_ros1/
```

运行前修改：

```text
scripts/inference_ros1/eval_real_robot.sh
```

需要重点修改：

```bash
export LD_LIBRARY_PATH="/path/to/miniconda3/envs/openpi/lib:$LD_LIBRARY_PATH"
--policy.config=<your_config_name>
--policy.dir=<checkpoint_dir>
```

启动顺序：

```bash
# 1. 启动机械臂 ROS 驱动
# 根据实际机械臂驱动启动对应 launch 文件

# 2. 启动相机 ROS 驱动
# 根据实际相机驱动启动对应 launch 文件

# 3. 加载 Y1 ROS 环境
# 如果使用 python sdk:
cd /path/to/y1_sdk_python/y1_ros
source devel/setup.bash

# 如果使用 c++ sdk:
cd /path/to/y1_sdk
source devel/setup.bash

# 4. 启动模型推理
cd /home/ubuntu/projects/y1_robot/openpi
bash scripts/inference_ros1/eval_real_robot.sh
```

ROS1 模式下，模型输出会通过 ROS topic 与机械臂驱动通信。

## 3. Ubuntu 22.04 部署建议

Ubuntu 22.04 通常使用 ROS2 Humble，而 ROS2 Humble 常用 Python 3.10；完整 openpi 环境需要 Python 3.11。PDF 建议在 Ubuntu 22.04 上优先使用纯 Python SDK 或远端推理方式，避免 ROS2 和 openpi Python 版本冲突。

推荐两种方式：

- 云端 GPU 跑策略服务，本地 Y1 控制机跑最小推理环境：见 [05_imeta_y1_remote_inference_min.md](05_imeta_y1_remote_inference_min.md)。
- 本机完整 openpi 环境直接跑 `scripts/inference_python/`：适合本机有 GPU，并且能接受完整 openpi 依赖。

## 4. 纯 Python SDK 部署

相关代码：

```text
scripts/inference_python/
```

安装 Y1 Python SDK：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
uv pip install /path/to/y1_sdk_python/y1_sdk/
```

将 `/path/to/y1_sdk_python/y1_sdk/` 替换为本机实际路径。

当前 `RealRobotEnv` 默认：

```text
camera_type = v4l2
left_arm -> can0
right_arm -> can1
```

默认 CAN 配置在：

```text
scripts/inference_python/real_robot_env.py
```

如果实际 CAN 不一致，需要修改 `DEFAULT_ARM_CAN_IDS`，或在远端推理脚本里通过 `ARM_CAN_IDS` 覆盖。

## 5. 相机配置

当前涉及三类相机入口：

- Orbbec 奥比中光。
- V4L2 免驱 RGB 相机。
- ROS2 `usb_cam` 图像 topic。

需要区分两条相机链路：

- `/home/ubuntu/projects/y1_robot/start_y1_cameras_tmux.sh` 使用 ROS2 `usb_cam`，发布 `/camera_left/color/image_raw`、`/camera_right/color/image_raw`、`/camera_high/color/image_raw`。当前 `data_collection` 就是按这条链路采集训练数据。
- `scripts/inference_remote/` 默认使用 `CAMERA_TYPE=ros2` 订阅同一套 ROS2 topic，这是用 `data_collection` 数据训练后的推荐推理方式。
- V4L2 直连使用 `/dev/cam_high` 或 `/dev/v4l/by-path/...` 直接打开设备，只建议在明确复现采集时相机参数后使用。

训推图像链路要尽量一致。如果训练数据来自 ROS2 `usb_cam`，推理时直接改成 V4L2 直连，可能引入曝光、白平衡、对比度、颜色空间、像素格式和压缩方式差异。如果同一个相机已经被 ROS2 `usb_cam` 占用，V4L2 直连也可能打不开。

### Orbbec 相机

安装 Orbbec SDK。PDF 中示例使用：

```bash
uv pip install pyorbbecsdk-1.3.1-cp311-cp311-linux_x86_64.whl
```

注意：Dabai DCW2 暂不支持 Orbbec SDK V2，V1 版本安装会更复杂。

查询 Orbbec 相机序列号：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
uv run scripts/inference_python/utils/list_orbbc_serial.py
```

然后修改：

```text
scripts/inference_python/real_robot_env.py
```

重点是：

```python
DEFAULT_CAMERA_SERIALS = {
    "cam_high": "...",
    "cam_left_wrist": "...",
    "cam_right_wrist": "...",
}
```

如果使用 Orbbec，相机类型需要设置为：

```text
camera_type="orbbec"
```

### V4L2 免驱相机

这一节是 V4L2 直连备选方案。对于当前用 `data_collection` 采集出来的数据，优先使用远端推理里的 `CAMERA_TYPE=ros2`，复用 ROS2 `usb_cam` topic。

如果是在完整 openpi 环境里做同步推理，安装依赖：

```bash
conda activate openpi
uv pip install v4l2
```

如果是在本地 Y1 控制机做远程推理，`scripts/inference_remote/setup_local_env.sh` 已经安装了 `v4l2`。

绑定相机别名：

完整 openpi 环境：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
conda activate openpi
sudo env "PATH=$PATH" uv run scripts/inference_python/utils/set_v4l2_camera_rules.py
```

本地最小远程推理环境：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
conda activate openpi_local_infer
sudo env "PATH=$PATH" python scripts/inference_python/utils/set_v4l2_camera_rules.py
```

这里用 `sudo env "PATH=$PATH"` 是为了让 `sudo` 保留当前 conda 环境里的 `python` 或 `uv`。

脚本会抓拍每个相机的一帧图片并保存到 `images/` 目录。根据视角提示依次分配：

```text
cam_high
cam_right_wrist
cam_left_wrist
```

如果某个位置没有相机，可以直接按 Enter 跳过。

验证相机：

完整 openpi 环境：

```bash
uv run scripts/inference_python/camera/v4l2_camera.py /dev/cam_high
uv run scripts/inference_python/camera/v4l2_camera.py /dev/cam_left_wrist
uv run scripts/inference_python/camera/v4l2_camera.py /dev/cam_right_wrist
```

本地最小远程推理环境：

```bash
python scripts/inference_python/camera/v4l2_camera.py /dev/cam_high
python scripts/inference_python/camera/v4l2_camera.py /dev/cam_left_wrist
python scripts/inference_python/camera/v4l2_camera.py /dev/cam_right_wrist
```

默认 V4L2 设备映射：

```python
DEFAULT_V4L2_CAMERA_DEVICES = {
    "cam_high": "/dev/cam_high",
    "cam_left_wrist": "/dev/cam_left_wrist",
    "cam_right_wrist": "/dev/cam_right_wrist",
}
```

## 6. 同步推理

同步推理使用：

```text
scripts/inference_python/eval_real_robot.sh
scripts/inference_python/eval_real_robot.py
scripts/inference_python/real_robot_env.py
```

运行前修改：

```text
scripts/inference_python/eval_real_robot.sh
```

重点参数：

```bash
export LD_LIBRARY_PATH="/path/to/miniconda3/envs/openpi/lib:$LD_LIBRARY_PATH"
--policy.config=<your_config_name>
--policy.dir=<checkpoint_dir>
```

启动：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
bash scripts/inference_python/eval_real_robot.sh
```

流程特点：

- 脚本会从训练数据集里读取一条 episode，用它判断单臂/双臂、相机列表和任务 prompt。
- 脚本会提示先按 Enter 让机械臂移动到数据集初始位姿。
- 再按 Enter 后开始模型推理。
- 默认对 action chunk 做插值执行，减小动作突变。

运行前必须确认：

- `real_robot_env.py` 里的 CAN id 正确。
- 相机别名或 Orbbec 序列号正确。
- checkpoint 对应的训练 config 和当前真实相机数量一致。

## 7. RTC 异步推理

RTC 推理分两个进程：

- 策略服务：`scripts/inference_python/server_policy.sh`
- Y1 RTC 控制端：`scripts/inference_python/y1_inference_rtc.sh`

先检查或新增 RTC 推理 config。当前仓库已有：

```text
pi05_rtc_inference_dual_arm
pi0_rtc_inference_dual_arm
```

这类 config 与训练 config 的主要区别是 `model` 使用 RTC 版本，例如：

```python
model=pi0_config.Pi0RTCConfig(pi05=True)
```

启动策略服务：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
bash scripts/inference_python/server_policy.sh
```

运行前修改：

```bash
--policy.config=<rtc_config_name>
--policy.dir=<checkpoint_dir>
--port=8000
```

启动 Y1 RTC 控制端：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
bash scripts/inference_python/y1_inference_rtc.sh
```

常用参数在脚本顶部：

```bash
HOST="127.0.0.1"
PORT="8000"
PROMPT="..."
CAMERA_TYPE="v4l2"
CAMERA_NAMES=("cam_high" "cam_right_wrist" "cam_left_wrist")
CONTROL_FREQUENCY="30"
INFERENCE_RATE="4"
CHUNK_SIZE="30"
SINGLE_ARM="false"
INTERPOLATION="true"
RTC_EXECUTE_HORIZON="8"
RTC_MAX_GUIDANCE_WEIGHT="0.3"
LATENCY_K="8"
```

如果还有明显抖动，优先根据模型推理延迟调整：

- `INFERENCE_RATE`
- `RTC_EXECUTE_HORIZON`
- `LATENCY_K`
- `MIN_SMOOTH_STEPS`
- `RTC_MAX_GUIDANCE_WEIGHT`
- `INTERP_STEPS`
- `INTERP_FREQUENCY`

不要在机械臂附近直接试大幅参数变化。每次只改一两个参数，并先低速验证。

## 8. 远端推理

如果策略服务跑在云端 GPU，本地只负责相机、状态读取和动作执行，使用：

```text
scripts/inference_remote/
```

流程见 [05_imeta_y1_remote_inference_min.md](05_imeta_y1_remote_inference_min.md)。

远端推理前，先停掉旧 Y1 会话并启动普通控制链路：

```bash
bash /home/ubuntu/projects/y1_robot/stop_y1_tmux.sh
AUTO_ATTACH=0 bash /home/ubuntu/projects/y1_robot/start_y1_dual_arm_inference_tmux.sh
```

如果要调试 ROS2 话题或 tmux 控制链路，另开终端 source：

```bash
source /opt/ros/humble/setup.bash
source /home/ubuntu/projects/y1_robot/y1_sdk_python/y1_ros2/install/setup.bash
```

本地脚本支持通过环境变量覆盖：

```bash
SERVER_HOST=<cloud_ip>
SERVER_PORT=8000
PROMPT="replace_with_your_task"
CAMERA_TYPE=ros2
CAMERA_TOPICS="cam_high=/camera_high/color/image_raw cam_left_wrist=/camera_left/color/image_raw cam_right_wrist=/camera_right/color/image_raw"
SINGLE_ARM=1
CAM_NAMES="cam_high cam_right_wrist"
ARM_CAN_IDS="left_arm=can0 right_arm=can1"
```

图像会在本地 resize 到 `224x224` 再发送，以降低带宽和延迟。

## 9. 最终检查清单

上真机前确认：

- 数据集评估已通过。
- `--policy.config`、`--policy.dir` 指向同一个训练任务。
- `PROMPT` 与训练数据里的 `task` 语义一致。
- 单臂/双臂配置正确。
- 相机顺序和训练时一致。
- CAN id 正确。
- 机械臂初始位置安全。
- 推理机器 GPU 显存足够，PDF 中实机推理显存约 `9084 MB`。
- 急停可用，人和电脑离开运动范围。
