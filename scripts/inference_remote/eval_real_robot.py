import dataclasses
import logging
import pathlib
import sys
import time
from pprint import pformat

import numpy as np
from openpi_client import image_tools
from openpi_client import websocket_client_policy
import tyro

sys.path.append(str(pathlib.Path(__file__).resolve().parents[2]))

from scripts.inference_python.real_robot_env import DEFAULT_ARM_CAN_IDS
from scripts.inference_python.real_robot_env import DEFAULT_ROS2_CAMERA_TOPICS
from scripts.inference_python.real_robot_env import DEFAULT_V4L2_CAMERA_DEVICES
from scripts.inference_python.real_robot_env import RealRobotEnv


def _parse_kv_pairs(raw_pairs: list[str] | None) -> dict[str, str]:
    values: dict[str, str] = {}
    for pair in raw_pairs or []:
        if "=" not in pair:
            raise ValueError(f"Invalid KEY=VALUE pair: {pair}")
        key, value = pair.split("=", 1)
        values[key] = value
    return values


def _default_camera_names(single_arm: bool) -> list[str]:
    if single_arm:
        return ["cam_high", "cam_right_wrist"]
    return ["cam_high", "cam_left_wrist", "cam_right_wrist"]


@dataclasses.dataclass
class Args:
    host: str = "127.0.0.1"
    port: int = 8000
    prompt: str | None = None

    single_arm: bool = False
    camera_type: str = "ros2"
    cam_names: list[str] | None = None

    action_horizon: int = 30
    control_rate_hz: float = 30.0
    max_episode_steps: int = 1000

    image_height: int = 224
    image_width: int = 224

    reset_joints: list[float] | None = None
    camera_devices: list[str] | None = None
    camera_serials: list[str] | None = None
    camera_topics: list[str] | None = None
    arm_can_ids: list[str] | None = None


def _prepare_observation(observation: dict, image_height: int, image_width: int, prompt: str | None) -> dict:
    images: dict[str, np.ndarray] = {}
    for cam_name, image in observation["images"].items():
        hwc_image = np.transpose(image, (1, 2, 0))
        resized = image_tools.resize_with_pad(hwc_image, image_height, image_width)
        resized = image_tools.convert_to_uint8(resized)
        images[cam_name] = np.transpose(resized, (2, 0, 1))

    payload = {
        "state": np.asarray(observation["state"], dtype=np.float32),
        "images": images,
    }
    if prompt:
        payload["prompt"] = prompt
    return payload


def main(args: Args) -> None:
    logging.info(pformat(dataclasses.asdict(args)))

    cam_names = args.cam_names or _default_camera_names(args.single_arm)
    camera_devices = dict(DEFAULT_V4L2_CAMERA_DEVICES)
    camera_devices.update(_parse_kv_pairs(args.camera_devices))
    camera_topics = dict(DEFAULT_ROS2_CAMERA_TOPICS)
    camera_topics.update(_parse_kv_pairs(args.camera_topics))
    arm_can_ids = dict(DEFAULT_ARM_CAN_IDS)
    arm_can_ids.update(_parse_kv_pairs(args.arm_can_ids))

    env = RealRobotEnv(
        single_arm=args.single_arm,
        cam_names=cam_names,
        camera_type=args.camera_type,
        camera_devices=camera_devices,
        camera_serials=_parse_kv_pairs(args.camera_serials),
        camera_topics=camera_topics,
        arm_can_ids=arm_can_ids,
    )
    env.set_up()

    policy = websocket_client_policy.WebsocketClientPolicy(host=args.host, port=args.port)
    metadata = policy.get_server_metadata()
    logging.info("Connected to remote server, metadata: %s", metadata)

    if args.reset_joints is not None:
        print("Move robot to reset joints.")
        env.step(np.asarray(args.reset_joints, dtype=np.float32))
        time.sleep(3)

    input("Press key [enter] to start remote inference: ")

    step_idx = 0
    while step_idx < args.max_episode_steps:
        try:
            observation = env.get_observation()
            if observation is None:
                time.sleep(1.0 / args.control_rate_hz)
                continue

            payload = _prepare_observation(
                observation,
                image_height=args.image_height,
                image_width=args.image_width,
                prompt=args.prompt,
            )

            start_time = time.time()
            action_chunk = policy.infer(payload)["actions"]
            print(f"remote inference time: {(time.time() - start_time) * 1000:.1f} ms")

            execute_len = min(len(action_chunk), args.action_horizon)
            for action in action_chunk[:execute_len]:
                env.step(np.asarray(action, dtype=np.float32))
                time.sleep(1.0 / args.control_rate_hz)
                step_idx += 1
                if step_idx >= args.max_episode_steps:
                    break

        except KeyboardInterrupt:
            print("KeyboardInterrupt")
            break


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, force=True)
    main(tyro.cli(Args))
