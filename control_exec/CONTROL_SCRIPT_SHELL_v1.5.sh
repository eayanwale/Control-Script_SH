#!/bin/bash

#utilization check
echo "The number of command-line arguments in this script is: $#"
if (( $# != 4 ))
then
   echo "You did not run this script correctly. Please run like below:"
   echo "UTILITY: <SCRIPT_NAME> <SRC> <DST> <RUNNER>"
   echo "e.g script_name home/oracle/file.txt home/oracle backup"
   exit 1
fi
echo

#variable declarations
script_func=$1
SRC=$2
DST=$3
RUNNER=$4

#declare the backup path
BACKUP=$DST/$RUNNER

#declare the function
#-creates backup directory
#-contains object type validation and copy logic
BACKUP_F_D()
{
   echo "creating backup directory ${BACKUP}..."
   mkdir -p ${BACKUP}
   
	if (( $? != 0 )) 
	then
		echo "Failed to create directory ${BACKUP}"
	else
		echo "Successfully created directory ${BACKUP}"
	fi 
	echo

   if [[ -d ${SRC} ]]
   then
      echo "${SRC} is a directory."
      echo "Copying the DIRECTORY to specified backup location ${BACKUP}..."
      cp -r ${SRC} ${BACKUP}

      if (( $? != 0 ))
      then
         echo "Directory copy FAILED!"
      else
         echo "Directory copy SUCCESSFUL!"
      fi

   elif [[ -f ${SRC} ]]
   then
      echo "${SRC} is a file."
      echo "Copying the FILE to specified backup location ${BACKUP}..."
      cp ${SRC} ${BACKUP}

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


#main body

#function check
if [[ ${script_func} == "backup" ]]
then
   echo "Calling ${script_func} function... "
   BACKUP_F_D
else
   echo "Cannot find that function. ${script_func} does not exist."
   exit 1
fi

#validate
echo "Showing ${SRC} in ${BACKUP}..."
ls -ltr ${BACKUP}

echo "Showing ${RUNNER} in ${DST}..."
ls -ltr ${DST}


