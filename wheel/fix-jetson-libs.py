#!/usr/bin/env python3
"""Apply the recorded Jetson library fixes only to the new virtualenv."""
from pathlib import Path
import os
import sys

root = Path(os.environ.get('VLLM_WORK', '/mnt/ros_data/vllm29')) / 'venv'
if Path(sys.prefix).resolve() != root.resolve():
    raise SystemExit(f'Refusing to change libraries in {sys.prefix}')
sp = root / 'lib/python3.10/site-packages'
system = Path('/usr/local/cuda/targets/aarch64-linux/lib')

def link(source, destination):
    if not source.exists():
        raise RuntimeError(f'Missing required source: {source}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        if destination.resolve() == source.resolve():
            return
        destination.unlink()
    elif destination.exists():
        backup = destination.with_name(destination.name + '.pip-original')
        if backup.exists():
            raise RuntimeError(f'Backup already exists: {backup}')
        destination.rename(backup)
    destination.symlink_to(source)
    print(f'{destination} -> {source}', flush=True)

for relative in ['cublas/lib/libcublas.so.12', 'cublas/lib/libcublasLt.so.12',
                 'cublas/lib/libnvblas.so.12', 'cuda_nvrtc/lib/libnvrtc.so.12']:
    source = system / Path(relative).name
    if source.exists():
        link(source, sp / 'nvidia' / relative)
libs = list((sp / 'nvidia/cu12/lib').glob('libcudss*.so.0'))
if not libs:
    raise RuntimeError('cuDSS libraries were not installed')
for source in libs:
    link(source, sp / 'torch/lib' / source.name)
triton = sp / 'triton/backends/nvidia'
link(Path('/usr/local/cuda/include/cuda.h'), triton / 'include/cuda.h')
link(Path('/usr/local/cuda/bin/ptxas'), triton / 'bin/ptxas')
