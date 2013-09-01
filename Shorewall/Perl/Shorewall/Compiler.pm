#! /usr/bin/perl -w
#
#     The Shoreline Firewall Packet Filtering Firewall Compiler - V4.5
#
#     This program is under GPL [http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt]
#
#     (c) 2007,2008,2009,2010,2011,2012,2013 - Tom Eastep (teastep@shorewall.net)
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
#	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
package Shorewall::Compiler;
require Exporter;
use Shorewall::Config qw(:DEFAULT :internal);
use Shorewall::Chains qw(:DEFAULT :internal);
use Shorewall::Zones;
use Shorewall::Nat;
use Shorewall::Providers;
use Shorewall::Tc;
use Shorewall::Tunnels;
use Shorewall::Accounting;
use Shorewall::Rules;
use Shorewall::Proc;
use Shorewall::Proxyarp;
use Shorewall::Raw;
use Shorewall::Misc;
use Shorewall::ARP;

use strict;

our @ISA = qw(Exporter);
our @EXPORT = qw( compiler );
our @EXPORT_OK = qw( $export );
our $VERSION = 'MODULEVERSION';

our $export;

our $test;

our $family;

our $have_arptables;

#
# Initilize the package-globals in the other modules
#
sub initialize_package_globals( $$$ ) {
    Shorewall::Config::initialize($family, $_[1], $_[2]);
    Shorewall::Chains::initialize ($family, 1, $export );
    Shorewall::Zones::initialize ($family, $_[0]);
    Shorewall::Nat::initialize($family);
    Shorewall::Providers::initialize($family);
    Shorewall::Tc::initialize($family);
    Shorewall::Accounting::initialize;
    Shorewall::Rules::initialize($family);
    Shorewall::Proxyarp::initialize($family);
    Shorewall::IPAddrs::initialize($family);
    Shorewall::Misc::initialize($family);
}

#
# First stage of script generation.
#
#    Copy lib.core and lib.common to the generated script.
#    Generate the various user-exit jacket functions.
#
#    Note: This function is not called when $command eq 'check'. So it must have no side effects other
#          than those related to writing to the output script file.
#
sub generate_script_1( $ ) {

    my $script = shift;

    if ( $script ) {
	if ( $test ) {
	    emit "#!$config{SHOREWALL_SHELL}\n#\n# Compiled firewall script generated by Shorewall-perl\n#";
	} else {
	    my $date = localtime;

	    emit "#!$config{SHOREWALL_SHELL}\n#\n# Compiled firewall script generated by Shorewall $globals{VERSION} - $date\n#";

	    copy  $globals{SHAREDIRPL} . '/lib.core', 0;
	    copy2 $globals{SHAREDIRPL} . '/lib.common', 0;
	}

    }

    my $lib = find_file 'lib.private';

    copy2( $lib, $debug ) if -f $lib;

    emit <<'EOF';
################################################################################
# Functions to execute the various user exits (extension scripts)
################################################################################
EOF

    for my $exit ( qw/init start tcclear started stop stopped clear refresh refreshed restored/ ) {
	emit "\nrun_${exit}_exit() {";
	push_indent;
	append_file $exit or emit 'true';
	pop_indent;
	emit '}';
    }

    for my $exit ( qw/isusable findgw/ ) {
	emit "\nrun_${exit}_exit() {";
	push_indent;
	append_file($exit, 1) or emit 'true';
	pop_indent;
	emit '}';
    }

    emit <<'EOF';
################################################################################
# End user exit functions
################################################################################
EOF

}

#
# Second stage of script generation.
#
#    Generate the 'initialize()' function.
#
#    Note: This function is not called when $command eq 'check'. So it must have no side effects other
#          than those related to writing to the output script file.

sub generate_script_2() {

    emit ( '',
	   '#',
	   '# This function initializes the global variables used by the program',
	   '#',
	   'initialize()',
	   '{',
	   '    #',
	   '    # Be sure that umask is sane',
	   '    #',
	   '    umask 077' );

    emit ( '',
	   '    #',
	   '    # These variables are required by the library functions called in this script',
	   '    #'
	   );

    push_indent;

    if ( $shorewallrc1{TEMPDIR} ) {
	emit( '',
	      qq(TMPDIR="$shorewallrc{TEMPDIR}") ,
	      q(export TMPDIR) );
    }

    if ( $family == F_IPV4 ) {
	emit( 'g_family=4' );

	if ( $export ) {
	    emit ( qq(g_confdir=$shorewallrc1{CONFDIR}/shorewall-lite),
		   'g_product="Shorewall Lite"',
		   'g_program=shorewall-lite',
		   'g_basedir=/usr/share/shorewall-lite',
		   qq(CONFIG_PATH="$shorewallrc1{CONFDIR}/shorewall-lite:$shorewallrc1{SHAREDIR}/shorewall-lite") ,
		 );
	} else {
	    emit ( qq(g_confdir=$shorewallrc1{CONFDIR}/shorewall),
		   'g_product=Shorewall',
		   'g_program=shorewall',
		   'g_basedir=/usr/share/shorewall',
		   qq(CONFIG_PATH="$config{CONFIG_PATH}") ,
		 );
	}
    } else {
	emit( 'g_family=6' );

	if ( $export ) {
	    emit ( qq(g_confdir=$shorewallrc1{CONFDIR}/shorewall6-lite),
		   'g_product="Shorewall6 Lite"',
		   'g_program=shorewall6-lite',
		   'g_basedir=/usr/share/shorewall6',
		   qq(CONFIG_PATH="$shorewallrc1{CONFDIR}/shorewall6-lite:$shorewallrc{SHAREDIR}/shorewall6-lite") ,
		 );
	} else {
	    emit ( qq(g_confdir=$shorewallrc1{CONFDIR}/shorewall6),
		   'g_product=Shorewall6',
		   'g_program=shorewall6',
		   'g_basedir=/usr/share/shorewall',
		   qq(CONFIG_PATH="$config{CONFIG_PATH}") ,
		 );
	}
    }

    emit (   '[ -f ${g_confdir}/vardir ] && . ${g_confdir}/vardir' );
    emit ( qq([ -n "\${VARDIR:=$shorewallrc1{VARDIR}}" ]) );
    emit ( qq([ -n "\${VARLIB:=$shorewallrc1{VARLIB}}" ]) );

    emit 'TEMPFILE=';

    propagateconfig;

    my @dont_load = split_list $config{DONT_LOAD}, 'module';

    emit ( '[ -n "${COMMAND:=restart}" ]',
	   '[ -n "${VERBOSITY:=0}" ]',
	   qq([ -n "\${RESTOREFILE:=$config{RESTOREFILE}}" ]) );

    emit ( qq(SHOREWALL_VERSION="$globals{VERSION}") ) unless $test;

    emit ( qq(PATH="$config{PATH}") ,
	   'TERMINATOR=fatal_error' ,
	   qq(DONT_LOAD="@dont_load") ,
	   qq(STARTUP_LOG="$config{STARTUP_LOG}") ,
	   ''
	   );

    set_chain_variables;

    my $need_arptables = $have_arptables || $config{SAVE_ARPTABLES};

    if ( my $arptables = $config{ARPTABLES} ) {
	emit( qq(ARPTABLES="$arptables"),
	      '[ -x "$ARPTABLES" ] || startup_error "ARPTABLES=$ARPTABLES does not exist or is not executable"',
	    );
    } elsif ( $need_arptables ) {
	emit( '[ -z "$ARPTABLES" ] && ARPTABLES=$(mywhich arptables)',
	      '[ -n "$ARPTABLES" -a -x "$ARPTABLES" ] || startup_error "Can\'t find arptables executable"' );
    }

    if ( $need_arptables ) {
	emit( 'ARPTABLES_RESTORE=${ARPTABLES}-restore',
	      '[ -x "$ARPTABLES_RESTORE" ] || startup_error "$ARPTABLES_RESTORE does not exist or is not executable"' );
    }

    if ( $config{EXPORTPARAMS} ) {
	append_file 'params';
    } else {
	export_params;
    }

    emit ( '',
	   "g_stopping=",
	   '',
	   '#',
	   '# The library requires that ${VARDIR} exist',
	   '#',
	   '[ -d ${VARDIR} ] || mkdir -p ${VARDIR}'
	   );

    pop_indent;

    emit "\n}\n"; # End of initialize()

    emit( '' ,
	  '#' ,
	  '# Set global variables holding detected IP information' ,
	  '#' ,
	  'detect_configuration()',
	  '{' );

    my $global_variables = have_global_variables;

    push_indent;

    if ( $global_variables ) {

	emit( 'case $COMMAND in' );

	push_indent;

	if ( $global_variables & NOT_RESTORE ) {
	    emit( 'start|restart|refresh|disable|enable)' );
	} else {
	    emit( 'start|restart|refresh|disable|enable|restore)' );
	}

	push_indent;

	set_global_variables(1);

	handle_optional_interfaces(0);

	emit ';;';

	if ( $global_variables == ( ALL_COMMANDS | NOT_RESTORE ) ) {
	    pop_indent;

	    emit 'restore)';

	    push_indent;

	    set_global_variables(0);

	    handle_optional_interfaces(0);

	    emit ';;';
	}

	pop_indent;
	pop_indent;

	emit ( 'esac' ) ,
    } else {
	emit( 'true' ) unless handle_optional_interfaces(1);
    }

    pop_indent;

    emit "\n}\n"; # End of detect_configuration()

}

# Final stage of script generation.
#
#    Generate code for loading the various files in /var/lib/shorewall[6][-lite]
#    Generate code to add IP addresses under ADD_IP_ALIASES and ADD_SNAT_ALIASES
#    Generate the 'setup_netfilter()' function that runs iptables-restore.
#    Generate the 'define_firewall()' function.
#
#    Note: This function is not called when $command eq 'check'. So it must have no side effects other
#          than those related to writing to the output script file.
#
sub generate_script_3($) {

    if ( $family == F_IPV4 ) {
	progress_message2 "Creating iptables-restore input...";
    } else {
	progress_message2 "Creating ip6tables-restore input...";
    }

    create_netfilter_load( $test );
    create_arptables_load( $test ) if $have_arptables;
    create_chainlist_reload( $_[0] );

    emit "#\n# Start/Restart the Firewall\n#";

    emit 'define_firewall() {';

    push_indent;

    save_progress_message 'Initializing...';

    if ( $export || $config{EXPORTMODULES} ) {
	my $fn = find_file( $config{LOAD_HELPERS_ONLY} ? 'helpers' : 'modules' );

	if ( -f $fn && ( $config{EXPORTMODULES} || ( $export && ! $fn =~ "^$globals{SHAREDIR}/" ) ) ) {
	    emit 'echo MODULESDIR="$MODULESDIR" > ${VARDIR}/.modulesdir';
	    emit 'cat > ${VARDIR}/.modules << EOF';
	    open_file $fn;

	    emit_unindented $currentline while read_a_line( NORMAL_READ );

	    emit_unindented 'EOF';
	    emit '', 'reload_kernel_modules < ${VARDIR}/.modules';
	} else {
	    emit 'load_kernel_modules Yes';
	}
    } else {
	emit 'load_kernel_modules Yes';
    }

    emit '';

    load_ipsets;
    create_nfobjects;

    if ( $family == F_IPV4 ) {
	emit ( 'if [ "$COMMAND" = refresh ]; then' ,
	       '   run_refresh_exit' ,
	       'else' ,
	       '    run_init_exit',
	       'fi',
	       '' );

	verify_address_variables;
	save_dynamic_chains;
	mark_firewall_not_started;

	emit ( '',
	       'delete_proxyarp',
	       ''
	     );

	if ( have_capability( 'NAT_ENABLED' ) ) {
	    emit(  'if [ -f ${VARDIR}/nat ]; then',
		   '    while read external interface; do',
		   '        del_ip_addr $external $interface',
		   '    done < ${VARDIR}/nat',
		   '',
		   '    rm -f ${VARDIR}/nat',
		   "fi\n" );
	}

	emit "disable_ipv6\n" if $config{DISABLE_IPV6};

    } else {
	emit ( 'if [ "$COMMAND" = refresh ]; then' ,
	       '   run_refresh_exit' ,
	       'else' ,
	       '    run_init_exit',
	       'fi',
	       '' );

	verify_address_variables;
	save_dynamic_chains;
	mark_firewall_not_started;

	emit ('',
	       'delete_proxyndp',
	       ''
	     );
    }

    emit qq(delete_tc1\n) if $config{CLEAR_TC};

    emit( 'setup_common_rules', '' );

    emit( 'setup_routing_and_traffic_shaping', '' );

    if ( $family == F_IPV4 ) {
	emit 'cat > ${VARDIR}/proxyarp << __EOF__';
    } else {
	emit 'cat > ${VARDIR}/proxyndp << __EOF__';
    }

    dump_proxy_arp;
    emit_unindented '__EOF__';

    emit( '',
	  'if [ "$COMMAND" != refresh ]; then' );

    push_indent;

    emit 'cat > ${VARDIR}/zones << __EOF__';
    dump_zone_contents;
    emit_unindented '__EOF__';

    emit 'cat > ${VARDIR}/policies << __EOF__';
    save_policies;
    emit_unindented '__EOF__';

    emit 'cat > ${VARDIR}/marks << __EOF__';
    dump_mark_layout;
    emit_unindented '__EOF__';

    pop_indent;

    emit "fi\n";

    emit '> ${VARDIR}/nat';

    add_addresses;

    emit( '',
	  'if [ $COMMAND = restore ]; then',
	  '    iptables_save_file=${VARDIR}/$(basename $0)-iptables',
	  '    if [ -f $iptables_save_file ]; then' );

    if ( $family == F_IPV4 ) {
	emit( '        cat $iptables_save_file | $IPTABLES_RESTORE # Use this nonsensical form to appease SELinux' );

	emit( '',
	      '        arptables_save_file=${VARDIR}/$(basename $0)-arptables',
	      '        if [ -f $arptables_save_file ]; then',
	      '            cat $arptables_save_file | $ARPTABLES_RESTORE',
	      '        fi')
	    if $config{SAVE_ARPTABLES};

    } else {
	emit '        cat $iptables_save_file | $IP6TABLES_RESTORE # Use this nonsensical form to appease SELinux'
    }

    emit( '    else',
	  '       fatal_error "$iptables_save_file does not exist"',
	  '    fi',
	  ''
	);

    push_indent;
    setup_load_distribution;
    setup_forwarding( $family , 1 );
    pop_indent;

    my $config_dir = $globals{CONFIGDIR};

    emit<<"EOF";
    set_state Started $config_dir
    run_restored_exit
elif [ \$COMMAND = refresh ]; then
    chainlist_reload
EOF
    push_indent;
    setup_load_distribution;
    setup_forwarding( $family , 0 );
    pop_indent;
    #
    # Use a parameter list rather than 'here documents' to avoid an extra blank line
    #
    emit(
'    run_refreshed_exit',
'    do_iptables -N shorewall' );

    emit ( '    do_iptables -A shorewall -m recent --set --name %CURRENTTIME' ) if have_capability 'RECENT_MATCH';

    emit(
"    set_state Started $config_dir",
'    [ $0 = ${VARDIR}/firewall ] || cp -f $(my_pathname) ${VARDIR}/firewall',
'else',
'    setup_netfilter'
	);
    push_indent;
    emit 'setup_arptables' if $have_arptables;
    setup_load_distribution;
    pop_indent;

    emit<<'EOF';
    conditionally_flush_conntrack
EOF
    push_indent;
    initialize_switches;
    setup_forwarding( $family , 0 );
    pop_indent;

    emit<<"EOF";
    run_start_exit
    do_iptables -N shorewall
EOF

    emit ( '    do_iptables -A shorewall -m recent --set --name %CURRENTTIME' ) if have_capability 'RECENT_MATCH';

    emit<<"EOF";
    set_state Started $config_dir
    my_pathname=\$(my_pathname)
    [ \$my_pathname = \${VARDIR}/firewall ] || cp -f \$my_pathname \${VARDIR}/firewall
    run_started_exit
fi
EOF

    emit<<'EOF';
date > ${VARDIR}/restarted

case $COMMAND in
    start)
        logger -p kern.info "$g_product started"
        ;;
    restart)
        logger -p kern.info "$g_product restarted"
        ;;
    refresh)
        logger -p kern.info "$g_product refreshed"
        ;;
    restore)
        logger -p kern.info "$g_product restored"
        ;;
esac
EOF

    pop_indent;

    emit "}\n";

}

#
#  The Compiler.
#
#     Arguments are named -- see %parms below.
#
sub compiler {

    my ( $scriptfilename, $directory, $verbosity, $timestamp , $debug, $chains , $log , $log_verbosity, $preview, $confess , $update , $annotate , $convert, $config_path, $shorewallrc                      , $shorewallrc1 , $directives ) =
       ( '',              '',         -1,          '',          0,      '',       '',   -1,             0,        0,         0,        0,        , 0       , ''          , '/usr/share/shorewall/shorewallrc', ''            , 0 );

    $export         = 0;
    $test           = 0;
    $have_arptables = 0;

    sub validate_boolean( $ ) {
	 my $val = numeric_value( shift );
	 defined($val) && ($val >= 0) && ($val < 2);
     }

    sub validate_verbosity( $ ) {
	 my $val = numeric_value( shift );
	 defined($val) && ($val >= MIN_VERBOSITY) && ($val <= MAX_VERBOSITY);
     }

    sub validate_family( $ ) {
	my $val = numeric_value( shift );
	defined($val) && ($val == F_IPV4 || $val == F_IPV6);
    }

    my %parms = ( object        => { store => \$scriptfilename },    #Deprecated
		  script        => { store => \$scriptfilename },
		  directory     => { store => \$directory  },
		  family        => { store => \$family    ,    validate => \&validate_family    } ,
		  verbosity     => { store => \$verbosity ,    validate => \&validate_verbosity } ,
		  timestamp     => { store => \$timestamp,     validate => \&validate_boolean   } ,
		  debug         => { store => \$debug,         validate => \&validate_boolean   } ,
		  export        => { store => \$export ,       validate => \&validate_boolean   } ,
		  chains        => { store => \$chains },
		  log           => { store => \$log },
		  log_verbosity => { store => \$log_verbosity, validate => \&validate_verbosity } ,
		  test          => { store => \$test },
		  preview       => { store => \$preview,       validate=> \&validate_boolean    } ,
		  confess       => { store => \$confess,       validate=> \&validate_boolean    } ,
		  update        => { store => \$update,        validate=> \&validate_boolean    } ,
		  convert       => { store => \$convert,       validate=> \&validate_boolean    } ,
		  annotate      => { store => \$annotate,      validate=> \&validate_boolean    } ,
		  directives    => { store => \$directives,    validate=> \&validate_boolean    } ,
		  config_path   => { store => \$config_path } ,
		  shorewallrc   => { store => \$shorewallrc } ,
		  shorewallrc1  => { store => \$shorewallrc1 } ,
		);
    #
    #                               P A R A M E T E R    P R O C E S S I N G
    #
    while ( defined ( my $name = shift ) ) {
	fatal_error "Unknown parameter ($name)" unless my $ref = $parms{$name};
	fatal_error "Undefined value supplied for parameter $name" unless defined ( my $val = shift ) ;
	if ( $ref->{validate} ) {
	    fatal_error "Invalid value ( $val ) supplied for parameter $name" unless $ref->{validate}->($val);
	}

	${$ref->{store}} = $val;
    }

    #
    # Now that we know the address family (IPv4/IPv6), we can initialize the other modules' globals
    #
    initialize_package_globals( $update, $shorewallrc, $shorewallrc1 );

    set_config_path( $config_path ) if $config_path;

    if ( $directory ne '' ) {
	fatal_error "$directory is not an existing directory" unless -d $directory;
	set_shorewall_dir( $directory );
    }

    $verbosity = 1 if $debug && $verbosity < 1;

    set_verbosity( $verbosity );
    set_log($log, $log_verbosity) if $log;
    set_timestamp( $timestamp );
    set_debug( $debug , $confess );
    #
    #                      S H O R E W A L L . C O N F  A N D  C A P A B I L I T I E S
    #
    get_configuration( $export , $update , $annotate , $directives );
    #
    # Create a temp file to hold the script
    #
    if ( $scriptfilename ) {
	set_command( 'compile', 'Compiling', 'Compiled' );
	create_temp_script( $scriptfilename , $export );
    } else {
	set_command( 'check', 'Checking', 'Checked' );
    }
    #
    # Chain table initialization depends on shorewall.conf and capabilities. So it must be deferred until
    # now when shorewall.conf has been processed and the capabilities have been determined.
    #
    initialize_chain_table(1);
    #
    # Allow user to load Perl modules
    #
    run_user_exit1 'compile';
    #
    #                                     Z O N E   D E F I N I T I O N
    #                              (Produces no output to the compiled script)
    #
    determine_zones;
    #
    # Process the interfaces file.
    #
    validate_interfaces_file ( $export );
    #
    # Process the hosts file.
    #
    validate_hosts_file;
    #
    # Report zone contents
    #
    zone_report;
    #
    # Do action pre-processing.
    #
    process_actions;
    #
    #                                        P O L I C Y
    #                           (Produces no output to the compiled script)
    #
    process_policies;

    enable_script;

    if ( $scriptfilename || $debug ) {
	#
	# Place Header in the script
	#
	generate_script_1( $scriptfilename );
	#
	#                               C O M M O N _ R U L E S
	#           (Writes the setup_common_rules() function to the compiled script)
	#
	emit(  "\n#",
	       '# Setup Common Rules (/proc)',
	       '#',
	       'setup_common_rules() {'
	    );

	push_indent;
    }
    #
    # Do all of the zone-independent stuff (mostly /proc)
    #
    add_common_rules( $convert );
    #
    # More /proc
    #
    if ( $family == F_IPV4 ) {
	setup_arp_filtering;
	setup_route_filtering;
	setup_martian_logging;
    }

    setup_source_routing($family);
    #
    # Proxy Arp/Ndp
    #
    setup_proxy_arp;

    emit( "#\n# Disable automatic helper association on kernel 3.5.0 and later\n#" ,
	  'if [ -f /proc/sys/net/netfilter/nf_conntrack_helper ]; then' ,
	  '    progress_message "Disabling Kernel Automatic Helper Association"',
	  "    echo 0 > /proc/sys/net/netfilter/nf_conntrack_helper",
	  'fi',
	  ''
	);

    setup_accept_ra if $family == F_IPV6;

    if ( $scriptfilename || $debug ) {
	emit 'return 0';
	pop_indent;
	emit '}'; # End of setup_common_rules()
    }

    disable_script;
    #
    #                      R O U T I N G _ A N D _ T R A F F I C _ S H A P I N G
    #         (Writes the setup_routing_and_traffic_shaping() function to the compiled script)
    #
    enable_script;
    #
    # Validate the TC files so that the providers will know what interfaces have TC
    #
    my $tcinterfaces = process_tc;
    #
    # Generate a function to bring up each provider
    #
    process_providers( $tcinterfaces );
    #
    # [Re-]establish Routing
    #
    if ( $scriptfilename || $debug ) {
	emit(  "\n#",
	       '# Setup routing and traffic shaping',
	       '#',
	       'setup_routing_and_traffic_shaping() {'
	    );

	push_indent;
    }

    setup_providers;
    #
    # TCRules and Traffic Shaping
    #
    setup_tc;

    if ( $scriptfilename || $debug ) {
	pop_indent;
	emit "}\n"; # End of setup_routing_and_traffic_shaping()
    }

    $have_arptables = process_arprules if $family == F_IPV4;

    disable_script;
    #
    #                                       N E T F I L T E R
    #       (Produces no output to the compiled script -- rules are stored in the chain table)
    #
    process_tos;
    #
    # ECN
    #
    setup_ecn if $family == F_IPV4 && have_capability( 'MANGLE_ENABLED' ) && $config{MANGLE_ENABLED};
    #
    # Setup Masquerading/SNAT
    #
    setup_masq;
    #
    # Setup Nat
    #
    setup_nat if $family == F_IPV4;
    #
    # Setup NETMAP
    #
    setup_netmap;
    #
    # MACLIST Filtration
    #
    setup_mac_lists 1;
    #
    # Process the rules file.
    #
    process_rules( $convert );
    #
    # Process the conntrack file
    #
    setup_conntrack;
    #
    # Add Tunnel rules.
    #
    setup_tunnels;
    #
    # Clear the current filename
    #
    clear_currentfilename;
    #
    # MACLIST Filtration again
    #
    setup_mac_lists 2;
    #
    # Apply Policies
    #
    apply_policy_rules;
    #
    # Reject Action
    #
    process_reject_action if $config{REJECT_ACTION};
    #
    # Accounting.
    #
    setup_accounting if $config{ACCOUNTING};

    if ( $scriptfilename ) {
	#
	# Compiling a script - generate the zone by zone matrix
	#
	generate_matrix;

	optimize_level0;

	if ( ( my $optimize = $config{OPTIMIZE} ) & 0x1E ) {
	    progress_message2 'Optimizing Ruleset...';
	    #
	    # Optimize Policy Chains
	    #
	    optimize_policy_chains if ( $optimize & OPTIMIZE_POLICY_MASK2n4 ) == OPTIMIZE_POLICY_MASK; # Level 2 but not 4
	    #
	    # More Optimization
	    #
	    optimize_ruleset if $config{OPTIMIZE} & OPTIMIZE_RULESET_MASK;
	}

	enable_script;
	#
	#                             I N I T I A L I Z E
	#           (Writes the initialize() function to the compiled script)
	#
	generate_script_2;
	#
	#                          N E T F I L T E R   L O A D
	#    (Produces setup_netfilter(), setup_arptables(), chainlist_reload() and define_firewall() )
	#
	generate_script_3( $chains );
	#
	# We must reinitialize Shorewall::Chains before generating the iptables-restore input
	# for stopping the firewall
	#
	Shorewall::Chains::initialize( $family, 0 , $export );
	initialize_chain_table(0);
	#
	#                           S T O P _ F I R E W A L L
	#         (Writes the stop_firewall() function to the compiled script)
	#
	compile_stop_firewall( $test, $export , $have_arptables );
	#
	#                               U P D O W N
	#               (Writes the updown() function to the compiled script)
	#
	compile_updown;
	#
	# Copy the footer to the script
	#
	copy $globals{SHAREDIRPL} . 'prog.footer' unless $test;

	disable_script;
	#
	# Close, rename and secure the script
	#
	finalize_script ( $export );
	#
	# And generate the auxilary config file
	#
	enable_script, generate_aux_config if $export;
	#
	# Report used/required capabilities
	#
	report_used_capabilities;
    } else {
	#
	# Just checking the configuration
	#
	if ( $preview || $debug ) {
	    #
	    # User wishes to preview the ruleset or we are tracing -- generate the rule matrix
	    #
	    generate_matrix;

	    optimize_level0;

	    if ( ( my $optimize = $config{OPTIMIZE} ) & 0x1e ) {
		progress_message2 'Optimizing Ruleset...';
		#
		# Optimize Policy Chains
		#
		optimize_policy_chains if ( $optimize & OPTIMIZE_POLICY_MASK2n4 ) == OPTIMIZE_POLICY_MASK; # Level 2 but not 4
		#
		# Ruleset Optimization
		#
		optimize_ruleset if $optimize & OPTIMIZE_RULESET_MASK;
	    }

	    enable_script if $debug;

	    generate_script_2 if $debug;

	    if ( $preview ) {
		preview_netfilter_load;
		preview_arptables_load if $have_arptables;
	    }
	}
	#
	# Re-initialize the chain table so that process_routestopped() has the same
	# environment that it would when called by compile_stop_firewall().
	#
	Shorewall::Chains::initialize( $family , 0 , $export );
	initialize_chain_table(0);

	if ( $debug ) {
	    compile_stop_firewall( $test, $export, $have_arptables );
	    disable_script;
	} else {
	    #
	    # compile_stop_firewall() also validates the routestopped file. Since we don't
	    # call that function during normal 'check', we must validate routestopped here.
	    #
	    process_routestopped;
	    process_stoppedrules;
	}
	#
	# Report used/required capabilities
	#
	report_used_capabilities;

	if ( $family == F_IPV4 ) {
	    progress_message3 "Shorewall configuration verified";
	} else {
	    progress_message3 "Shorewall6 configuration verified";
	}
    }

    close_log if $log;

    1;
}

1;
