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
		-h | --help)
			echo "Usage: `basename $0` [OPTION]"
			echo " -c --client	 Install and prepare a client system"
			echo " -e --erase	 Erase packages for LDAP"
			echo " -h --help	 This message"
			echo " -r --remove	 Remove installed packages for LDAP"
			echo " -s --server	 Install and prepare an OpenLDAP server"
			echo " -u --uninstall	 Remove Virtualmin/Webmin"
			exit 0
		;;
		-c | --client)
			mode="client"
		;;
		-s | --server)
			mode="server"
			break
		;;
		-e | --erase)
			mode="erase"
		;;
		-r | --remove)
			mode="remove"
		;;
		-u | --uninstall)
			mode="uninstall"
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
str_misc_schema="sed \"s/  DESC 'Internet local mail recipient' SUP top AXUILIARY MAY ( mailLocalAddres/    DESC 'Internet local mail recipient' SUP top STRUCTURAL MAY ( mailLocalAddres/g\""

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

spinner() {
	i=1
	sp="/-\|"
	while [ -e $1 ]; do
		printf "\b${sp:i++%${#sp}:1}"
		sleep .1
	done
	printf "\b"
}

result() {
	success="$cf_lgreen SUCCESS "
	error="$cf_lred  ERROR  "
	warning="$cf_lyellow WARNING "
	printf "\n\b\b\b\b\b\b\b\b\b\b\b"
	printf "$cf_blue%s" "["
	if [ "$1" = 0 ]; then
		printf "$success"
	elif [ "$1" = 1 ]; then
		echo "ERROR"
		printf "$error"
	elif [ "$1" = 2 ]; then
		printf "$warning"
	fi
	printf "$cf_blue%s$cf_resetall\n" "]"
}

# Displays a spinner while a command is busy
# runner cmd/$1 description/$2
runner () {
	cmd=$1
	echo "$2 in progress..."
	touch busy
	spinner busy &
	if $cmd &> /dev/null; then
		rm busy
		sleep .2
		return 0
	else
		rm busy
		sleep .2
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
	if $download $1 $2
	then
		success "$cf_lcyan$str $cf_lyellow$3$cf_resetall"
  	return $?
	else
		error "$cf_lcyan$str $cf_lyellow$3$cf_resetall"
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
		result 1
		return 1
	fi
	result 0
	return 0
}

install() {
	if ! runner "$install $1" "Installing $2"; then
		result 1
		return 1
	fi
	result 0
	return 0
}

cleanup() {
	rm -rf $tempdir
}

term() {
	cleanup
	if [ "$1" != 0 ]; then
		printf "\n$cf_red%s" "[Terminating...]"
		echo "$cf_resetall"
		exit $1
	elif [ "$1" = 0 ] || [ "$1" = "" ]; then
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

installvw() {
	if [ "$install_virtualmin" = 1 ]; then
		# Webmin
		if [ $pkg_sys = "yum" ]; then
			download "webmin.rpm" "$webmin_latest_rpm" "Webmin RPM"
			cmd="/bin/rpm -ivh $tempdir/webmin.rpm"
			if $cmd; then
				return 0
			else
				return 1
			fi
		elif [ $pkg_sys = "apt-get" ]; then
			webdeps="perl libnet-ssleay-perl openssl libauthen-pam-perl libpam-runtime libio-pty-perl apt-show-versions python"
			install "$webdeps" "Webmin dependencies: $webdeps"
			download "webmin.deb" "$webmin_latest_deb" "Webmin DEB"
			cmd="dpkg --install $tempdir/webmin.deb"
			if $cmd; then
				return 0
			else
				return 1
			fi
		fi
	elif [ "$install_virtualmin" = 2 ]; then
		# Virtualmin GPL
		download "install.sh" "http://software.virtualmin.com/gpl/scripts/install.sh" "Virtualmin GPL Installer"
		cmd="/bin/sh $tempdir/install.sh"
		if $cmd; then
			return 0
		else
			return 1
		fi
	elif [ "$install_virtualmin" = 3 ]; then
		# Get license and serial for download
		printf "$cf_lcyan%s\n" "Enter your serial number and license key:"
		echo "(I will download the customized Virtualmin install.sh script for you.)"
		printf "$cf_lyellow%s\n" "WARNING: Your serial number and key ARE NOT validated!"
		echo -e "\tMake sure you type them correctly!"
		printf "$cf_cyan%s $cf_lmagenta" "Serial Number:"
		read serial
		printf "$cf_cyan%s $cf_lmagenta" "License Key:"
		read key
		url="http://software.virtualmin.com/cgi-bin/install.cgi?serial=$serial&key=$key"
		download  "install.sh" "$url" "Virtualmin Pro Installer"
		cmd="/bin/sh $tempdir/install.sh"
		if $cmd; then
			return 0
		else
			return 1
		fi
	fi
}
## End Functions

## Only root can run this
printf "$cf_lcyan%s" "Checking if script was ran as root user..."
id | grep "uid=0(" >/dev/null
if [ "$?" = 0 ]; then
	result "0"
else
	result 1
	error "$cf_lred\nFatal Error: This script must be run as root! Execution"
	term 1
fi
## End root user detection


## OS Detection
source /etc/os-release
os_str="$NAME $VERSION_ID"
printf "$cf_lcyan%s$cf_lyellow$os_str $cf_lgreen%s" "Checking if running supported OS... " "detected!"
if in_array "$os_str" "${supported_os[@]}"; then
	result 0
else
	result 1
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
	wdp="curl"
	download="/usr/bin/curl -s -L -o"
elif [ -x "/usr/bin/wget" ]; then
	wdp="wget"
	download="/usr/bin/wget -nv -O"
else
	printf "$cf_lred%s" "None found!"
	result "1"
	printf "$cf_lred%s" "Please install curl or wget and try again."
	term 1
fi
printf "$cf_lgreen Found $cf_lyellow$wdp$cf_lgreen!"
result "0"

# Determines which OS and sets variables as needed
case $os_str in
	"CentOS Linux 7")
		pkg_sys="yum"
		pkgs=$rhpkgs
		pkgs_c=$rhpkgs_c
		install="/usr/bin/yum -y -d 2 install"
		update="/usr/bin/yum -y -d 2 update"
	;;
	"Ubuntu 14.04")
		pkg_sys="apt-get"
		pkgs=$ubpkgs
		pkgs_c=$ubpkgs_c
		runner "apt-get update" "Updating apt-get..."
		install="/usr/bin/apt-get --config-file apt.conf.noninteractive -y --force-yes install"
		update="/usr/bin/apt-get -y upgrade"
		export DEBIAN_FRONTEND=noninteractive
		# Get the noninteractive apt-get configuration file (this is 
		# stupid... -y ought to do all of this).
		download "apt.conf.noninteractive" "http://software.virtualmin.com/lib/apt.conf.noninteractive" "apt-get non-interactive conf file"
	;;
esac

## End prep


## Erase/remove/uninstall
case $mode in
	"erase")
		if askyn "Are you sure you want to$cf_bold$cf_lred erase$cf_resetf$cf_lgreen all LDAP packages?"; then
			str="Not Implemented!"
			error "$cf_lred$str Execution"
			term 1
		else
			printf "$cf_lcyan%s\n" "Aborting..."
			term 0
		fi
	;;
	"remove")
		if askyn "Are you sure you want to$cf_bold$cf_lred remove$cf_resetf$cf_lgreen all LDAP packages?"; then
			str="Not Implemented!"
			error "$cf_lred$str Execution"
			term 1
		else
			printf "$cf_lcyan%s\n" "Aborting..."
			term 0
		fi
	;;
	"uninstall")
		if askyn "Are you sure you want to$cf_bold$cf_lred uninstall$cf_resetf$cf_lgreen Virtualmin/Webmin packages?"; then
			str="Not Implemented!"
			error "$cf_lred$str Execution"
			term 1
		else
			printf "$cf_lcyan%s\n" "Aborting..."
			term 0
		fi
	::
esac
## END Erase/remove/uninstall


## Get user input

str="Update system? (Recommended)"
if askyn "$cf_cyan$str"; then
	update
else
	printf "\b"
	result 2
	printf "$cf_yellow%s$cf_resetc\n\n" "Not updating!"
fi

printline() {
	echo -e "\t$cf_blue$1) $cf_lyellow$2$cf_lblue$3"
}

# Find out if user wants Virtualmin GPL/Pro or Webmin
printf "$cf_cyan%s\n" "Would you like me to install Virtualmin or Webmin for you?"
printline "1" "Webmin" "\t\t(Recommended for server)"
printline "2" "Virtualmin GPL" "\t(Recommended for client)"
printline "3" "Virtualmin Pro" "\t(Recommended for client)"
str="Nothing"
printline "n" "$cf_lred$str" "\t\t(You will have to install one yourself)"
printf "$cf_cyan%s$cf_lmagenta" "Selection [1-3 / n]: "
while read line; do
	case $line in
		1) # Webmin
			install_virtualmin=1
			vw_selection="Webmin"
			break
		;;
		2) # GPL
			install_virtualmin=2
			vw_selection="Virtualmin GPL"
			break
		;;
		3) # Pro
			install_virtualmin=3
			vw_selection="Virtualmin Pro"
			break
		;;
		"n" | "N" | "No" | "nO" | "NO") # Nothing
			install_virtualmin=0
			break
		;;
		*)
			printf "$cf_cyan%s" "Please enter a valid selection [1|2|3 / n]: $cf_lmagenta"
			break
		;;
	esac
done

printf "\n$cf_green$cf_under%s$cf_resetall\n" "Ready to install packages!"

### CLIENT SETUP
if [ "$mode" = "client" ]; then
	#install_cmd="$install $pkgs_c"
	install_cmd="sleep 2"
	str="Installing packages:"
	if runner "$install_cmd" "$cf_lblue$str $cf_lyellow$pkgs_c"; then
		result 0
	else
		result 1
		echo
		echo "Please try running the following command manually and correcting any errors produced:"
		echo
		echo "$install_cmd"
		echo
		term 1;
	fi
	# Install desired Virtualmin/Webmin package
	if [ "$install_virtualmin" != "0" ]; then
		echo "Doing"
		if runner "${installvw}" "$cf_lyellow$vw_selection$cf_lcyan installation"; then
			result 0
		else
			result 1
		fi
	else
		printf "$cf_yellow$cf_bold%s\n" "Virtualmin/Webmin installation rejected!"
		printf "$cf_resetf%s$cf_resetall\n" "Unless you know what you are doing, I suggest you install Webmin!"
	fi
fi
### END CLIENT SETUP

### SERVER SETUP
if [ "$mode" = "server" ]; then
	term 0
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