# Laya System 1 Docker image

Builds the Docker image for the Laya System 1 Unraid template from the
[Laya](https://github.com/NandhaKishorM/laya) source. Laya has no official
image.

| Tag | For | Extra Parameters on Unraid |
|---|---|---|
| `pikkonmg/laya-system-one:cpu` | Any CPU | Empty |
| `pikkonmg/laya-system-one:nvidia` | NVIDIA GPU, driver 560 or newer | `--runtime=nvidia` |

Each release also gets a fixed tag, for example `0.3.20-cpu`.

## How it updates

`.github/workflows/build.yml` runs every day. When Laya has a release that
Docker Hub does not have yet, it builds both tags, runs `smoke_test.sh`, and
pushes them. A push to `main` or a manual run rebuilds the latest release.

The repository needs two secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`: a Docker Hub personal access token with write access

## Build on your own computer

```bash
git clone https://github.com/NandhaKishorM/laya upstream
docker build --build-arg TARGET=cpu --build-context laya=upstream -t pikkonmg/laya-system-one:cpu .
./smoke_test.sh pikkonmg/laya-system-one:cpu cpu
```

Use `TARGET=nvidia` for the NVIDIA image.

## Files

| File | Job |
|---|---|
| `Dockerfile` | Python 3.11, PyTorch 2.14 for the target, Laya server |
| `start.sh` | Sets the device, fixes `/data` ownership, checks the GPU, drops to `PUID:PGID` |
| `smoke_test.sh` | Checks the image without a GPU or model download |
