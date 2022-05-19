#!/bin/bash

#When error occurs, notify and exit
err_report() {
	
	echo -e "ERROR LINE $1"
	exit 1;
}
trap 'err_report ${LINENO}' ERR

# --- CHECK ARGUMENTS ---
while getopts "c:m:" opt; do
  case $opt in
	c) cpu="${OPTARG}"
	;;
	m) memory="${OPTARG}" #In Gb
    ;;
    \?) echo "Unknown argument provided"
	    exit
	;;
  esac  
done

if [ ! -z ${cpu+x} ]; then
	if [ ! $(grep -E "^([0-9]+)$" <<< $cpu) ] ; then
		echo -e "\n\e[91mThe cpu argument (-c) needs to be a postive integer\e[0m"
		exit 1
	fi
else 
	echo "  No number of CPUs provided, the default of 2 is used"
	cpu=2
fi 

if [ ! -z ${memory+x} ]; then
	if [ ! $(grep -E "^([0-9]+)$" <<< $memory) ] ; then
		echo -e "\n\e[91mThe memory argument (-m) needs to be a positive integer\e[0m"
		exit 1
	fi
else 
	echo "  No value for memory provided, the default of 8GB is used"
	memory=8
fi 

# --- SET VARIABLES ---

#All IDs can be found on the OCI website
compartment="ocid1.compartment.oc1.."
subnet "ocid1.subnet.oc1.iad..."
image="ocid1.image.oc1.iad..."
volume"ocid1.volume.oc1.iad..."
availabilityDomain="uNZJ:US-ASHBURN-AD-2"

user="username" #Valid username on the attached image
label="" #Label for the new instance
privateIP="10.0.0.11" #Set any that is not currently in use
logFolder="/temp" #local folder to save logs to
mountDevice="/dev/oracleoci/oraclevdb" \  #Might be different depending on block volume mounting setup

# --- CHECK ---

#Check if there is no pipeline instance running at the moment
existing=$(oci compute instance list \
	-c $compartment \
	--lifecycle-state RUNNING --display-name "$label" | \
	grep -oP "\"id\":\s*\"\K([^\"]+)" || true)
	
if [ ! -z $existing ]; then
	echo -e "\e[91mA $label instance is already running.\n" \
	"Shut it down first before starting a new one.\n" \
	"id = $existing\e[0m"
	exit 1
fi

# --- LAUNCH INSTANCE ---

#Use the UNIX timestamp as a reference for this run
dateTime=`date "+%s"`

#Launch the instance
echo -e `date "+%T"`" - Launching the instance ..."
oci compute instance launch \
	--availability-domain $availabilityDomain \
	-c $compartment \
	--shape "VM.Standard.E3.Flex" \
	--shape-config "{\"ocpus\": $cpu,\"memoryInGBs\": $memory}" \
	--hostname-label $label \
	--display-name $label \
	--image-id $image \
	--subnet-id $subnet \
	--private-ip $privateIP \
	--wait-for-state RUNNING \
	> $logFolder/$dateTime\_launchedInstance.json
	
instanceId=`cat /srv/instanceLogs/$dateTime\_launchedInstance.json | grep -oP "ocid1.instance.oc1.iad[^\"]+"`
echo -e `date "+%T"`" - Launching the instance completed\n"

#Attach the meta2amrData block volume
echo -e `date "+%T"`" - Attach the meta2amrData block volume ..."
oci compute volume-attachment attach \
	--instance-id $instanceId \
	--type iscsi \
	--volume-id $volume \
	--is-shareable true \
	--device $mountDevice \ 
	--wait-for-state ATTACHED \
	> $logFolder/$dateTime\_attachedBlockVolume.json

ipv4=`cat $logFolder/$dateTime\_attachedBlockVolume.json | \
	grep -oP "\"ipv4\":\s*\"\K([^\"]+)"`
iqn=`cat $logFolder/$dateTime\_attachedBlockVolume.json | \
	grep -oP "\"iqn\":\s*\"\K([^\"]+)"`
echo -e `date "+%T"`" - Attaching block volume completed\n"

#Wait for the system to boot up
echo -en `date "+%T"`" - System booting ..."
while ! ssh $user@$privateIP -q -o ConnectTimeout=5 true
do
    echo -n "."
	sleep 3
done
echo -e "\n"`date "+%T"`"   done\n"

#Run the commands to properly mount the volume
echo -e `date "+%T"`" - Run the commands to properly mount the volume ..."
ssh $user@$privateIP \
	"sudo iscsiadm -m node -o new -T $iqn -p $ipv4:3260; \
	sudo iscsiadm -m node -o update -T $iqn -n node.startup -v automatic; \
	sudo iscsiadm -m node -T $iqn -p $ipv4:3260 -l; \
	sudo /sbin/service o2cb restart; \
	sudo mount -a; \
	echo -e \"\e[32m\n The instance is ready! \n - Private IP: $privateIP\n - Public IP: `curl -s https://ifconfig.co`\e[0m\""

