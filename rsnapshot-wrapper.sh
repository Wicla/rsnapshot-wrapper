#!/bin/bash
####################### READ THIS INTRODUCTION #################################
# This script is a wrapper for rsnapshot. It makes it possible to use passphrase-protected public key authentication and more.
# See README for more.
#
# This script uses the following *nix programs.
#  * ssh-agent
#  * keychain (http://www.funtoo.org/en/security/keychain/intro/)
#  * rsnapshot (http://rsnapshot.org/)
#  * other common *nix commands

# Print help message if not the two required arguments is supplied.
if [ $# -ne 2 ]
then
  echo "$0 takes two argumetnts. If not supplied a help message is shown."
  echo "$0 [config] [backup type]"
  echo '[config]: assumed location (/etc/rsnapshot/rsnapshot-[config].conf)'
  echo '[backup type]: hourly, daily... (parsed from configuration file)'
  exit 1
fi

####################### Executables ############################################
DATE=/bin/date
GREP=/bin/grep
CUT=/usr/bin/cut
TR=/usr/bin/tr
PING=/bin/ping
RSNAPSHOT=/usr/bin/rsnapshot

####################### CONFIGURATION BEGINS HERE ##############################
PINGPREFIX='-c 1 -w 5'
NETSTATPREFIX='-tl'

HOST="$1"
BACKUPTYPE="$2"
CURRENTDATE=$($DATE +%F)

# Build path to configuration file.
CONFIG="/etc/rsnapshot/rsnapshot-$HOST.conf"

####################### CONFIGURATION ENDS HERE ################################

####################### Functions ##############################################

# verifyArguments verifies that arguments are correct.
verifyArguments() {
# Verify that first argument is correct.
  if [ ! -r $CONFIG ]; then
    echo 'First argument is invalid.'
    echo "Configuration file is missing or unreadable ($CONFIG). Please check your input."
    exit 1
  fi
# Verify the second argument by looping through $BACKUPTYPES (set in parseConfigurationFile()).
  PASS=
  for TYPE in ${BACKUPTYPES[@]}; do
    if [ $TYPE == $BACKUPTYPE ]; then
      PASS=0
    fi
  done
  if [ $PASS -ne 0 ]; then
    echo "Second argument is invalid. Please choose any of the following (parsed from $CONFIG): "
    echo "${BACKUPTYPES[@]}"
    exit 1
  fi
}

# parseConfigurationFile() fetches necessary info from $CONFIG
# HOSTCONF contains IP/hostname of remote host
# BACKUPTYPES contains all intervales
# SSHTUNNELPORT contains ssh_args port. Used in case localhost apears as remote host (user@localhost). (SSH reverse tunnel)
# TODO: Find a cleaner solution to get port number. 
parseConfigurationFile() {
  HOSTCONF=$($GREP -m 1 ^backup $CONFIG | $CUT -d@ -f2 | $CUT -d: -f1)
  BACKUPTYPES=( $($GREP ^interval $CONFIG | $CUT -f2) )
  SSHTUNNELPORT=$($GREP -E -o "\-p[[:space:]]??[[:digit:]]*?" $CONFIG | $CUT -dp -f2 | $TR -d '[[:space:]]')
}

# setEnv() makes sure the public key is known to the script
setEnv() {
  ENV=$HOME/.bashrc
  source $HOME/.keychain/$HOSTNAME-sh
}

# giveUp() is executed if there is no more attempts to be made to contact remote host$
# Alerts administrator (mail set by cron) and exits script.$
giveUp() {
    echo "$BACKUPTYPE backup of $HOST failed."
    echo "Date: $CURRENTDATE."
    echo "Remote host is not responding."
    exit 1
}

# executeRsnapshot is executed if remote host is up. It runs rsnapshot and sets TRIES to $MAXTRIES to avoid any wierd loops.
# Exits gracefully.
executeRsnapshot() {
  $RSNAPSHOT -c $CONFIG $BACKUPTYPE
  exit 0
}

####################### Execution ##############################################

# Call parseConfigurationFile to get all necessary information.
parseConfigurationFile;
# Verify that arguments are correct.
verifyArguments;
# Sent enviromental and load cached private key.
setEnv;

# Connectivity to remote host is only needed if the first interval entry is run.
# http://rsnapshot.org/howto/1.2/rsnapshot-HOWTO.en.html#how_it_works
# If $BACKUPTYPE isn't "daily" run executeRsnapshot directy since connectivity is not needed.
if [ $BACKUPTYPE != ${BACKUPTYPES[0]} ]; then
  executeRsnapshot;
fi

if [ $HOSTCONF == 'localhost' ]; then
# Remote host is localhost. Reverse SSH tunnel == check if system is listening to designated port.
  $NETSTAT $NETSTATPREFIX | $GREP ":$SSHTUNNELPORT" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    executeRsnapshot;
  else
    giveUp;
  fi
else
# Remote host isn't 'localhost'. Use ping to determine if host is up.
  $PING $PINGPREFIX $HOSTCONF >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    executeRsnapshot;
  else
    giveUp;
  fi
fi
