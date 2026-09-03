#!/bin/bash

npx --yes brighterscript --no-project --root-dir . --files manifest source/**/* components/**/* images/**/* --out-file dist/rokumio-client.zip --diagnostic-level error
