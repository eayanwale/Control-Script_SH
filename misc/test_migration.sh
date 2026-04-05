#!/bin/bash

# Credentials - set via environment variables before running:
#   export DB_USER=<oracle_username>
#   export DB_PASS=<oracle_password>
DB_USER="${DB_USER:?'Error: DB_USER environment variable not set'}"
DB_PASS="${DB_PASS:?'Error: DB_PASS environment variable not set'}"

SRC_DB=$1
DST_DB=$2
SCHEMA=$3
RUNNER=$4
DIRECTORY=$5

DATAPUMP="/backup/AWSJAN26/DATAPUMP"
SRC_DB_PATH="${DATAPUMP}/${SRC_DB}"

TS=$(date "+%m_%d_%Y_%H_%M_%S")

if [ $# -ne 5 ]
then
	echo "The number of command argumants in this script is $#"
	echo "You did not run this script properly."
	echo "Run like: <SRC_DB> <DST_DB> <SCHEMA_LIKE> <RUNNER> <DIRECTORY>"
	echo "Example:   APEXDB    SAMD    STACK_TEMP    ENOCH   DATA_PUMP_DIR"
	echo
	read -p "Do you need help? (y/n) " ANSWER
	if [[ ${ANSWER^^} == 'Y' ]]
	then
		echo "You have opted for help..."
		read -p "Enter source database: " SRC_DB
		read -p "Enter destination database: " DST_DB
		read -p "Enter Schema wildcard: " SCHEMA
		read -p "Who is running this script: " RUNNER
		read -p "Enter directory for data pump: " DIRECTORY
	else
		echo "Aborting..."
		exit 1
	fi
fi


#write stdout to log file
exec &> >(tee "test_migration.log")

<<comment
source "home/oracle/scripts/oracle_env_APEXDB.sh"

start_time=$(date '+%Y-%m-%d %H:%M:%S')
#log starttime and status in operations table
sqlplus ${DB_USER}/${DB_PASS} << EOF
insert into operations_test(START_TIME, OPERATION, STATUS, RUNNER)
values(to_timestamp('${start_time}', 'YYYY-MM-DD HH24:MI:SS'), 'LOCAL MIGRATION', 'IN PROGRESS', 'ENOCH');
commit;
select * from operations_test;
exit
EOF

get_op_id=$(sqlplus ${DB_USER}/${DB_PASS} << EOF
set feedback off term off echo off pagesize 0
select op_id from operations_test where START_TIME = '${start_time}';
exit
EOF
)
comment

SRC_ENV="/home/oracle/scripts/oracle_env_${SRC_DB}.sh"
if [[ -f ${SRC_ENV} ]]
then
	echo "Environment variable found. Sourcing..."
else
	echo "Environment variable not found. Aborting."
	exit 1
fi
echo
source ${SRC_ENV}

if ps -ef | grep [p]mon | grep ${SRC_DB} && ps -ef | grep [p]mon | grep ${DST_DB}
then
	echo "Database instances are running"
else
	echo "At least one database is DOWN"
	exit 1
fi
echo

DBCHECKLOG="./dbcheck.log"
sqlplus ${DB_USER}/${DB_PASS} << EOF > ${DBCHECKLOG}
set term on feedback on echo on pagesize 0
select status from v\$instance;
exit
EOF

if grep "OPEN" "${DBCHECKLOG}"
then
	echo "Database is open for backup."
else
	echo "Database is not open. Backup cannot occur."
	exit 1
fi
echo

SCHEMACHECKLOG="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/schemacheck.log"
sqlplus -s ${DB_USER}/${DB_PASS} << EOF > ${SCHEMACHECKLOG}
set term off feedback off echo off pagesize 0
select username from dba_users where username like '%${SCHEMA}%';
exit
EOF
SCHEMA_COUNT=$(wc -l < ${SCHEMACHECKLOG})


if [[ ! -f ${SCHEMACHECKLOG} || ! -s ${SCHEMACHECKLOG} ]]
then
	echo "${SCHEMACHECKLOG} is either empty of does not exist."
	echo "No schemas to export. Aborting..."
	exit 1
fi

echo
if [ ${SCHEMA_COUNT} -gt 1 ]
then
   echo "${SCHEMA_COUNT} schema matches found for ${SCHEMA}"
else
   echo "Found singular schema for ${SCHEMA}"
fi
cat ${SCHEMACHECKLOG}
echo "--------###---------"

FILES=()
count=1
while read schema_lst
do
	echo "Processing backup for ${schema_lst}"

	EXPDP_PAR="test_expdp_${schema_lst}_${RUNNER}.par"
	DUMPFILE="test_expdp_${schema_lst}_${RUNNER}.dmp"
	EXPDP_LOG="test_expdp_${schema_lst}_${RUNNER}.log"
	EXPDP_LOG_PATH="${DATAPUMP}/${SRC_DB}/${EXPDP_LOG}"

	echo "userid=${DB_USER}/${DB_PASS}" > ${EXPDP_PAR}
	echo "schemas=${schema_lst}" >> ${EXPDP_PAR}
	echo "dumpfile=${DUMPFILE}" >> ${EXPDP_PAR}
	echo "logfile=${EXPDP_LOG}" >> ${EXPDP_PAR}
	echo "directory=${DIRECTORY}" >> ${EXPDP_PAR}

	expdp parfile=${EXPDP_PAR}
	EX_RC=$?
	if (( ${EX_RC} == 0 || ${EX_RC} == 5 ))
	then
		echo "expdp completed with errors, or succeeded."
	else
		echo "expdp FAILED"
		exit 1
	fi

	if grep "successful" ${EXPDP_LOG_PATH}
	then
		echo "Export succeeded."
	elif grep "completed with" ${EXPDP_LOG_PATH}
	then
		echo "Export completed with errors."
	else
		echo "Export failed."
	fi

	FILES+=("${DUMPFILE}")
	FILES+=("${EXPDP_LOG}")

	echo "Exported ${count} schema. Continuing..."

	(( count ++ ))

done < ${SCHEMACHECKLOG}

echo
echo "Archiving all exports..."
echo "................."

IMP_SCHEMALOG="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/import_schema.log"
echo "${FILES[@]}" > ${IMP_SCHEMALOG}

EXPDP_TAR="test_expdp_${RUNNER}_${TS}.tar.gz"
cd "${DATAPUMP}/${SRC_DB}"
tar -czvf "${DATAPUMP}/${SRC_DB}/${EXPDP_TAR}" "${FILES[@]}" --remove-files
TAR_RC=$?
if [ ${TAR_RC} -ne 0 ] 
then
	echo "Archive failed."
	exit 1
else
	echo "Archive successful."
fi

echo "Displaying files in archive: "
tar -tvf "${DATAPUMP}/${SRC_DB}/${EXPDP_TAR}"
echo "---------Export complete------------"
echo "------------------------------------"
echo

echo "Grabbing dumpfile from archived backup."
cd "${DATAPUMP}/${SRC_DB}"
tar -xzvf "${EXPDP_TAR}" -C "${DATAPUMP}/${DST_DB}"
TAR_EX=$?
if [ ${TAR_EX} -ne 0 ]
then
	echo "Unzip failed"
	exit 1
else
	echo "Successfully unzipped files."
fi
cd "${DATAPUMP}/${SRC_DB}"

DST_ENV="/home/oracle/scripts/oracle_env_${DST_DB}.sh"
if [[ -f ${DST_ENV} ]]
then
	echo "Database environment found for ${DST_DB}"
else
	echo "Database environment not found. Aborting..."
	exit 1
fi
source ${DST_ENV}

sqlplus ${DB_USER}/${DB_PASS} << EOF > ${DBCHECKLOG}
set term on feedback on echo on pagesize 0
select status from v\$instance;
exit
EOF

if grep "OPEN" ${DBCHECKLOG}
then
	echo "The database is open for import."
else
	echo "The database is not open. Aborting..."
	exit 1
fi

echo
echo "Exported schemas matching ${SCHEMA} that are available for import:"
cat ${SCHEMACHECKLOG}
echo "-----------------------"

import_count=1
while read imp_schemas
do
	echo "Processing import for ${imp_schemas}"

	DUMPFILE="test_expdp_${imp_schemas}_${RUNNER}.dmp"
	IMPDP_PAR="impdp_${imp_schemas}_${RUNNER}_${TS}.par"
	IMPDP_LOG="impdp_${imp_schemas}_${RUNNER}_${TS}.log"
	IMPDP_LOG_PATH="${DATAPUMP}/${DST_DB}/${IMPDP_LOG}"

	echo "userid=${DB_USER}/${DB_PASS}" > ${IMPDP_PAR}
	echo "schemas=${imp_schemas}" >> ${IMPDP_PAR}
	echo "remap_schema=${imp_schemas}:${imp_schemas}_${RUNNER}" >> ${IMPDP_PAR}
	echo "dumpfile=${DUMPFILE}" >> ${IMPDP_PAR}
	echo "logfile=${IMPDP_LOG}" >> ${IMPDP_PAR}
	echo "table_exists_action=replace" >> ${IMPDP_PAR}
	echo "directory=${DIRECTORY}" >> ${IMPDP_PAR}

	impdp parfile=${IMPDP_PAR}
	IM_RC=$?
	if (( ${IM_RC} == 0 || ${IM_RC} == 5 ))
	then
		echo "Import completed with errors, or was successful."
	else
		echo "Import failed."
		exit 1
	fi

	if grep "successfully completed" ${IMPDP_LOG_PATH}
	then
		echo "Import successful."
	elif grep "completed with" ${IMPDP_LOG_PATH}
	then
		echo "Import completed with errors."
	else
		echo "Import failed."
		exit 1
	fi

	(( import_count ++ ))

done < ${SCHEMACHECKLOG}	

echo
echo
echo
echo "--------------------------------------"
echo "Migration completed. Please check logs."
echo "Please come again :)"
echo "--------------------------------------"


<<comment
source "/home/oracle/scripts/oracle_env_APEXDB.sh"

end_time=$(date '+%Y-%m-%d %H:%M:%S')
#log starttime and status in operations table
sqlplus ${DB_USER}/${DB_PASS} << EOF
update operations_test
set STATUS = 'COMPLETE'
set END_TIME = to_timestamp('${end_time}', 'YYYY-MM-DD HH24:MI:SS')
where op_id = ${operation_id};
commit;
select * from operations_test;
exit
EOF

comment






















