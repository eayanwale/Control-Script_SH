#!/bin/bash

ENV_SECRETS="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/.env_secrets.sh"
# Source env_cloud secrets file
if [[ -f ${ENV_SECRETS} ]]
then
   echo "Found cloud secrets file. Will use secrets if/when needed."
   source ${ENV_SECRETS}
else
   echo "Cannot find secrets. Exiting."
   exit 1
fi

#Function declaration
SCP()
{
   # Assign to env variables
   local pem_key=${PEM_KEY}
   local stack_email=${STACK_EMAIL}

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
         if [[ ! -f ${pem_key} ]]
         then
            echo "Private key not found. Aborting."
            exit 1
         fi
			echo
         echo "Copying ${SRC} to ${DST_USER}@${DST_SERV} at ${DST_PATH}"
         scp -r -i ${pem_key} "${SRC}" "${DST_USER}"@"${DST_SERV}":"${DST_PATH}"
			ON_PREM_EX=$?
			if [ ${ON_PREM_EX} -ne 0 ]
			then
            echo "Secure copy Skipped One or More Files! !"
				mailx -s "WARNING: [${RUNNER}] Secure Copy Skip Alert" ${stack_email} << EOF
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
            mailx -s "WARNING: [${RUNNER}] Secure Copy Failure Alert" ${stack_email} << EOF
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
   local DISKS=${BACKUP_DISK}
	local THRESHOLD="80"
	local stack_email=${STACK_EMAIL}
	local prac_dir=${PRACTICE_DIR}

   echo "Checking disk utilization..."
   echo "------------------"
   DISK_UTILIZATION "${DISKS}" "${THRESHOLD}" "${RUNNER}"
   if [ $? -ne 0 ]
   then
      echo "Disk check failed. Skipping backup."
      exit 1
   fi

	BACKUP_DIR=${prac_dir}/backup/${RUNNER}/$TS

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
         mailx -s "WARNING: [${RUNNER}] File/Directory Copy Failure Alert" ${stack_email} << EOF
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
         mailx -s "WARNING: [${RUNNER}] File/Directory Copy Failure Alert" ${stack_email} << EOF
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
	ls -ltr ${prac_dir}/backup/${RUNNER}
}

DISK_UTILIZATION()
{
	local stack_email=${STACK_EMAIL}

	for disk in ${DISKS}
	do
		#-check if disk is mounted
		if ! df -h | grep -q "${disk}"
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
			echo "Sending alert to DevOps distro..."
			mailx -s "Alert: [${RUNNER}] Disk Utilization Exceeded!" ${stack_email} <<EOF
-------ALERT-------
RUNNER: ${RUNNER}
Disk Utilization on ${disk} is ${disk_check}
${disk} utilization has exceeded threshold: ${THRESHOLD}%
EOF
			return 1
		fi
	done
}

DATABASE_BACKUP() 
{
	local THRESHOLD="80"
	local DISKS="/backup"
	local DATA_PUMP=${DB_DIR}
	local stack_email=${STACK_EMAIL}
	local prac_dir=${PRACTICE_DIR}
	local script_dir=${SCRIPT_DIR}
	local db_user=${ONPREM_DB_USER}
	local db_pass=${ONPREM_DB_PASS}
	echo "Checking disk utilization..."
	echo "------------------"	
	DISK_UTILIZATION "${DISKS}" "${THRESHOLD}" "${RUNNER}"		
	if [ $? -ne 0 ] 
	then
		echo "Disk check failed. Skipping backup."
		exit 1
	fi

   #-database status	
	ENV_FILE="${script_dir}/oracle_env_${DB_NAME}.sh"
   #-settiing database environment variable dynamically
	if [[ ! -f ${ENV_FILE} ]] 
	then
		echo "Environment file ${ENV_FILE} not found. Stopping."
		exit 1
	fi
   source ${ENV_FILE}

	SCHEMALIST="${prac_dir}/schemas.lst"

	#-boolean check
	if ( ps -ef | grep pmon | grep ${DB_NAME} )
	then
		echo "The ${DB_NAME} database instance is up and running!"
	else
		echo "THE ${DB_NAME} DATABASE IS DOWN!"
		exit 1
	fi
	echo

	DBCHECKLOG="${prac_dir}/dbcheck.log"
	#-get database open status
	sqlplus -s /@enoch_apexdb <<EOF > ${DBCHECKLOG}
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

   sqlplus -s /@enoch_apexdb << LSTEOF > ${SCHEMALIST}
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

	exp_tar="${prac_dir}/exp_tar.lst"
	exp_schemas="${prac_dir}/exp_schemas.lst"

	> ${exp_tar}
	> ${exp_schemas}

   count=1
   #-loop each schema in list
   while read lst_schema
   do
      echo "Processing for schema: ${lst_schema}"

		PARFILE="${prac_dir}/expdp_${lst_schema}_${RUNNER}_${TS}.par"
   	EXPDP_LOG="expdp_${lst_schema}_${RUNNER}_${TS}.log"
   	EXPDP_LOG_PATH=${DATA_PUMP}/${DB_NAME}/${EXPDP_LOG}
	   DUMP_FILE="expdp_${lst_schema}_${RUNNER}_${TS}.dmp"
   	DUMP_PATH=${DATA_PUMP}/${DB_NAME}/${DUMP_FILE}

		#-creating backup config file
		echo "userid=${db_user}/${db_pass}" > ${PARFILE}
		echo "schemas=${lst_schema}" >> ${PARFILE}
		echo "dumpfile=${DUMP_FILE}" >> ${PARFILE}
		echo "logfile=${EXPDP_LOG}" >> ${PARFILE}
		echo "directory=${DIRECTORY}" >> ${PARFILE}
		
		expdp parfile=${PARFILE}
		if [ $? -eq 3 ] 
		then
			echo "expdp FAILED"
			mailx -s "WARNING: [${RUNNER}] Database Backup Failure Alert" ${stack_email} << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Database backup of ${lst_schema} from ${DB_NAME} into ${DUMP_FILE} failed!
EOF
			exit 1
		else
			echo "expdp SUCCEEDED"
		mailx -s "SUCCESS: [${RUNNER}] Database Backup Success Alert" ${stack_email} << EOF
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
			mailx -s "WARNING: [${RUNNER}] EXPDP Dump Archive Failure Alert" ${stack_email} << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Archiving of ${DUMP_FILE} has failed for the database backup of ${lst_schema} to ${DB_NAME}
EOF
			exit 1
		else
			echo "Successfully zipped archived backup."
		fi
		tar -tvf ${DATA_PUMP}/${DB_NAME}/expdp_${lst_schema}_${RUNNER}_${TS}.tar
		
		echo "expdp_${lst_schema}_${RUNNER}_${TS}.tar" >> "${exp_tar}"

      TAR_FILE="expdp_${lst_schema}_${RUNNER}_${TS}.tar"
      DUMP_FILE="expdp_${lst_schema}_${RUNNER}_${TS}.dmp"

		local MTIME="+2"
		local FILE_PATH="${DATA_PUMP}/${DB_NAME}"
		local FILES="${lst_schema}_${RUNNER}"
		CLEANUP ${MTIME} ${FILE_PATH} ${FILES}

		(( count ++ ))

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
		
		echo "${lst_schema}" >> ${exp_schemas}

	done < ${SCHEMALIST}
}

DATABASE_IMPORT()
{
	local db_user=${ONPREM_DB_USER}
	local db_pass=${ONPREM_DB_PASS}
	local DATA_PUMP=${DB_DIR}
	local stack_email=${STACK_EMAIL}
	local prac_dir=${PRACTICE_DIR}
	local script_dir=${SCRIPT_DIR}

	exp_tar="${prac_dir}/exp_tar.lst"
	exp_schemas="${prac_dir}/exp_schemas.lst"

	#-check if database is present on server
	if ( ! grep ${DEST_DB} /etc/oratab )
	then
   	echo "The ${DEST_DB} database does not exist on this server."
   	exit 1
	fi

	ENV_FILE="${script_dir}/oracle_env_${DEST_DB}.sh"
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

	DBCHECKLOG="${prac_dir}/dbcheck.log"
	#-check open status
	sqlplus /@enoch_samd << EOF > ${DBCHECKLOG}
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

	SCHEMALIST="${prac_dir}/schemas.lst"

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

		TAR_FILE=$(grep "expdp_${lst_schema}" "${exp_tar}")
		DUMP_FILE=$(tar -tf "${DATA_PUMP}/${SRC_DB}/${TAR_FILE}" | grep "${lst_schema}.*\.dmp")

    	echo "Extracting from ${TAR_FILE}"
    	cd ${DATA_PUMP}/${SRC_DB}
    	if ( ! tar -xzvf ${DATA_PUMP}/${SRC_DB}/${TAR_FILE} -C ${DATA_PUMP}/${DEST_DB} ${DUMP_FILE} )
    	then
      	echo "Unable to extract files!"
      	mailx -s "WARNING: [${RUNNER}] EXPDP Dump Extract Failure Alert" ${stack_email} << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Extraction of ${TAR_FILE} has failed for the database import of ${lst_schema} to ${DEST_DB}
EOF
      	exit 1
    	else
      	echo "Successfully extracted dump file."
    	fi

		echo "Processing for schema: ${lst_schema}"

		PARFILE="${prac_dir}/impdp_${lst_schema}_${RUNNER}_${TS}.par"
		IMPDP_LOG="impdp_${lst_schema}_${RUNNER}_${TS}.log"
		IMPDP_LOG_PATH=${DATA_PUMP}/${DEST_DB}/${IMPDP_LOG}

		echo "userid=${db_user}/${db_pass}" > ${PARFILE}
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
         mailx -s "WARNING: [${RUNNER}] Database Import Completed With Warnings" ${stack_email} << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Database import of ${SCHEMA} from ${SRC_DB} : [${DUMP_FILE}] into ${SCHEMA}_${RUNNER} in ${DEST_DB} completed with warnings.
EOF
		else
			echo "impdp FAILED"
         mailx -s "WARNING: [${RUNNER}] Database Import Failure Alert" ${stack_email} << EOF
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

		SCHEMACHECKLOG="${prac_dir}/schemacheck.log"
		#-get imported schema
		sqlplus /@enoch_samd << SCHEMAEOF > ${SCHEMACHECKLOG}
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

      local MTIME="+1"
      local FILE_PATH="${DATA_PUMP}/${DEST_DB}"
      local FILES="${lst_schema}_${RUNNER}"
      CLEANUP ${MTIME} ${FILE_PATH} ${FILES}

		(( count ++ ))

	done < ${exp_schemas}
	echo
	echo "----- Import Successful -----"
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

	TAR_FILE=${TAR_FILE}
	DUMP_FILE=${DUMP_FILE}

	echo "----------------###---------------"
	echo "Export complete. Please check command-line for errors."
	#confirm before beginning import
	PROMPT "Proceed with import? " ANSWER </dev/tty
		if [[ ${ANSWER^^} == 'Y' ]]
		then
			echo
			#importing database schema
			echo "Importing into the ${DEST_DB} database..."
			DATABASE_IMPORT "${SRC_DB}" "${DEST_DB}" "${RUNNER}" "${DIRECTORY}" "${QUERY}"
			echo "Import complete!"
		else
			echo "Import canceled."
			break
		fi
	echo
	echo "---- MIGRATION COMPLETE ----"
}

CLOUD_MIGRATION()
{
	echo "------------ Starting Cloud Database Migration ---------------"
	echo
	
	# Initialize variables
	local script_dir=${SCRIPT_DIR}
	local cloud_env="${script_dir}/oracle_env_${DEST_DB}.sh"
	local datapump=${DB_DIR}
	local prac_dir=${PRACTICE_DIR}
	local temp_dir="${prac_dir}/tmp"
	local THRESHOLD=80
	local DEST_USER=${AWS_SERV_USER}
	local pem_key=${PEM_KEY}
	local stack_email=${STACK_EMAIL}

	echo
	echo "Backup starting for ${SRC_DB}..."
	
	# Assign db_name variable for db_backup
	DB_NAME=${SRC_DB}

	# Call the backup function
		# All functions, checks and safeguards have been pre-defined in the database_backup function
	DATABASE_BACKUP "${RUNNER}" "${THRESHOLD}" "${DB_NAME}" "${DIRECTORY}" "${QUERY}"		
	echo
	echo "Backup finished."

	# Check if tar list exists
	echo "Finding tar files..."
	if [[ ! -s ${exp_tar} ]]
	then
   	echo "No tar files found. Cannot migrate."
   	exit 1
	fi
   cat "${exp_tar}"
	echo

	DST_USER=${DEST_USER}
	DST_SERV=${DEST_SERV}
	# Transfer tar files to cloud server using SCP() function
	echo "Transferring tar files to ${DEST_SERV}..."
	cd ${datapump}/${SRC_DB}
	#SCP $(cat ${exp_tar}) ${DST_USER} ${DST_SERV} "${datapump}/${DEST_DB}" ${RUNNER}
	scp -i ${pem_key} $(cat ${exp_tar}) ${DEST_USER}@${DEST_SERV}:"${datapump}/${DEST_DB}" 		
	echo

	# Copy schema list to cloud server using SCP() function
	#SCP ${exp_schemas} ${DST_USER} ${DST_SERV} "${temp_dir}/schemas.lst" ${RUNNER}
	scp -i ${pem_key} ${exp_schemas} ${DEST_USER}@${DEST_SERV}:"${temp_dir}/schemas.lst"
	echo

   # Define the dynamic import script
   local remote_script=${DEST_SERV}_import_${TS}.sh

	# Generate import script
		# Using SCRIPTEOF + EOF seperately to just to differentiate
		# SCRIPTEOF in single-quotes to treat strings literally and disable variable expansion, etc.
	echo "Generating import script..."
	cat > ${temp_dir}/${remote_script} << 'SCRIPTEOF'
#!/bin/bash
SCRIPTEOF
	
	cat >> ${temp_dir}/${remote_script} << EOF

source ${cloud_env}
DEST_DPUMP=${datapump}
DIRECTORY=${DIRECTORY}
DEST_DB=${DEST_DB}
SERV_NAME=${DEST_SERV}
TS=${TS}
RUNNER=${RUNNER}
TAR_LIST="$(sed 's|.*/||' ${exp_tar})"
PRAC_DIR=${prac_dir}
TEMP_DIR="${temp_dir}"
SCHEMALIST="${temp_dir}/schemas.lst"
DB_USER=${AWS_DB_USER}
DB_PASS=${AWS_DB_PASS}
EOF

	cat >> ${temp_dir}/${remote_script} << 'SCRIPTEOF'
		
if ( ! grep ${DEST_DB} /etc/oratab )
then
   echo "The ${DEST_DB} database does not exist on this server."
   exit 1
fi

if ( ps -ef | grep pmon | grep ${DEST_DB} )
then
   echo "The ${DEST_DB} database instance is up and running."
else
   echo "THE ${DEST_DB} DATABASE IS DOWN!!!"
   exit 1
fi

DBCHECKLOG="${PRAC_DIR}/dbcheck.log"

sqlplus ${DB_USER}/${DB_PASS} << SQLEOF > ${DBCHECKLOG}
set echo on feedback on term on pagesize 0
select status from v\$instance;
exit
SQLEOF

if ( grep "OPEN" ${DBCHECKLOG} )
then
   echo "The database is open for import."
else
   echo "The database is not open. Import cannot occur."
   exit 1
fi
echo

cd ${DEST_DPUMP}/${DEST_DB}
	
for tar_file in ${TAR_LIST}
do
	dump_file=$(tar -tf ${tar_file} | grep '\.dmp')
	echo "Extracting ${dump_file}..."
	tar -xzf ${tar_file} ${dump_file}
	if [ $? -ne 0 ]
	then
		echo "Failed to extract ${tar_file}"
		exit 1
	fi
	echo "${dump_file} extracted.->>"
	rm ${tar_file}
done

echo "Extracted all dump files."
echo

while read -r schema
do
	echo "Importing schema: ${schema}"
	
	IMPDP_LOG="impdp_${schema}_${RUNNER}_${TS}.log"
	PARFILE="${PRAC_DIR}/impdp_${schema}_${RUNNER}_${TS}.par"
	DUMP_FILE="expdp_${schema}_${RUNNER}_${TS}.dmp"

	echo "userid=${DB_USER}/${DB_PASS}" > ${PARFILE}
	echo "schemas=${schema}" >> ${PARFILE}
	echo "remap_schema=${schema}:${schema}_${RUNNER}" >> ${PARFILE}
	echo "dumpfile=${DUMP_FILE}" >> ${PARFILE}
	echo "logfile=${IMPDP_LOG}" >> ${PARFILE}
	echo "table_exists_action=replace" >> ${PARFILE}
	echo "directory=${DIRECTORY}" >> ${PARFILE}	
	
	impdp parfile=${PARFILE}

	echo "Imported schema: ${schema}"
	find ${DEST_DPUMP} -maxdepth 1 -name "*${schema}_${RUNNER}*" -mtime +1 -exec rm {} \;
done < ${SCHEMALIST}

echo "Exported all schemas!"
echo
echo "-----------Import complete---------------"
SCRIPTEOF

	# Push import script to the cloud server
	echo 
	echo "Pushing import script to ${DEST_SERV}..."
	#SCP "${temp_dir}/${remote_script}" ${DST_USER} ${DST_SERV} "${prac_dir}" ${RUNNER}
	scp -i ${pem_key} ${temp_dir}/${remote_script} ${DEST_USER}@${DEST_SERV}:"${prac_dir}"

	# Connect to the remote server, allow execute permissions, and run the script
	echo
	echo "Executing import script on ${DEST_SERV}..."
	ssh -i ${pem_key} ${DEST_USER}@${DEST_SERV} "cd ${prac_dir} && chmod 744 ${remote_script} && ./${remote_script}"
	SSH_EX=$?
	# impdp exit codes: 0=success, 5=completed with warnings, 1+=error
	if (( ${SSH_EX} == 0 || ${SSH_EX} == 5 ))
	then
		echo "impdp succeeded or completed with warnings."
		mailx -s "WARNING: [${RUNNER}] Database Import Completed With Warnings" ${stack_email} << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Database import from ${SRC_DB} into ${DEST_DB} in ${DEST_SERV} completed with warnings.
EOF
		# Reconnect to the server and 
		ssh -i ${pem_key} ${DEST_USER}@${DEST_SERV} "cd ${prac_dir} && mv ${remote_script} ${temp_dir}/.${remote_script}"
	else
		echo "impdp FAILED"
		mailx -s "WARNING: [${RUNNER}] Database Import Failure Alert" ${stack_email} << EOF
-------ALERT-------
RUNNER: ${RUNNER}
Database import from ${SRC_DB} into ${DEST_DB} in ${DEST_SERV} has failed
EOF
		exit 1
	fi
	
	mv ${temp_dir}/${remote_script} ${temp_dir}/.${remote_script} 
	
	echo
	echo "			  ---- MIGRATION COMPLETE ----"
	echo "			Thank you for using this service."
}

CLEANUP()
{

	local stack_email=${STACK_EMAIL}
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
            mailx -s "WARNING: [${RUNNER}] Cleanup Failure Alert" ${stack_email} << EOF
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
      mailx -s "WARNING: [${RUNNER}] Cleanup Canceled Alert" ${stack_email} << EOF
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

#AUTO_CONFIRM=true

functions="scp backup_f_d disk_util database_backup database_import local_migration cloud_migration cleanup quit"
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
	if [ $# -ne 5 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <SRC> <DST_USER> <DST SERVER> <DST PATH> <RUNNER>"
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
	if [ $# != 4 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <SRC> <RUNNER>"
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
		THRESHOLD=$2
		SRC=$3
		RUNNER=$4
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
	if [ $# -ne 4 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <THRESHOLD> <RUNNER>"
		echo

		read -p "Do you need help running this script? :" ANSWER
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "Enter disk(s) to be checked: " DISKS
				read -p "Enter threshold value " THRESHOLD
				read -p "Who is running this script: " RUNNER

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				DISK_UTILIZATION ${DISKS} ${THRESHOLD} ${RUNNER}
			else
				exit 1
			fi
	else
		DISKS=$2
		THRESHOLD=$3
		RUNNER=$4
		#call function BACKUP_F_D
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		DISK_UTILIZATION ${DISKS} ${THRESHOLD} ${RUNNER}
	fi
	echo
	;;
database_backup)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 5 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <RUNNER> <DB_NAME> <DIRECTORY> <QUERY>"
		echo

		read -p "Do you need help running this script? :" ANSWER
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "Who is running this script? " RUNNER
				read -p "What is the database name? " DB_NAME
				read -p "What is the directory name? " DIRECTORY
				read -p "Enter the SQL query: " QUERY

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				DATABASE_BACKUP ${RUNNER} ${DB_NAME} ${DIRECTORY} ${QUERY}
			else
				exit 1
			fi
	else
		RUNNER=$2
		DB_NAME=$3
		DIRECTORY=$4
		QUERY="$5"
		#Call function
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		DATABASE_BACKUP ${RUNNER} ${DB_NAME} ${DIRECTORY} ${QUERY}
	fi
	echo
	;;
database_import)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 6 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <SRC_DB> <DEST_DB> <RUNNER> <DIRECTORY> <QUERY>"
		echo

		read -p "Do you need help running this script? " ANSWER
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "What is the source database? " SRC_DB
				read -p "What is the destination database? " DEST_DB
				read -p "Who is running this script? " RUNNER
				read -p "What is the directory name? " DIRECTORY
				read -p "Enter the SQL query. Please put in quotes: " QUERY

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				DATABASE_IMPORT ${SRC_DB} ${DEST_DB} ${RUNNER} ${DIRECTORY} "${QUERY}"
			else
				exit 1
			fi
	else
		SRC_DB=$2
		DEST_DB=$3
		RUNNER=$4
		DIRECTORY=$5
		QUERY="$6"
		#Call function
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		DATABASE_IMPORT ${SRC_DB} ${DEST_DB} ${RUNNER} ${DIRECTORY} "${QUERY}"
	fi
	echo
	;;
local_migration)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 6 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <SRC_DB> <DEST_DB> <RUNNER> <DIRECTORY> <QUERY>"
		echo

		read -p "Do you need help running this script? " ANSWER
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "What is the source database? " SRC_DB
				read -p "What is the destination database? " DEST_DB
				read -p "Who is running this script? " RUNNER
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
		DB_NAME=$2
		DEST_DB=$3
		RUNNER=$4
		DIRECTORY=$5
		QUERY="$6"
		#Call function
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		LOCAL_MIGRATION ${SRC_DB} ${DEST_DB} ${RUNNER} ${SCHEMA} ${DIRECTORY} ${QUERY}
	fi
	echo
	;;
cloud_migration)
	#utilization check
   echo "The number of command-line arguments in this script is: $#"
   if [ $# -ne 7 ]
   then
      echo "You did not run this script correctly. Please run like below:"
      echo "UTILITY: <SCRIPT_NAME> <SRC_DB> <DEST_DB> <DEST_SERV> <RUNNER> <DIRECTORY> <QUERY>"
      echo

      read -p "Do you need help running this script? " ANSWER
         if [[ ${ANSWER^^} == 'Y' ]]
         then
            echo "You have opted for help..."
            read -p "What is the source database? " SRC_DB
            read -p "What is the destination database? " DEST_DB
				read -p "What is the destination server? " DEST_SERV
            read -p "Who is running this script? " RUNNER
            read -p "What is the directory name? " DIRECTORY
            read -p "What is the SQL query contained in double-quotes: " QUERY

            echo "Calling ${SCRIPT_FUNC} function..."
            echo "..."
            CLOUD_MIGRATION ${SRC_DB} ${DEST_DB} ${DEST_SERV} ${RUNNER} ${DIRECTORY} ${QUERY}
         else
            exit 1
         fi
   else
		SRC_DB=$2
      DB_NAME=$2
      DEST_DB=$3
      DEST_SERV=$4
      RUNNER=$5
      DIRECTORY=$6
      QUERY="$7"
      echo "Calling ${SCRIPT_FUNC} function..."
      echo "..."
      CLOUD_MIGRATION ${SRC_DB} ${DEST_DB} ${DEST_SERV} ${RUNNER} ${DIRECTORY} ${QUERY}
   fi
   echo
	;;	
cleanup)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if [ $# -ne 5 ]
	then
		echo "You did not run this script correctly. Please run like below:"
		echo "UTILITY: <SCRIPT_NAME> <MTIME> <FILE_PATH> <FILES> <RUNNER>"
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
