# IMETA Y1 训练步骤

本文根据《PI0、PI0.5 算法训练、推理 (同步推理, RTC推理).pdf》整理 Y1 数据微调 PI0 / PI0.5 的训练流程。环境创建见 [01_openpi_environment_setup.md](01_openpi_environment_setup.md)，数据预处理见 [03_imeta_y1_data_preprocessing.md](03_imeta_y1_data_preprocessing.md)。

整体顺序：

```text
准备 openpi 环境
-> 转换 HDF5 为 LeRobot Dataset
-> 修改训练 config
-> 计算 norm stats
-> 启动训练
-> 检查 checkpoint 和数据集评估
```

## 1. 准备训练环境

训练环境使用完整 openpi 环境，要求 Python 3.11。完整创建步骤见 [01_openpi_environment_setup.md](01_openpi_environment_setup.md)，这里保留最短命令：

```bash
git clone https://github.com/IMETA-Robotics/openpi.git
cd openpi
git checkout imeta_robotics

conda create -n openpi python=3.11 -y
conda activate openpi
pip install uv

GIT_LFS_SKIP_SMUDGE=1 uv sync
GIT_LFS_SKIP_SMUDGE=1 uv pip install -e .
```

如果依赖下载慢，可以临时切换 PyPI 源：

```bash
export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
GIT_LFS_SKIP_SMUDGE=1 uv sync
GIT_LFS_SKIP_SMUDGE=1 uv pip install -e .
```

如果 LeRobot 依赖下载特别慢，可以提前克隆指定 commit，然后在 `pyproject.toml` 里把 `lerobot` 改成本地路径：

```bash
git clone https://github.com/huggingface/lerobot.git
cd lerobot
git checkout 0cf864870cf29f4738d3ade893e6fd13fbd7cdb5
```

LeRobot 解析视频数据需要 ffmpeg：

```bash
conda install ffmpeg -c conda-forge
```

如果后续读取 LeRobot Dataset 出问题，再尝试固定版本：

```bash
conda install ffmpeg=7.1.1 -c conda-forge
```

## 2. 准备训练数据

先把 Y1 采集得到的 HDF5 转为 LeRobot Dataset v2.1。详细检查项和转换命令见：

```text
docs/03_imeta_y1_data_preprocessing.md
```

训练前至少确认：

- `repo_id` 已经生成，例如 `openpi/<dataset_name>`。
- `HF_LEROBOT_HOME` 指向 LeRobot 数据集所在目录，或者数据位于默认 `~/.cache/huggingface/lerobot`。
- 单臂数据是 7 维 `state/action`，双臂数据是 14 维 `state/action`。
- 相机 key 与训练 config 的 `images` 映射一致。
- LeRobot `task` 字段能作为训练 prompt。

## 3. 选择训练配置

Y1 当前在 `src/openpi/training/config.py` 里提供了 4 个全参微调配置：

```text
pi0_base_full_single_arm    # 单臂 PI0
pi05_base_full_single_arm   # 单臂 PI0.5
pi0_base_full_dual_arm      # 双臂 PI0
pi05_base_full_dual_arm     # 双臂 PI0.5
```

选择规则：

- 单臂数据选 `*_single_arm`。
- 双臂数据选 `*_dual_arm`。
- 训练 PI0 选 `pi0_*`。
- 训练 PI0.5 选 `pi05_*`。

## 4. 修改 config.py

打开：

```text
src/openpi/training/config.py
```

在对应 `TrainConfig` 里修改数据集：

```python
repo_id="openpi/<dataset_name>"
```

然后根据相机数量修改 `repack_transforms` 里的 `images` 映射。

单臂常用双相机：

```python
"images": {
    "cam_high": "observation.images.cam_high",
    "cam_right_wrist": "observation.images.cam_right_wrist",
},
```

双臂常用三相机：

```python
"images": {
    "cam_high": "observation.images.cam_high",
    "cam_left_wrist": "observation.images.cam_left_wrist",
    "cam_right_wrist": "observation.images.cam_right_wrist",
},
```

Y1 当前配置建议保持：

```python
use_delta_joint_actions=False
adapt_to_pi=False
base_config=DataConfig(prompt_from_task=True)
```

## 5. 核对训练参数

当前 Y1 config 里的主要训练参数：

```python
num_train_steps=30000
save_interval=5000
keep_period=10000
batch_size=32
fsdp_devices=1
```

含义：

- `num_train_steps`: 总训练 step，当前默认 30000。PDF 经验是通常训练到 20000 step 左右已经可以观察效果。
- `save_interval`: 每隔多少 step 保存一次 checkpoint，当前默认 5000。
- `keep_period`: 满足 `step % keep_period == 0` 的 checkpoint 不删除。PDF 里示例说明为 5000，当前代码配置是 10000。
- `batch_size`: 总 batch size，多卡时会再分到每张 GPU。
- `fsdp_devices`: 使用几张 GPU 做 FSDP，单卡训练保持 1。

checkpoint 体积很大。PDF 经验是每个 checkpoint 大约 41 GB，云端训练建议准备 300-500 GB 数据盘。

## 6. 计算 norm stats

训练前必须先计算 normalization statistics：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
conda activate openpi
uv run scripts/compute_norm_stats.py --config-name <your_config_name>
```

示例：

```bash
uv run scripts/compute_norm_stats.py --config-name pi05_base_full_dual_arm
```

生成文件位置：

```text
assets/<repo_id>/norm_stats.json
```

例如：

```text
assets/openpi/<dataset_name>/norm_stats.json
```

如果训练时报 missing norm stats，通常就是这一步没跑，或者 `repo_id` 与数据集不一致。

## 7. 启动训练

训练命令：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
conda activate openpi
XLA_PYTHON_CLIENT_MEM_FRACTION=0.9 uv run scripts/train.py <your_config_name> \
  --exp-name=<experiment_name>
```

示例：

```bash
XLA_PYTHON_CLIENT_MEM_FRACTION=0.9 uv run scripts/train.py pi05_base_full_dual_arm \
  --exp-name=folded_orange_towel_1122
```

训练输出会保存到：

```text
checkpoints/<your_config_name>/<experiment_name>/
```

例如：

```text
checkpoints/pi05_base_full_dual_arm/folded_orange_towel_1122/
```

其中具体 step 目录可用于后续推理，例如：

```text
checkpoints/pi05_base_full_dual_arm/folded_orange_towel_1122/30000
```

## 8. AutoDL / 云端训练路径设置

如果在 AutoDL 或其他云端机器训练，建议把 openpi 源码、预训练模型、LeRobot 数据集和缓存都放到数据盘，例如 `/root/autodl-tmp`。

当前仓库提供：

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

训练前按实际路径修改，然后执行：

```bash
cd /path/to/openpi
source scripts/set_env.sh
XLA_PYTHON_CLIENT_MEM_FRACTION=0.9 uv run scripts/train.py <your_config_name> \
  --exp-name=<experiment_name>
```

变量含义：

- `OPENPI_DATA_HOME`: openpi 预训练模型缓存目录。设置后会先从这里找 `pi0_base` / `pi05_base`。
- `XDG_CACHE_HOME`: 系统缓存目录。
- `HF_HOME`: HuggingFace Hub 缓存目录。
- `HF_LEROBOT_HOME`: LeRobot Dataset 本地目录。加载数据时会从 `HF_LEROBOT_HOME/<repo_id>` 查找。

如果本地已经处理好预训练模型或数据集，可以用 `rclone` 传到云端数据盘；训练完成后也可以用 `rclone` 把 checkpoint 传回本地。示例命令见 [01_openpi_environment_setup.md](01_openpi_environment_setup.md)。

## 9. 训练后检查

训练完成后，先做数据集评估，再上真机：

```bash
cd /home/ubuntu/projects/y1_robot/openpi
bash scripts/eval_dataset.sh
```

运行前修改 `scripts/eval_dataset.sh`：

```bash
--policy.config=<your_config_name>
--policy.dir=checkpoints/<your_config_name>/<experiment_name>/<step>
```

评估会生成 `eval_dataset.png`。如果预测 action 曲线和真实 action 大体一致，说明模型至少学到了数据集里的动作趋势，可以继续进入同步推理或 RTC 推理部署。完整真机推理流程见 [06_imeta_y1_real_robot_inference.md](06_imeta_y1_real_robot_inference.md)。

## 10. 常见问题检查顺序

训练失败时按这个顺序查：

- `uv` 不存在：确认已 `conda activate openpi`，并安装 `pip install uv`。
- 找不到数据集：确认 `HF_LEROBOT_HOME` 和 `repo_id`。
- 图像 key 报错：确认 `config.py` 的 `images` 映射和 LeRobot Dataset 字段一致。
- action/state 维度不对：确认单臂/双臂 config 没选错。
- missing norm stats：重新运行 `scripts/compute_norm_stats.py`。
- loss 发散：检查 `assets/<repo_id>/norm_stats.json` 里的 `q01`、`q99`、`std`，尤其是不动或很少动的关节维度。
- GPU 显存不足：确认设置了 `XLA_PYTHON_CLIENT_MEM_FRACTION=0.9`，必要时减小 batch size 或使用更多 `fsdp_devices`。
