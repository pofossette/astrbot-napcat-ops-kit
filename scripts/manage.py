#!/usr/bin/env python3
from __future__ import annotations

import sys

from deploy_lib import DeployError, manage_loop, print_error


def main() -> int:
    try:
        manage_loop()
        return 0
    except (KeyboardInterrupt, EOFError):
        print()
        return 0
    except DeployError as exc:
        print_error(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
