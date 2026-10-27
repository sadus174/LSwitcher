#!/usr/bin/env python3
from pathlib import Path
import sys

application = Path(sys.argv[1])
size = sum(p.stat().st_size for p in application.rglob('*') if p.is_file())
baseline = 2_687_792  # Published 0.2.0 application; no private benchmark files required.
print('Application bytes:',size,'baseline:',baseline,'difference:',size-baseline)
if size > baseline:
    raise SystemExit('Size budget exceeded: application must not grow compared with 0.2.0')
