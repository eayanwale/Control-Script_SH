#!/bin/bash

TXT=file1.txt
FILES=$(find -maxdepth 1 -name "*${TXT}*" -exec ls {} \;)
#echo "Viewing files"
echo ${FILES} 
echo
echo

FILE_REAL_COUNT=$(find . -maxdepth 1 -name "*${TXT}*" -exec ls {} \; | wc -l)
echo "file count is "
echo ${FILE_REAL_COUNT}
echo ${REAL_REAL}
