#!/bin/bash
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1
open .build/release/FileBox
