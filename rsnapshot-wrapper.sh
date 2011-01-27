#!/bin/bash
###################################
###### Introduction ###############
# This script uses password-protected public key authentication.
# It makes use of:
#  * ssh-agent
#  * keychain (http://www.funtoo.org/en/security/keychain/intro/)
#  * rsnapshot (http://rsnapshot.org/)
#  * other common *nix commands

# Script takes 2 arguments. Argument mismatch returns an error.
if [ $# -ne 2 ]
then
  echo "$0 takes two argumetnts. If not supplied a help message is shown."
  echo "$0 [config] [backup type]"
  echo '[config]: assumed location (/etc/rsnapshot/rsnapshot-[config].conf)'
  echo '[backup type]: hourly, daily... (parsed from configuration file)'
  exit 1
fi

###################################
######## Executables ##############
DATE=/bin/date
GREP=/bin/grep
CUT=/usr/bin/cut
TR=/usr/bin/tr
PING=/bin/ping
NETSTAT=/bin/netstat
SLEEP=/bin/sleep
RSNAPSHOT=/usr/bin/rsnapshot

###################################
######## Variables ################
# Prefixes
PINGPREFIX='-c 1 -w 5'
NETSTATPREFIX='-tl'

HOST="$1"
BACKUPTYPE="$2"
CURRENTDATE=$($DATE +%F)

# Path to configuration file 
CONFIG="/etc/rsnapshot/rsnapshot-$HOST.conf"

# TRIES defines how many times connectivity has been tested 
# MAXTRIES is the amount of times the script is allowed to run. 
# MAXTRIES*SLEEPTIME seconds
TRIES=0
MAXTRIES=12
# SLEEPTIME defines wait time between each try, in seconds.
SLEEPTIME=1800

###################################
############ Functions ############

# Verifies that arguments are correct
verifyArguments() {
# Verify that first argument is correct.
  if [ ! -r $CONFIG ]; then
    echo 'First argument is invalid.'
    echo "Configuration file is missing or unreadable ($CONFIG). Please check your input."
    exit 1
  fi
# Verify the second argument by looping through $BACKUPTYPES (set in setInfoFromConf()).
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

# sleepTime() waites for $SLEEPTIME in case remote host isn't up and increments $TRIES with 1.
sleepTime() {
  $SLEEP $SLEEPTIME
  TRIES=$(($TRIES+1))
}

# noMoreTries() is executed if there is no more attempts to be made to contact remote host
# Alerts administrator (mail set by cron) and exits script.
noMoreTries() {
    echo "$BACKUPTYPE backup of $HOST failed."
    echo "Date: $CURRENTDATE."
    echo "Remote host is not responding."
    exit 1
}

# executeRsnapshot is executed if remote host is up. It runs rsnapshot and sets TRIES to $MAXTRIES to avoid any wierd loops.
# Exits gracefully.
executeRsnapshot() {
  $RSNAPSHOT -c $CONFIG $BACKUPTYPE
  TRIES=$MAXTRIES
  exit 0
}

###################################
############ Execution ############

parseConfigurationFile;
verifyArguments;

setEnv;

# Remote host connectivity is only needed for the first interval entry.
# http://rsnapshot.org/howto/1.2/rsnapshot-HOWTO.en.html#how_it_works
# If it isn't "daily" run executeRsnapshot directy since connectivity is not needed.
if [ $BACKUPTYPE != ${BACKUPTYPES[0]} ]; then
  executeRsnapshot;
fi

while [ $TRIES -lt $MAXTRIES ]; do
# Remote host is localhost. Reverse SSH tunnel == check if system is listening to designated port.
  if [ $HOSTCONF == 'localhost' ]; then
    $NETSTAT $NETSTATPREFIX | $GREP ":$SSHTUNNELPORT" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      executeRsnapshot;
    else
      sleepTime;
    if [ $TRIES -eq $MAXTRIES ]; then
      noMoreTries;
    fi
  fi
  else
# Remote host isn't 'localhost'. Use ping to determine if host is up.
    $PING $PINGPREFIX $HOSTCONF >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      executeRsnapshot;
    else
      sleepTime;
      if [ $TRIES -eq $MAXTRIES ]; then
        noMoreTries;
      fi
    fi
  fi
done  
