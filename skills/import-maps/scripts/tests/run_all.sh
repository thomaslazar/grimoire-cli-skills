#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
bash test_publish_maps_check.sh
python3 ../publish_maps.py --self-test
python3 ../transparency.py --self-test
