
# 远程运行 openpi 模型

本仓库提供了远程运行 openpi 模型的工具。远程推理适合把模型放在更强的 GPU 机器上运行，机器人本体只负责采集观测和执行动作。这样也能把机器人运行环境和策略模型环境隔离开，减少依赖冲突。

## 启动远程策略服务

启动远程策略服务可以直接运行：

```bash
uv run scripts/serve_policy.py --env=[DROID | ALOHA | LIBERO]
```

`env` 参数用于指定要加载哪个 $\pi_0$ checkpoint。脚本内部会执行类似下面的命令。对于你自己训练出的 checkpoint，也可以直接使用这种形式启动策略服务。下面是 DROID 环境的示例：

```bash
uv run scripts/serve_policy.py policy:checkpoint --policy.config=pi0_fast_droid --policy.dir=gs://openpi-assets/checkpoints/pi0_fast_droid
```

这会启动一个策略服务，加载由 `config` 和 `dir` 指定的 policy。服务监听指定端口，默认是 `8000`。

## 在机器人代码中请求远程策略服务

仓库提供了依赖很少的 client 工具，可以方便地嵌入到机器人代码中。

先在机器人运行环境中安装 `openpi-client`：

```bash
cd $OPENPI_ROOT/packages/openpi-client
pip install -e .
```

然后就可以在机器人代码里调用远程策略服务。示例：

```python
from openpi_client import image_tools
from openpi_client import websocket_client_policy

# 在 episode 循环外初始化 policy client。
# 策略服务地址由 host 和 port 指定，默认是 localhost:8000。
client = websocket_client_policy.WebsocketClientPolicy(host="localhost", port=8000)

for step in range(num_steps):
    # 在 episode 循环内构造 observation。
    # 建议在 client 侧 resize 图像，以降低带宽和延迟。图像始终使用 uint8。
    # 这里使用仓库提供的 resize 和 uint8 转换工具，以匹配训练流程。
    # 预训练 pi0 模型常用 resize_size 是 224。
    # 本体状态 state 可以传未归一化的原始值，服务端会负责归一化。
    observation = {
        "observation/image": image_tools.convert_to_uint8(
            image_tools.resize_with_pad(img, 224, 224)
        ),
        "observation/wrist_image": image_tools.convert_to_uint8(
            image_tools.resize_with_pad(wrist_img, 224, 224)
        ),
        "observation/state": state,
        "prompt": task_instruction,
    }

    # 用当前 observation 请求策略服务。
    # 返回值是 shape 为 (action_horizon, action_dim) 的 action chunk。
    # 通常不需要每一步都调用策略；可以每隔 N 步调用一次，
    # 中间步骤开环执行上一次预测出的 action chunk。
    action_chunk = client.infer(observation)["actions"]

    # 在环境中执行动作。
    ...

```

其中 `host` 和 `port` 指定远程策略服务的 IP 和端口。你可以把它们做成机器人程序的命令行参数，也可以直接写在代码里。`observation` 是观测和 prompt 组成的字典，必须符合当前 policy 的输入定义。不同环境下如何构造这个字典，可以参考 [simple client 示例](../examples/simple_client/main.py)。
