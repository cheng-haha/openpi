# 归一化统计

按照常见做法，模型在训练和推理时会对本体状态输入和动作目标做归一化。归一化所需的统计量从训练数据中计算得到，并与模型 checkpoint 一起保存。

## 重新加载归一化统计

在新数据集上微调模型时，需要决定是复用已有归一化统计，还是基于新的训练数据重新计算统计量。哪种方式更合适，取决于你的机器人和任务与预训练数据中机器人、任务分布的相似程度。下面列出每个模型可用的预训练归一化统计。

**如果目标机器人与某个预训练统计项匹配，可以考虑复用对应的归一化统计。** 复用统计量后，你的数据集动作分布对模型来说会更“熟悉”，有可能带来更好的效果。做法是在训练 config 中添加 `AssetsConfig`，指向对应 checkpoint 的 assets 目录和统计 ID。下面示例加载 `pi0_base` checkpoint 中 `Trossen`，也就是 ALOHA，机器人的归一化统计：

```python
TrainConfig(
    ...
    data=LeRobotAlohaDataConfig(
        ...
        assets=AssetsConfig(
            assets_dir="gs://openpi-assets/checkpoints/pi0_base/assets",
            asset_id="trossen",
        ),
    ),
)
```

完整示例可以参考 [training config 文件](https://github.com/physical-intelligence/openpi/blob/main/src/openpi/training/config.py) 里的 `pi0_aloha_pen_uncap` 配置。

**注意：** 要成功复用归一化统计，你的机器人和数据集必须遵循预训练时使用的动作空间定义。下文给出了动作空间定义。

**注意 2：** 复用统计是否有效，取决于你的机器人和任务与预训练数据分布的相似度。建议同时尝试两种方式：一种是复用已有统计，另一种是基于新数据重新计算统计，最后选择实际效果更好的方案。如何计算新统计量可以参考 [README](../README.md)。


## 已提供的预训练归一化统计

下面是当前提供的预训练归一化统计。`pi0_base` 和 `pi0_fast_base` 都提供这些统计。对于 `pi0_base`，`assets_dir` 设置为 `gs://openpi-assets/checkpoints/pi0_base/assets`；对于 `pi0_fast_base`，`assets_dir` 设置为 `gs://openpi-assets/checkpoints/pi0_fast_base/assets`。

| 机器人 | 说明 | Asset ID |
|-------|-------------|----------|
| ALOHA | 6 自由度双臂机器人，平行夹爪 | trossen |
| Mobile ALOHA | 安装在 Slate 底盘上的移动版 ALOHA | trossen_mobile |
| Franka Emika (DROID) | DROID 设置中的 7 自由度机械臂，平行夹爪 | droid |
| Franka Emika (non-DROID) | Franka FR3 机械臂，Robotiq 2F-85 夹爪 | franka |
| UR5e | 6 自由度 UR5e 机械臂，Robotiq 2F-85 夹爪 | ur5e |
| UR5e bi-manual | 双臂 UR5e 设置，Robotiq 2F-85 夹爪 | ur5e_dual |
| ARX | 双臂 ARX-5 机器人，平行夹爪 | arx |
| ARX mobile | 安装在 Slate 底盘上的移动版双臂 ARX-5 | arx_mobile |
| Fibocom mobile | Fibocom 移动机器人，配置两条 ARX-5 机械臂 | fibocom_mobile |


## Pi0 模型动作空间定义

默认情况下，`pi0_base` 和 `pi0_fast_base` 使用下面的动作空间定义。左臂和右臂的方向定义为从机器人后方朝工作空间看过去：

```
    "dim_0:dim_5": "左臂关节角",
    "dim_6": "左臂夹爪位置",
    "dim_7:dim_12": "右臂关节角（仅双臂）",
    "dim_13": "右臂夹爪位置（仅双臂）",

    # 对移动机器人:
    "dim_14:dim_15": "x-y 底盘速度（仅移动机器人）",
```

本体状态使用与动作空间相同的定义。例外是移动机器人底盘的 x-y 位置，也就是最后两个维度，不会包含在本体状态中。

对于 7 自由度机器人，例如 Franka，动作空间前 7 维用于关节动作，第 8 维用于夹爪动作。

Pi 机器人通用约定：

- 关节角使用弧度表示。位置 0 对应各机器人接口库报告的零位。ALOHA 例外，标准 ALOHA 代码使用的约定略有不同，细节见 [ALOHA 示例代码](../examples/aloha_real/README.md)。
- 夹爪位置范围是 `[0.0, 1.0]`，`0.0` 表示完全打开，`1.0` 表示完全闭合。
- 控制频率方面，UR5e 和 Franka 是 20 Hz，ARX 和 Trossen，也就是 ALOHA，机械臂是 50 Hz。

对于 DROID，我们使用原始 DROID 动作配置：前 7 维是关节速度动作，第 8 维是夹爪动作，控制频率为 15 Hz。
