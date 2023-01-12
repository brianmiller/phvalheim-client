#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# generate the compat file
echo "10" > $SCRIPT_DIR/../debian/compat
