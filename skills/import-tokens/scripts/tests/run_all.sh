#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
python3 ../draft_tokens.py --self-test
