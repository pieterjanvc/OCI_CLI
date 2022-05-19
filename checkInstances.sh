#!/bin/bash

#When error occurs, notify and exit
err_report() {
	
	echo -e "ERROR LINE $1 $2 $0"
	exit 1;
}
trap 'err_report ${LINENO}' ERR

#Check the input args
while getopts "s" opt; do
  case $opt in
	s) silent=true #Do not show script output
    ;;
    \?) echo "Unknown argument provided"
	    exit
	;;
  esac  
done

### SET PARAMETERS ###
#--------------------#

#Compartment id
cOCID="ocid1.compartment.oc1.."
#Free instance name. If multiple, separate by |
alwaysFree="freeInstance" #Label (name) of the always free instance


### START SCRIPT ###
#------------------#

if [ "$silent" != true ]; then 
	echo -e `date "+%T"`" - Check if any non-free instances are running at the moment ..."
fi

#Count the number of non-free instances running at the moment
nonFree=$(/opt/oracle-cli/oci compute instance list --compartment-id $cOCID --lifecycle-state RUNNING | \
	grep -cP '\"display-name\":\s\"(?!'$alwaysFree')' || true)


#Send the message
if [ "$nonFree" != 0 ]; then
	
	if [ "$nonFree" == 1 ]; then
		if [ "$silent" != true ]; then echo "  One non-free instance is still running"; fi
	else
		if [ "$silent" != true ]; then echo "  $nonFree non-free instances are still running"; fi
	fi	
	
	#Add any code you like to run in case non-free instances are running

else

	if [ "$silent" != true ]; then echo "  The are no non-free instances running"; fi

fi 
