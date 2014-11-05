#!/bin/bash
########################################################################
#                                                                      #
# This script will install and execute all steps required to setup an  #
# OpenLDAP server for use with Virtualmin.                             #
#                                                                      #
# Created by: Dustin Schreiber (http://www.dustinschreiber.me)         #
# Created: November, 5th 2014 at 11:27 AM EST                          #
# Last Updated: Never                                                  #
#                                                                      #
# Copyright (C) 2014 Dustin Schreiber                                  #
#                                                                      #
# This program is free software: you can redistribute it and/or modify #
# it under the terms of the GNU General Public License as published by #
# the Free Software Foundation, either version 3 of the License, or    #
# (at your option) any later version.                                  #
#                                                                      #
# This program is distributed in the hope that it will be useful,      #
# but WITHOUT ANY WARRANTY; without even the implied warranty of       #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        #
# GNU General Public License for more details.                         #
#                                                                      #
# You should have received a copy of the GNU General Public License    #
# along with this program.  If not, see <http://www.gnu.org/licensess>.#
#                                                                      #
########################################################################

## Help and usage
while [ "$1" != "" ]; do
	case $1 in
		-h | --help | "help")
			echo "Usage: `basename $0` [OPTION]"
			echo "  -c --client	client	: Installs and prepares a client system"
			echo "  -s --server	server	: Installs and prepares an OpenLDAP server"
			echo "  -h --help	help	: This message"
			exit 0
		;;
		-c | --client | client)
			mode="client"
			break
		;;
		-s | --server | server)
			mode="server"
			break
		;;
		*)
			echo "Invalid selection!"
			echo "`$0 --help`"
			exit 1
		;;
	esac
	shift
done
## End help and usage

# trap ctrl-c and call ctrl_c() (We have cleanup to do most likely)
trap ctrl_c INT

# See if user made a selection
if [ "$mode" = "" ]; then
	echo "Missing selection!"
	echo
	echo "`$0 --help`"
	exit 1
fi

# Only root can run this
id | grep "uid=0(" >/dev/null
if [ "$?" != "0" ]; then
	uname -a | grep -i CYGWIN >/dev/null
	if [ "$?" != "0" ]; then
		echo "Fatal Error: This script must be run as root!"
		exit 1
	fi
fi

## Variables
webmin_latest_rpm="http://prdownloads.sourceforge.net/webadmin/webmin-1.710-1.noarch.rpm"
webmin_latest_deb="http://prdownloads.sourceforge.net/webadmin/webmin_1.710_all.deb"

supported_os=("CentOS Linux 7", "Ubuntu 14.04")

# Color and formatting
cf_resetall=$'\e[0m\e[39m'
cf_resetf=$'\e[0'
cf_resetc=$'\e[39m'
cf_bold=$'\e[1m'
cf_green=$'\e[32m'
cf_lgreen=$'\e[92m'
cf_blue=$'\e[34m'
cf_lblue=$'\e[96m'
cf_red=$'\e[31m'
cf_lred=$'\e[91m'
cf_yellow=$'\e[33m'
cf_lyellow=$'\e[93m'
cf_magenta=$'\e[35m'
cf_lmagenta=$'\e[95m'

# String replacements
misc_schema="sed \"s/  DESC 'Internet local mail recipient' SUP top AXUILIARY MAY ( mailLocalAddres/    DESC 'Internet local mail recipient' SUP top STRUCTURAL MAY ( mailLocalAddres/g\""

# Packages, Server
# CentOS
rhpkgs="openldap openldap-servers openldap-clients perl-LDAP"
# Ubuntu
ubpkgs="slapd php-net-ldap"

# Packages, Client
# Red Hat-based systems
rhpkgs_c="openldap-clients"
# Ubuntu
ubpkgs_c=""

## End Variables


## Functions

# Asks a yes or no and gets response
# Used because coloring user selection requires reset
askyn() {
	printf "$1"
	yn
	if yesno; then
		echo -e "$cf_resetall"
		return 0
	else
		echo -e "$cf_resetall"
		return 1
	fi
}

# Handles a yes or no question
yesno() {
	while read line; do
		case $line in
			y|Y|Yes|YES|yes|yES|yEs|YeS|yeS) return 0
			;;
			n|N|No|NO|no|nO) return 1
			;;
			*)
			printf "\nPlease enter y or n: "
			;;
		esac
	done
}

# Displays a spinner while a command is busy
# runner cmd/$1 description/$2
runner () {
	cmd=$1
	echo " $2 in progress..."
	touch busy
	$tempdir/spinner busy &
	if $cmd &> /dev/null; then
		rm busy
		sleep 1
		success "$cmd:"
		return 0
	else
		rm busy
		sleep 1
		echo "$cmd failed.  Error (if any): $?"
		return 1
	fi
}

# Displays succeeded message
# success what_was_successful
success() {
	echo "$cf_green$1 succeeded!$cf_resetall"
}

# Displays error message
# error what_went_wrong
error() {
	echo "$cf_lred$1 failed!$cf_resetall"
}

# download()
# Downloads using system tool (wget, curl, etc)
download() {
	if $download $1
	then
		success "Download of $1"
  	return $?
	else
		error "Download of $1"
	fi
}

# Check if a value exists in an array
# @param $1 mixed  Needle  
# @param $2 array  Haystack
# @return  Success (0) if value exists, Failure (1) otherwise
# Usage: in_array "$needle" "${haystack[@]}"
# See: http://fvue.nl/wiki/Bash:_Check_if_array_element_exists
in_array() {
	local hay needle=$1
	for hay; do
		[[ $hay == $needle ]] && return 0
	done
	return 1
}

update() {
	if ! runner "$update update" "Updating system"; then
		error "Updating system"
		return 1
	fi
	return 0
}

install() {
	if ! runner "$install $1" "Installing $2"; then
		error "Installing packages"
		return 1
	fi
	return 0
}

cleanup() {
	rm -rf $tempdir
}

term() {
	cleanup
	if [[ "$1" != "0" ]]; then
		echo
		echo "Terminating..."
		exit $1
	elif [ "$1" == 0 ] || [ "$1" = "" ]; then
		exit 0
	fi
}

ctrl_c() {
        term 1
}

# Outputs [y/n] in a colored format
yn() {
	printf " %s[%sy%s/%sn%s]%s: %s" "$cf_blue" "$cf_green" "$cf_blue" "$cf_red" "$cf_blue" "$cf_resetc" "$cf_lmagenta"
}
## End Functions


## OS Detection
source /etc/os-release
os_str="$NAME $VERSION_ID"
if in_array "$os_str" "${supported_os[@]}"; then
	echo "$os_str detected and supported!"
else
	echo "$os_str detected but not supported!"
	term 1
fi
## End OS Detection


## Prep

# Find temp directory
if [ "$TMPDIR" = "" ]; then
	TMPDIR=/tmp
fi
if [ "$tempdir" = "" ]; then
	tempdir=$TMPDIR/.setupldap-$$
	if [ -e "$tempdir" ]; then
		rm -rf $tempdir
	fi
	mkdir $tempdir
fi
cd $tempdir

# Check for wget or curl or fetch
printf "Checking for HTTP client..."
if [ -x "/usr/bin/curl" ]; then
	download="/usr/bin/curl -s -O "
elif [ -x "/usr/bin/wget" ]; then
	download="/usr/bin/wget -nv"
elif [ -x "/usr/bin/fetch" ]; then
	download="/usr/bin/fetch"
else
	echo "No web download program available: Please install curl, wget, or fetch"
	echo "and try again."
	term 1
fi
printf "found $download\n"

# Download spinner
download http://software.virtualmin.com/lib/spinner
chmod +x spinner

# Determines which OS and sets variables as needed
case $os_str in
	"CentOS Linux 7")
		pkgs=$rhpkgs
		install="/usr/bin/yum -y -d 2 install"
		update="/usr/bin/yum -y -d 2 update"
	;;
	"Ubuntu 14.04")
		pkgs=$ubpkgs
		runner "apt-get update" "Updating apt-get..."
		install="/usr/bin/apt-get --config-file apt.conf.noninteractive -y --force-yes install"
		update="/usr/bin/apt-get -y upgrade"
		export DEBIAN_FRONTEND=noninteractive
		# Get the noninteractive apt-get configuration file (this is 
		# stupid... -y ought to do all of this).
		download "http://software.virtualmin.com/lib/apt.conf.noninteractive"
	;;
esac

## End prep


## Get user input

#printf "Update system? (Recommended)" && yn
if askyn "Update system? (Recommended)"; then
	update
else
	echo "Not updating!"
fi

echo
echo "Ready to install packages!"
printf "%b" "You want to make this system a $cf_green$cf_bold$mode$cf_resetall correct?" && yn
if ! yesno; then
	term 1
fi

### CLIENT SETUP
install_cmd="$install $pkgs_c"
if ! runner $install_cmd; then
	error "Installation"
	echo
	echo "Please try running the following command manually and correcting any errors produced:"
	echo
	echo "$install_cmd"
	echo
	term 1;
fi

### END CLIENT SETUP

### SERVER SETUP


### END SERVER SETUP

#install_cmd="$install $pkgs"
#if ! runner $install_cmd; then
#	error "OpenLDAP setup"
#fi

#if ! runner "download $webminLatest" "Fetching Webmin"; then
#	error "Webmin download"
#fi

#download "http://software.virtualmin.com/lib/RPM-GPG-KEY-webmin" "Webmin package signing keys..."

term
exit 0