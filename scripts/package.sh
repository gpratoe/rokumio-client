#!/bin/bash

npx --yes brighterscript --no-project --root-dir . --files manifest source/**/* components/**/* images/**/* --out-file dist/stroku-native.zip --diagnostic-level error
