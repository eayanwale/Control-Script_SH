#!/bin/bash

#Function declaration
SCP()
{
	if ( ! ping -q -c 1 -W 3 "${DST_SERV}" )
	then
		echo "Server ${DST_SERV} cannot be reached!"
		exit 1
	else
		echo "SERVER IS REACHABLE. COPYING FILES.."
	fi

   #-check server type
	#-assuming this script only copies to STACKCLOUDSERVER
   if [[ ${DST_SERV} == *"amazon"* || ${DST_SERV} == *"ec2"* || ${DST_SERV} == *"aws"* ]]
   then
         echo "${DST_SERV} is a CLOUD server..."
         #-check if .pem file exists
         if [[ ! -f ${PEM_KEY} ]]
         then
            echo "Private key not found. Aborting."
            exit 1
         fi
			echo
         echo "Copying ${SRC} to ${DST_USER}@${DST_SERV} at ${DST_PATH}"
         scp -r -i ${PEM_KEY} "${SRC}" "${DST_USER}"@"${DST_SERV}":"${DST_PATH}"
			ON_PREM_EX=$?
			if [ ${ON_PREM_EX} -ne 0 ]
			then
            echo "Secure copy Skipped One or More Files! !"
				mailx -s "WARNING: [${RUNNER}] Secure Copy Skip Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Secure Copy of ${SRC} to ${DST_USER}@${DST_SERV} at path: ${DST_PATH} skipped some files!
EOF
         else
            echo "Secure copy SUCCESSFUL!"
         fi
   else
         echo "${DST_SERV} is an ON PREM server..."
    
         echo "Copying ${SRC} to ${DST_USER}@${DST_SERV} at ${DST_PATH}"
         if ! scp -r -o HostKeyAlgorithms=+ssh-rsa "${SRC}" "${DST_USER}"@"${DST_SERV}":"${DST_PATH}"
			then
             echo "Secure copy FAILED!"
            mailx -s "WARNING: [${RUNNER}] Secure Copy Failure Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Secure Copy of ${SRC} to ${DST_USER}@${DST_SERV} at path: ${DST_PATH} FAILED!
EOF
         else
             echo "Secure copy SUCCESSFUL!"
         fi
   fi
}

BACKUP_F_D()
{
	BACKUP_DIR=${PRACTICE_DIR}/backup/${RUNNER}/$TS

   echo "Creating backup directory ${BACKUP_DIR}..."
   mkdir -p ${BACKUP_DIR}
   mkdir -p ${BACKUP_DIR}/backup_dir
   mkdir -p ${BACKUP_DIR}/backup_file

	#Copy logic
   if [[ -d ${SRC} ]]
   then
      echo "${SRC} is a directory."
      echo "Copying the DIRECTORY to specified backup location ${BACKUP_DIR}..."
      cp -r "${SRC}" "${BACKUP_DIR}/backup_dir"
      if [ $? -ne 0 ]
      then
         echo "Directory copy FAILED!"
         mailx -s "WARNING: [${RUNNER}] File/Directory Copy Failure Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
File/Directory  Copy of ${SRC} to ${BACKUP_DIR}/backup_dir FAILED!
EOF
      else
         echo "Directory copy SUCCESSFUL!"
      fi

   elif [[ -f ${SRC} ]]
   then
      echo "${SRC} is a file."
      echo "Copying the FILE to specified backup location ${BACKUP_DIR}..."
      cp "${SRC}" "${BACKUP_DIR}/backup_file"
      if [ $? -ne 0 ]
      then
         echo "File copy FAILED!"
         mailx -s "WARNING: [${RUNNER}] File/Directory Copy Failure Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
File/Directory  Copy of ${SRC} to ${BACKUP_DIR}/backup_file FAILED!
EOF
      else
         echo "File copy SUCCESSFUL!"
      fi
   else
      echo "${SRC} does not exist. Please re-run the script."
      exit 1
   fi
   echo

	#validate
	echo "Showing ${SRC} in specific backup directory:"
	if [[ -f ${SRC} ]] 
	then
		echo "${BACKUP_DIR}/backup_file :::"
		ls -ltr ${BACKUP_DIR}/backup_file
	else
		echo "${BACKUP_DIR}/backup_dir :::"
		ls -ltr ${BACKUP_DIR}/backup_dir
	fi

	echo "Showing timestamped backup: "
	ls -ltr ${PRACTICE_DIR}/backup/${RUNNER}
}

DISK_UTILIZATION()
{
	#disks mounted on this server
	DSKS="/u01 /u02 /u03 /u04 /u05 /backup"
	
	for disk in ${DSKS}
	do
		#-check if disk is mounted
		if ! df -h | grep "${disk}"
		then
   		echo "Disk(s) are not mounted!"
   		exit 1
		fi

		disk_check=$(df -h | grep "${disk}" | awk '{print $4}' | sed 's/%//g')

		echo "Checking ${disk} : ${disk_check}% used"
		echo	

		if (( disk_check > THRESHOLD ))
		then
			echo "WARNING: ${disk} utilization is ${disk_check}% (threshold: ${THRESHOLD}%)"
			echo "Sending alert to DevOps distro...\n"
			mail -s "Alert: [${RUNNER}] Disk Utilization Exceeded!" stackcloud15@mkitconsulting.net <<EOF
-------ALERT-------
RUNNER: ${RUNNER}
Disk Utilization on ${disk} is ${disk_check}
${disk} utilization has exceeded threshold: ${THRESHOLD}%
EOF
			if [ $? -ne 0 ]
			then
				echo "Failed to send email."
         	mailx -s "WARNING: [${RUNNER}] An Email failed to send" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
An email for Disk Utilization check failed to send.
EOF
				exit 1
			fi
		fi
	done
}

DATABASE_BACKUP() 
{
   #-database status	
	local TS=$(date "+%m_%d_%Y_%H_%M_%S")
	ENV_FILE="/home/oracle/scripts/oracle_env_${DB_NAME}.sh"
   #-settiing database environment variable dynamically
	if [[ ! -f ${ENV_FILE} ]] 
	then
		echo "Environment file not found. Stopping."
		exit 1
	fi
   source ${ENV_FILE}

	DATA_PUMP="/backup/AWSJAN26/DATAPUMP"
   PARFILE="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/expdp_${SCHEMA}_${RUNNER}_${TS}.par"
   SCHEMALIST="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/schemas.lst"

	#-boolean check
	if ( ps -ef | grep pmon | grep ${DB_NAME} )
	then
		echo "The ${DB_NAME} database instance is up and running!"
	else
		echo "THE ${DB_NAME} DATABASE IS DOWN!"
		exit 1
	fi
	echo

	DBCHECKLOG="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/dbcheck.log"
	#-get database open status
	sqlplus ${DB_USER}/${DB_PASS} <<EOF > ${DBCHECKLOG}
set echo on feedback on term on pagesize 0
select status from v\$instance;
EOF

	#-checking file for open status
	if ( grep "OPEN" ${DBCHECKLOG} )
	then
		echo "The database is open for backup."
	else
		echo "The database is not open. Backup cannot occur."
		exit 1
	fi
	echo

   sqlplus -s ${DB_USER}/${DB_PASS} << LSTEOF > ${SCHEMALIST}
set echo off feedback off term off pagesize 0
${QUERY}
exit
LSTEOF

	echo "---Schema file contents---"
	cat ${SCHEMALIST}
	echo "--------------------------"

   SCHEMA_COUNT=$(wc -l < ${SCHEMALIST})
<<comment
   if [ ${SCHEMA_COUNT} -gt 1 ]
   then
      echo "Schema list detected: ${SCHEMA_COUNT} matches found for ${SCHEMA}"
   else
      echo "Single schema detected: ${SCHEMA}"
   fi
comment

   PROMPT "Continue with backup? (y/n) " INPUT </dev/tty
   if [[ ${INPUT^^} == 'Y' ]]
   then
      echo "Proceeding with backup..."
   else
      echo "Backup canceled."
      exit 1
   fi

   count=1
   #-loop each schema in list
   while read lst_schema
   do
      echo "Processing for schema: ${lst_schema}"

   	EXPDP_LOG="expdp_${lst_schema}_${RUNNER}_${TS}.log"
   	EXPDP_LOG_PATH=${DATA_PUMP}/${DB_NAME}/${EXPDP_LOG}
	   DUMP_FILE="expdp_${lst_schema}_${RUNNER}_${TS}.dmp"
   	DUMP_PATH=${DATA_PUMP}/${DB_NAME}/${DUMP_FILE}

		#-creating backup config file
		echo "userid=${DB_USER}/${DB_PASS}" > ${PARFILE}
		echo "schemas=${lst_schema}" >> ${PARFILE}
		echo "dumpfile=${DUMP_FILE}" >> ${PARFILE}
		echo "logfile=${EXPDP_LOG}" >> ${PARFILE}
		echo "directory=${DIRECTORY}" >> ${PARFILE}
		
		expdp parfile=${PARFILE}
		if [ $? -eq 3 ] 
		then
			echo "expdp FAILED"
			mailx -s "WARNING: [${RUNNER}] Database Backup Failure Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Database backup of ${lst_schema} from ${DB_NAME} into ${DUMP_FILE} failed!
EOF
			exit 1
		else
			echo "expdp SUCCEEDED"
		mailx -s "SUCCESS: [${RUNNER}] Database Backup Success Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Database backup of ${lst_schema} from ${DB_NAME} into ${DUMP_FILE} succeeded!
EOF
		fi
		echo

		#-check log file for success
		if ( grep -q "successfully completed" "${EXPDP_LOG_PATH}" )
		then
			echo "Backup completed successfully."
		elif ( grep -q "completed with" "${EXPDP_LOG_PATH}" )
		then
			echo "Backup completed, with errors."
		else
			echo "Backup failed. Check log: ${EXPDP_LOG_PATH}"
			exit 1
		fi
		echo

		#-archive backup using gzip
		echo
		echo "Archiving backups..."
		cd ${DATA_PUMP}/${DB_NAME}
		tar -czvf ${DATA_PUMP}/${DB_NAME}/expdp_${lst_schema}_${RUNNER}_${TS}.tar ${DUMP_FILE} ${EXPDP_LOG} --remove-files
		TAR_EX=$?
		if [ ${TAR_EX} -ne 0 ]
		then
			echo "Failed with exit code: ${TAR_EX}"
			echo "Unable to archive this backup. Check logs: ${LOG_FILE}"
			mailx -s "WARNING: [${RUNNER}] EXPDP Dump Archive Failure Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Archiving of ${DUMP_FILE} has failed for the database backup of ${lst_schema} to ${DB_NAME}
EOF
			exit 1
		else
			echo "Successfully zipped archived backup."
		fi
		tar -tvf ${DATA_PUMP}/${DB_NAME}/expdp_${lst_schema}_${RUNNER}_${TS}.tar

      LAST_TAR_FILE="expdp_${lst_schema}_${RUNNER}_${TS}.tar"
      LAST_DUMP_FILE="expdp_${lst_schema}_${RUNNER}_${TS}.dmp"

		local MTIME="+2"
		local FILE_PATH="${DATA_PUMP}/${DB_NAME}"
		local FILES="${lst_schema}_${RUNNER}"
		CLEANUP ${MTIME} ${FILE_PATH} ${FILES}

		if [ ${count} -lt ${SCHEMA_COUNT} ]
		then
			echo "      ----------------Completed ${count} schema export(s)---------------      "
         PROMPT "Schema ${lst_schema} export complete. Would you like to continue? (y/n) " RESPONSE </dev/tty
			if [[ ${RESPONSE^^} == 'Y' ]]
			then
				echo "Continuing with backup..."
			else
				echo "Future backups canceled."
				break
			fi
		fi

		(( count ++ ))

	done < ${SCHEMALIST}
}

DATABASE_IMPORT()
{
	local TS=$(date "+%m_%d_%Y_%H_%M_%S")
	DATA_PUMP="/backup/AWSJAN26/DATAPUMP"

	#-extract tar file
	#DUMP_FILE=$(echo ${TAR_FILE} | sed 's/.tar/.dmp/g')
	echo "Extracting ${DUMP_FILE} from ${TAR_FILE}"
	cd ${DATA_PUMP}/${SRC_DB}
	if ( ! tar -xzvf ${DATA_PUMP}/${SRC_DB}/${TAR_FILE} -C ${DATA_PUMP}/${DEST_DB} ${DUMP_FILE} )
	then
		echo "Unable to extract files!"
		mailx -s "WARNING: [${RUNNER}] EXPDP Dump Extract Failure Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Extraction of ${DUMP_FILE} has failed for the database import of ${SCHEMA} to ${DB_NAME}
EOF
		exit 1
	else
		echo "Successfully extracted dump file."
		#ls -ltr *${RUNNER}* ${DATA_PUMP}/${DEST_DB} 
		echo
	fi

	#-check if database is present on server
	if ( ! grep ${DEST_DB} /etc/oratab )
	then
   	echo "The ${DEST_DB} database does not exist on this server."
   	exit 1
	fi

	ENV_FILE="/home/oracle/scripts/oracle_env_${DEST_DB}.sh"
	#-check if database environment file exists
	if [[ ! -f ${ENV_FILE} ]]
	then
		echo "Environment not found. Exiting..."		
		exit 1
	fi
	source ${ENV_FILE}

	#-check if instance is running
	if ( ps -ef | grep pmon | grep ${DEST_DB} )	
	then
		echo "The ${DEST_DB} database instance is up and running."
	else
		echo "THE ${DEST_DB} DATABASE IS DOWN!!!"
		exit 1
	fi

	DBCHECKLOG="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/dbcheck.log"
	#-check open status
	sqlplus ${DB_USER}/${DB_PASS} << EOF > ${DBCHECKLOG}
set echo on feedback on term on pagesize 0
select status from v\$instance;
exit
EOF
	#-log open status
	if ( grep "OPEN" ${DBCHECKLOG} )
	then
		echo "The database is open for import."
	else
		echo "The database is not open. Import cannot occur."
		exit 1
	fi
	echo

	SCHEMALIST="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/schemas.lst"

   echo "---Schema file contents---"
   cat ${SCHEMALIST}
   echo "--------------------------"

	SCHEMA_COUNT=$(wc -l < ${SCHEMALIST})
<<comment
	if [ ${SCHEMA_COUNT} -gt 1 ] 
	then
		echo "Schema list detected: ${SCHEMA_COUNT} matches found for ${SCHEMA}"
	else
		echo "Single schema detected: ${SCHEMA}"
	fi
comment

	PROMPT "Continue with import? (y/n)" INPUT </dev/tty
	if [[ ${INPUT^^} == 'Y' ]]
	then
		echo "Proceeding with import..."
	else
		echo "Import canceled."
		exit 1
	fi

	count=1
	#-loop each schema in list
	while read lst_schema
	do 
		echo "Processing for schema: ${lst_schema}"

		PARFILE="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/impdp_${lst_schema}_${RUNNER}_${TS}.par"
		IMPDP_LOG="impdp_${lst_schema}_${RUNNER}_${TS}.log"
		IMPDP_LOG_PATH=${DATA_PUMP}/${DEST_DB}/${IMPDP_LOG}

		echo "userid=${DB_USER}/${DB_PASS}" > ${PARFILE}
		echo "schemas=${lst_schema}" >> ${PARFILE}
		echo "remap_schema=${lst_schema}:${lst_schema}_${RUNNER}" >> ${PARFILE}
		echo "dumpfile=${DUMP_FILE}" >> ${PARFILE}
		echo "logfile=${IMPDP_LOG}" >> ${PARFILE}
		echo "table_exists_action=replace" >> ${PARFILE}
		echo "directory=${DIRECTORY}" >> ${PARFILE}

		impdp parfile=${PARFILE}
		if (( $? == 0 || $? == 5 ))
		then
			echo "impdp succeeded or completed with warnings. Check log: ${IMPDP_LOG_PATH}"
         mailx -s "WARNING: [${RUNNER}] Database Import Completed With Warnings" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Database import of ${SCHEMA} from ${SRC_DB} : [${DUMP_FILE}] into ${SCHEMA}_${RUNNER} in ${DEST_DB} completed with warnings.
EOF
		else
			echo "impdp FAILED"
         mailx -s "WARNING: [${RUNNER}] Database Import Failure Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Database import of ${SCHEMA} from ${SRC_DB} : [${DUMP_FILE}] into ${SCHEMA}_${RUNNER} in ${DEST_DB} has failed
EOF
         exit 1
		fi

		#-check log file for success
		if ( grep "successfully completed" ${IMPDP_LOG_PATH} )
		then
			echo "The import was SUCCESSFUL!"
		elif ( grep "completed with" ${IMPDP_LOG_PATH} )
		then
			echo "The import completed with errors. See log: ${IMPDP_LOG_PATH}"
		else
			echo "The import FAILED!"
			echo "Check logs: ${IMPDP_LOG_PATH}"
			exit 1
		fi
		echo

		SCHEMACHECKLOG="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/schemacheck.log"
		#-get imported schema
		sqlplus ${DB_USER}/${DB_PASS} << SCHEMAEOF > ${SCHEMACHECKLOG}
select username from dba_users where username like '%${lst_schema}_${RUNNER}%';
exit
SCHEMAEOF

		echo "---------#####----------"
		if grep -q "${lst_schema}_${RUNNER}" "${SCHEMACHECKLOG}"
		then
			echo "Found imported schema: ${lst_schema} in ${DEST_DB} as ${lst_schema}_${RUNNER}"
		else
			echo "Cannot find the exported schema."
			exit 1
		fi
		echo "---------#####----------"

      if [ ${count} -lt ${SCHEMA_COUNT} ]
      then
         echo "      ----------------Completed ${count} schema export(s)---------------      "
         PROMPT "Schema ${lst_schema} import complete. Would you like to continue? (y/n) " RESPONSE </dev/tty
         if [[ ${RESPONSE^^} == 'Y' ]]
         then
            echo "Continuing with import..."
         else
            echo "Future imports canceled."
            exit 1
         fi
      fi

		(( count ++ ))

	done < ${SCHEMALIST}
}

LOCAL_MIGRATION()
{
	local TS=$(date "+%m_%d_%Y_%H_%M_%S")

<<comment
	#check for added security
	if [[ ${SRC_DB} == ${DEST_DB} ]]
	then
   	echo "The source database cannot be the same as the destination database!"
   	exit 1
	fi
comment

	DB_NAME=${SRC_DB}
	#exporting databse. calling database backup function
	echo "Exporting the ${SRC_DB} database..."

	DATABASE_BACKUP "${RUNNER}" "${SRC_DB}" "${DIRECTORY}" "${QUERY}"

	TAR_FILE=${LAST_TAR_FILE}
	DUMP_FILE=${LAST_DUMP_FILE}

	echo "----------------###---------------"
	echo "Export complete. Please check command-line for errors."
	#confirm before beginning import
	PROMPT "Proceed with import? " ANSWER </dev/tty
		if [[ ${ANSWER^^} == 'Y' ]]
		then
			echo
			#importing database schema
			echo "Importing into the ${DEST_DB} database..."
			DATABASE_IMPORT "${SRC_DB}" "${DEST_DB}" "${RUNNER}" "${DIRECTORY}" "${TAR_FILE}" "${DUMP_FILE}" "${QUERY}"
			echo "Import complete!"
		else
			echo "Import canceled."
			break
		fi
	echo
	echo "---- MIGRATION COMPLETE ----"
}

CLEANUP()
{
   cd ${FILE_PATH}

   count_before=0
   count_after=0

   PROMPT "Are you sure you want to delete ${FILES} files ? " ANSWER </dev/tty
   if [[ ${ANSWER^^} == 'Y' ]]
   then
      echo "Cleaning up ${FILES} from ${FILE_PATH}..."
      for file in "${FILES}"
      do
         count=$(find . -maxdepth 1 -name "*${file}*" -mtime ${MTIME} -exec ls {} \; | wc -l)
         count_before=$(( count_before + count ))

         if ( ! find . -maxdepth 1 -name "*${file}*" -mtime ${MTIME} -exec rm -rf {} \; )
         then
            echo "Exit code: $?. Cleanup failed for ${file}"
            mailx -s "WARNING: [${RUNNER}] Cleanup Failure Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Clean up of ${file} from ${FILE_PATH} has failed!
EOF
            exit 1
         fi

         count=$(find . -maxdepth 1 -name "*${file}*" -mtime ${MTIME} -exec ls {} \; | wc -l)
         count_after=$(( count_after + count ))
      done

      echo "Number of matches in ${FILE_PATH} BEFORE cleanup: ${count_before}"
      echo "Number of matches in ${FILE_PATH} AFTER cleanup: ${count_after}"
   else
      echo "Cleanup canceled."
      mailx -s "WARNING: [${RUNNER}] Cleanup Canceled Alert" stackcloud15@mkitconsulting.net << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Clean up of ${file} from ${FILE_PATH} was initiated then canceled by ${RUNNER}!
EOF
      break
   fi
}

PROMPT()
{
	local answer=$2
	eval "${answer}=Y"
}

#variable declarations
SCRIPT_FUNC=$1
TS=$(date "+%m_%d_%Y_%H_%M_%S")

PRACTICE_DIR="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH"

#AUTO_CONFIRM=true

functions="scp backup_f_d disk_util database_backup database_import local_migration cleanup quit"
if [ $# -eq 0 ]
then

	#PS3 function check
	echo "Invalid or no function"
	echo "Function list: "
	PS3="Select a function: "

	select function in ${functions}
	do
		break
	done
else
	function=${SCRIPT_FUNC}
fi	

#Case statements: function declaration
case ${function} in
scp)
#Utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 6 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <SRC> <DST_USER> <DST SERVER> <DST PATH> <RUNNER>"
		echo "e.g script_name file1.txt oracle onprem.stack-clixx.com home/oracle/file1.txt ENOCH"
		echo

		read -p "Do you need help running this script? :" ANSWER
		if [[ ${ANSWER^^} == 'Y' ]]
		then
			echo "You have opted for help..."
			read -p "Enter the source file/directory: " SRC
			read -p "Enter the destination user name: " DST_USER
			read -p "Enter the destination server name: " DST_SERV
			read -p "Enter the destination path: " DST_PATH
			read -p "Who is running this script: " RUNNER

			echo "Calling ${SCRIPT_FUNC} function..."
			echo "..."
			SCP ${SRC} ${DST_USER} ${DST_SERV} ${DST_PATH} ${RUNNER}
		else
			exit 1
		fi
	else
		SRC=$2
		DST_USER=$3
		DST_SERV=$4
		DST_PATH=$5
		RUNNER=$6
		#call function
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		SCP ${SRC} ${DST_USER} ${DST_SERV} ${DST_PATH} ${RUNNER}
	fi
	echo
	;;
backup_f_d)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# != 3 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <SRC> <RUNNER>"
		echo "e.g script_name home/oracle/file.txt backup"
		echo

		read -p "Do you need help running this script? :" ANSWER
		if [[ ${ANSWER^^} == 'Y' ]]
		then
			echo "You have opted for help..."
			read -p "Enter the source file: " SRC
			read -p "Enter the runner name: " RUNNER

			echo "Calling ${SCRIPT_FUNC} function..."
			echo "..."
			BACKUP_F_D ${SRC} ${RUNNER}
		else
			exit 1
		fi
	else
		SRC=$2
		RUNNER=$3
		#call function BACKUP_F_D
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		BACKUP_F_D ${SRC} ${RUNNER}
	fi
	echo
	;;
disk_util)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 3 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <THRESHOLD> <RUNNER>"
		echo "e.g script_name 70 enoch"
		echo

		read -p "Do you need help running this script? :" ANSWER
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "Enter threshold value " THRESHOLD
				read -p "Who is running this script: " RUNNER

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				DISK_UTILIZATION ${THRESHOLD} ${RUNNER}
			else
				exit 1
			fi
	else
		THRESHOLD=$2
		#call function BACKUP_F_D
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		DISK_UTILIZATION ${THRESHOLD} ${RUNNER}
	fi
	echo
	;;
database_backup)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 5 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <RUNNER> <SCHEMA> <DEST_DB> <DIRECTORY>"
		echo "e.g database_backup ENOCH STACK_TEMP APEXDB DATA_PUMP_DIR"
		echo

		read -p "Do you need help running this script? :" ANSWER
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "Who is running this script? " RUNNER
				#read -p "What is the schema name? " SCHEMA
				read -p "What is the database name? " DB_NAME
				read -p "What is the firectory name? " DIRECTORY
				read -p "Enter the SQL query contained in double-quotes:  " QUERY

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				DATABASE_BACKUP ${RUNNER} ${DB_NAME} ${DIRECTORY} ${QUERY}
			else
				exit 1
			fi
	else
		RUNNER=$2
		#SCHEMA=$3
		DB_NAME=$3
		DIRECTORY=$4
		QUERY="$5"
		#Call function
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		DATABASE_BACKUP ${RUNNER} ${SCHEMA} ${DB_NAME} ${DIRECTORY} ${QUERY}
	fi
	echo
	;;
database_import)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 8 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <SRC_DB> <DB_NAME> <RUNNER> <SCHEMA> <DIRECTORY> <TAR_FILE> <DUMP_FILE>"
		echo "e.g database_import APEXDB ENOCH STACK_TEMP DATA_PUMP_DIR enoch_backup.tar enoch_backup.dmp"
		echo

		read -p "Do you need help running this script? " ANSWER
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "What is the source database? " SRC_DB
				read -p "What is the destination database? " DEST_DB
				read -p "Who is running this script? " RUNNER
				#read -p "What is the schema name? " SCHEMA
				read -p "What is the directory name? " DIRECTORY
				read -p "What is the tar file? " TAR_FILE
				read -p "What is the dump file? " DUMP_FILE
				read -p "Enter the SQL query. Please put in quotes: " QUERY

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				DATABASE_IMPORT ${SRC_DB} ${DEST_DB} ${RUNNER} ${DIRECTORY} ${TAR_FILE} ${DUMP_FILE} "${QUERY}"
			else
				exit 1
			fi
	else
		SRC_DB=$2
		DEST_DB=$3
		RUNNER=$4
		#SCHEMA=$5
		DIRECTORY=$5
		TAR_FILE=$6
		DUMP_FILE=$7
		QUERY="$8"
		#Call function
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		DATABASE_IMPORT ${SRC_DB} ${DEST_DB} ${RUNNER} ${SCHEMA} ${DIRECTORY} ${TAR_FILE} ${DUMP_FILE} "${QUERY}"
	fi
	echo
	;;
local_migration)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 6 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <SRC_DB> <DEST_DB> <RUNNER> <SCHEMA> <DIRECTORY>"
		echo "e.g database_import APEXDB ENOCH STACK_TEMP DATA_PUMP_DIR"
		echo

		read -p "Do you need help running this script? " ANSWER
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "What is the source database? " SRC_DB
				read -p "What is the destination database? " DEST_DB
				read -p "Who is running this script? " RUNNER
				#read -p "What is the source schema name? " SCHEMA
				read -p "What is the directory name? " DIRECTORY
				read -p "What is the SQL query contained in double-quotes: " QUERY

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				LOCAL_MIGRATION ${SRC_DB} ${DEST_DB} ${RUNNER} ${DIRECTORY} ${QUERY}
			else
				exit 1
			fi
	else
		SRC_DB=$2
		DEST_DB=$3
		DB_NAME=$3
		RUNNER=$4
		#SCHEMA=$5
		DIRECTORY=$5
		QUERY="$6"
		#Call function
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		LOCAL_MIGRATION ${SRC_DB} ${DEST_DB} ${RUNNER} ${SCHEMA} ${DIRECTORY} ${QUERY}
	fi
	echo
	;;
AWS)
	;;	
cleanup)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 5 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <MTIME> <FILE_PATH> <FILES>"
		echo "e.g cleanup +2 backup/AWSJAN26/DATAPUMP/APEXDB file1.txt"
		echo

		read -p "Do you need help running this script? :" ANSWER
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "Enter retention policy days (e.g. +1, -5, 6): " MTIME
				read -p "Enter file path: " FILE_PATH
				read -p "Enter a list or wildcard? " FILES
				read -p "Who is running this script: " RUNNER

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				CLEANUP ${MTIME} ${RESPONSE} ${FILES} ${RUNNER}
			else
				exit 1
			fi
	else
		MTIME=$2
		FILE_PATH=$3
		FILES=$4
		RUNNER=$5
		#Call function
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		CLEANUP ${MTIME} ${RESPONSE} ${FILES} ${RUNNER}
	fi
	echo
	;;
quit)
	echo "You have quit this process."
	exit 1
	;;
*)
	echo "Invalid function. Try again."
	functions="scp backup_f_d disk_util database_backup database_import local_migration cleanup quit"

	PS3="Please select a valid function: "
	select function in ${functions}
   do
		break		
   done
	"$0" ${function}
	;;
esac
