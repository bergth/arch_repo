#!/bin/bash

WORK_DIR="$HOME/archrepo/work"
DEST_DIR="$HOME/archrepo/dest"

test_and_mkdir()
{
    if [ ! -d "$WORK_DIR" ]; then
        mkdir -p "$WORK_DIR"

    fi

    if [ ! -d "$DEST_DIR" ]; then
        mkdir -p "$DEST_DIR"
    fi
}

