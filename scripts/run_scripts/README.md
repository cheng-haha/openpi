# stack_bowls_basket Training Run Scripts

These scripts prepare and launch PI0.5 full fine-tuning for the dual-arm Y1 `stack_bowls_basket` dataset.

Run location:

```bash
ssh vla0
cd /inspire/hdd/global_user/chengdongzhou-240108390137/vla_projects/openpi-cheng-haha
```

Order:

```bash
bash scripts/run_scripts/01_validate_stack_bowls_basket_dataset.sh
bash scripts/run_scripts/02_compute_norm_stats_stack_bowls_basket.sh
bash scripts/run_scripts/03_train_pi05_stack_bowls_basket_vla0_4gpu.sh
```

Remote real-robot inference runs on the Y1 control machine after the GPU policy server is already up:

```bash
cd /home/ubuntu/projects/y1_robot/openpi
SERVER_URL="<current VS Code / Inspire forwarded URL ending with /proxy/8000/>" \
bash scripts/run_scripts/06_infer_stack_bowls_basket_remote_real_robot.sh
```

Do not write the full `SERVER_URL` into scripts or docs. It contains a session token and changes when the notebook / VS Code / Inspire session changes.

For the mixed Y1 policy server, use the task-specific wrappers below. They share the same RTC-capable Y1 remote inference path and only change the task prompt:

```bash
SERVER_URL="<current VS Code / Inspire forwarded URL ending with /proxy/8000/>" \
bash scripts/run_scripts/16_infer_y1_mixed_paper_ball_cleanup.sh

SERVER_URL="<current VS Code / Inspire forwarded URL ending with /proxy/8000/>" \
bash scripts/run_scripts/17_infer_y1_mixed_stack_bowls_basket.sh

SERVER_URL="<current VS Code / Inspire forwarded URL ending with /proxy/8000/>" \
bash scripts/run_scripts/18_infer_y1_mixed_bottle_handoff_basket.sh
```

Mixed-task prompts:

```text
paper_ball_cleanup:      clear paper balls into trash bin
stack_bowls_basket:     stack bowls then place in basket
bottle_handoff_basket:  handoff water bottle into basket
```

Default config:

```text
pi05_base_full_dual_arm_stack_bowls_basket
```

Default dataset:

```text
/inspire/hdd/global_user/chengdongzhou-240108390137/datasets/y1_data/lerobot_data/openpi/stack_bowls_basket
```

Default base checkpoint cache:

```text
/inspire/hdd/global_user/chengdongzhou-240108390137/ai_models/physical-intelligence/openpi-assets/checkpoints/pi05_base
```

Default tokenizer cache:

```text
/inspire/hdd/global_user/chengdongzhou-240108390137/ai_models/physical-intelligence/big_vision/paligemma_tokenizer.model
```

The norm-stats and training scripts run `uv` with `--offline --no-sync` and set Hugging Face / Transformers offline environment variables. Missing local assets should fail fast instead of being downloaded during training.

Before full training, confirm the converted LeRobot dataset episode count is expected. The current dataset metadata reports 20 episodes and 16696 frames, matching the 20 raw HDF5 files.

Useful overrides:

```bash
EXP_NAME=stack_bowls_basket_test_$(date +%Y%m%d_%H%M%S) \
NUM_TRAIN_STEPS=1000 \
bash scripts/run_scripts/03_train_pi05_stack_bowls_basket_vla0_4gpu.sh
```

WandB runs in offline mode by default for no-network training. Offline logs are written under:

```text
/inspire/hdd/global_user/chengdongzhou-240108390137/openpi_data/wandb
```

To fully disable WandB instead of offline logging:

```bash
DISABLE_WANDB=1 bash scripts/run_scripts/03_train_pi05_stack_bowls_basket_vla0_4gpu.sh
```

Resume:

```bash
EXP_NAME=<existing_exp_name> RESUME=1 bash scripts/run_scripts/03_train_pi05_stack_bowls_basket_vla0_4gpu.sh
```

Overwrite an existing run:

```bash
EXP_NAME=<existing_exp_name> OVERWRITE=1 bash scripts/run_scripts/03_train_pi05_stack_bowls_basket_vla0_4gpu.sh
```

Real-robot inference defaults:

```text
PROMPT=stack bowls then place in basket
CAMERA_TYPE=ros2
CAM_NAMES="cam_high cam_left_wrist cam_right_wrist"
CAMERA_TOPICS="cam_high=/camera_high/color/image_raw cam_left_wrist=/camera_left/color/image_raw cam_right_wrist=/camera_right/color/image_raw"
ARM_CAN_IDS="left_arm=can0 right_arm=can1"
ACTION_HORIZON=30
CONTROL_RATE_HZ=30
MAX_EPISODE_STEPS=300
```

PI0.5 returns 50-step action chunks. This wrapper defaults to
`ACTION_HORIZON=30` to match upstream IMETA synchronous Y1 inference at 30 Hz;
use `ACTION_HORIZON=50` only when you intentionally want to execute the full
chunk before re-querying.

The inference wrapper can optionally start local robot support tmux sessions:

```bash
START_Y1_CONTROL=1 START_Y1_CAMERAS=1 \
SERVER_URL="<current forwarded URL ending with /proxy/8000/>" \
bash scripts/run_scripts/06_infer_stack_bowls_basket_remote_real_robot.sh
```
