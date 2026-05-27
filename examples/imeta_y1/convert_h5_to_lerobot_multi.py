"""
Convert multiple IMETA Y1/Aloha-style HDF5 directories into one LeRobot v2.1 dataset.

This avoids creating an intermediate merged raw-HDF5 directory. Each input directory
is scanned for episode_*.hdf5 files, and all episodes are appended into a single
LeRobot repo. Per-episode HDF5 `task` attrs are preserved when present.

Example:
    python examples/imeta_y1/convert_h5_to_lerobot_multi.py \
        --config.repo-id openpi/y1_dual_arm_mixed_20260526 \
        --config.no-single-arm \
        --config.cam-names cam_high cam_left_wrist cam_right_wrist \
        --config.h5-raw-dirs \
            /inspire/hdd/global_user/chengdongzhou-240108390137/datasets/y1_data/raw_hdf5/2026-05-26/paper_ball_cleanup \
            /inspire/hdd/global_user/chengdongzhou-240108390137/datasets/y1_data/raw_hdf5/2026-05-26/stack_bowls_basket \
            /inspire/hdd/global_user/chengdongzhou-240108390137/datasets/y1_data/raw_hdf5/2026-05-26/bottle_handoff_basket
"""

from dataclasses import dataclass, field
from pathlib import Path
import shutil
from typing import List

from lerobot.common.datasets.lerobot_dataset import HF_LEROBOT_HOME
from lerobot.common.datasets.lerobot_dataset import LeRobotDataset
import tqdm
import tyro

from convert_h5_to_lerobot import DatasetConfig
from convert_h5_to_lerobot import create_empty_dataset
from convert_h5_to_lerobot import load_raw_episode_data


@dataclass(frozen=True)
class MultiDatasetConfig:
    h5_raw_dirs: List[Path]
    repo_id: str
    # True: single arm, False: dual arm.
    single_arm: bool = True
    cam_names: List[str] = field(default_factory=lambda: ["cam_high", "cam_right_wrist", "cam_left_wrist"])
    has_velocity: bool = False
    has_effort: bool = False
    # If not None, override all per-episode task attrs with this task.
    task: str | None = None
    # If an episode has no HDF5 task attr and task is None, use the source directory name.
    task_fallback_from_dir: bool = True

    use_videos: bool = True
    fps: int = 30
    robot_type: str = "IMETA_Y1"
    push_to_hub: bool = False
    tolerance_s: float = 0.0001
    image_writer_processes: int = 10
    image_writer_threads: int = 5
    video_backend: str | None = None


def _single_dataset_config(config: MultiDatasetConfig) -> DatasetConfig:
    if not config.h5_raw_dirs:
        raise ValueError("At least one --config.h5-raw-dirs entry is required.")

    return DatasetConfig(
        h5_raw_dir=config.h5_raw_dirs[0],
        repo_id=config.repo_id,
        single_arm=config.single_arm,
        cam_names=config.cam_names,
        has_velocity=config.has_velocity,
        has_effort=config.has_effort,
        task=config.task,
        use_videos=config.use_videos,
        fps=config.fps,
        robot_type=config.robot_type,
        push_to_hub=config.push_to_hub,
        tolerance_s=config.tolerance_s,
        image_writer_processes=config.image_writer_processes,
        image_writer_threads=config.image_writer_threads,
        video_backend=config.video_backend,
    )


def _normalize_task(task: object) -> str | None:
    if task is None:
        return None
    if isinstance(task, bytes):
        return task.decode("utf-8")
    return str(task)


def collect_hdf5_files(raw_dirs: list[Path]) -> list[Path]:
    hdf5_files: list[Path] = []
    for raw_dir in raw_dirs:
        raw_dir = raw_dir.resolve()
        if not raw_dir.exists():
            raise ValueError(f"h5_raw_dir does not exist: {raw_dir}")
        if not raw_dir.is_dir():
            raise ValueError(f"h5_raw_dir is not a directory: {raw_dir}")

        files = sorted(raw_dir.glob("episode_*.hdf5"))
        if not files:
            raise ValueError(f"No episode_*.hdf5 files found in {raw_dir}")

        print(f"{raw_dir}: {len(files)} episodes")
        hdf5_files.extend(files)

    print(f"total episodes: {len(hdf5_files)}")
    return hdf5_files


def populate_mixed_dataset(
    config: MultiDatasetConfig,
    dataset: LeRobotDataset,
    hdf5_files: list[Path],
) -> LeRobotDataset:
    for ep_path in tqdm.tqdm(hdf5_files):
        imgs_per_cam, state, action, velocity, effort, task_description = load_raw_episode_data(
            ep_path,
            config.cam_names,
        )
        num_frames = state.shape[0]

        task = _normalize_task(config.task) or _normalize_task(task_description)
        if task is None and config.task_fallback_from_dir:
            task = ep_path.parent.name.replace("_", " ")
        if task is None:
            raise ValueError(f"No task found for {ep_path}. Set --config.task or enable task_fallback_from_dir.")

        for i in range(num_frames):
            frame = {
                "observation.state": state[i],
                "action": action[i],
                "task": task,
            }

            for camera, img_array in imgs_per_cam.items():
                frame[f"observation.images.{camera}"] = img_array[i]

            if velocity is not None and config.has_velocity:
                frame["observation.velocity"] = velocity[i]
            if effort is not None and config.has_effort:
                frame["observation.effort"] = effort[i]

            dataset.add_frame(frame)

        dataset.save_episode()

    return dataset


def port_multi_aloha(config: MultiDatasetConfig):
    output_dir = HF_LEROBOT_HOME / config.repo_id
    if output_dir.exists():
        shutil.rmtree(output_dir)

    hdf5_files = collect_hdf5_files(config.h5_raw_dirs)
    dataset = create_empty_dataset(dataset_config=_single_dataset_config(config))
    dataset = populate_mixed_dataset(config, dataset, hdf5_files)

    if config.push_to_hub:
        dataset.push_to_hub()


if __name__ == "__main__":
    tyro.cli(port_multi_aloha)
