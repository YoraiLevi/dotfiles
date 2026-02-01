#!/bin/bash

echo "Running test script..."

# check if cursor is installed
if ! command -v cursor &> /dev/null; then
    echo "Cursor could not be found"
    exit 1
fi

# check if code-insiders is installed
if ! command -v code-insiders &> /dev/null; then
    echo "Code Insiders could not be found"
    exit 1
fi