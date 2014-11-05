#!/bin/bash
########################################################################
#
# This script will install and execute all steps required to setup an
# OpenLDAP server for use with Virtualmin.
#
# Created by: Dustin Schreiber (http://www.dustinschreiber.me)
# Contributors: Logan Merrill (http://www.airshock.net)
# Created: November, 5th 2014 at 11:27 AM EST
#
# Copyright (C) 2014 Dustin Schreiber
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licensess>.
#
########################################################################

# Colour and formatting
cf_resetall=$'\e[0m\e[39m'
cf_resetf=$'\e[0m'
cf_resetc=$'\e[39m'
cf_bold=$'\e[1m'
cf_under=$'\e[4m'
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
cf_cyan=$'\e[36m'
cf_lcyan=$'\e[96m'

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

## Variables
webmin_latest_rpm="http://prdownloads.sourceforge.net/webadmin/webmin-1.710-1.noarch.rpm"
webmin_latest_deb="http://prdownloads.sourceforge.net/webadmin/webmin_1.710_all.deb"

supported_os=("CentOS Linux 7", "Ubuntu 14.04")

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
		printf "$cf_resetall"
		return 0
	else
		printf "$cf_resetall"
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
			printf "$cf_cyan%s" "Please enter y or n: $cf_lmagenta"
			;;
		esac
	done
}

# Displays a spinner while a command is busy
# runner cmd/$1 description/$2
runner () {
	cmd=$1
	echo "$2 in progress...$cf_yellow"
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
	printf "$1$cf_green succeeded!$cf_resetall\n"
}

# Displays error message
# error what_went_wrong
error() {
	printf "$1$cf_lred failed!$cf_resetall\n"
}

# download()
# Downloads using system tool (wget, curl, etc)
download() {
	str="Download of"
	if $download $1
	then
		success "$cf_lcyan$str $cf_lyellow$1$cf_resetall"
  	return $?
	else
		error "$cf_lcyan$str $cf_lyellow$1$cf_resetall"
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
	str="System update"
	if ! runner "$update" "$cf_lcyan$str"; then
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
		printf "\n\n$cf_red%s" "[Terminating...]"
		echo "$cf_resetall"
		exit $1
	elif [ "$1" == 0 ] || [ "$1" = "" ]; then
		printf "$cf_resetall"
		exit 0
	fi
}

ctrl_c() {
        term 1
}

# Outputs [y/n] in a colored format
yn() {
	printf " $cf_resetall%s[%sy%s/%sn%s]%s: %s" "$cf_blue" "$cf_green" "$cf_blue" "$cf_red" "$cf_blue" "$cf_resetall" "$cf_lmagenta"
}
## End Functions

## Only root can run this
printf "$cf_lcyan%s" "Checking if script was ran as root user..."
id | grep "uid=0(" >/dev/null
if [ "$?" = "0" ]; then
	echo "$cf_green Yes!"
else
	error "$cf_lred\nFatal Error: This script must be run as root! Execution"
	term 1
fi
## End root user detection


## OS Detection
source /etc/os-release
os_str="$NAME $VERSION_ID"
if in_array "$os_str" "${supported_os[@]}"; then
	echo "$cf_green$os_str$cf_lcyan detected and supported!$cf_resetc"
else
	echo "$cf_lred$os_str$cf_lcyan detected but not supported!$cf_resetc"
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
printf "$cf_lblue%s" "Checking for HTTP client..."
if [ -x "/usr/bin/curl" ]; then
	download="/usr/bin/curl -s -O "
elif [ -x "/usr/bin/wget" ]; then
	download="/usr/bin/wget -nv"
elif [ -x "/usr/bin/fetch" ]; then
	download="/usr/bin/fetch"
else
	printf "$cf_lred%s" "No web download program available: Please install curl, wget, or fetch and try again."
	term 1
fi
printf "$cf_lgreen Found $download\n"

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
str="Update system? (Recommended)"
if askyn "$cf_cyan$str"; then
	update
else
	printf "\r\r$cf_yellow%s$cf_resetc\n" "Not updating!"
fi

# Find out if user wants Virtualmin GPL/Pro or Webmin
printf "$cf_cyan%s\n" "Would you like me to install Virtualmin or Webmin for you?"
printf "\t$cf_blue%s) $cf_lblue%s\t\t%s\n" "Webmin" "(Recommended for server)"
printf "\t$cf_blue%s) $cf_lblue%s\t\t%s\n" "Virtualmin GPL" "(Recommended for client)"
printf "\t$cf_blue%s) $cf_lblue%s\t\t%s\n" "Virtualmin Pro" "(Recommended for client)"
echo
printf "$cf_cyan%s$cf_lmagenta" "Selection [1-3]:"
while read line; do
	case $line in
		1)
		
		break;
		;;
		2)
		
		break;
		;;
		3)
		
		break;
		;;
		*)
		printf "$cf_cyan%s" "Please enter a number [1,2,3]: $cf_lmagenta"
		;;
	esac
done



echo
printf "$cf_lcyan%s$cf_resetc\n" "Ready to install packages!"
str="You want to make this system a $cf_green$cf_bold$mode$cf_resetf$cf_cyan correct?"
if ! askyn "$cf_cyan$str"; then
	printf "$cf_red%s " "Please re-run this script using the proper argument!"
	term 1
fi

### CLIENT SETUP
if [ $mode = "client" ]; then

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
	
fi
### END CLIENT SETUP

### SERVER SETUP
if [ $mode = "client" ]; then



fi
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
