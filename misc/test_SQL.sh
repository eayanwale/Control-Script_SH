#!/bin/bash

# Credentials - set via environment variables before running:
#   export DB_USER=<oracle_username>
#   export DB_PASS=<oracle_password>
DB_USER="${DB_USER:?'Error: DB_USER environment variable not set'}"
DB_PASS="${DB_PASS:?'Error: DB_PASS environment variable not set'}"

source /home/oracle/scripts/oracle_env_SAMD.sh

sqlplus ${DB_USER}/${DB_PASS} << EOF 
spool /home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/schema_check.log
select username from dba_users where username like '%MIKE4%';

spool off
EOF

cat /home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/schema_check.log
if ( grep "STACK_TEMP_MIKE4" "/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/schema_check.log" )
then	
	echo "found schema and runner"
else
	echo "not found"
	exit 1
fi
