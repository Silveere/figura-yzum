#!/bin/sh
rm yzum.zip
git submodule update --init --recursive
find . -mindepth 1 -maxdepth 1 -not \( -name '*.xcf' -o -name '.*' -o -name '*.md' -o -name '*.sh' \) -exec apack yzum.zip '{}' +
