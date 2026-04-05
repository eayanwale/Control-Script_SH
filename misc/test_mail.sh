#!/bin/bash

# Credentials - set via environment variables before running:
#   export ALERT_EMAIL=<email_address>
ALERT_EMAIL="${ALERT_EMAIL:?'Error: ALERT_EMAIL environment variable not set'}"

echo "Mike is a great teacher" | mailx -s "STACKIT MESSAGE" email ${ALERT_EMAIL}
