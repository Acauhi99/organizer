#!/bin/sh
set -e

if [ ! -e ".git" ]; then
  exit 0
fi

git config --local core.hooksPath .githooks
