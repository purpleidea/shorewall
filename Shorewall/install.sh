#!/bin/sh
#
# Script to install Shoreline Firewall
#
#     This program is under GPL [http://www.gnu.org/copyleft/gpl.htm]
#
#     (c) 2000,2001,2002,2003,2004 - Tom Eastep (teastep@shorewall.net)
#
#       Shorewall documentation is available at http://shorewall.net
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of Version 2 of the GNU General Public License
#       as published by the Free Software Foundation.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA
#

VERSION=2.5.5

usage() # $1 = exit status
{
    ME=$(basename $0)
    echo "usage: $ME"
    echo "       $ME -v"
    echo "       $ME -h"
    exit $1
}

run_install()
{
    if ! install $*; then
	echo
	echo "ERROR: Failed to install $*"
	exit 1
    fi
}

cant_autostart()
{
    echo
    echo  "WARNING: Unable to configure shorewall to start"
    echo  "           automatically at boot"
}

backup_directory() # $1 = directory to backup
{
    if [ -d $1 ]; then
	if cp -a $1  ${1}-${VERSION}.bkout ; then
	    echo
	    echo "$1 saved to ${1}-${VERSION}.bkout"
	else
	    exit 1
	fi
    fi
}
    
backup_file() # $1 = file to backup
{
    if [ -z "$PREFIX" -a -f $1 -a ! -f ${1}-${VERSION}.bkout ]; then
	if (cp $1 ${1}-${VERSION}.bkout); then
	    echo
	    echo "$1 saved to ${1}-${VERSION}.bkout"
        else
	    exit 1
        fi
    fi
}

delete_file() # $1 = file to delete
{
    if [ -z "$PREFIX" -a -f $1 -a ! -f ${1}-${VERSION}.bkout ]; then
	if (mv $1 ${1}-${VERSION}.bkout); then
	    echo
	    echo "$1 moved to ${1}-${VERSION}.bkout"
        else
	    exit 1
        fi
    fi
}

install_file() # $1 = source $2 = target $3 = mode
{
    run_install $OWNERSHIP -m $3 $1 ${2}
}

install_file_with_backup() # $1 = source $2 = target $3 = mode
{
    backup_file $2
    run_install $OWNERSHIP -m $3 $1 ${2}
}

#
# Parse the run line
#
# DEST is the SysVInit script directory
# INIT is the name of the script in the $DEST directory
# RUNLEVELS is the chkconfig parmeters for firewall
# ARGS is "yes" if we've already parsed an argument
#
ARGS=""

if [ -z "$DEST" ] ; then
	DEST="/etc/init.d"
fi

if [ -z "$INIT" ] ; then
	INIT="shorewall"
fi

if [ -z "$RUNLEVELS" ] ; then
	RUNLEVELS=""
fi

if [ -z "$OWNER" ] ; then
	OWNER=root
fi

if [ -z "$GROUP" ] ; then
	GROUP=root
fi

while [ $# -gt 0 ] ; do
    case "$1" in
	-h|help|?)
	    usage 0
	    ;;
        -v)
	    echo "Shorewall Firewall Installer Version $VERSION"
	    exit 0
	    ;;
	*)
	    usage 1
	    ;;
    esac
    shift
    ARGS="yes"
done

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin:/usr/local/sbin

#
# Determine where to install the firewall script
#
DEBIAN=

OWNERSHIP="-o $OWNER -g $GROUP"

if [ -n "$PREFIX" ]; then
	if [ `id -u` != 0 ] ; then
	    echo "Not setting file owner/group permissions, not running as root."
	    OWNERSHIP=""
	fi

	install -d $OWNERSHIP -m 755 ${PREFIX}/sbin
	install -d $OWNERSHIP -m 755 ${PREFIX}${DEST}
elif [ -d /etc/apt -a -e /usr/bin/dpkg ]; then
    DEBIAN=yes
elif [ -f /etc/slackware-version ] ; then
    DEST="/etc/rc.d"
    INIT="rc.firewall"
elif [ -f /etc/arch-release ] ; then 
      DEST="/etc/rc.d"
      INIT="shorewall"
      ARCHLINUX=yes
fi

#
# Change to the directory containing this script
#
cd "$(dirname $0)"

echo "Installing Shorewall Version $VERSION"

#
# First do Backups
#

#
# Check for /etc/shorewall
#
if [ -d ${PREFIX}/etc/shorewall ]; then
    first_install=""
    backup_directory ${PREFIX}/etc/shorewall
    backup_directory ${PREFIX}/usr/share/shorewall
    backup_directory ${PREFIX}/var/lib/shorewall
else
    first_install="Yes"
fi

install_file_with_backup shorewall ${PREFIX}/sbin/shorewall 0544

echo
echo "shorewall control program installed in ${PREFIX}/sbin/shorewall"

#
# Install the Firewall Script
#
if [ -n "$DEBIAN" ]; then
    install_file_with_backup init.debian.sh /etc/init.d/shorewall 0544
else
    install_file_with_backup init.sh ${PREFIX}${DEST}/$INIT 0544
fi

echo
echo  "Shorewall script installed in ${PREFIX}${DEST}/$INIT"

#
# Create /etc/shorewall, /usr/share/shorewall and /var/shorewall if needed
#
mkdir -p ${PREFIX}/etc/shorewall
mkdir -p ${PREFIX}/usr/share/shorewall
mkdir -p ${PREFIX}/var/lib/shorewall
#
# Install the config file
#
if [ ! -f ${PREFIX}/etc/shorewall/shorewall.conf ]; then
   run_install $OWNERSHIP -m 0744 shorewall.conf ${PREFIX}/etc/shorewall/shorewall.conf
   echo
   echo "Config file installed as ${PREFIX}/etc/shorewall/shorewall.conf"
fi

if [ -n "$ARCHLINUX" ] ; then

   sed -e 's!LOGFILE=/var/log/messages!LOGFILE=/var/log/messages.log!' -i ${PREFIX}/etc/shorewall/shorewall.conf
fi 
#
# Install the zones file
#
if [ ! -f ${PREFIX}/etc/shorewall/zones ]; then
    run_install $OWNERSHIP -m 0744 zones ${PREFIX}/etc/shorewall/zones
    echo
    echo "Zones file installed as ${PREFIX}/etc/shorewall/zones"
fi

#
# Install the functions file
#

install_file functions ${PREFIX}/usr/share/shorewall/functions 0444

echo
echo "Common functions installed in ${PREFIX}/usr/share/shorewall/functions"

#
# Install the Help file
#
install_file help ${PREFIX}/usr/share/shorewall/help 0544

echo
echo "Help command executor installed in ${PREFIX}/usr/share/shorewall/help"

#
# Install the tcstart file
#
install_file tcstart ${PREFIX}/usr/share/shorewall/tcstart 0544

echo
echo "Traffic Shaper installed in ${PREFIX}/usr/share/shorewall/tcstart"

#
# Install the policy file
#
if [ ! -f ${PREFIX}/etc/shorewall/policy ]; then
    run_install $OWNERSHIP -m 0600 policy ${PREFIX}/etc/shorewall/policy
    echo
    echo "Policy file installed as ${PREFIX}/etc/shorewall/policy"
fi
#
# Install the interfaces file
#
if [ ! -f ${PREFIX}/etc/shorewall/interfaces ]; then
    run_install $OWNERSHIP -m 0600 interfaces ${PREFIX}/etc/shorewall/interfaces
    echo
    echo "Interfaces file installed as ${PREFIX}/etc/shorewall/interfaces"
fi
#
# Install the ipsec file
#
if [ ! -f ${PREFIX}/etc/shorewall/ipsec ]; then
    run_install $OWNERSHIP -m 0600 ipsec ${PREFIX}/etc/shorewall/ipsec
    echo
    echo "Dummy IPSEC file installed as ${PREFIX}/etc/shorewall/ipsec"
fi

#
# Install the hosts file
#
if [ ! -f ${PREFIX}/etc/shorewall/hosts ]; then
    run_install $OWNERSHIP -m 0600 hosts ${PREFIX}/etc/shorewall/hosts
    echo
    echo "Hosts file installed as ${PREFIX}/etc/shorewall/hosts"
fi
#
# Install the rules file
#
if [ ! -f ${PREFIX}/etc/shorewall/rules ]; then
    run_install $OWNERSHIP -m 0600 rules ${PREFIX}/etc/shorewall/rules
    echo
    echo "Rules file installed as ${PREFIX}/etc/shorewall/rules"
fi
#
# Install the NAT file
#
if [ ! -f ${PREFIX}/etc/shorewall/nat ]; then
    run_install $OWNERSHIP -m 0600 nat ${PREFIX}/etc/shorewall/nat
    echo
    echo "NAT file installed as ${PREFIX}/etc/shorewall/nat"
fi
#
# Install the NETMAP file
#
if [ ! -f ${PREFIX}/etc/shorewall/netmap ]; then
    run_install $OWNERSHIP -m 0600 netmap ${PREFIX}/etc/shorewall/netmap
    echo
    echo "NETMAP file installed as ${PREFIX}/etc/shorewall/netmap"
fi
#
# Install the Parameters file
#
if [ ! -f ${PREFIX}/etc/shorewall/params ]; then
    run_install $OWNERSHIP -m 0600 params ${PREFIX}/etc/shorewall/params
    echo
    echo "Parameter file installed as ${PREFIX}/etc/shorewall/params"
fi
#
# Install the proxy ARP file
#
if [ ! -f ${PREFIX}/etc/shorewall/proxyarp ]; then
    run_install $OWNERSHIP -m 0600 proxyarp ${PREFIX}/etc/shorewall/proxyarp
    echo
    echo "Proxy ARP file installed as ${PREFIX}/etc/shorewall/proxyarp"
fi
#
# Install the Stopped Routing file
#
if [ ! -f ${PREFIX}/etc/shorewall/routestopped ]; then
    run_install $OWNERSHIP -m 0600 routestopped ${PREFIX}/etc/shorewall/routestopped
    echo
    echo "Stopped Routing file installed as ${PREFIX}/etc/shorewall/routestopped"
fi
#
# Install the Mac List file
#
if [ ! -f ${PREFIX}/etc/shorewall/maclist ]; then
    run_install $OWNERSHIP -m 0600 maclist ${PREFIX}/etc/shorewall/maclist
    echo
    echo "MAC list file installed as ${PREFIX}/etc/shorewall/maclist"
fi
#
# Install the Masq file
#
if [ ! -f ${PREFIX}/etc/shorewall/masq ]; then
    run_install $OWNERSHIP -m 0600 masq ${PREFIX}/etc/shorewall/masq
    echo
    echo "Masquerade file installed as ${PREFIX}/etc/shorewall/masq"
fi
#
# Install the Modules file
#
if [ ! -f ${PREFIX}/etc/shorewall/modules ]; then
    run_install $OWNERSHIP -m 0600 modules ${PREFIX}/etc/shorewall/modules
    echo
    echo "Modules file installed as ${PREFIX}/etc/shorewall/modules"
fi
#
# Install the TC Rules file
#
if [ ! -f ${PREFIX}/etc/shorewall/tcrules ]; then
    run_install $OWNERSHIP -m 0600 tcrules ${PREFIX}/etc/shorewall/tcrules
    echo
    echo "TC Rules file installed as ${PREFIX}/etc/shorewall/tcrules"
fi

#
# Install the TOS file
#
if [ -f ${PREFIX}/etc/shorewall/tos ]; then
    backup_file /etc/shorewall/tos
else
    run_install $OWNERSHIP -m 0600 tos ${PREFIX}/etc/shorewall/tos
    echo
    echo "TOS file installed as ${PREFIX}/etc/shorewall/tos"
fi
#
# Install the Tunnels file
#
if [ ! -f ${PREFIX}/etc/shorewall/tunnels ]; then
    run_install $OWNERSHIP -m 0600 tunnels ${PREFIX}/etc/shorewall/tunnels
    echo
    echo "Tunnels file installed as ${PREFIX}/etc/shorewall/tunnels"
fi
#
# Install the blacklist file
#
if [ ! -f ${PREFIX}/etc/shorewall/blacklist ]; then
    run_install $OWNERSHIP -m 0600 blacklist ${PREFIX}/etc/shorewall/blacklist
    echo
    echo "Blacklist file installed as ${PREFIX}/etc/shorewall/blacklist"
fi
#
# Delete the Routes file
#
delete_file /etc/shorewall/routes

#
# Install the Providers file
#
if [ ! -f ${PREFIX}/etc/shorewall/providers ]; then
    run_install $OWNERSHIP -m 0600 providers ${PREFIX}/etc/shorewall/providers
    echo
    echo "Providers file installed as ${PREFIX}/etc/shorewall/providers"
fi

#
# Install the tcclasses file
#
if [ ! -f ${PREFIX}/etc/shorewall/tcclasses ]; then
    run_install $OWNERSHIP -m 0600 tcclasses ${PREFIX}/etc/shorewall/tcclasses
    echo
    echo "TC Classes file installed as ${PREFIX}/etc/shorewall/tcclasses"
fi

#
# Install the tcdevices file
#
if [ ! -f ${PREFIX}/etc/shorewall/tcdevices ]; then
    run_install $OWNERSHIP -m 0600 tcdevices ${PREFIX}/etc/shorewall/tcdevices
    echo
    echo "TC Devices file installed as ${PREFIX}/etc/shorewall/tcdevices"
fi

#
# Install the rfc1918 file
#
install_file rfc1918 ${PREFIX}/usr/share/shorewall/rfc1918 0600
echo
echo "RFC 1918 file installed as ${PREFIX}/usr/share/shorewall/rfc1918"
#
# Install the default config path file
#
install_file configpath ${PREFIX}/usr/share/shorewall/configpath 0600
echo
echo " Default config path file installed as ${PREFIX}/usr/share/shorewall/configpath"
#
# Install the init file
#
if [ ! -f ${PREFIX}/etc/shorewall/init ]; then
    run_install $OWNERSHIP -m 0600 init ${PREFIX}/etc/shorewall/init
    echo
    echo "Init file installed as ${PREFIX}/etc/shorewall/init"
fi
#
# Install the initdone file
#
if [ ! -f ${PREFIX}/etc/shorewall/initdone ]; then
    run_install $OWNERSHIP -m 0600 initdone ${PREFIX}/etc/shorewall/initdone
    echo
    echo "Initdone file installed as ${PREFIX}/etc/shorewall/initdone"
fi
#
# Install the start file
#
if [ ! -f ${PREFIX}/etc/shorewall/start ]; then
    run_install $OWNERSHIP -m 0600 start ${PREFIX}/etc/shorewall/start
    echo
    echo "Start file installed as ${PREFIX}/etc/shorewall/start"
fi
#
# Install the stop file
#
if [ ! -f ${PREFIX}/etc/shorewall/stop ]; then
    run_install $OWNERSHIP -m 0600 stop ${PREFIX}/etc/shorewall/stop
    echo
    echo "Stop file installed as ${PREFIX}/etc/shorewall/stop"
fi
#
# Install the stopped file
#
if [ ! -f ${PREFIX}/etc/shorewall/stopped ]; then
    run_install $OWNERSHIP -m 0600 stopped ${PREFIX}/etc/shorewall/stopped
    echo
    echo "Stopped file installed as ${PREFIX}/etc/shorewall/stopped"
fi
#
# Install the ECN file
#
if [ ! -f ${PREFIX}/etc/shorewall/ecn ]; then
    run_install $OWNERSHIP -m 0600 ecn ${PREFIX}/etc/shorewall/ecn
    echo
    echo "ECN file installed as ${PREFIX}/etc/shorewall/ecn"
fi
#
# Install the Accounting file
#
if [ ! -f ${PREFIX}/etc/shorewall/accounting ]; then
    run_install $OWNERSHIP -m 0600 accounting ${PREFIX}/etc/shorewall/accounting
    echo
    echo "Accounting file installed as ${PREFIX}/etc/shorewall/accounting"
fi
#
# Install the Continue file
#
if [ ! -f ${PREFIX}/etc/shorewall/continue ]; then
    run_install $OWNERSHIP -m 0600 continue ${PREFIX}/etc/shorewall/continue
    echo
    echo "Continue file installed as ${PREFIX}/etc/shorewall/continue"
fi
#
# Install the Started file
#
if [ ! -f ${PREFIX}/etc/shorewall/started ]; then
    run_install $OWNERSHIP -m 0600 started ${PREFIX}/etc/shorewall/started
    echo
    echo "Started file installed as ${PREFIX}/etc/shorewall/started"
fi
#
# Install the Standard Actions file
#
install_file actions.std ${PREFIX}/usr/share/shorewall/actions.std 0600
echo
echo "Standard actions file installed as ${PREFIX}/etc/shorewall/actions.std"

#
# Install the Actions file
#
if [ ! -f ${PREFIX}/etc/shorewall/actions ]; then
    run_install $OWNERSHIP -m 0600 actions ${PREFIX}/etc/shorewall/actions
    echo
    echo "Actions file installed as ${PREFIX}/etc/shorewall/actions"
fi

if [ ! -f ${PREFIX}/etc/shorewall/Makefile ]; then
    run_install $OWNERSHIP -m 0600 Makefile ${PREFIX}/etc/shorewall/Makefile
    echo
    echo "Makefile installed as ${PREFIX}/etc/shorewall/Makefile"
fi
#
# Install the Action files
#
for f in action.* ; do
    install_file $f ${PREFIX}/usr/share/shorewall/$f 0600
    echo
    echo "Action ${f#*.} file installed as ${PREFIX}/usr/share/shorewall/$f"
done
#
# Install the Macro files
#
for f in macro.* ; do
    install_file $f ${PREFIX}/usr/share/shorewall/$f 0600
    echo
    echo "Macro ${f#*.} file installed as ${PREFIX}/usr/share/shorewall/$f"
done

#
# Create the version file
#
echo "$VERSION" > ${PREFIX}/usr/share/shorewall/version
chmod 644 ${PREFIX}/usr/share/shorewall/version
#
# Remove and create the symbolic link to the init script
#

if [ -z "$PREFIX" ]; then
    rm -f /usr/share/shorewall/init
    ln -s ${DEST}/${INIT} /usr/share/shorewall/init
fi

#
# Install the firewall script
#
install_file firewall ${PREFIX}/usr/share/shorewall/firewall 0544

if [ -z "$PREFIX" -a -n "$first_install" ]; then
    if [ -n "$DEBIAN" ]; then
	run_install $OWNERSHIP -m 0644 default.debian /etc/default/shorewall
	ln -s ../init.d/shorewall /etc/rcS.d/S40shorewall
	echo
	echo "shorewall will start automatically at boot"
	echo "Set startup=1 in /etc/default/shorewall to enable"
    else
	if [ -x /sbin/insserv -o -x /usr/sbin/insserv ]; then
	    if insserv /etc/init.d/shorewall ; then
		echo
		echo "shorewall will start automatically at boot"
		echo "Set STARTUP_ENABLED=Yes in /etc/shorewall/shorewall.conf to enable"
	    else
		cant_autostart
	    fi
	elif [ -x /sbin/chkconfig -o -x /usr/sbin/chkconfig ]; then
	    if chkconfig --add shorewall ; then
		echo
		echo "shorewall will start automatically in run levels as follows:"
		echo "Set STARTUP_ENABLED=Yes in /etc/shorewall/shorewall.conf to enable"
		chkconfig --list shorewall
	    else
		cant_autostart
	    fi
	elif [ -x /sbin/rc-update ]; then
	    if rc-update add shorewall default; then
		echo
		echo "shorewall will start automatically at boot"
		echo "Set STARTUP_ENABLED=Yes in /etc/shorewall/shorewall.conf to enable"
	    else
		cant_autostart
	    fi
	elif [ "$INIT" != rc.firewall ]; then #Slackware starts this automatically
	    cant_autostart
	fi
    fi
fi

#
#  Report Success
#
echo
echo "shorewall Version $VERSION Installed"
