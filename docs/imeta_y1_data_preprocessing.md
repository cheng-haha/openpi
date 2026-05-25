# IMETA Y1 数据预处理

本文说明如何把 Y1 采集得到的 HDF5 数据预处理成 openpi 训练可用的 LeRobot Dataset v2.1，并生成训练所需的 normalization statistics。

对应流程来自《PI0、PI0.5 算法训练、推理 (同步推理, RTC推理).pdf》中的“基于你的数据微调”部分，结合当前仓库中的实际脚本：

- `examples/imeta_y1/convert_h5_to_lerobot.py`
- `src/openpi/training/config.py`
- `scripts/compute_norm_stats.py`

## 1. 原始数据要求

预处理输入是 `data_collection` 采集出的 `episode_*.hdf5` 文件。每个 episode 至少需要包含：

```text
/observation/state
/action
/observation/images/<camera_name>
root.attrs["task"]
```

当前 Y1 采集脚本写出的字段与转换脚本一致：

- `state`: 机械臂观测状态，单臂 7 维，双臂 14 维。
- `action`: 训练目标动作，单臂 7 维，双臂 14 维。
- `observation/images/<camera_name>`: 每帧压缩图像字节。
- `task`: 每条 episode 的语言指令，后续会写入 LeRobot 的 `task` 字段并作为训练 prompt。

维度顺序必须和推理时一致：

```text
单臂:
left_joint1..left_joint6, left_gripper

双臂:
left_joint1..left_joint6, left_gripper,
right_joint1..right_joint6, right_gripper
```

训练前建议先检查一条数据：

```bash
cd /home/ubuntu/projects/y1_robot/data_collection
h5dump -H data/<task_name>/episode_0.hdf5
python -m scripts.visualize_h5_episode --dataset_dir data/<task_name> --episode_idx 0
```

重点确认：

- episode 文件连续命名为 `episode_0.hdf5`, `episode_1.hdf5`, ...
- `state` 和 `action` 的长度一致。
- 图像能正常解码，且相机名称和视角正确。
- `task` 是简洁、单行、非空的英文任务描述。
- 单臂/双臂维度没有混用。

## 2. 转换为 LeRobot Dataset

在完整 openpi 环境中运行转换脚本。openpi 需要 Python 3.11：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
conda activate openpi
```

如果出现 `uv: command not found`，说明当前 shell 没有进入完整 openpi 环境，先确认已执行 `conda activate openpi`，必要时安装：

```bash
pip install uv
```

默认转换后的数据保存在 `HF_LEROBOT_HOME` 指定目录；如果没有设置该变量，通常在 `~/.cache/huggingface/lerobot` 下。

建议显式指定数据目录，方便本地和云端保持一致：

```bash
export HF_LEROBOT_HOME=/home/ubuntu/projects/y1_robot/lerobot_dataset
```

### 单臂数据

单臂默认使用 `--config.single-arm=True`，通常只需要传原始 HDF5 目录和 repo id：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
uv run examples/imeta_y1/convert_h5_to_lerobot.py \
  --config.h5-raw-dir /home/ubuntu/projects/y1_robot/data_collection/data/<task_name> \
  --config.repo-id openpi/<dataset_name>
```

如果单臂数据只使用两个相机，保持训练配置中的相机映射一致，例如：

```bash
uv run examples/imeta_y1/convert_h5_to_lerobot.py \
  --config.h5-raw-dir /home/ubuntu/projects/y1_robot/data_collection/data/<task_name> \
  --config.repo-id openpi/<dataset_name> \
  --config.cam-names cam_high cam_right_wrist
```

如果当前 `tyro` 版本不能正确解析列表参数，就直接修改 `examples/imeta_y1/convert_h5_to_lerobot.py` 里的默认值：

```python
cam_names: List[str] = field(default_factory=lambda: ["cam_high", "cam_right_wrist"])
```

### 双臂数据

双臂需要传 `--config.no-single-arm`，转换脚本会创建 14 维 `state/action`：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
uv run examples/imeta_y1/convert_h5_to_lerobot.py \
  --config.h5-raw-dir /home/ubuntu/projects/y1_robot/data_collection/data/<task_name> \
  --config.repo-id openpi/<dataset_name> \
  --config.no-single-arm
```

双臂建议使用三个相机：

```text
cam_high
cam_left_wrist
cam_right_wrist
```

如果实际采集的相机名称不同，需要同时修改：

- 转换脚本参数 `--config.cam-names`
- `src/openpi/training/config.py` 中对应 config 的 `images` 映射
- 真机推理脚本中的相机名或设备映射

## 3. 转换后检查

转换完成后，用 LeRobotDataset 快速检查字段、任务名和维度：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
python - <<'PY'
from lerobot.common.datasets.lerobot_dataset import LeRobotDataset

dataset = LeRobotDataset(repo_id="openpi/<dataset_name>")
print(dataset.meta.features)
print(dataset.meta.tasks)
sample = dataset[0]
print(sample["observation.state"].shape)
print(sample["action"].shape)
print([key for key in sample if key.startswith("observation.images.")])
PY
```

期望结果：

- 单臂 `observation.state` 和 `action` 是 7 维。
- 双臂 `observation.state` 和 `action` 是 14 维。
- 图像 key 形如 `observation.images.cam_high`。
- `task` 能对应采集配置里的 `task_description`。

## 4. 修改训练配置

在 `src/openpi/training/config.py` 中选择或复制一个 Y1 配置：

```text
pi0_base_full_single_arm
pi05_base_full_single_arm
pi0_base_full_dual_arm
pi05_base_full_dual_arm
```

需要修改的核心参数：

```python
repo_id="openpi/<dataset_name>"
```

并确保 `repack_transforms` 中的图像映射与 LeRobot Dataset 的图像字段完全一致。

单臂两相机示例：

```python
"images": {
    "cam_high": "observation.images.cam_high",
    "cam_right_wrist": "observation.images.cam_right_wrist",
},
```

双臂三相机示例：

```python
"images": {
    "cam_high": "observation.images.cam_high",
    "cam_left_wrist": "observation.images.cam_left_wrist",
    "cam_right_wrist": "observation.images.cam_right_wrist",
},
```

Y1 当前配置里应保持：

```python
use_delta_joint_actions=False
adapt_to_pi=False
base_config=DataConfig(prompt_from_task=True)
```

含义：

- 不把关节动作转成 delta action，训练使用采集数据中的绝对关节位置。
- 不套 ALOHA 到 PI 内部空间的转换。
- 使用 LeRobot `task` 字段作为 prompt。

## 5. 计算 normalization statistics

训练前必须先为当前数据集计算 norm stats。否则训练时会报 missing norm stats。

```bash
cd /home/ubuntu/projects/y1_robot/openpi
uv run scripts/compute_norm_stats.py --config-name <your_config_name>
```

例如：

```bash
uv run scripts/compute_norm_stats.py --config-name pi05_base_full_dual_arm
```

生成结果会写到：

```text
assets/<repo_id>/norm_stats.json
```

例如：

```text
assets/openpi/<dataset_name>/norm_stats.json
```

`compute_norm_stats.py` 会在应用 `repack_transforms` 和数据变换后，对这两个 key 统计归一化参数：

```text
state
actions
```

如果训练 loss 发散，先检查 `norm_stats.json` 里的 `q01`、`q99`、`std`。某些几乎不动的维度可能导致 `std` 过小，归一化后数值异常放大。

## 6. 训练前最终检查

启动训练前确认这几项：

- HDF5 已经转成 LeRobot v2.1。
- `HF_LEROBOT_HOME` 指向转换后的数据目录，或者数据确实在默认 HuggingFace cache 下。
- `repo_id` 与转换命令完全一致。
- `images` 映射覆盖训练需要的所有相机，且没有引用不存在的相机。
- 单臂使用单臂 config，双臂使用双臂 config。
- 已运行 `scripts/compute_norm_stats.py`。
- `task` prompt 和真机推理时传入的 `PROMPT` 语义一致。

然后再开始训练：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
XLA_PYTHON_CLIENT_MEM_FRACTION=0.9 uv run scripts/train.py <your_config_name> \
  --exp-name=<experiment_name>
```

训练完成后，建议先跑数据集评估，再上真机：

```bash
bash scripts/eval_dataset.sh
```

运行前需要把 `scripts/eval_dataset.sh` 里的 `--policy.config` 改成训练 config 名称，把 `--policy.dir` 改成实际 checkpoint 目录。

如果数据集评估中预测 action 曲线和真实 action 大体一致，再继续同步推理或 RTC 推理部署。
