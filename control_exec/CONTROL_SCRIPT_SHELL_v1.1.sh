#!/bin/bash

#variable declarations
SRC=$1
DST=$2
RUNNER=$3

#declare the backup path
BACKUP=$DST/$RUNNER

#main body

#creating backup directory
echo "creating backup directory ${BACKUP}..."
mkdir -p ${BACKUP}

#copying source value to backup destination
echo "copying ${SRC} to specified  backup location ${BACKUP}..."
cp -rf ${SRC} ${BACKUP}

#validate
echo "listing files in backup directory ${BACKUP}" 
ls -ltr ${BACKUP}
