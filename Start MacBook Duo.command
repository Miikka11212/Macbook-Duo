#!/bin/bash
set -euo pipefail
if [[ ! -d '/Applications/MacBook Duo.app' ]]; then
    echo 'Please run scripts/install.sh from the project folder first.'
    exit 1
fi
open '/Applications/MacBook Duo.app'
