#!/bin/bash

#variable declarations
SRC=/home/oracle/scripts/practicedireno_jan26/BIN/BASH/file1.txt
DST=/home/oracle/scripts/practicedireno_jan26/BIN/BASH/backup


#main body

#creating backup directory
mkdir -p ${DST}

#copying source value to backup destination
cp -f ${SRC} ${DST}

#validate
echo "listing files in backup directory ${BACKUP}" 
ls -l
ls -l ${DST}


