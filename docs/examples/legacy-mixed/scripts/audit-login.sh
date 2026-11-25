#!/usr/bin/env bash
set -eu

mkdir -p logs
printf '%s\n' "login:$1" >> logs/audit.log
