#!/bin/bash

exec &> >(tee -a "script.log")
echo "I need this to log into a file"
