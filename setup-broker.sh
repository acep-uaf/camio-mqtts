#!/usr/bin/env bash

# setup-broker.sh
# Description: This script will install a Secure Mosquitto MQTT Broker on a Ubuntu / Debian system.
# Verson: 1.0.0
# Version_Date: 2024-03-26
# Author: John Haverlack (jehaverlack@alaska.edu)
# License: MIT (Proposed/Pending) / UAF Only
# Source: https://github.com/acep-uaf/camio-mqtts

# Check if dependancy binaries are installed.
req_binaries=(apt awk cat cut date df egrep grep jq lsblk mount sed stat tail tr uname uptime wc which)
for i in "${req_binaries[@]}"; do
  if ! which $i > /dev/null 2>&1; then
    echo "Error: $i binary not found or not executable.  Please install $i"
    exit 1
  fi
done

# Verify that this script is being run as root.
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

# Determine the directory full path where this seal-os.sh file is located.
rundir=$(realpath $(dirname $0))

# Check to see if the losd-lib.sh file exists and is readable.
if [ ! -r $rundir/losd/losd-lib.sh ]; then
  echo "Error: $rundir/losd/losd-lib.sh file not found or not readable."
  exit 1
fi

# Defined supported OS
supported_os=("Ubuntu" "Debian")

# Source the losd-lib.sh file.
source $rundir/losd/losd-lib.sh

losd_json=$(losd)

os_name=$(echo $losd_json | jq '.DISTRO.NAME' | sed -r 's/"//g')
os_version=$(echo $losd_json | jq '.DISTRO.VERSION' | sed -r 's/"//g')
hw_platform=$(echo $losd_json | jq '.HARDWARE.HOSTNAMECTL.Chassis' | tr -dc '[:print:]' | sed -r 's/\s//g' | sed -r 's/"//g')

echo "OS Name:           $os_name"
echo "OS Version:        $os_version"
echo "Hardware Platform: $hw_platform"

# Check if the OS is supported
if [[ ! " ${supported_os[@]} " =~ " ${os_name} " ]]; then
    echo "ERROR: Unsupported OS detected: $os_name $os_version"
    exit 1
fi


echo "WARNING:"
echo "This script [setup-broker.sh] will install and configure a TLS secured Mosquitto MQTT Broker."
read -p "Continue [y/N]:" ans

if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
    echo "INFO: Aborting Script."
    exit 1
fi

# Install the necessary packages
apt update
apt install -y mosquitto mosquitto-clients

