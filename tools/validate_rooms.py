#!/usr/bin/env python3
"""Backwards-compatible wrapper delegating to validate_world.py."""

from validate_world import main

if __name__ == "__main__":
    raise SystemExit(main())
