# Docker 环境配置

本仓库里的示例通常同时提供普通运行方式和 Docker 运行方式。Docker 不是必需的，但推荐使用，因为它可以简化软件安装，提供更稳定的环境；对于依赖 ROS 的示例，也可以避免把 ROS 直接安装到宿主机上。

- Docker 基础安装说明见 [Docker 官方文档](https://docs.docker.com/engine/install/)。
- Docker 必须以 [rootless mode](https://docs.docker.com/engine/security/rootless/) 安装。
- 如果要在容器中使用 GPU，还需要安装 [NVIDIA container toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)。
- 通过 `snap` 安装的 Docker 与 NVIDIA container toolkit 不兼容，会导致无法访问 `libnvidia-ml.so`，见相关 [issue](https://github.com/NVIDIA/nvidia-container-toolkit/issues/154)。可以用 `sudo snap remove docker` 卸载 snap 版本。
- Docker Desktop 也与 NVIDIA runtime 不兼容，见相关 [issue](https://github.com/NVIDIA/nvidia-container-toolkit/issues/229)。可以用 `sudo apt remove docker-desktop` 卸载 Docker Desktop。


如果宿主机是 Ubuntu 22.04，并且从零开始安装，可以直接使用这两个脚本完成上面的安装：

```text
scripts/docker/install_docker_ubuntu22.sh
scripts/docker/install_nvidia_container_toolkit.sh
```

构建 Docker 镜像并启动容器：

```bash
docker compose -f scripts/docker/compose.yml up --build
```

如果只想构建并运行某个指定示例的 Docker 镜像：

```bash
docker compose -f examples/<example_name>/compose.yml up --build
```

其中 `<example_name>` 是要运行的示例名称。

第一次运行某个示例时，Docker 会构建镜像，耗时会比较久。后续运行会复用缓存，因此速度会更快。
