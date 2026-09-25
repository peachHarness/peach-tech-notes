# qmd 플랫폼별 임베딩 운영 가이드

> qmd 2.5.x 기준. `peach-wiki`에서 INIT/INGEST 후 qmd embed를 실행할 때 OS와 GPU별로 선택할 기준을 정리한다.

---

## 핵심 원칙

- `qmd --index "$QMD_INDEX"`는 모든 명령에 반드시 붙인다.
- 대형 인덱스는 `update`와 `embed`를 분리한다.
- `embed`에는 `--max-docs-per-batch`와 `--max-batch-mb`를 붙여 메모리 피크를 낮춘다.
- Apple Silicon은 Metal 병렬도 2부터 시작한다.
- Windows CUDA/Vulkan은 병렬도 1부터 시작한다.
- GPU가 불안정하면 CPU-only로 낮추고 `--no-rerank`로 검색 비용을 줄인다.
- embed 직후 `doctor`로 벡터 정합성을 검증한다. "differ"면 `embed --force`로 전체 재구축한다.

공통 대형 인덱스 패턴:

```bash
qmd --index "$QMD_INDEX" update
qmd --index "$QMD_INDEX" embed --max-docs-per-batch 32 --max-batch-mb 32
# 정합성 검증 — embed 성공 ≠ 전체 벡터 정합. "differ"면 embed --force로 마무리
qmd --index "$QMD_INDEX" doctor | grep -i "vector sample"
```

### doctor 진단 해석

`qmd doctor`는 런타임·sqlite-vec·GPU 백엔드·임베딩 벡터 정합성을 점검한다. 임베딩 이상 진단의 핵심 도구다.

| doctor 출력 | 의미 | 조치 |
|------|------|------|
| `✓ device mode: metal` / `device probe: GPU metal` | GPU 가속 정상 동작 | 없음 |
| `✓ embedding vector sample: N reproduce stored vectors` | 저장 벡터가 현재 파이프라인에서 재현됨 (정합) | 없음 |
| `⚠ embedding vector sample: N/M differ` | 일반 embed는 변경분만 처리 → 파이프라인 변경분이 어긋남 | `qmd --index "$QMD_INDEX" embed --force` |

> **`ggml_metal_library_init_from_source: error compiling source` 메시지는 무해하다.** Metal 셰이더 소스 컴파일만 실패하고
> 사전컴파일 백엔드로 폴백할 뿐, 임베딩·검색은 GPU로 정상 수행된다. 메시지 직후에도 `doctor`가 `✓ device mode: metal`을
> 보고하면 정상이다(M5 실측 확인). 메시지 유무가 아니라 `doctor`의 device/vector 항목으로 판정한다.

---

## Apple Silicon

### 기본값

```bash
QMD_LLAMA_GPU=metal QMD_EMBED_PARALLELISM=2 \
qmd --index "$QMD_INDEX" embed --max-docs-per-batch 32 --max-batch-mb 32
```

| 옵션 | 의미 |
|------|------|
| `QMD_LLAMA_GPU=metal` | Apple GPU Metal backend 명시 |
| `QMD_EMBED_PARALLELISM=2` | embedding context 병렬도 2로 제한 |
| `--max-docs-per-batch 32` | 한 번에 처리할 문서 수 제한 |
| `--max-batch-mb 32` | 한 batch 메모리 크기 제한 |

### M4 / M4 Pro / M4 Max

- Metal backend를 기본으로 본다.
- Metal tensor API 비활성 로그가 있어도 pre-M5에서는 정상일 수 있다.
- CPU-only 대비 처리 시간, chunks/sec, CPU 점유율로 판단한다.

### M5

`ggml_metal_library_init_from_source: error compiling source` 메시지는 M5에서도 무해하다(위 doctor 해석 참조). 먼저 `doctor`로 `device mode: metal`이 정상인지 확인한다 — 정상이면 그대로 쓴다.

`doctor`가 실제로 GPU 미동작을 보고하거나 embed가 멈추는 등 **진짜 tensor API 장애**일 때만 tensor API 회피 옵션을 검증한다.

```bash
GGML_METAL_TENSOR_DISABLE=1 QMD_LLAMA_GPU=metal \
qmd --index "$QMD_INDEX" embed -f --max-docs-per-batch 32 --max-batch-mb 32
```

> `-f`(=`--force`)는 전 벡터를 삭제 후 재임베딩하는 옵션이다. 정합성 문제(`doctor`의 "differ") 또는 파이프라인 변경 시 사용한다.

### CPU-only 비교

```bash
QMD_FORCE_CPU=1 QMD_EMBED_PARALLELISM=2 \
qmd --index "$QMD_INDEX" embed -f --max-docs-per-batch 32 --max-batch-mb 32
```

성공 기준:

- `QMD Warning: no GPU acceleration` 경고가 사라진다.
- Metal 실행이 CPU-only 대비 2배 이상 빠르거나, 최소한 낮은 CPU 점유로 같은 처리량을 낸다.
- 대형 인덱스 실행 중 RAM/swap 압박이 과도하지 않다.

---

## Windows

Windows는 Apple Silicon의 Metal 경로를 쓰지 않는다. 먼저 qmd와 GPU runtime을 진단한다.

```powershell
node -v
npm -v
qmd --version
qmd --index peach-harness status
qmd --index peach-harness doctor
```

권장 기준:

- Node.js 22 이상
- qmd 2.5.2 이상
- `qmd doctor`에서 GPU/CPU runtime 진단 확인
- `qmd` 명령이 없으면 npm global prefix와 PATH 확인

### NVIDIA CUDA

```powershell
nvidia-smi
npx --no node-llama-cpp inspect gpu

$env:QMD_LLAMA_GPU = "cuda"
$env:QMD_EMBED_PARALLELISM = "1"
qmd --index peach-harness doctor
qmd --index peach-harness embed --max-docs-per-batch 32 --max-batch-mb 32
```

Windows CUDA는 안정성을 우선해 병렬도 1부터 시작한다. 드라이버와 CUDA runtime이 안정적이라고 확인된 뒤에만 2 이상을 실측한다.

```powershell
$env:QMD_EMBED_PARALLELISM = "2"
```

### AMD/Intel 또는 CUDA 불안정 환경

CUDA가 아니면 Vulkan을 먼저 검증한다.

```powershell
npx --no node-llama-cpp inspect gpu

$env:QMD_LLAMA_GPU = "vulkan"
$env:QMD_EMBED_PARALLELISM = "1"
qmd --index peach-harness doctor
qmd --index peach-harness embed --max-docs-per-batch 32 --max-batch-mb 32
```

Vulkan은 GPU 드라이버와 GPU 세대 의존성이 크다. 대형 embed는 병렬도 1부터 시작한다.

### CPU-only fallback

```powershell
$env:QMD_FORCE_CPU = "1"
qmd --index peach-harness doctor
qmd --index peach-harness embed --max-docs-per-batch 16 --max-batch-mb 16
```

검색도 느리면 rerank를 끈다.

```powershell
qmd --index peach-harness query "검색어" --no-gpu --no-rerank
```

---

## Windows 셸별 환경변수 문법

PowerShell:

```powershell
$env:QMD_LLAMA_GPU = "cuda"
qmd --index peach-harness embed
```

cmd:

```cmd
set QMD_LLAMA_GPU=cuda
qmd --index peach-harness embed
```

Git Bash / WSL bash:

```bash
QMD_LLAMA_GPU=cuda qmd --index peach-harness embed
```

---

## WSL2 기준

WSL2는 native Windows qmd와 별도 환경으로 본다.

- WSL 내부에 Linux용 Node/npm/qmd를 별도로 설치한다.
- Windows npm cache와 WSL npm cache는 분리된다.
- Windows 경로(`/mnt/c/...`)의 대형 repo는 파일 I/O가 느릴 수 있다.
- 대형 인덱스는 가능하면 WSL ext4 내부 경로에서 검증한다.
- NVIDIA CUDA on WSL은 Windows NVIDIA driver와 WSL 내부 CUDA runtime 조건을 별도 확인한다.

WSL bash 예시:

```bash
node -v
npm install -g @tobilu/qmd

export QMD_LLAMA_GPU=cuda
export QMD_EMBED_PARALLELISM=1
qmd --index peach-harness doctor
qmd --index peach-harness embed --max-docs-per-batch 32 --max-batch-mb 32
```

---

## 빠른 선택표

| 환경 | 우선 옵션 | 병렬도 | batch |
|------|-----------|--------|-------|
| Apple Silicon M4/M5 | `QMD_LLAMA_GPU=metal` | 2 | 32 docs / 32MB |
| Apple Silicon CPU 비교 | `QMD_FORCE_CPU=1` | 2 | 32 docs / 32MB |
| Windows NVIDIA | `QMD_LLAMA_GPU=cuda` | 1 | 32 docs / 32MB |
| Windows AMD/Intel | `QMD_LLAMA_GPU=vulkan` | 1 | 32 docs / 32MB |
| Windows CPU-only | `QMD_FORCE_CPU=1` 또는 `--no-gpu` | 1 | 16 docs / 16MB |
| WSL2 NVIDIA | `QMD_LLAMA_GPU=cuda` | 1 | 32 docs / 32MB |

---

## 참고 자료

- qmd README: https://github.com/tobi/qmd/blob/main/README.md
- qmd Releases: https://github.com/tobi/qmd/releases
- node-llama-cpp CUDA: https://node-llama-cpp.withcat.ai/guide/CUDA
- node-llama-cpp Vulkan: https://node-llama-cpp.withcat.ai/guide/Vulkan
- node-llama-cpp Metal: https://node-llama-cpp.withcat.ai/guide/Metal
- Microsoft WSL install 문서
- NVIDIA CUDA on WSL 사용자 가이드
