#! /usr/bin/perl -w
#
#     The Shoreline Firewall (Shorewall) Packet Filtering Firewall Compiler - V3.9
#
#     This program is under GPL [http://www.gnu.org/copyleft/gpl.htm]
#
#     (c) 2007 - Tom Eastep (teastep@shorewall.net)
#
#	Complete documentation is available at http://shorewall.net
#
#	This program is free software; you can redistribute it and/or modify
#	it under the terms of Version 2 of the GNU General Public License
#	as published by the Free Software Foundation.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program; if not, write to the Free Software
#	Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA
#
#	Commands are:
#
#          compiler.pl                          Verify the configuration files.
#	   compile <path name>                  Compile into <path name>
#
#	Environmental Variables are set up by the Compiler wrapper ('compiler' program).
#
#	    EXPORT=Yes                          -e option specified to /sbin/shorewall
#	    SHOREWALL_DIR                       A directory name was passed to /sbin/shorewall
#	    VERBOSE                             Standard Shorewall verbosity control.
#           DEBUG=Yes                           Debugging Enabled
#           VERSION                             Shorewall Version
#           TMP_DIR                             Temporary Directory containing stripped copies
#                                               of all configuration files. Shell variable substitution 
#                                               has been performed on these files.
#           TIMESTAMP=Yes                       -t option specified to /sbin/shorewall
#
#       This program performs rudimentary shell variable expansion on action and macro files.

use strict;
use lib '/usr/share/shorewall/Shorewall';
use Shorewall::Common;
use Shorewall::Config;
use Shorewall::Chains;
use Shorewall::Zones;
use Shorewall::Interfaces;
use Shorewall::Hosts;
use Shorewall::Nat;
use Shorewall::Tc;
use Shorewall::Tunnels;
use Shorewall::Providers;
use Shorewall::Policy;
use Shorewall::Macros;
use Shorewall::Actions;
use Shorewall::Accounting;
use Shorewall::Rules;

sub generate_script_1 {
    copy find_file 'prog.header';

    my $date = localtime;

    emit "#\n# Compiled firewall script generated by Shorewall $ENV{VERSION} - $date\n#";

    if ( $ENV{EXPORT} ) {
	emit 'SHAREDIR=/usr/share/shorewall-lite';
	emit 'CONFDIR=/etc/shorewall-lite';
	emit 'VARDIR=/var/lib/shorewall-lite';
	emit 'PRODUCT="Shorewall Lite"';
	
	copy "$env{SHAREDIR}/lib.base";
	
	emit '################################################################################';
	emit '# End of /usr/share/shorewall/lib.base';
	emit '################################################################################';
    } else {
	emit 'SHAREDIR=/usr/share/shorewall';
	emit 'CONFDIR=/etc/shorewall';
	emit 'VARDIR=/var/lib/shorewall\n';
	emit 'PRODUCT=\'Shorewall\'';
	emit '. /usr/share/shoreall-lite/lib.base';
    }
	
    emit '';
    
    for my $exit qw/init start tcclear started stop stopped/ {
	emit "run_${exit}_exit() {";
	push_indent;
	append_file $exit;
	pop_indent;
	emit "}\n";
    }
    
    emit 'initialize()';
    emit '{';

    push_indent;
    
    if ( $ENV{EXPORT} ) {
	emit '#';
	emit '# These variables are required by the library functions called in this script';
	emit '#';
	emit 'CONFIG_PATH="/etc/shorewall-lite:/usr/share/shorewall-lite"';
    } else {
	emit 'if [ ! -f ${SHAREDIR}/version ]; then';
	emit '    fatal_error "This script requires Shorewall which do not appear to be installed on this system (did you forget \"-e\" when you compiled?)"';
	emit 'fi';
	emit '';
	emit 'local version=\$(cat \${SHAREDIR}/version)';
	emit '';
	emit 'if [ ${SHOREWALL_LIBVERSION:-0} -lt 30203 ]; then';
	emit '    fatal_error "This script requires Shorewall version 3.3.3 or later; current version is $version"';
	emit 'fi';
	emit '#';
	emit '# These variables are required by the library functions called in this script';
	emit '#';
	emit "CONFIG_PATH=\"$config{CONFIG_PATH}\"";
    }

    propagateconfig;
	
    emit '[ -n "${COMMAND:=restart}" ]';
    emit '[ -n "${VERBOSE:=0}" ]';
    emit '[ -n "${RESTOREFILE:=$RESTOREFILE}" ]';
    emit '[ -n "$LOGFORMAT" ] || LOGFORMAT="Shorewall:%s:%s:"';
    emit "VERSION=\"$ENV{VERSION}\"";
    emit "PATH=\"$config{PATH}\"";
    emit 'TERMINATOR=fatal_error';
    
    if ( $config{IPTABLES} ) {
	emit "IPTABLES=\"$config{IPTABLES}\"\n";
	emit "[ -x \"$config{IPTABLES}\" ] || startup_error \"IPTABLES=$config{IPTABLES} does not exist or is not executable\"";
    } else {
	emit '[ -z "$IPTABLES" ] && IPTABLES=$(mywhich iptables 2> /dev/null)';
	emit '';
	emit '[ -n "$IPTABLES" -a -x "$IPTABLES" ] || startup_error "Can\'t find iptables executable"';
    }

    emit '';
    emit "STOPPING=";
    emit "COMMENT=\n";        # Fixme -- eventually this goes but it's ok now to maintain compability with lib.base
    emit '#';
    emit '# The library requires that ${VARDIR} exist';
    emit '#';
    emit '[ -d ${VARDIR} ] || mkdir -p ${VARDIR}';
    
    pop_indent;
    
    emit "}\n";

        
}

sub compile_stop_firewall() {

    emit "
#
# Stop/restore the firewall after an error or because of a 'stop' or 'clear' command
#
stop_firewall() {

    deletechain() {
	qt \$IPTABLES -L \$1 -n && qt \$IPTABLES -F \$1 && qt \$IPTABLES -X \$1
    }

    deleteallchains() {
	\$IPTABLES -F
	\$IPTABLES -X
    }

    setcontinue() {
	\$IPTABLES -A \$1 -m state --state ESTABLISHED,RELATED -j ACCEPT
    }

    delete_nat() {
	\$IPTABLES -t nat -F
	\$IPTABLES -t nat -X

	if [ -f \${VARDIR}/nat ]; then
	    while read external interface; do
		del_ip_addr \$external \$interface
	    done < \${VARDIR}/nat

	    rm -f \${VARDIR}/nat
	fi
    }

    case \$COMMAND in
	stop|clear)
	    ;;
	*)
	    set +x

            case \$COMMAND in
	        start)
	            logger -p kern.err \"ERROR:\$PRODUCT start failed\"
	            ;;
	        restart)
	            logger -p kern.err \"ERROR:\$PRODUCT restart failed\"
	            ;;
	        restore)
	            logger -p kern.err \"ERROR:\$PRODUCT restore failed\"
	            ;;
            esac
            
            if [ \"\$RESTOREFILE\" = NONE ]; then
                COMMAND=clear
                clear_firewall
                echo \"\$PRODUCT Cleared\"

	        kill \$\$
	        exit 2
            else
	        RESTOREPATH=\${VARDIR}/\$RESTOREFILE

	        if [ -x \$RESTOREPATH ]; then

		    if [ -x \${RESTOREPATH}-ipsets ]; then
		        progress_message2 Restoring Ipsets...
		        #
		        # We must purge iptables to be sure that there are no
		        # references to ipsets
		        #
		        for table in mangle nat filter; do
			    \$IPTABLES -t \$table -F
			    \$IPTABLES -t \$table -X
		        done

		        \${RESTOREPATH}-ipsets
		    fi

		    echo Restoring \${PRODUCT:=Shorewall}...

		    if \$RESTOREPATH restore; then
		        echo \"\$PRODUCT restored from \$RESTOREPATH\"
		        set_state \"Started\"
		    else
		        set_state \"Unknown\"
		    fi

	            kill \$\$
	            exit 2
	        fi
            fi
	    ;;
    esac

    set_state \"Stopping\"

    STOPPING=\"Yes\"

    TERMINATOR=

    deletechain shorewall

    determine_capabilities

    run_stop_exit;

    if [ -n \"\$MANGLE_ENABLED\" ]; then
	run_iptables -t mangle -F
	run_iptables -t mangle -X
	for chain in PREROUTING INPUT FORWARD POSTROUTING; do
	    qt \$IPTABLES -t mangle -P \$chain ACCEPT
	done
    fi

    if [ -n \"\$RAW_TABLE\" ]; then
	run_iptables -t raw -F
	run_iptables -t raw -X
	for chain in PREROUTING OUTPUT; do
	    qt \$IPTABLES -t raw -P \$chain ACCEPT
	done
    fi

    if [ -n \"\$NAT_ENABLED\" ]; then
	delete_nat
	for chain in PREROUTING POSTROUTING OUTPUT; do
	    qt \$IPTABLES -t nat -P \$chain ACCEPT
	done
    fi

    if [ -f \${VARDIR}/proxyarp ]; then
	while read address interface external haveroute; do
	    qt arp -i \$external -d \$address pub
	    [ -z \"\${haveroute}\${NOROUTES}\" ] && qt ip route del \$address dev \$interface
	done < \${VARDIR}/proxyarp

        for f in /proc/sys/net/ipv4/conf/*; do
            [ -f \$f/proxy_arp ] && echo 0 > \$f/proxy_arp
        done
    fi

    rm -f \${VARDIR}/proxyarp\n";

    push_indent;

    emit 'delete_tc1' if $config{CLEAR_TC};
    emit 'undo_routing';
    emit 'restore_default_route';
    
    my $criticalhosts = process_criticalhosts;

    if ( $criticalhosts ) {
	if ( $config{ADMINISABSENTMINDED} ) {
	    emit 'for chain in INPUT OUTPUT; do';
	    emit '    setpolicy \$chain ACCEPT';
	    emit "done\n";

	    emit "setpolicy FORWARD DROP\n";
	    
	    emit "deleteallchains\n";

	    for my $hosts ( @$criticalhosts ) {
                my ( $interface, $host ) = ( split /,/, $hosts );
                my $source = match_source_net $host;
		my $dest   = match_dest_net $host;

		emit "\$IPTABLES -A INPUT  -i $interface $source -j ACCEPT";
		emit "\$IPTABLES -A OUTPUT -o $interface $dest   -j ACCEPT";
	    }
	    
	    pop_indent;
	    emit "
    for chain in INPUT OUTPUT; do
	setpolicy \$chain DROP
    done

";
	} else {
	    pop_indent;
	    emit "
    for chain in INPUT OUTPUT; do
	setpolicy \$chain ACCEPT
    done

    setpolicy FORWARD DROP

    deleteallchains

";

	    for my $hosts ( @$criticalhosts ) {
                my ( $interface, $host ) = ( split /,/, $hosts );
                my $source = match_source_net $host;
		my $dest   = match_dest_net $host;

		emit "\$IPTABLES -A INPUT  -i $interface $source -j ACCEPT";
		emit "\$IPTABLES -A OUTPUT -o $interface $dest   -j ACCEPT";
	    }

	    emit "
    setpolicy INPUT DROP

    for chain in INPUT FORWARD; do
	setcontinue \$chain
    done

";
	}
    } elsif ( ! $config{ADMINISABSENTMINDED} ) {
	pop_indent;
	emit "
    for chain in INPUT OUTPUT FORWARD; do
	setpolicy \$chain DROP
    done

    deleteallchains
";
    } else {
	pop_indent;
	emit "
    for chain in INPUT FORWARD; do
	setpolicy \$chain DROP
    done

    setpolicy OUTPUT ACCEPT

    deleteallchains

    for chain in INPUT FORWARD; do
	setcontinue \$chain
    done

";
    }

    push_indent;

    process_routestopped;

    emit '$IPTABLES -A INPUT  -i lo -j ACCEPT';
    emit '$IPTABLES -A OUTPUT -o lo -j ACCEPT';
    emit '$IPTABLES -A OUTPUT -o lo -j ACCEPT' unless $config{ADMINISABSENTMINDED};

    my $interfaces = find_interfaces_by_option 'dhcp';

    for my $interface ( @$interfaces ) {
	emit "\$IPTABLES -A INPUT  -p udp -i $interface --dport 67:68 -j ACCEPT";
	emit "\$IPTABLES -A OUTPUT -p udp -o $interface --dport 67:68 -j ACCEPT" unless $config{ADMINISABSENTMINDED};
	#
	# This might be a bridge
	#
	emit "\$IPTABLES -A FORWARD -p udp -i $interface -o $interface --dport 67:68 -j ACCEPT";
    }

    emit '';

    if ( $config{IP_FORWARDING} =~ /on/i ) {
	emit 'echo 1 > /proc/sys/net/ipv4/ip_forward';
	emit 'progress_message2 IP Forwarding Enabled';
    } elsif ( $config{IP_FORWARDING} =~ /off/i ) {
	emit 'echo 0 > /proc/sys/net/ipv4/ip_forward';
	emit 'progress_message2 IP Forwarding Disabled!';
    }
    
    append_file 'stopped';

    pop_indent;

    emit "
    set_state \"Stopped\"

    logger -p kern.info \"\$PRODUCT Stopped\"

    case \$COMMAND in
    stop|clear)
	;;
    *)
	#
	# The firewall is being stopped when we were trying to do something
	# else. Remove the lock file and Kill the shell in case we're in a
	# subshell
	#
	kill \$\$
	;;
    esac
}";
}

sub generate_script_2 () {

    copy find_file 'prog.functions';

    emit '#';
    emit '# Setup Routing and Traffic Shaping';
    emit '#';
    emit 'setup_routing_and_traffic_shaping() {';

    push_indent;
    
    emit 'local restore_file=$1';

    save_progress_message 'Initializing...';
    
    if ( $ENV{EXPORT} ) {
	my $mf = find_file 'modules';

	if ( $mf ne "$env{SHAREDIR}/module" && -f $mf ) {

	    emit 'echo MODULESDIR="$MODULESDIR" > ${VARDIR}/.modulesdir';
	    emit 'cat > ${VARDIR}/.modules << EOF';

	    open MF, $mf or fatal_error "Unable to open $mf: $!";

	    while ( $line = <MF> ) { emit_as_is $line if $line =~ /^\s*loadmodule\b/; }

	    close MF;

	    emit_unindented "EOF\n";

	    emit 'reload_kernel_modules < ${VARDIR}/.modules';
	} else {
	    emit 'load_kernel_modules Yes';
	}
    } else {
	emit 'load_kernel_modules Yes';
    }

    emit '';

    for my $interface ( @{find_interfaces_by_option 'norfc1918'} ) {
	emit "addr=\$(ip -f inet addr show $interface 2> /dev/null | grep 'inet\ ' | head -n1)";
	emit 'if [ -n "$addr" ]; then';
	emit "    addr=\$(echo \$addr | sed 's/inet //;s/\/.*//;s/ peer.*//')";
	emit '    for network in 10.0.0.0/8 176.16.0.0/12 192.168.0.0/16; do';
        emit '        if in_network $addr $network; then';
        emit "            startup_error \"The 'norfc1918' option has been specified on an interface with an RFC 1918 address. Interface:$interface\"";
        emit '        fi';
	emit '    done';
	emit "fi\n";
    }

    emit "run_init_exit\n";
    emit 'qt $IPTABLES -L shorewall -n && qt $IPTABLES -F shorewall && qt $IPTABLES -X shorewall';
    emit '';
    emit "delete_proxyarp\n";
    emit "delete_tc1\n"   if $config{CLEAR_TC};

    emit "disable_ipv6\n" if $config{DISABLE_IPV6};

}

sub generate_script_3() {
    pop_indent;

    emit "}\n";
    
    progress_message2 "Creating iptables-restore input...";
    create_netfilter_load;	
    emit "#\n# Start/Restart the Firewall\n#";
    emit 'define_firewall() {';
    emit '   setup_routing_and_traffic_shaping;';
    emit '   setup_netfilter';
    emit '   [ $COMMAND = restore ] || restore_dynamic_rules';
    emit "}\n";
    
    copy find_file 'prog.footer';	
}

sub compile_firewall( $ ) {
    
    my $objectfile = $_[0];

    ( $command, $doing, $done ) = qw/ check Checking Checked / unless $objectfile;

    initialize_chain_table;

    if ( $command eq 'compile' ) {
	create_temp_object( $objectfile );
	generate_script_1;
    }

    report_capabilities if $ENV{VERBOSE} > 1;

    fatal_error "Shorewall $ENV{VERSION} requires Conntrack Match Support" 
	unless $capabilities{CONNTRACK_MATCH};
    fatal_error "Shorewall $ENV{VERSION} requires Extended Multi-port Match Support"
	unless $capabilities{XMULTIPORT};
    fatal_error "Shorewall $ENV{VERSION} requires Address Type Match Support"
	unless $capabilities{ADDRTYPE};
    fatal_error 'BRIDGING=Yes requires Physdev Match support in your Kernel and iptables'
	if $config{BRIDGING} && ! $capabilities{PHYSDEV_MATCH};
    fatal_error 'MACLIST_TTL requires the Recent Match capability which is not present in your Kernel and/or iptables'
	if $config{MACLIST_TTL} && ! $capabilities{RECENT_MATCH};
    fatal_error 'RFC1918_STRICT=Yes requires Connection Tracking match'
	if $config{RFC1918_STRICT} && ! $capabilities{CONNTRACK_MATCH};
    #
    # Process the zones file.
    #
    progress_message2 "Determining Zones...";                    
    determine_zones;
    #
    # Process the interfaces file.
    #
    progress_message2 "Validating interfaces file...";           
    validate_interfaces_file;             
    dump_interface_info                if $ENV{DEBUG};
    #
    # Process the hosts file.
    #
    progress_message2 "Validating hosts file...";                
    validate_hosts_file;

    if ( $ENV{DEBUG} ) {
	dump_zone_info;
    } elsif ( $ENV{VERBOSE} > 1 ) {
	progress_message "Determining Hosts in Zones...";        
	zone_report;
    }
    #
    # Do action pre-processing.
    #
    progress_message2 "Preprocessing Action Files...";           
    process_actions1;
    #
    # Process the Policy File.
    #
    progress_message2 "Validating Policy file...";               
    validate_policy;
    #
    # Compile the 'stop_firewall()' function
    #
    compile_stop_firewall;
    #
    # Start Second Part of script
    #
    generate_script_2;
    #
    # Do all of the zone-independent stuff
    #
    progress_message2 "Setting up Common Rules...";              
    add_common_rules;
    #
    # [Re-]establish Routing
    # 
    if ( -s "$ENV{TMP_DIR}/providers" ) {
	setup_providers;
    } else {
	emit "\nundo_routing";
	emit 'restore_default_route';
    }
    #
    # Traffic Shaping
    #
    setup_traffic_shaping if -s "$ENV{TMP_DIR}/tcdevices";
    #
    # Setup Masquerading/SNAT
    #
    progress_message2 "$doing Masq file...";                     
    setup_masq;
    #
    # MACLIST Filtration
    #
    progress_message2 "Setting up MAC Filtration -- Phase 1..."; 
    setup_mac_lists 1;
    #
    # Process the rules file.
    #
    progress_message2 "$doing Rules...";                         
    process_rules;
    #
    # Add Tunnel rules.
    #
    progress_message2 "Adding Tunnels...";                       
    setup_tunnels;
    #
    # Post-rules action processing.
    #
    process_actions2;
    process_actions3;
    #
    # MACLIST Filtration again
    #
    progress_message2 "Setting up MAC Filtration -- Phase 2..."; 
    setup_mac_lists 2;
    #
    # Apply Policies
    #
    progress_message2 'Applying Policies...';                    
    apply_policy_rules;                    
    dump_action_table         if $ENV{DEBUG};
    #
    # Setup Nat
    #
    progress_message2 "$doing one-to-one NAT...";                
    setup_nat;
    #
    # TCRules
    #
    progress_message2 "Processing TC Rules...";                  
    process_tcrules;
    #
    # Accounting.
    #
    progress_message2 "Setting UP Accounting...";                
    setup_accounting;

    unless ( $command eq 'check' ) {
	#
	# Finish the script.
	#
	progress_message2 'Generating Rule Matrix...';           
	generate_matrix;                       
	dump_chain_table               if $ENV{DEBUG};
	generate_script_3;
	finalize_object;
    }
}

#
#                        E x e c u t i o n   S t a r t s   H e r e
#

$ENV{VERBOSE} = 2 if $ENV{DEBUG};
#
# Get shorewall.conf and capabilities.
#
get_configuration;
#
# Compile/Check the configuration.
#
compile_firewall $ARGV[0];
