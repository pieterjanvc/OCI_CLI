#!/bin/bash

#When error occurs, notify and exit
err_report() {
	
	echo -e "ERROR LINE $1 $2 $0"
	exit 1;
}
trap 'err_report ${LINENO}' ERR

#Check the input args
while getopts "d" opt; do
  case $opt in
	d) dontwait=true
    ;;
    \?) echo "Unknown argument provided"
	    exit
	;;
  esac  
done

### SET PARAMETERS ###
#--------------------#
instanceHostName="myInstance" #Instance name to terminiate
cOCID="ocid1.compartment.oc1..."


### START SCRIPT ###
#------------------#

echo -e `date "+%T"`" - Check if there is an instance with name $instanceHostName running at the moment ..."
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
		" - All (new) data on a shared block volume will be preserved \n"\
		" - The original instance image will be kept (but no changes to it)\e[0m"
		read -p "> DELETE/no/exit: " yn 
		case $yn in 
		DELETE ) echo -e `date "+%T"`" - Terminate instance without saving boot volume"
				saveBoot=false
				break;;
		NO|no|No ) echo -e `date "+%T"`" - Terminate instance and save boot volume"
				saveBoot=true
				break;; 
		"exit" ) echo -e `date "+%T"`" - Instance termination exited"
				exit;; 
		* ) echo "Please answer DELETE/no/exit. " >&2
		esac
	done
	
	#Terminate instanse and wait if -d not set
	if [ "$dontwait" == "true" ]; then
		oci compute instance terminate --force \
		--instance-id $existing \
		--preserve-boot-volume $saveBoot
	else
		oci compute instance terminate --force \
		--instance-id $existing \
		--preserve-boot-volume $saveBoot \
		--wait-for-state TERMINATED
	fi
	
		
	echo -e "\e[32m\n The instance terminated successfully\e[0m"
fi 
