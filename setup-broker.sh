#!/usr/bin/env bash

# setup-broker.sh
# Description: This script will install a Secure Mosquitto MQTT Broker on a Ubuntu / Debian system.
# Verson: 1.0.0
# Version_Date: 2024-03-26
# Author: John Haverlack (jehaverlack@alaska.edu)
# License: MIT (Proposed/Pending) / UAF Only
# Source: https://github.com/acep-uaf/camio-mqtts

# This script is intended to be idemopotent.  It can be run multiple times without causing issues.

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

host_name=$(echo $losd_json | jq '.HOST.HOSTNAME' | sed -r 's/"//g')
os_name=$(echo $losd_json | jq '.DISTRO.NAME' | sed -r 's/"//g')
os_version=$(echo $losd_json | jq '.DISTRO.VERSION' | sed -r 's/"//g')
hw_platform=$(echo $losd_json | jq '.HARDWARE.HOSTNAMECTL.Chassis' | tr -dc '[:print:]' | sed -r 's/\s//g' | sed -r 's/"//g')
ip_addr=$(echo $losd_json | jq .HARDWARE.NETWORK | jq -r '.[] | select(.INTERFACE != "lo") | .IPV4_ADDR')

# Check to see if the losd-lib.sh file exists and is readable.
if [ ! -r $rundir/conf/mqtt.json ]; then
  echo "Error: $rundir/losd/losd-lib.sh file not found or not readable."
  exit 1
fi

# Read the mqtt.json file
mqtt_json=$(cat $rundir/conf/mqtt.json | jq)

# Extract MQTT Vars
mqtt_conf_file=$(echo $mqtt_json | jq '.CONFIG.CONF_FILE' | sed -r 's/"//g')

## Defaults
mqtt_allow_anon=true
mqtt_host=$(echo $mqtt_json | jq '.BROKER.HOST' | sed -r 's/"//g')
mqtt_port=$(echo $mqtt_json | jq '.BROKER.PORT' | sed -r 's/"//g')

mqtt_tls_status=$(echo $mqtt_json | jq '.TLS.ENABLED' | sed -r 's/"//g')
# if mqtt_tls_status is true, then set mqtt_tls_status to "Enabled", else set it to "Disabled"
if [ $mqtt_tls_status ]; then
  mqtt_tls_ca_key=$(echo $mqtt_json | jq '.TLS.CA_KEY' | sed -r 's/"//g')
  mqtt_tls_ca_cert=$(echo $mqtt_json | jq '.TLS.CA_CERT' | sed -r 's/"//g')
  mqtt_tls_server_key=$(echo $mqtt_json | jq '.TLS.SERVER_KEY' | sed -r 's/"//g')
  mqtt_tls_server_csr=$(echo $mqtt_json | jq '.TLS.SERVER_CSR' | sed -r 's/"//g')
  mqtt_tls_server_cert=$(echo $mqtt_json | jq '.TLS.SERVER_CERT' | sed -r 's/"//g')

  mqtt_host=$(echo $mqtt_json | jq '.TLS.HOST' | sed -r 's/"//g')
  mqtt_port=$(echo $mqtt_json | jq '.TLS.PORT' | sed -r 's/"//g')

  mqtt_cert_days=$(echo $mqtt_json | jq '.CERT.DAYS' | sed -r 's/"//g')
  mqtt_cert_C=$(echo $mqtt_json | jq '.CERT.SUBJECT.C' | sed -r 's/"//g')
  mqtt_cert_ST=$(echo $mqtt_json | jq '.CERT.SUBJECT.ST' | sed -r 's/"//g')
  mqtt_cert_L=$(echo $mqtt_json | jq '.CERT.SUBJECT.L' | sed -r 's/"//g')
  mqtt_cert_O=$(echo $mqtt_json | jq '.CERT.SUBJECT.O' | sed -r 's/"//g')
  mqtt_cert_OU=$(echo $mqtt_json | jq '.CERT.SUBJECT.OU' | sed -r 's/"//g')
  mqtt_cert_CN=$(echo $mqtt_json | jq '.CERT.SUBJECT.CN' | sed -r 's/"//g')
fi


mqtt_auth_status=$(echo $mqtt_json | jq '.AUTH.ENABLED' | sed -r 's/"//g')
# if mqtt_auth_status is true, then set mqtt_auth_status to "Enabled", else set it to "Disabled"
if [ $mqtt_auth_status ]; then
  mqtt_allow_anon=false
  mqtt_passwd_file=$(echo $mqtt_json | jq '.CONFIG.PASSWD_FILE' | sed -r 's/"//g')
  mqtt_user=$(echo $mqtt_json | jq '.AUTH.USERS[0]' | sed -r 's/"//g')
fi


echo ""
echo "Host Name:         $host_name"
echo "OS Name:           $os_name"
echo "OS Version:        $os_version"
echo "Hardware Platform: $hw_platform"
echo "IP Address:        $ip_addr"
echo ""

echo "MQTT Broker Host:  $mqtt_host"
echo "MQTT Broker Port:  $mqtt_port"
echo "MQTT TLS Status:   $mqtt_tls_status"
echo "MQTT Auth Status:  $mqtt_auth_status"
echo ""

# Check if the OS is supported
if [[ ! " ${supported_os[@]} " =~ " ${os_name} " ]]; then
    echo "ERROR: Unsupported OS detected: $os_name $os_version"
    exit 1
fi

echo ""
echo "WARNING:"
echo "This script [setup-broker.sh] will install and configure a TLS secured Mosquitto MQTT Broker."
read -p "Continue [y/N]:" ans
echo ""

if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
    echo "INFO: Aborting Script."
    exit 1
fi

# ==================== BEGIN MQTTS SETUP SCRIPT ====================

# Install the necessary packages
apt update
apt install -y mosquitto mosquitto-clients ufw


# Generate mqtt_conf_file
mqtt_config=""
mqtt_config+="# This file was generated by the setup-broker.sh script. See: https://github.com/acep-uaf/camio-mqtts\n"
mqtt_config+="# Mosquitto MQTT Broker Configuration File\n"
mqtt_config+="\n"
mqtt_config+="listener $mqtt_port $mqtt_host\n"
mqtt_config+="\n"
mqtt_config+="allow_anonymous $mqtt_allow_anon\n"
if [ $mqtt_auth_status ]; then
    mqtt_config+="password_file $mqtt_passwd_file\n"
fi
mqtt_config+="\n"

if [ $mqtt_tls_status ]; then
    mqtt_config+="cafile $mqtt_tls_ca_cert\n"
    mqtt_config+="certfile $mqtt_tls_server_cert\n"
    mqtt_config+="keyfile $mqtt_tls_server_key\n"
    mqtt_config+="\n"
fi

# echo "DEBUG: mqtt_config"
# echo -e "$mqtt_config"

# Configure MQTT Passwords
if [ $mqtt_auth_status ]; then
  if [ ! -f $mqtt_passwd_file ]; then
    echo ""
    echo "INFO: Creating Mosquitto Password File: $mqtt_passwd_file"
    echo "Please enter a password for the user: $mqtt_user"
    mosquitto_passwd -c $mqtt_passwd_file $mqtt_user

    # Set the permissions on the password file
    chmod 600 $mqtt_passwd_file
    chown mosquitto:mosquitto $mqtt_passwd_file
  fi
fi


# Create a self-signed certificate
# If either file is missing: $mqtt_tls_ca_key, $mqtt_tls_ca_cert, $mqtt_tls_server_key or $mqtt_tls_server_cert
if [ ! -f $mqtt_tls_ca_key ] || [ ! -f $mqtt_tls_ca_cert ] || [ ! -f $mqtt_tls_server_key ] || [ ! -f $mqtt_tls_server_cert ]; then
  echo ""
  echo "INFO: Creating Self-Signed Certificate"
  cert_subject="/C=$mqtt_cert_C/ST=$mqtt_cert_ST/L=$mqtt_cert_L/O=$mqtt_cert_O/OU=$mqtt_cert_OU/CN=$mqtt_cert_CN"
  echo "DEBUG: cert_subject: $cert_subject"
  
  # Create the directories for the certificate files if they do not exist
  mkdir -p $(dirname $mqtt_tls_ca_cert) $(dirname $mqtt_tls_ca_key) $(dirname $mqtt_tls_server_cert) $(dirname $mqtt_tls_server_key)
  
  # Generate the CA key and certificate files
  openssl genpkey -algorithm RSA -out $mqtt_tls_ca_key
  openssl req -new -x509 -key $mqtt_tls_ca_key -out $mqtt_tls_ca_cert -days $mqtt_cert_days -subj "$cert_subject"
  
  # Generate the server key and CSR
  openssl genpkey -algorithm RSA -out $mqtt_tls_server_key
  openssl req -new -key $mqtt_tls_server_key -out $mqtt_tls_server_csr -subj "$cert_subject"
  
  # Sign the server CSR with the CA certificate and key
  openssl x509 -req -in $mqtt_tls_server_csr -CA $mqtt_tls_ca_cert -CAkey $mqtt_tls_ca_key -CAcreateserial -out $mqtt_tls_server_cert -days $mqtt_cert_days
  
  # Set the permissions on the certificate files
  chmod 600 $mqtt_tls_ca_key $mqtt_tls_ca_cert $mqtt_tls_server_cert $mqtt_tls_server_key
  chown mosquitto:mosquitto $mqtt_tls_ca_key $mqtt_tls_ca_cert $mqtt_tls_server_cert $mqtt_tls_server_key
fi


# Configure the Mosquitto Broker
echo ""
echo "INFO: Configuring Mosquitto Broker: $mqtt_conf_file"
echo -e $mqtt_config > $mqtt_conf_file

# Set the permissions on the configuration file
chmod 644 $mqtt_conf_file
chown mosquitto:mosquitto $mqtt_conf_file

# Configure the UFW Firewall
echo ""
echo "INFO: Configuring UFW Firewall"
ufw allow $mqtt_port/tcp

# Enable and Start the Mosquitto Broker
echo ""
echo "INFO: Enabling and Starting Mosquitto Broker"
systemctl enable mosquitto

# Restart the Mosquitto Broker
echo ""
echo "INFO: Restarting Mosquitto Broker"
systemctl restart mosquitto

# Check the status of the Mosquitto Broker
echo ""
echo "INFO: Checking the status of the Mosquitto Broker"
systemctl status mosquitto