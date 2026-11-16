#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
bash test_check_plan.sh
bash test_pipeline_upload.sh
bash test_resolve_ids.sh
bash test_check_shelf.sh
bash test_apply.sh
bash test_readback.sh
bash test_system_meta.sh
bash test_ocr.sh
bash test_skill_doc.sh
