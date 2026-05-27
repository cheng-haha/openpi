import argparse
import dataclasses
import time
from urllib.parse import urlparse
from urllib.parse import urlunparse

import numpy as np
from openpi_client import websocket_client_policy


CAMERA_NAMES = ("cam_high", "cam_left_wrist", "cam_right_wrist")


def _as_websocket_url(address: str) -> str:
    parsed = urlparse(address)
    if parsed.scheme == "http":
        return urlunparse(parsed._replace(scheme="ws"))
    if parsed.scheme == "https":
        return urlunparse(parsed._replace(scheme="wss"))
    return address


def _make_fake_image(seed: int, height: int, width: int, layout: str) -> np.ndarray:
    rng = np.random.default_rng(seed)
    image = np.zeros((height, width, 3), dtype=np.uint8)
    image[..., 0] = np.linspace(0, 255, width, dtype=np.uint8)[None, :]
    image[..., 1] = np.linspace(0, 255, height, dtype=np.uint8)[:, None]
    image[..., 2] = rng.integers(0, 255, size=(height, width), dtype=np.uint8)
    if layout == "chw":
        return np.transpose(image, (2, 0, 1))
    return image


def _make_payload(prompt: str, state_dim: int, image_height: int, image_width: int, image_layout: str) -> dict:
    return {
        "images": {
            camera_name: _make_fake_image(seed=i, height=image_height, width=image_width, layout=image_layout)
            for i, camera_name in enumerate(CAMERA_NAMES)
        },
        "state": np.zeros((state_dim,), dtype=np.float32),
        "prompt": prompt,
    }


@dataclasses.dataclass
class Args:
    host: str = "127.0.0.1"
    port: int | None = 8000
    server: str | None = None
    prompt: str = "stack bowls then place in basket"
    state_dim: int = 14
    image_height: int = 224
    image_width: int = 224
    image_layout: str = "chw"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=Args.host)
    parser.add_argument("--port", type=int, default=Args.port)
    parser.add_argument("--server", default=None, help="Optional ws://, wss://, http://, or https:// forwarded URL.")
    parser.add_argument("--prompt", default=Args.prompt)
    parser.add_argument("--state-dim", type=int, default=Args.state_dim)
    parser.add_argument("--image-height", type=int, default=Args.image_height)
    parser.add_argument("--image-width", type=int, default=Args.image_width)
    parser.add_argument("--image-layout", choices=("chw", "hwc"), default=Args.image_layout)
    args = parser.parse_args()

    if args.server:
        client = websocket_client_policy.WebsocketClientPolicy(host=_as_websocket_url(args.server), port=None)
    else:
        client = websocket_client_policy.WebsocketClientPolicy(host=args.host, port=args.port)

    metadata = client.get_server_metadata()
    print("server_metadata:", metadata)

    payload = _make_payload(
        prompt=args.prompt,
        state_dim=args.state_dim,
        image_height=args.image_height,
        image_width=args.image_width,
        image_layout=args.image_layout,
    )
    print("payload_state_shape:", payload["state"].shape)
    print("payload_image_shapes:", {name: image.shape for name, image in payload["images"].items()})
    print("payload_image_layout:", args.image_layout)
    print("payload_prompt:", payload["prompt"])

    start = time.time()
    result = client.infer(payload)
    elapsed_ms = (time.time() - start) * 1000

    actions = np.asarray(result["actions"])
    print("roundtrip_ms:", round(elapsed_ms, 2))
    print("actions_shape:", actions.shape)
    print("actions_dtype:", actions.dtype)
    print("actions_first:", actions[0].tolist() if actions.ndim >= 2 and len(actions) else actions.tolist())
    print("actions_min_max:", float(np.nanmin(actions)), float(np.nanmax(actions)))
    if "policy_timing" in result:
        print("policy_timing:", result["policy_timing"])
    if "server_timing" in result:
        print("server_timing:", result["server_timing"])

    if actions.ndim != 2:
        raise SystemExit(f"Expected 2-D action chunk, got shape {actions.shape}")
    if actions.shape[-1] != args.state_dim:
        raise SystemExit(f"Expected action dim {args.state_dim}, got {actions.shape[-1]}")


if __name__ == "__main__":
    main()
