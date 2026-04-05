#!/bin/bash

#Function declaration
BACKUP_F_D()
{
   echo "Creating backup directory ${BACKUP_DIR}..."
   mkdir -p ${BACKUP_DIR}

   if (($? != 0 ))
   then
      echo "Failed to create directory ${BACKUP_DIR}"
   else
      echo "Successfully created directory ${BACKUP_DIR}"
   fi
   echo

	#Copy logic
   if [[ -d ${SRC} ]]
   then
      echo "${SRC} is a directory."
      echo "Copying the DIRECTORY to specified backup location ${BACKUP_DIR}..."
      cp -r ${SRC} ${BACKUP_DIR}

      if (( $? != 0 ))
      then
         echo "Directory copy FAILED!"
      else
         echo "Directory copy SUCCESSFUL!"
      fi

   elif [[ -f ${SRC} ]]
   then
      echo "${SRC} is a file."
      echo "Copying the FILE to specified backup location ${BACKUP_DIR}..."
      cp ${SRC} ${BACKUP_DIR}

      if (( $? != 0 ))
      then
         echo "File copy FAILED!"
      else
         echo "File copy SUCCESSFUL!"
      fi

   else
      echo "${SRC} does not exist. Please re-run the script."
      exit 1
   fi
   echo
}


#variable declarations
script_func=$1
TS=$(date "+%m%d%Y%H%M%S")
SRC=$2
PRACTICE_DIR="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH"
RUNNER=$3

#declare the backup path
BACKUP_DIR=${PRACTICE_DIR}/backup/${RUNNER}/$TS

#Case statements: function declaration
case ${script_func} in
backup_f_d)
		#utilization check
		echo "The number of command-line arguments in this script is: $#"
		if (( $# != 3 ))
		then
   		echo "You did not run this script correctly. Please run like below:"
   		echo "UTILITY: <SCRIPT_NAME> <SRC> <RUNNER>"
   		echo "e.g script_name home/oracle/file.txt backup"
   		exit 1
		fi
		
		#Call function BACKUP_F_D
   	echo "Calling ${script_func} function... "
   	BACKUP_F_D
	;;
database_backup)
	;;
database_import)
	;;
secure_copy)
	;;
data_migration)
	;;
AWS)
	;;	
*)
	echo "${script_func} was not found in this code."
	exit 1
	;;
esac


#main body

#validate
echo "Showing ${SRC} in ${BACKUP_DIR}..."
ls -ltr ${BACKUP_DIR}

echo "Showing timestamped backup: "
ls -ltr ${PRACTICE_DIR}/backup/${RUNNER}
