import pathlib
import sys
import threading
import time
from typing import Literal
from typing import Union

import cv2
import numpy as np

sys.path.append("./")
sys.path.append(str(pathlib.Path(__file__).resolve().parents[2]))
sys.path.append(str(pathlib.Path(__file__).resolve().parent))

# Default mapping for this robot workstation.
DEFAULT_CAMERA_SERIALS = {
    "cam_high": "CH8R554001M",
    "cam_left_wrist": "CH8G65200Z9",
    "cam_right_wrist": "CH8G65200Y4",
}

DEFAULT_V4L2_CAMERA_DEVICES = {
    "cam_high": "/dev/cam_high",
    "cam_left_wrist": "/dev/cam_left_wrist",
    "cam_right_wrist": "/dev/cam_right_wrist",
}

DEFAULT_ROS2_CAMERA_TOPICS = {
    "cam_high": "/camera_high/color/image_raw",
    "cam_left_wrist": "/camera_left/color/image_raw",
    "cam_right_wrist": "/camera_right/color/image_raw",
}

DEFAULT_ARM_CAN_IDS = {
    "left_arm": "can0",
    "right_arm": "can1",
}


class RealRobotEnv:
    def __init__(
        self,
        single_arm: bool,
        cam_names: list[str],
        visual: bool = False,
        camera_type: Literal["orbbec", "v4l2", "ros2"] = "v4l2",
        visual_fps: float = 30.0,
        camera_devices: dict[str, str] | None = None,
        camera_serials: dict[str, str] | None = None,
        camera_topics: dict[str, str] | None = None,
        arm_can_ids: dict[str, str] | None = None,
    ):
        self.single_arm = single_arm
        self.camera_names = cam_names
        self.camera_type = camera_type
        self.visual = visual
        self.visual_fps = visual_fps
        self.camera_devices = camera_devices or DEFAULT_V4L2_CAMERA_DEVICES
        self.camera_serials = camera_serials or DEFAULT_CAMERA_SERIALS
        self.camera_topics = camera_topics or DEFAULT_ROS2_CAMERA_TOPICS
        self.arm_can_ids = arm_can_ids or DEFAULT_ARM_CAN_IDS
        self._visualizer_running = False
        self._visualizer_thread = None
        self._visualizer_step = 0
        self._rr = None

        arm_names = ["right_arm"] if self.single_arm else ["left_arm", "right_arm"]
        self.controllers = {"arm": {arm_name: self._create_controller(arm_name) for arm_name in arm_names}}

        self.cameras = {"images": {}}
        for cam_name in self.camera_names:
            self.cameras["images"][cam_name] = self._create_camera(cam_name)

    def _create_controller(self, name: str):
        try:
            from scripts.inference_python.robot.imeta_y1 import Y1Controller
        except ModuleNotFoundError:
            from robot.imeta_y1 import Y1Controller

        return Y1Controller(name)

    def _create_camera(self, cam_name: str):
        if self.camera_type == "orbbec":
            try:
                from scripts.inference_python.camera.orbbec_camera import OrbbecCamera
            except ModuleNotFoundError:
                from camera.orbbec_camera import OrbbecCamera

            return OrbbecCamera(cam_name, visual=False)

        if self.camera_type == "v4l2":
            try:
                from scripts.inference_python.camera.v4l2_camera import V4l2Camera
            except ModuleNotFoundError:
                from camera.v4l2_camera import V4l2Camera

            return V4l2Camera(cam_name, visual=False)

        if self.camera_type == "ros2":
            try:
                from scripts.inference_python.camera.ros2_topic_camera import Ros2TopicCamera
            except ModuleNotFoundError:
                from camera.ros2_topic_camera import Ros2TopicCamera

            return Ros2TopicCamera(cam_name, visual=False)

        raise ValueError(f"Unsupported camera_type: {self.camera_type}")

    def _compose_display_image(self, frames: dict[str, np.ndarray]):
        display_order = ["cam_left_wrist", "cam_high", "cam_right_wrist"]
        ordered_frames = []

        for cam_name in display_order:
            if cam_name in self.camera_names and cam_name in frames:
                ordered_frames.append(frames[cam_name])

        for cam_name in self.camera_names:
            if cam_name not in display_order and cam_name in frames:
                ordered_frames.append(frames[cam_name])

        if not ordered_frames:
            return None

        target_height = min(frame.shape[0] for frame in ordered_frames)
        resized_frames = []
        for frame in ordered_frames:
            height, width = frame.shape[:2]
            if height != target_height:
                target_width = max(1, int(round(width * target_height / height)))
                frame = cv2.resize(frame, (target_width, target_height), interpolation=cv2.INTER_LINEAR)
            resized_frames.append(frame)

        return np.concatenate(resized_frames, axis=1)

    def set_up(self, teleop=False):
        for arm_name, controller in self.controllers["arm"].items():
            if arm_name not in self.arm_can_ids:
                raise RuntimeError(f"Missing CAN id for {arm_name}")
            controller.set_up(self.arm_can_ids[arm_name], teleop=teleop)

        for cam_name, camera in self.cameras["images"].items():
            if self.camera_type == "orbbec":
                if cam_name not in self.camera_serials:
                    raise RuntimeError(f"Missing Orbbec serial for camera {cam_name}")
                camera.set_up(self.camera_serials[cam_name])
            elif self.camera_type == "v4l2":
                if cam_name not in self.camera_devices:
                    raise RuntimeError(f"Missing V4L2 device for camera {cam_name}")
                camera.set_up(self.camera_devices[cam_name])
            elif self.camera_type == "ros2":
                if cam_name not in self.camera_topics:
                    raise RuntimeError(f"Missing ROS2 topic for camera {cam_name}")
                camera.set_up(self.camera_topics[cam_name])
            else:
                raise ValueError(f"Unsupported camera_type: {self.camera_type}")

        if self.visual:
            self.start_visualizer()
        print("set up success!")

    def start_visualizer(self):
        if self._visualizer_running:
            return

        import rerun as rr

        self._rr = rr
        rr.init("openpi_real_robot_inference", spawn=True)
        self._visualizer_running = True
        self._visualizer_thread = threading.Thread(
            target=self._visualizer_loop,
            name="real_robot_visualizer",
            daemon=True,
        )
        self._visualizer_thread.start()
        print(f"rerun visualizer started at {self.visual_fps:.1f} FPS")

    def _visualizer_loop(self):
        rr = self._rr
        if rr is None:
            return

        sleep_time = 1.0 / self.visual_fps if self.visual_fps > 0 else 0.0
        while self._visualizer_running:
            try:
                frame_bundle = {}
                for cam_name in self.camera_names:
                    image = self.cameras["images"][cam_name].get_image(timeout=0.0)
                    if image is not None:
                        frame_bundle[cam_name] = image

                if frame_bundle:
                    rr.set_time("frame", sequence=self._visualizer_step)
                    for cam_name, image in frame_bundle.items():
                        rr.log(f"camera/{cam_name}", rr.Image(image))

                    display_image = self._compose_display_image(frame_bundle)
                    if display_image is not None:
                        rr.log("camera/stitched", rr.Image(display_image))

                    self._visualizer_step += 1

                if sleep_time > 0:
                    time.sleep(sleep_time)
            except KeyboardInterrupt:
                self._visualizer_running = False
                break
            except Exception as exc:
                self._visualizer_running = False
                print(f"visualizer stopped: {exc}")
                break

    def get_observation(self):
        observation = {}

        if "arm" in self.controllers:
            arm_controller = self.controllers["arm"]
            if len(arm_controller) == 1:
                right_arm_state = arm_controller["right_arm"].get_state()
                observation["state"] = np.concatenate(
                    [
                        right_arm_state["joint_position"],
                        [right_arm_state["gripper"]],
                    ]
                )
            elif len(arm_controller) == 2:
                left_arm_state = arm_controller["left_arm"].get_state()
                right_arm_state = arm_controller["right_arm"].get_state()

                left_joint_and_gripper = np.concatenate(
                    [
                        left_arm_state["joint_position"],
                        [left_arm_state["gripper"]],
                    ]
                )
                right_joint_and_gripper = np.concatenate(
                    [
                        right_arm_state["joint_position"],
                        [right_arm_state["gripper"]],
                    ]
                )
                observation["state"] = np.concatenate([left_joint_and_gripper, right_joint_and_gripper])
            else:
                raise RuntimeError(f"arm controller size is {len(arm_controller)}")
        else:
            raise RuntimeError("Not find arm controller!")

        camere_images = self.cameras["images"]
        images = {}
        for cam_name in self.camera_names:
            if cam_name not in camere_images:
                raise RuntimeError(f"Not find camera {cam_name}!")

            image_start = time.time()
            image = camere_images[cam_name].get_image(timeout=0.0)
            if image is None:
                image = camere_images[cam_name].get_image()
            if image is None:
                print(
                    f"not receive {cam_name} image data "
                    f"after {(time.time() - image_start) * 1000:.1f} ms"
                )
                return None

            images[cam_name] = np.transpose(image, (2, 0, 1))

        observation["images"] = images
        return observation

    def step(self, action: Union[list, np.ndarray]):
        if self.single_arm:
            assert len(action) >= 7

            right_arm_controller = self.controllers["arm"]["right_arm"]
            right_arm_controller.set_joint_position(action[0:6])
            right_arm_controller.set_gripper(action[6])
        else:
            assert len(action) >= 14

            left_arm_controller = self.controllers["arm"]["left_arm"]
            left_arm_controller.set_joint_position(action[0:6])
            left_arm_controller.set_gripper(action[6])

            right_arm_controller = self.controllers["arm"]["right_arm"]
            right_arm_controller.set_joint_position(action[7:13])
            right_arm_controller.set_gripper(action[13])

    def stop(self):
        self._visualizer_running = False
        if self._visualizer_thread is not None:
            try:
                self._visualizer_thread.join(timeout=1.0)
            except BaseException:
                pass
            self._visualizer_thread = None

        for camera in self.cameras["images"].values():
            try:
                camera.stop()
            except BaseException:
                pass


if __name__ == "__main__":
    env = RealRobotEnv(single_arm=False, cam_names=["cam_high", "cam_right_wrist", "cam_left_wrist"], visual=True)
    env.set_up()

    try:
        while True:
            obs = env.get_observation()
            print(f"observation : {obs}")
            time.sleep(1.0 / 30)
    finally:
        env.stop()
