import re
import threading
import time

import numpy as np

try:
    from scripts.inference_python.camera.base_camera import BaseCamera
except ModuleNotFoundError:
    try:
        from camera.base_camera import BaseCamera
    except ModuleNotFoundError:
        from base_camera import BaseCamera


class Ros2TopicCamera(BaseCamera):
    def __init__(self, name: str, visual: bool = False):
        super().__init__(name, visual)
        self.topic = None
        self.node = None
        self.executor = None
        self.subscription = None
        self.bridge = None
        self.lock = threading.Lock()
        self.latest_image = None
        self.latest_stamp = None
        self._frame_event = threading.Event()
        self._spin_thread = None

    def _callback(self, msg):
        try:
            image = self.bridge.imgmsg_to_cv2(msg, desired_encoding="rgb8")
            image = np.asarray(image, dtype=np.uint8)
            stamp = None
            if getattr(msg, "header", None) is not None:
                stamp = float(msg.header.stamp.sec) + float(msg.header.stamp.nanosec) / 1_000_000_000.0

            with self.lock:
                self.latest_image = image.copy()
                self.latest_stamp = stamp
            self._frame_event.set()
        except Exception as exc:
            print(f"failed to decode ROS2 image for {self.name}: {exc}")

    def set_up(self, topic: str):
        try:
            import rclpy
            from cv_bridge import CvBridge
            from rclpy.executors import SingleThreadedExecutor
            from rclpy.qos import DurabilityPolicy
            from rclpy.qos import HistoryPolicy
            from rclpy.qos import QoSProfile
            from rclpy.qos import ReliabilityPolicy
            from sensor_msgs.msg import Image
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "ROS2 camera mode requires ROS2 Python packages. "
                "Run: source /opt/ros/humble/setup.bash"
            ) from exc

        if not rclpy.ok():
            rclpy.init(args=None)

        self.topic = topic
        self.bridge = CvBridge()
        node_name = "openpi_" + re.sub(r"[^a-zA-Z0-9_]", "_", self.name) + "_camera"
        self.node = rclpy.create_node(node_name)

        qos_profile = QoSProfile(
            depth=1,
            durability=DurabilityPolicy.VOLATILE,
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
        )
        self.subscription = self.node.create_subscription(Image, topic, self._callback, qos_profile)
        self.executor = SingleThreadedExecutor()
        self.executor.add_node(self.node)
        self._spin_thread = threading.Thread(target=self.executor.spin, name=f"{self.name}_ros2_spin", daemon=True)
        self._spin_thread.start()
        print(f"Started ROS2 camera: {self.name} ({topic})")

    def get_image(self, timeout: float = 2.0):
        deadline = time.monotonic() + max(timeout, 0.0)
        while True:
            with self.lock:
                if self.latest_image is not None:
                    return self.latest_image.copy()

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            self._frame_event.wait(timeout=min(remaining, 0.05))

    def stop(self):
        if self.executor is not None:
            try:
                self.executor.shutdown()
            except BaseException:
                pass
            self.executor = None

        if self._spin_thread is not None:
            try:
                self._spin_thread.join(timeout=1.0)
            except BaseException:
                pass
            self._spin_thread = None

        if self.node is not None:
            try:
                self.node.destroy_node()
            except BaseException:
                pass
            self.node = None

        with self.lock:
            self.latest_image = None
            self.latest_stamp = None
        self._frame_event.clear()
