#!/usr/bin/env python3
from __future__ import annotations

import sys

from deploy_lib import DeployError, command_down


def main() -> int:
    try:
        command_down()
        return 0
    except DeployError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
