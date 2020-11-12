#!/bin/bash

#When error occurs, notify and exit
err_report() {
	
	echo -e "ERROR LINE $1 $2 $0"
	exit 1;
}
trap 'err_report ${LINENO}' ERR

### SET PARAMETERS ###
#--------------------#
instanceHostName=<put hostname here>
cOCID=<put compartment OCID here>


### START SCRIPT ###
#------------------#

echo -e `date "+%T"`" - Check if there is a pipeline instance running at the moment ..."
#Check if there is no pipeline instance running at the moment
existing=$(oci compute instance list \
	--compartment-id $cOCID \
	--display-name $instanceHostName --lifecycle-state RUNNING)

if [ -z "$existing" ]; then
	echo -e "\e[91mThere is no compute instance running\n" \
	"==> exit script\e[0m"
	exit 1 
else
	existing=$(echo $existing | grep -oP "\"id\":\s*\"\K([^\"]+)")
	echo  -e "\ninstance found with id = $existing\n"
	
	while true; do
		echo -e "\e[91mDo you want to DELETE the current boot volume?\n"\
		" - All (new) data on the shared block volume will be preserved \n"\
		" - The original instance image will be kept (but no changes to it)\e[0m"
		read -p "> yes/no/exit: " yn 
		case $yn in 
		[Yy]* ) echo -e `date "+%T"`" - Terminate instance without saving boot volume"
				saveBoot=false
				break;;
		[Nn]* ) echo -e `date "+%T"`" - Terminate instance and save boot volume"
				saveBoot=false
				break;; 
		[Ee]* ) exit;; 
		* ) echo "Please answer yes/no/exit. " >&2
		esac
	done
	
	oci compute instance terminate \
		--instance-id $existing \
		--preserve-boot-volume $saveBoot \
		--wait-for-state TERMINATED
		
	echo -e "\e[32m\n The instance terminated successfully\e[0m"
fi 
