# Inference Commands

Run on `our_robot` after the vla0 policy server is up and port `8000` is forwarded. Do not commit the real forwarded URL; it contains a temporary session token.

## Legacy Stack-Bowls Checkpoint

```bash
cd /home/ubuntu/projects/y1_robot/openpi

SERVER_URL="<current VS Code / Inspire forwarded URL ending with /proxy/8000/>" \
bash scripts/run_scripts/06_infer_stack_bowls_basket_remote_real_robot.sh
```

## Mixed Y1 Policy Tasks

The mixed checkpoint uses one deployed policy server and switches tasks through the prompt in each wrapper.

### Paper Ball Cleanup

```bash
cd /home/ubuntu/projects/y1_robot/openpi

SERVER_URL="<current VS Code / Inspire forwarded URL ending with /proxy/8000/>" \
bash scripts/run_scripts/16_infer_y1_mixed_paper_ball_cleanup.sh
```

Prompt:

```text
clear paper balls into trash bin
```

### Stack Bowls Basket

```bash
cd /home/ubuntu/projects/y1_robot/openpi

SERVER_URL="<current VS Code / Inspire forwarded URL ending with /proxy/8000/>" \
bash scripts/run_scripts/17_infer_y1_mixed_stack_bowls_basket.sh
```

Prompt:

```text
stack bowls then place in basket
```

### Bottle Handoff Basket

```bash
cd /home/ubuntu/projects/y1_robot/openpi

SERVER_URL="<current VS Code / Inspire forwarded URL ending with /proxy/8000/>" \
bash scripts/run_scripts/18_infer_y1_mixed_bottle_handoff_basket.sh
```

Prompt:

```text
handoff water bottle into basket
```
