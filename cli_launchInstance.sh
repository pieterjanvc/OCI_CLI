#!/bin/bash

#When error occurs, notify and exit
err_report() {
	
	echo -e "ERROR LINE $1 $2 $0"
	exit 1;
}
trap 'err_report ${LINENO}' ERR

### SET PARAMETERS ###
#--------------------#
#The hostname and IP of the compute instance should match the ocfs2 config file
instanceIP=<put private IP here>
instanceHostName=<put hostname here>
instanceKey=<path to instance private key file> #file should have been copied to the freeInstance
instanceShape=<put instance share name here> #e.g. "VM.Standard2.4"
logFolder=<path to log folder> #e.g. ~/.oci/logs

cOCID=<put compartment OCID here>
iOCID=<put image OCID here>
sOCID=<put subnet OCID here>
vOCID=<put block volume OCID here>

### START SCRIPT ###
#------------------#

echo -e `date "+%T"`" - Check if there is no pipeline instance running at the moment ..."
#Check if there is no pipeline instance running at the moment
existing=$(oci compute instance list \
	--compartment-id $cOCID \
	--display-name "computeInstance" \
	--lifecycle-state RUNNING --lifecycle-state STOPPED)

if [ ! -z "$existing" ]; then
	existing=$(echo $existing | grep -oP "\"id\":\s*\"\K([^\"]+)")
	echo -e "\e[91mA computeInstance is already running (or stopped but not terminated).\n" \
	"Terminate it before starting a new one.\n" \
	"id = $existing\e[0m"
	exit 1 
fi
echo -e `date "+%T"`" - none found\n"

#Use the UNIX timestamp as a reference for this run
dateTime=`date "+%s"`

#Launch the instance
echo -e `date "+%T"`" - Launching the instance ..."
oci compute instance launch \
	--availability-domain "uNZJ:US-ASHBURN-AD-2" \
	--compartment-id $cOCID \
	--shape $instanceShape \
	--hostname-label $instanceHostName \
	--display-name $instanceHostName \
	--image-id $iOCID \
	--subnet-id $scOCID \
	--private-ip $instanceIP \
	--wait-for-state RUNNING \
	> $logFolder/$dateTime\_launchedInstance.json
	
instanceId=`cat $logFolder/$dateTime\_launchedInstance.json | grep -oP "ocid1.instance.oc1.iad[^\"]+"`
echo -e `date "+%T"`" - Launching the instance completed\n"

#Attach the meta2amrData block volume
echo -e `date "+%T"`" - Attach the meta2amrData block volume ..."
oci compute volume-attachment attach \
	--instance-id $instanceId \
	--type iscsi \
	--volume-id $vOCID \
	--is-shareable true \
	--device "/dev/oracleoci/oraclevdb" \
	--wait-for-state ATTACHED \
	> $logFolder/$dateTime\_attachedBlockVolume.json

ipv4=`cat $logFolder/$dateTime\_attachedBlockVolume.json | \
	grep -oP "\"ipv4\":\s*\"\K([^\"]+)"`
iqn=`cat $logFolder/$dateTime\_attachedBlockVolume.json | \
	grep -oP "\"iqn\":\s*\"\K([^\"]+)"`
echo -e `date "+%T"`" - Attaching block volume completed\n"

#Wait for the system to boot up
echo -e `date "+%T"`" - Wait for the system to boot up ..."
while ! ssh -i $instanceKey opc@$instanceIP -o ConnectTimeout=5 true
do
    sleep 10
done
echo -e `date "+%T"`" - done\n"

#Run the commands to properly mount the volume
echo -e `date "+%T"`" - Run the commands to properly mount the volume ..."
ssh -i $instanceKey opc@$instanceIP \
	"sudo iscsiadm -m node -o new -T $iqn -p $ipv4:3260;" \
	"sudo iscsiadm -m node -o update -T $iqn -n node.startup -v automatic;" \
	"sudo iscsiadm -m node -T $iqn -p $ipv4:3260 -l;" \
	"sudo /sbin/service o2cb restart;" \
	"sudo mount -a;" \
	"- Private IP: 10.0.0.11\n - Public IP: $ipv4\e[0m\""
