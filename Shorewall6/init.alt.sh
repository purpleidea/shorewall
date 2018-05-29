#!/bin/sh
#
# Shorewall6 init script
#
# chkconfig: - 28 90
# description: Packet filtering firewall
#
### BEGIN INIT INFO
# Provides: shorewall6
# Required-Start: $local_fs $remote_fs $syslog $network
# Should-Start: $time $named
# Required-Stop:
# Default-Start: 3 4 5
# Default-Stop:  0 1 2 6
# Short-Description: Packet filtering firewall
# Description: The Shoreline Firewall, more commonly known as "Shorewall", is a
#              Netfilter (iptables) based firewall
### END INIT INFO

# Do not load RH compatibility interface.
WITHOUT_RC_COMPAT=1

# Source function library.
. /etc/init.d/functions

#
# The installer may alter this
#
. /usr/share/shorewall/shorewallrc

NAME="Shorewall6 firewall"
PROG="shorewall"
SHOREWALL="$SBINDIR/$PROG -6"
LOGGER="logger -i -t $PROG"

# Get startup options (override default)
OPTIONS=

SourceIfNotEmpty $SYSCONFDIR/${PROG}6

LOCKFILE="/var/lock/subsys/${PROG}6"
RETVAL=0

start() {
	action $"Applying $NAME rules:" "$SHOREWALL" "$OPTIONS" start "$STARTOPTIONS" 2>&1 | "$LOGGER"
	RETVAL=$?
	[ $RETVAL -eq 0 ] && touch "$LOCKFILE"
	return $RETVAL
}

stop() {
	action $"Stoping $NAME :" "$SHOREWALL" "$OPTIONS" stop "$STOPOPTIONS" 2>&1 | "$LOGGER"
	RETVAL=$?
	[ $RETVAL -eq 0 ] && rm -f "$LOCKFILE"
	return $RETVAL
}

restart() {
	action $"Restarting $NAME rules: " "$SHOREWALL" "$OPTIONS" restart "$RESTARTOPTIONS" 2>&1 | "$LOGGER"
	RETVAL=$?
	return $RETVAL
}

reload() {
	action $"Reloadinging $NAME rules: " "$SHOREWALL" "$OPTIONS" reload "$RELOADOPTIONS" 2>&1 | "$LOGGER"
	RETVAL=$?
	return $RETVAL
}

clear() {
	action $"Clearing $NAME rules: " "$SHOREWALL" "$OPTIONS" clear 2>&1 | "$LOGGER"
	RETVAL=$?
	return $RETVAL
}

# See how we were called.
case "$1" in
	start)
	    start
	    ;;
	stop)
	    stop
	    ;;
	restart)
	    restart
	    ;;
	reload)
	    reload
	    ;;
	clear)
	    clear
	    ;;
	condrestart)
	    if [ -e "$LOCKFILE" ]; then
		restart
	    fi
	    ;;
	condreload)
	    if [ -e "$LOCKFILE" ]; then
		restart
	    fi
	    ;;
	condstop)
	    if [ -e "$LOCKFILE" ]; then
		stop
	    fi
	    ;;
	status)
	    "$SHOREWALL" status
	     RETVAL=$?
	    ;;
	*)
	    echo $"Usage: ${0##*/}  {start|stop|restart|reload|clear|condrestart|condstop|status}"
	    RETVAL=1
esac

exit $RETVAL
