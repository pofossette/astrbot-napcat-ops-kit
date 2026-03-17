#!/usr/bin/env python3
from __future__ import annotations

import sys

from deploy_lib import DeployError, logs_cli


def main(argv: list[str] | None = None) -> int:
    try:
        return logs_cli(argv or sys.argv[1:])
    except DeployError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
