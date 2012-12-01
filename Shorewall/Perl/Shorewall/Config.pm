#
# Shorewall 4.4 -- /usr/share/shorewall/Shorewall/Config.pm
#
#     This program is under GPL [http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt]
#
#     (c) 2007,2008,2009,2010,2011,2012 - Tom Eastep (teastep@shorewall.net)
#
#       Complete documentation is available at http://shorewall.net
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
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
#   This module is responsible for lower level configuration file handling.
#   It also exports functions for generating warning and error messages.
#   The get_configuration function parses the shorewall.conf, capabilities and
#   modules files during compiler startup. The module also provides the basic
#   output file services such as creation of temporary 'script' files, writing
#   into those files (emitters) and finalizing those files (renaming
#   them to their final name and setting their mode appropriately).
#
package Shorewall::Config;

use strict;
use warnings;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use Cwd qw(abs_path getcwd);
use autouse 'Carp' => qw(longmess confess);
use Scalar::Util 'reftype';
use FindBin;

our @ISA = qw(Exporter);
#
# Imported variables should be treated as read-only by importers
#
our @EXPORT = qw(
		 warning_message
		 fatal_error
		 assert
		 currentlineinfo

		 progress_message
		 progress_message_nocompress
		 progress_message2
		 progress_message3

		 supplied
		 split_list

		 get_action_params
		 get_action_chain
		 set_action_param

		 have_capability
		 require_capability
		 kernel_version
                );

our @EXPORT_OK = qw( $shorewall_dir initialize shorewall);

our %EXPORT_TAGS = ( internal => [ qw( create_temp_script
				       finalize_script
				       enable_script
				       disable_script
		                       numeric_value
		                       numeric_value1
				       normalize_hex
		                       hex_value
		                       in_hex
		                       in_hex2
		                       in_hex3
		                       in_hex4
		                       in_hex8
		                       in_hexp
				       emit
				       emitstd
				       emit_unindented
				       save_progress_message
				       save_progress_message_short
				       set_timestamp
				       set_verbosity
				       set_log
				       set_config_path
				       close_log
				       set_command
				       push_indent
				       pop_indent
				       copy
				       copy1
				       copy2
				       create_temp_aux_config
				       finalize_aux_config
				       set_shorewall_dir
				       set_debug
				       find_file
				       split_list
				       split_list1
				       split_line
				       split_line1
				       first_entry
				       open_file
				       close_file
				       push_open
				       pop_open
				       push_action_params
				       pop_action_params
				       default_action_params
				       read_a_line
				       validate_level
				       which
				       qt
				       ensure_config_path
				       add_param
				       export_params
				       get_configuration
				       report_capabilities
				       propagateconfig
				       append_file
				       run_user_exit
				       run_user_exit1
				       run_user_exit2
				       generate_aux_config
				       dump_mark_layout

				       $product
				       $Product
				       $toolname
				       $command
				       $doing
				       $done
				       $currentline
				       $currentfilename
				       $debug
				       %config
				       %globals
				       %config_files
				       %shorewallrc
				       %shorewallrc1

				       %helpers
				       %helpers_map
				       %helpers_enabled
				       %helpers_aliases
				       
		                       F_IPV4
		                       F_IPV6

				       TCP
				       UDP
				       UDPLITE
				       ICMP
				       DCCP
				       IPv6_ICMP
				       SCTP
				       GRE

				       MIN_VERBOSITY
				       MAX_VERBOSITY

				       PLAIN_READ
				       EMBEDDED_ENABLED
				       EXPAND_VARIABLES
				       STRIP_COMMENTS
				       SUPPRESS_WHITESPACE
				       CONFIG_CONTINUATION
				       DO_INCLUDE
				       NORMAL_READ
				     ) , ] ,
		   protocols => [ qw (
				       TCP
				       UDP
				       UDPLITE
				       ICMP
				       DCCP
				       IPv6_ICMP
				       SCTP
				       GRE
				    ) , ],
		   );

Exporter::export_ok_tags('internal');

our $VERSION = 'MODULEVERSION';

#
# describe the current command, it's present progressive, and it's completion.
#
our ($command, $doing, $done );
#
# VERBOSITY
#
my $verbosity;
#
# Logging
#
my ( $log, $log_verbosity );
#
# Timestamp each progress message, if true.
#
my $timestamp;
#
# Script (output) file handle
#
my $script;
#
# When 'true', writes to the script are enabled. Used to catch code emission between functions
#
my $script_enabled;
#
# True, if last line emitted is blank
#
my $lastlineblank;
#
# Tabs to indent the output
#
my $indent1;
#
# Characters to indent the output
#
my $indent2;
#
# Total indentation
#
my $indent;
#
# Script's Directory and File
#
my ( $dir, $file );
#
# Temporary output file's name
#
my $tempfile;
#
# Fully qualified name of the configuration file
#
my $configfile;
#
# Misc Globals exported to other modules
#
our %globals;
#
# From shorewall.conf file - exported to other modules.
#
our %config;
#
# Entries in shorewall.conf that have been renamed
#
my %renamed = ( AUTO_COMMENT => 'AUTOCOMMENT' );
#
# Config options and global settings that are to be copied to output script
#
my @propagateconfig = qw/ DISABLE_IPV6 MODULESDIR MODULE_SUFFIX LOAD_HELPERS_ONLY SUBSYSLOCK LOG_VERBOSITY/;
#
# From parsing the capabilities file or detecting capabilities
#
my %capabilities;
#
# Capabilities
#
my  %capdesc = ( NAT_ENABLED     => 'NAT',
		 MANGLE_ENABLED  => 'Packet Mangling',
		 MULTIPORT       => 'Multi-port Match' ,
		 XMULTIPORT      => 'Extended Multi-port Match',
		 CONNTRACK_MATCH => 'Connection Tracking Match',
		 OLD_CONNTRACK_MATCH =>
		                    'Old conntrack match syntax',
		 NEW_CONNTRACK_MATCH =>
		                    'Extended Connection Tracking Match',
		 USEPKTTYPE      => 'Packet Type Match',
		 POLICY_MATCH    => 'Policy Match',
		 PHYSDEV_MATCH   => 'Physdev Match',
		 PHYSDEV_BRIDGE  => 'Physdev-is-bridged support',
		 LENGTH_MATCH    => 'Packet length Match',
		 IPRANGE_MATCH   => 'IP Range Match',
		 RECENT_MATCH    => 'Recent Match',
		 OWNER_MATCH     => 'Owner Match',
		 OWNER_NAME_MATCH
		                 => 'Owner Name Match',
		 IPSET_MATCH     => 'Ipset Match',
		 OLD_IPSET_MATCH => 'Old Ipset Match',
		 IPSET_V5        => 'Version 5 ipsets',
		 CONNMARK        => 'CONNMARK Target',
		 XCONNMARK       => 'Extended CONNMARK Target',
		 CONNMARK_MATCH  => 'Connmark Match',
		 XCONNMARK_MATCH => 'Extended Connmark Match',
		 RAW_TABLE       => 'Raw Table',
		 IPP2P_MATCH     => 'IPP2P Match',
		 OLD_IPP2P_MATCH => 'Old IPP2P Match Syntax',
		 CLASSIFY_TARGET => 'CLASSIFY Target',
		 ENHANCED_REJECT => 'Extended Reject',
		 KLUDGEFREE      => 'Repeat match',
		 MARK            => 'MARK Target',
		 XMARK           => 'Extended Mark Target',
		 EXMARK          => 'Extended Mark Target 2',
		 MANGLE_FORWARD  => 'Mangle FORWARD Chain',
		 COMMENTS        => 'Comments',
		 ADDRTYPE        => 'Address Type Match',
		 TCPMSS_MATCH    => 'TCPMSS Match',
		 HASHLIMIT_MATCH => 'Hashlimit Match',
		 NFQUEUE_TARGET  => 'NFQUEUE Target',
		 REALM_MATCH     => 'Realm Match',
		 HELPER_MATCH    => 'Helper Match',
		 CONNLIMIT_MATCH => 'Connlimit Match',
		 TIME_MATCH      => 'Time Match',
		 GOTO_TARGET     => 'Goto Support',
		 LOG_TARGET      => 'LOG Target',
		 ULOG_TARGET     => 'ULOG Target',
		 NFLOG_TARGET    => 'NFLOG Target',
		 LOGMARK_TARGET  => 'LOGMARK Target',
		 IPMARK_TARGET   => 'IPMARK Target',
		 PERSISTENT_SNAT => 'Persistent SNAT',
		 OLD_HL_MATCH    => 'Old Hash Limit Match',
		 TPROXY_TARGET   => 'TPROXY Target',
		 FLOW_FILTER     => 'Flow Classifier',
		 FWMARK_RT_MASK  => 'fwmark route mask',
		 MARK_ANYWHERE   => 'Mark in any table',
		 HEADER_MATCH    => 'Header Match',
		 ACCOUNT_TARGET  => 'ACCOUNT Target',
		 AUDIT_TARGET    => 'AUDIT Target',
		 RAWPOST_TABLE   => 'Rawpost Table',
		 CONDITION_MATCH => 'Condition Match',
		 IPTABLES_S      => 'iptables -S',
		 BASIC_FILTER    => 'Basic Filter',
		 CT_TARGET       => 'CT Target',
		 STATISTIC_MATCH =>
		                    'Statistics Match',
		 IMQ_TARGET      => 'IMQ Target',
		 DSCP_MATCH      => 'DSCP Match',
		 DSCP_TARGET     => 'DSCP Target',
		 GEOIP_MATCH     => 'GeoIP Match' ,
		 RPFILTER_MATCH  => 'RPFilter Match',
		 NFACCT_MATCH    => 'NFAcct Match',
		 CHECKSUM_TARGET => 'Checksum Target',
		 AMANDA_HELPER   => 'Amanda Helper',
		 FTP_HELPER      => 'FTP Helper',
		 FTP0_HELPER     => 'FTP-0 Helper',
		 H323_HELPER     => 'H323 Helpers',
		 IRC_HELPER      => 'IRC Helper',
		 IRC0_HELPER     => 'IRC-0 Helper',
		 NETBIOS_NS_HELPER =>
                                    'Netbios-ns Helper',
		 PPTP_HELPER     => 'PPTP Helper',
		 SANE_HELPER     => 'SANE Helper',
		 SANE0_HELPER    => 'SANE-0 Helper',
		 SIP_HELPER      => 'SIP Helper',
		 SIP0_HELPER     => 'SIP-0 Helper',
		 SNMP_HELPER     => 'SNMP Helper',
		 TFTP_HELPER     => 'TFTP Helper',
		 TFTP0_HELPER     => 'TFTP-0 Helper',
		 #
		 # Constants
		 #
		 LOG_OPTIONS     => 'Log Options',
		 CAPVERSION      => 'Capability Version',
		 KERNELVERSION   => 'Kernel Version',
	       );

use constant {
	       ICMP                => 1,
	       TCP                 => 6,
	       UDP                 => 17,
	       DCCP                => 33,
	       GRE                 => 47,
	       IPv6_ICMP           => 58,
	       SCTP                => 132,
	       UDPLITE             => 136,
	     };

our %helpers = ( amanda          => UDP,
		 ftp             => TCP,
		 irc             => TCP,
		 'netbios-ns'    => UDP,
		 pptp            => TCP,
		 'Q.931'         => TCP,
		 RAS             => UDP,
		 sane            => TCP,
		 sip             => UDP,
		 snmp            => UDP,
		 tftp            => UDP,
	       );

our %helpers_map;

our %helpers_names;

our %helpers_aliases;

our %helpers_enabled;

our %config_files = ( #accounting      => 1,
		      actions          => 1,
		      blacklist        => 1,
		      clear            => 1,
		      conntrack        => 1,
		      ecn              => 1,
		      findgw           => 1,
		      hosts            => 1,
		      init             => 1,
		      initdone         => 1,
		      interfaces       => 1,
		      isusable         => 1,
		      maclist          => 1,
		      masq             => 1,
		      nat              => 1,
		      netmap           => 1,
		      notrack          => 1,
		      params           => 1,
		      policy           => 1,
		      providers        => 1,
		      proxyarp         => 1,
		      refresh          => 1,
		      refreshed        => 1,
		      restored         => 1,
		      rawnat           => 1,
		      route_rules      => 1,
		      routes           => 1,
		      routestopped     => 1,
		      rtrules          => 1,
		      rules            => 1,
		      scfilter         => 1,
		      secmarks         => 1,
		      start            => 1,
		      started          => 1,
		      stop             => 1,
		      stopped          => 1,
		      stoppedrules     => 1,
		      tcclasses        => 1,
		      tcclear          => 1,
		      tcdevices        => 1,
		      tcfilters        => 1,
		      tcinterfaces     => 1,
		      tcpri            => 1,
		      tcrules          => 1,
		      tos              => 1,
		      tunnels          => 1,
		      zones            => 1 );
#
# Options that involve the the AUDIT target
#
our @auditoptions = qw( BLACKLIST_DISPOSITION MACLIST_DISPOSITION TCP_FLAGS_DISPOSITION );
#
# Directories to search for configuration files
#
my @config_path;
#
# Stash away file references here when we encounter INCLUDE
#
my @includestack;
#
# Allow nested opens
#
my @openstack;
#
# From the params file
#
my %params;
#
# Entries that the compiler adds to %params
#
my %compiler_params;
#
# Action parameters
#
my @actparms;

our $currentline;            # Current config file line image
my  $currentfile;            # File handle reference
our $currentfilename;        # File NAME
my  $currentlinenumber;      # Line number
my  $perlscript;             # File Handle Reference to current temporary file being written by an in-line Perl script
my  $perlscriptname;         # Name of that file.
my  $embedded;               # True if we're in an embedded perl script
my  @tempfiles;              # Files that need unlinking at END
my  $first_entry;            # Message to output or function to call on first non-blank line of a file

my $shorewall_dir;           # Shorewall Directory; if non-empty, search here first for files.

our $debug;                  # Global debugging flag
my  $confess;                # If true, use Carp to report errors with stack trace.

our $family;                 # Protocol family (4 or 6)
our $toolname;               # Name of the tool to use (iptables or iptables6)
my  $toolNAME;               # Tool name in CAPS
our $product;                # Name of product that will run the generated script
our $Product;                # $product with initial cap.

our $sillyname;              # Name of temporary filter chains for testing capabilities
our $sillyname1;
my $iptables;                # Path to iptables/ip6tables
my $tc;                      # Path to tc
my $ip;                      # Path to ip

my $shell;                   # Type of shell that processed the params file

use constant { BASH    => 1,
	       OLDBASH => 2,
	       ASH     => 3 };

use constant { MIN_VERBOSITY => -1,
	       MAX_VERBOSITY => 2 ,
	       F_IPV4 => 4,
	       F_IPV6 => 6,
	     };

my %validlevels;             # Valid log levels.

#
# Deprecated options with their default values
#
my %deprecated = ( LOGRATE            => '' ,
		   LOGBURST           => '' ,
		   EXPORTPARAMS       => 'no',
		   WIDE_TC_MARKS      => 'no',
		   HIGH_ROUTE_MARKS   => 'no'
		 );
#
# Deprecated options that are eliminated via update
#
my %converted = ( WIDE_TC_MARKS => 1,
		  HIGH_ROUTE_MARKS => 1 );
#
# Variables involved in ?IF, ?ELSE ?ENDIF processing
#
my $omitting;
my @ifstack;
my $ifstack;
#
# Entries on the ifstack are a 4-tuple:
#
#    [0] - Keyword (IF, ELSEIF, ELSE or ENDIF)
#    [1] - True if the outermost IF evaluated to false
#    [2] - True if the the last unterminated IF evaluated to false
#
# From .shorewallrc
#
our ( %shorewallrc, %shorewallrc1 );
#
# read_a_line options
#
use constant { PLAIN_READ          => 0,     # No read_a_line options
               EMBEDDED_ENABLED    => 1,     # Look for embedded Shell and Perl
	       EXPAND_VARIABLES    => 2,     # Expand Shell variables
	       STRIP_COMMENTS      => 4,     # Remove comments
	       SUPPRESS_WHITESPACE => 8,     # Ignore blank lines
	       CHECK_GUNK          => 16,    # Look for unprintable characters
	       CONFIG_CONTINUATION => 32,    # Suppress leading whitespace if
                                             # continued line ends in ',' or ':'
	       DO_INCLUDE          => 64,    # Look for INCLUDE <filename>
               NORMAL_READ         => -1     # All options
	   };

sub process_shorewallrc($$);
#
# Rather than initializing globals in an INIT block or during declaration,
# we initialize them in a function. This is done for two reasons:
#
#   1. Proper initialization depends on the address family which isn't
#      known until the compiler has started.
#
#   2. The compiler can run multiple times in the same process so it has to be
#      able to re-initialize its dependent modules' state.
#
sub initialize( $;$$) {
    ( $family, my ( $shorewallrc, $shorewallrc1 ) ) = @_;

    if ( $family == F_IPV4 ) {
	( $product, $Product, $toolname, $toolNAME ) = qw( shorewall  Shorewall iptables  IPTABLES );
    } else {
	( $product, $Product, $toolname, $toolNAME ) = qw( shorewall6 Shorewall6 ip6tables IP6TABLES );
    }

    $verbosity      = 0;       # Verbosity setting. -1 = silent, 0 = almost silent, 1 = major progress messages only, 2 = all progress messages (very noisy)
    $log            = undef;   # File reference for log file
    $log_verbosity  = -1;      # Verbosity of log.
    $timestamp      = '';      # If true, we are to timestamp each progress message
    $script         = 0;       # Script (output) file Handle Reference
    $script_enabled = 0;       # Writing to output file is disabled initially
    $lastlineblank  = 0;       # Avoid extra blank lines in the output
    $indent1        = '';      # Current indentation tabs
    $indent2        = '';      # Current indentation spaces
    $indent         = '';      # Current total indentation
    ( $dir, $file ) = ('',''); # Script's Directory and Filename
    $tempfile       = '';      # Temporary File Name
    $sillyname      =
    $sillyname1     = '';      # Temporary ipchains
    $omitting       = 0;
    $ifstack        = 0;
    @ifstack        = ();
    $embedded       = 0;
    #
    # Misc Globals
    #
    %globals  =   ( SHAREDIRPL => '' ,
		    CONFDIR    => '',         # Run-time configuration directory
		    CONFIGDIR  => '',         # Compile-time configuration directory (location of $product.conf)
		    LOGPARMS   => '',
		    TC_SCRIPT  => '',
		    EXPORT     => 0,
		    KLUDGEFREE => '',
		    STATEMATCH => '-m state --state',
		    VERSION    => "4.5.8-Beta2",
		    CAPVERSION => 40509 ,
		  );
    #
    # From shorewall.conf file
    #
    %config =
	( STARTUP_ENABLED => undef,
	  VERBOSITY => undef,
	  #
	  # Logging
	  #
	  LOGFILE => undef,
	  LOGFORMAT => undef,
	  LOGTAGONLY => undef,
	  LOGLIMIT => undef,
	  LOGRATE => undef,
	  LOGBURST => undef,
	  LOGALLNEW => undef,
	  BLACKLIST_LOGLEVEL => undef,
	  RELATED_LOG_LEVEL => undef,
	  RFC1918_LOG_LEVEL => undef,
	  MACLIST_LOG_LEVEL => undef,
	  TCP_FLAGS_LOG_LEVEL => undef,
	  SMURF_LOG_LEVEL => undef,
	  LOG_MARTIANS => undef,
	  LOG_VERBOSITY => undef,
	  STARTUP_LOG => undef,
	  SFILTER_LOG_LEVEL => undef,
	  RPFILTER_LOG_LEVEL => undef,
	  #
	  # Location of Files
	  #
	  IP => undef,
	  TC => undef,
	  IPSET => undef,
	  PERL => undef,
	  PATH => undef,
	  SHOREWALL_SHELL => undef,
	  SUBSYSLOCK => undef,
	  MODULESDIR => undef,
	  CONFIG_PATH => undef,
	  RESTOREFILE => undef,
	  IPSECFILE => undef,
	  LOCKFILE => undef,
	  GEOIPDIR => undef,
	  NFACCT => undef,
	  #
	  # Default Actions/Macros
	  #
	  DROP_DEFAULT => undef,
	  REJECT_DEFAULT => undef,
	  ACCEPT_DEFAULT => undef,
	  QUEUE_DEFAULT => undef,
	  NFQUEUE_DEFAULT => undef,
	  #
	  # RSH/RCP Commands
	  #
	  RSH_COMMAND => undef,
	  RCP_COMMAND => undef,
	  #
	  # Firewall Options
	  #
	  BRIDGING => undef,
	  IP_FORWARDING => undef,
	  ADD_IP_ALIASES => undef,
	  ADD_SNAT_ALIASES => undef,
	  RETAIN_ALIASES => undef,
	  TC_ENABLED => undef,
	  TC_EXPERT => undef,
	  TC_PRIOMAP => undef,
	  CLEAR_TC => undef,
	  MARK_IN_FORWARD_CHAIN => undef,
	  CLAMPMSS => undef,
	  ROUTE_FILTER => undef,
	  DETECT_DNAT_IPADDRS => undef,
	  MUTEX_TIMEOUT => undef,
	  ADMINISABSENTMINDED => undef,
	  BLACKLISTNEWONLY => undef,
	  DELAYBLACKLISTLOAD => undef,
	  MODULE_SUFFIX => undef,
	  DISABLE_IPV6 => undef,
	  DYNAMIC_ZONES => undef,
	  PKTTYPE=> undef,
	  MACLIST_TABLE => undef,
	  MACLIST_TTL => undef,
	  SAVE_IPSETS => undef,
	  MAPOLDACTIONS => undef,
	  FASTACCEPT => undef,
	  IMPLICIT_CONTINUE => undef,
	  IPSET_WARNINGS => undef,
	  HIGH_ROUTE_MARKS => undef,
	  USE_ACTIONS=> undef,
	  OPTIMIZE => undef,
	  EXPORTPARAMS => undef,
	  SHOREWALL_COMPILER => undef,
	  EXPAND_POLICIES => undef,
	  KEEP_RT_TABLES => undef,
	  DELETE_THEN_ADD => undef,
	  MULTICAST => undef,
	  DONT_LOAD => '',
	  AUTOCOMMENT => undef ,
	  MANGLE_ENABLED => undef ,
	  RFC1918_STRICT => undef ,
	  NULL_ROUTE_RFC1918 => undef ,
	  USE_DEFAULT_RT => undef ,
	  RESTORE_DEFAULT_ROUTE => undef ,
	  FAST_STOP => undef ,
	  AUTOMAKE => undef ,
	  WIDE_TC_MARKS => undef,
	  TRACK_PROVIDERS => undef,
	  ZONE2ZONE => undef,
	  ACCOUNTING => undef,
	  OPTIMIZE_ACCOUNTING => undef,
	  ACCOUNTING_TABLE => undef,
	  DYNAMIC_BLACKLIST => undef,
	  LOAD_HELPERS_ONLY => undef,
	  REQUIRE_INTERFACE => undef,
	  FORWARD_CLEAR_MARK => undef,
	  COMPLETE => undef,
	  EXPORTMODULES => undef,
	  LEGACY_FASTSTART => undef,
	  USE_PHYSICAL_NAMES => undef,
	  HELPERS => undef,
	  AUTOHELPERS => undef,
	  RESTORE_ROUTEMARKS => undef,
	  #
	  # Packet Disposition
	  #
	  MACLIST_DISPOSITION => undef,
	  TCP_FLAGS_DISPOSITION => undef,
	  BLACKLIST_DISPOSITION => undef,
	  SMURF_DISPOSITION => undef,
	  SFILTER_DISPOSITION => undef,
	  RPFILTER_DISPOSITION => undef,
	  RELATED_DISPOSITION => undef,
	  #
	  # Mark Geometry
	  #
	  TC_BITS => undef,
	  PROVIDER_BITS => undef,
	  PROVIDER_OFFSET => undef,
	  MASK_BITS => undef,
	  ZONE_BITS => undef,
	);


    #
    # Valid log levels
    #
    # Note that we don't include LOGMARK; that is so we can default its
    # priority to 'info' (LOGMARK itself defaults to 'warn').
    #
    %validlevels = ( DEBUG   => 7,
		     INFO    => 6,
		     NOTICE  => 5,
		     WARNING => 4,
		     WARN    => 4,
		     ERR     => 3,
		     ERROR   => 3,
		     CRIT    => 2,
		     ALERT   => 1,
		     EMERG   => 0,
		     PANIC   => 0,
		     NONE    => '',
		     NFLOG   => 'NFLOG',
		     LOGMARK => 'LOGMARK',
		   );

    #
    # From parsing the capabilities file or capabilities detection
    #
    %capabilities =
	     ( NAT_ENABLED => undef,
	       MANGLE_ENABLED => undef,
	       MULTIPORT => undef,
	       XMULTIPORT => undef,
	       CONNTRACK_MATCH => undef,
	       NEW_CONNTRACK_MATCH => undef,
	       OLD_CONNTRACK_MATCH => undef,
	       USEPKTTYPE => undef,
	       POLICY_MATCH => undef,
	       PHYSDEV_MATCH => undef,
	       PHYSDEV_BRIDGE => undef,
	       LENGTH_MATCH => undef,
	       IPRANGE_MATCH => undef,
	       RECENT_MATCH => undef,
	       OWNER_MATCH => undef,
	       OWNER_NAME_MATCH => undef,
	       IPSET_MATCH => undef,
	       OLD_IPSET_MATCH => undef,
	       IPSET_V5 => undef,
	       CONNMARK => undef,
	       XCONNMARK => undef,
	       CONNMARK_MATCH => undef,
	       XCONNMARK_MATCH => undef,
	       RAW_TABLE => undef,
	       RAWPOST_TABLE => undef,
	       IPP2P_MATCH => undef,
	       OLD_IPP2P_MATCH => undef,
	       CLASSIFY_TARGET => undef,
	       ENHANCED_REJECT => undef,
	       KLUDGEFREE => undef,
	       MARK => undef,
	       XMARK => undef,
	       EXMARK => undef,
	       MANGLE_FORWARD => undef,
	       COMMENTS => undef,
	       ADDRTYPE => undef,
	       TCPMSS_MATCH => undef,
	       HASHLIMIT_MATCH => undef,
	       NFQUEUE_TARGET => undef,
	       REALM_MATCH => undef,
	       HELPER_MATCH => undef,
	       CONNLIMIT_MATCH => undef,
	       TIME_MATCH => undef,
	       GOTO_TARGET => undef,
	       LOG_TARGET => 1,         # Assume that we have it.
	       ULOG_TARGET => undef,
	       NFLOG_TARGET => undef,
	       LOGMARK_TARGET => undef,
	       IPMARK_TARGET => undef,
	       TPROXY_TARGET => undef,
	       PERSISTENT_SNAT => undef,
	       OLD_HL_MATCH => undef,
	       FLOW_FILTER => undef,
	       FWMARK_RT_MASK => undef,
	       MARK_ANYWHERE => undef,
	       HEADER_MATCH => undef,
	       ACCOUNT_TARGET => undef,
	       AUDIT_TARGET => undef,
	       CONDITION_MATCH => undef,
	       IPTABLES_S => undef,
	       BASIC_FILTER => undef,
	       CT_TARGET => undef,
	       STATISTIC_MATCH => undef,
	       IMQ_TARGET => undef,
	       DSCP_MATCH => undef,
	       DSCP_TARGET => undef,
	       GEOIP_MATCH => undef,
	       RPFILTER_MATCH => undef,
	       NFACCT_MATCH => undef,
	       CHECKSUM_TARGET => undef,

	       AMANDA_HELPER => undef,
	       FTP_HELPER => undef,
	       FTP0_HELPER => undef,
	       H323_HELPER => undef,
	       IRC_HELPER => undef,
	       IRC0_HELPER => undef,
	       NETBIOS_NS_HELPER => undef,
	       PPTP_HELPER => undef,
	       SANE_HELPER => undef,
	       SANE0_HELPER => undef,
	       SIP_HELPER => undef,
	       SIP0_HELPER => undef,
	       SNMP_HELPER => undef,
	       TFTP_HELPER => undef,
	       TFTP0_HELPER => undef,

	       CAPVERSION => undef,
	       LOG_OPTIONS => 1,
	       KERNELVERSION => undef,
	       );
    #
    # Directories to search for configuration files
    #
    @config_path = ();
    #
    # Stash away file references here when we encounter INCLUDE
    #
    @includestack = ();
    #
    # Allow nested opens
    #
    @openstack = ();

    $currentline = '';        # Line image
    $currentfile = undef;     # File handle reference
    $currentfilename = '';    # File NAME
    $currentlinenumber = 0;   # Line number
    $first_entry = 0;         # Message to output or function to call on first non-blank file entry

    $shorewall_dir = '';      #Shorewall Directory

    $debug = 0;
    $confess = 0;

    %params = ();

    %compiler_params = ();

    @actparms = ();

    %helpers_enabled = (
			amanda       => 1,
			ftp          => 1,
			'ftp-0'      => 1,
			h323         => 1,
			irc          => 1,
			'irc-0'      => 1,
			'netbios-ns' => 1,
			pptp         => 1,
			sane         => 1,
			'sane-0'     => 1,
			sip          => 1,
			'sip-0'      => 1,
			snmp         => 1,
			tftp         => 1,
			'tftp-0'     => 1,
		       );

    %helpers_map = ( amanda          => 'AMANDA_HELPER',
		     ftp             => 'FTP_HELPER',
		     irc             => 'IRC_HELPER',
		     'netbios-ns'    => 'NETBIOS_NS_HELPER',
		     pptp            => 'PPTP_HELPER',
		     'Q.931'         => 'H323_HELPER',
		     RAS             => 'H323_HELPER',
		     sane            => 'SANE_HELPER',
		     sip             => 'SIP_HELPER',
		     snmp            => 'SNMP_HELPER',
		     tftp            => 'TFTP_HELPER',
		   );

    %helpers_aliases = ( amanda       => 'amanda',
			 ftp          => 'ftp',
			 irc          => 'irc',
			 'netbios-ns' => 'netbios-ns',
			 pptp         => 'pptp',
			 'Q.931'      => 'Q.931',
			 RAS          => 'RAS',
			 sane         => 'sane',
			 sip          => 'sip',
			 snmp         => 'snmp',
			 tftp         => 'tftp',
		       );

    %shorewallrc = (
		    SHAREDIR => '/usr/share/',
		    CONFDIR  => '/etc/',
		    );
    #
    # If we are compiling for export, process the shorewallrc from the remote system
    #
    if ( $shorewallrc1 ) {
	process_shorewallrc( $shorewallrc1,
			     $family == F_IPV4 ? 'shorewall-lite' : 'shorewall6-lite'
			   );

	%shorewallrc1 = %shorewallrc;

	%shorewallrc = (
			SHAREDIR => '/usr/share/',
			CONFDIR  => '/etc/',
		       );
    }
    #
    # Process the global shorewallrc file
    #
    #   Note: The build file executes this function passing only the protocol family
    #
    process_shorewallrc( $shorewallrc,
			 $family == F_IPV4 ? 'shorewall' : 'shorewall6'
		       ) if defined $shorewallrc;

    $globals{SHAREDIRPL} = "$shorewallrc{SHAREDIR}/shorewall/";

    if ( $family == F_IPV4 ) {
	$globals{SHAREDIR}      = "$shorewallrc{SHAREDIR}/shorewall";
	$globals{CONFDIR}       = "$shorewallrc{CONFDIR}/shorewall";
	$globals{PRODUCT}       = 'shorewall';
	$config{IPTABLES}       = undef;
	$validlevels{ULOG}      = 'ULOG';
    } else {
	$globals{SHAREDIR}      = "$shorewallrc{SHAREDIR}/shorewall6";
	$globals{CONFDIR}       = "$shorewallrc{CONFDIR}/shorewall6";
	$globals{PRODUCT}       = 'shorewall6';
	$config{IP6TABLES}      = undef;
    }

    %shorewallrc1 = %shorewallrc unless $shorewallrc1;
}

my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );

#
# Create 'currentlineinfo'
#
sub currentlineinfo() {
    my $linenumber = $currentlinenumber || 1;

    if ( $currentfile ) {
	my $lineinfo = " $currentfilename ";
	
	if ( $linenumber eq 'EOF' ) {
	    $lineinfo .= '(EOF)'
	} else {
	    $lineinfo .= "(line $linenumber)";
	}
	#
	# Unwind the current include stack
	#
	for ( my $i = @includestack - 1; $i >= 0; $i-- ) {
	    my $info = $includestack[$i];
	    $linenumber = $info->[2] || 1;
	    $lineinfo .= "\n      from $info->[1] (line $linenumber)";
	}
	#
	# Now unwind the open stack; each element is an include stack
	#
	for ( my $i = @openstack - 1; $i >= 0; $i-- ) {
	    my $istack = $openstack[$i];
	    for ( my $j = ( @$istack - 1 ); $j >= 0; $j-- ) {
		my $info = $istack->[$j];
		$linenumber = $info->[2] || 1;
		$lineinfo .= "\n      from $info->[1] (line $linenumber)";
	    }
	}

	$lineinfo;

    } else {
	'';
    }
}

#
# Issue a Warning Message
#
sub warning_message
{
    my $currentlineinfo = currentlineinfo;
    our @localtime;

    $| = 1; #Reset output buffering (flush any partially filled buffers).

    if ( $log ) {
	@localtime = localtime;
	printf $log '%s %2d %02d:%02d:%02d ', $abbr[$localtime[4]], @localtime[3,2,1,0];
    }

    if ( $confess ) {
	print STDERR longmess( "   WARNING: @_$currentlineinfo" );
	print $log   longmess( "   WARNING: @_$currentlineinfo\n" ) if $log;
    } else {
	print STDERR "   WARNING: @_$currentlineinfo\n";
	print $log   "   WARNING: @_$currentlineinfo\n" if $log;
    }

    $| = 0; #Re-allow output buffering
}

sub cleanup() {
    #
    # Close files first in case we're running under Cygwin
    #
    close  $script, $script = undef         if $script;
    close  $perlscript, $perlscript = undef if $perlscript;
    close  $log, $log = undef               if $log;

    if ( $currentfile ) {
	#
	# We have a current input file; close it
	#
	close $currentfile;
	#
	# Unwind the current include stack
	#
	for ( my $i = @includestack - 1; $i >= 0; $i-- ) {
	    my $info = $includestack[$i];
	    close $info->[0];
	}
	#
	# Now unwind the open stack; each element is an include stack
	#
	for ( my $i = @openstack - 1; $i >= 0; $i-- ) {
	    my $istack = $openstack[$i];
	    for ( my $j = ( @$istack - 1 ); $j >= 0; $j-- ) {
		my $info = $istack->[$j];
		close $info->[0];
	    }
	}
    }
    #
    # Unlink temporary files
    #
    unlink ( $tempfile ), $tempfile = undef             if $tempfile;
    unlink ( $perlscriptname ), $perlscriptname = undef if $perlscriptname;
    unlink ( @tempfiles ), @tempfiles = ()              if @tempfiles;
    #
    # Delete temporary chains
    #
    if ( $sillyname ) {
	#
	# We went through determine_capabilities()
	#
	qt1( "$iptables -F $sillyname" );
	qt1( "$iptables -X $sillyname" );
	qt1( "$iptables -F $sillyname1" );
	qt1( "$iptables -X $sillyname1" );
	qt1( "$iptables -t mangle -F $sillyname" );
	qt1( "$iptables -t mangle -X $sillyname" );
	qt1( "$iptables -t nat -F $sillyname" );
	qt1( "$iptables -t nat -X $sillyname" );
	qt1( "$iptables -t raw -F $sillyname" );
	qt1( "$iptables -t raw -X $sillyname" );
	qt1( "$iptables -t rawpost -F $sillyname" );
	qt1( "$iptables -t rawpost -X $sillyname" );
	$sillyname = '';
    }
}

#
# Issue fatal error message and die
#
sub fatal_error	{
    my $currentlineinfo = currentlineinfo;

    $| = 1; #Reset output buffering (flush any partially filled buffers).

    if ( $log ) {
	our @localtime = localtime;
	printf $log '%s %2d %02d:%02d:%02d ', $abbr[$localtime[4]], @localtime[3,2,1,0];

	if ( $confess ) {
	    print $log longmess( "   ERROR: @_$currentlineinfo\n" );
	} else {
	    print $log "   ERROR: @_$currentlineinfo\n";
	}

	close $log;
	$log = undef;
    }

    cleanup;

    if ( $embedded ) {
	confess "@_$currentlineinfo" if $confess;
	die "@_$currentlineinfo\n";
    }  else {
	confess "   ERROR: @_$currentlineinfo" if $confess;
	die "   ERROR: @_$currentlineinfo\n";
    }
}

sub fatal_error1 {
    $| = 1;

    if ( $log ) {
	our @localtime = localtime;
	printf $log '%s %2d %02d:%02d:%02d ', $abbr[$localtime[4]], @localtime[3,2,1,0];

	if ( $debug ) {
	    print $log longmess( "   ERROR: @_\n" );
	} else {
	    print $log "   ERROR: @_\n";
	}

	close $log;
	$log = undef;
    }

    cleanup;
    confess "   ERROR: @_" if $debug;
    die "   ERROR: @_\n";
}

#
# C/C++-like assertion checker -- the optional arguments are not used but will
#                                 appear in the stack trace
#
sub assert( $;@ ) {
    unless ( $_[0] ) {
	my @caller0 = caller 0; # Where assert() was called
	my @caller1 = caller 1; # Who called assert()

	$confess = 1;

	fatal_error "Internal error in $caller1[3] at $caller0[1] line $caller0[2]";
    }
}

#
# Convert value to decimal number
#
sub numeric_value ( $ ) {
    my $mark = lc $_[0];
    my $negative = ( $mark =~ s/^-// );
    return undef unless $mark =~ /^(0x[a-f0-9]+|0[0-7]*|[1-9]\d*)$/;
    no warnings;
    $mark = ( $mark =~ /^0/ ? oct $mark : $mark );
    use warnings;
    $negative ? - $mark : $mark;
}

sub numeric_value1 ( $ ) {
    no warnings;
    my $val = numeric_value $_[0];
    fatal_error "Invalid Number ($_[0])" unless defined $val;
    $val;
    use warnings;
}

sub hex_value( $ ) {
    my $val = lc $_[0];
    return undef unless $val =~ /^[a-fA-F0-9]+$/;
    no warnings;
    oct '0x' . $val;
    use warnings;
}

#
# Strip off superfluous leading zeros from a hex number
#
sub normalize_hex( $ ) {
    my $val = lc shift;

    $val =~ s/^0// while $val =~ /^0/ && length $val > 1;
    $val;
}

#
# Return the argument expressed in Hex
#
sub in_hex( $ ) {
    my $value = $_[0];

    $value =~ /^0x/ ? $value : sprintf '0x%x', $_[0];
}

sub in_hex2( $ ) {
    sprintf '0x%02x', $_[0];
}

sub in_hex3( $ ) {
    sprintf '%03x', $_[0];
}

sub in_hex4( $ ) {
    sprintf '0x%04x', $_[0];
}

sub in_hex8( $ ) {
    sprintf '0x%08x', $_[0];
}

sub in_hexp( $ ) {
    sprintf '%x', $_[0];
}

#
# Write the arguments to the script file (if any) with the current indentation.
#
# Replaces leading spaces with tabs as appropriate and suppresses consecutive blank lines.
#
sub emit {
    assert( $script_enabled );

    if ( $script || $debug ) {
	#
	# 'compile' as opposed to 'check'
	#
	for ( @_ ) {
	    unless ( /^\s*$/ ) {
		my $line = $_; # This copy is necessary because the actual arguments are almost always read-only.
		$line =~ s/^\n// if $lastlineblank;
		$line =~ s/^/$indent/gm if $indent;
		$line =~ s/        /\t/gm;
		print $script "$line\n" if $script;
		$lastlineblank = ( substr( $line, -1, 1 ) eq "\n" );

		if ( $debug ) {
		    $line =~ s/^\n//;
		    $line =~ s/\n/\nGS-----> /g;
		    print "GS-----> $line\n";
		}
	    } else {
		unless ( $lastlineblank ) {
		    print $script "\n"  if $script;
		    print "GS-----> \n" if $debug;
		}

		$lastlineblank = 1;
	    }
	}
    }
}

#
# Version of emit() that writes to standard out
#
sub emitstd {
    for ( @_ ) {
	unless ( /^\s*$/ ) {
	    my $line = $_; # This copy is necessary because the actual arguments are almost always read-only.
	    $line =~ s/^\n// if $lastlineblank;
	    $line =~ s/^/$indent/gm if $indent;
	    $line =~ s/        /\t/gm;
	    print "$line\n";
	    $lastlineblank = ( substr( $line, -1, 1 ) eq "\n" );
	} else {
	    print "\n" unless $lastlineblank;
	    $lastlineblank = 1;
	}
    }
}

#
# Write passed message to the script with newline but no indentation.
#
sub emit_unindented( $;$ ) {
    assert( $script_enabled );

    print $script $_[1] ? "$_[0]" : "$_[0]\n" if $script;
}

#
# Write a progress_message2 command with surrounding blank lines to the output file.
#
sub save_progress_message( $ ) {
    emit "\nprogress_message2 @_\n" if $script;
}

#
# Write a progress_message command to the output file.
#
sub save_progress_message_short( $ ) {
    emit "progress_message $_[0]" if $script;
}

#
# Set $timestamp
#
sub set_timestamp( $ ) {
    $timestamp = shift;
}

#
# Set $verbosity
#
sub set_verbosity( $ ) {
    $verbosity = shift;
}

#
# Set $log and $log_verbosity
#
sub set_log ( $$ ) {
    my ( $l, $v ) = @_;

    if ( defined $v ) {
	my $value = numeric_value( $v );
	fatal_error "Invalid Log Verbosity ( $v )" unless defined($value) && ( $value >= -1 ) && ( $value <= 2);
	$log_verbosity = $value;
    }

    if ( $l && $log_verbosity >= 0 ) {
	unless ( open $log , '>>' , $l ) {
	    $log = undef;
	    fatal_error "Unable to open STARTUP_LOG ($l) for writing: $!";
	}
    } else {
	$log_verbosity = -1;
    }
}

sub close_log() {
    close $log, $log = undef if $log;
}

#
# Set $command, $doing and $done
#
sub set_command( $$$ ) {
    ($command, $doing, $done) = @_;
}

#
# Print the current TOD to STDOUT.
#
sub timestamp() {
    our @localtime = localtime;
    printf '%02d:%02d:%02d ', @localtime[2,1,0];
}

#
# Write a message if $verbosity >= 2.
#
sub progress_message {
    my $havelocaltime = 0;

    if ( $verbosity > 1 || $log_verbosity > 1 ) {
	my $line = "@_";
	my $leading = $line =~ /^(\s+)/ ? $1 : '';
	$line =~ s/\s+/ /g;

	if ( $verbosity > 1 ) {
	    timestamp, $havelocaltime = 1 if $timestamp;
	    #
	    # We use this function to display messages containing raw config file images which may contains tabs (including multiple tabs in succession).
	    # The following makes such messages look more readable and uniform
	    #
	    print "${leading}${line}\n";
	}

	if ( $log_verbosity > 1 ) {
	    our @localtime;

	    @localtime = localtime unless $havelocaltime;

	    printf $log '%s %2d %2d:%02d:%02d ', $abbr[$localtime[4]], @localtime[3,2,1,0];
	    print $log "${leading}${line}\n";
	}
    }
}

sub progress_message_nocompress {
    my $havelocaltime = 0;

    if ( $verbosity > 1 ) {
	timestamp, $havelocaltime = 1 if $timestamp;
	print "@_\n";
    }

    if ( $log_verbosity > 1 ) {
	our @localtime;

	@localtime = localtime unless $havelocaltime;

	printf $log '%s %2d %2d:%02d:%02d ', $abbr[$localtime[4]], @localtime[3,2,1,0];
	print $log "@_\n";
    }
}

#
# Write a message if $verbosity >= 1
#
sub progress_message2 {
    my $havelocaltime = 0;

    if ( $verbosity > 0 ) {
	timestamp, $havelocaltime = 1 if $timestamp;
	print "@_\n";
    }

    if ( $log_verbosity > 0 ) {
	our @localtime;

	@localtime = localtime unless $havelocaltime;

	printf $log '%s %2d %2d:%02d:%02d ', $abbr[$localtime[4]], @localtime[3,2,1,0];
	print $log "@_\n";
    }
}

#
# Write a message if $verbosity >= 0
#
sub progress_message3 {
    my $havelocaltime = 0;

    if ( $verbosity >= 0 ) {
	timestamp, $havelocaltime = 1 if $timestamp;
	print "@_\n";
    }

    if ( $log_verbosity >= 0 ) {
	our @localtime;

	@localtime = localtime unless $havelocaltime;

	printf $log '%s %2d %2d:%02d:%02d ', $abbr[$localtime[4]], @localtime[3,2,1,0];
	print $log "@_\n";
    }
}

#
# Push/Pop Indent
#
sub push_indent(;$) {
    my $times = shift || 1;

    while ( $times-- ) {
	if ( $indent2 ) {
	    $indent2 = '';
	    $indent = $indent1 = $indent1 . "\t";
	} else {
	    $indent2 = '    ';
	    $indent = $indent1 . $indent2;
	}
    }
}

sub pop_indent(;$) {
    my $times = shift || 1;

    while ( $times-- ) {
	if ( $indent2 ) {
	    $indent2 = '';
	    $indent = $indent1;
	} else {
	    $indent1 = substr( $indent1 , 0, -1 );
	    $indent2 = '    ';
	    $indent = $indent1 . $indent2;
	}
    }
}

#
# Create the temporary script file -- the passed file name is the name of the final file.
# We create a temporary file in the same directory so that we can use rename to finalize it.
#
sub create_temp_script( $$ ) {
    my ( $scriptfile, $export ) = @_;
    my $suffix;

    if ( $scriptfile eq '-' ) {
	$verbosity = -1;
	$script = undef;
	open( $script, '>&STDOUT' ) or fatal_error "Open of STDOUT failed";
	$file = '-';
	return 1;
    }

    eval {
	( $file, $dir, $suffix ) = fileparse( $scriptfile );
    };

    cleanup, die if $@;

    fatal_error "$dir is a Symbolic Link"        if -l $dir;
    fatal_error "Directory $dir does not exist"  unless -d _;
    fatal_error "Directory $dir is not writable" unless -w _;
    fatal_error "$scriptfile is a Symbolic Link" if -l $scriptfile;
    fatal_error "$scriptfile is a Directory"     if -d _;
    fatal_error "$scriptfile exists and is not a compiled script" if -e _ && ! -x _;
    fatal_error "An exported \u$globals{PRODUCT} compiled script may not be named '$globals{PRODUCT}'" if $export && "$file" eq $globals{PRODUCT} && $suffix eq '';

    eval {
	$dir = abs_path $dir unless $dir =~ m|^/|; # Work around http://rt.cpan.org/Public/Bug/Display.html?id=13851
	( $script, $tempfile ) = tempfile ( 'tempfileXXXX' , DIR => $dir );
    };

    fatal_error "Unable to create temporary file in directory $dir" if $@;

    $file = "$file.$suffix" if $suffix;
    $dir .= '/' unless substr( $dir, -1, 1 ) eq '/';
    $file = $dir . $file;

}

#
# Finalize the script file
#
sub finalize_script( $ ) {
    my $export = $_[0];
    close $script;
    $script = 0;

    if ( $file ne '-' ) {
	rename $tempfile, $file or fatal_error "Cannot Rename $tempfile to $file: $!";
	chmod 0700, $file or fatal_error "Cannot secure $file for execute access";
	progress_message3 "Shorewall configuration compiled to $file" unless $export;
    }
}

#
# Create the temporary aux config file.
#
sub create_temp_aux_config() {
    eval {
	( $script, $tempfile ) = tempfile ( 'tempfileXXXX' , DIR => $dir );
    };

    cleanup, die if $@;
}

#
# Finalize the aux config file.
#
sub finalize_aux_config() {
    close $script;
    $script = 0;
    rename $tempfile, "$file.conf" or fatal_error "Cannot Rename $tempfile to $file.conf: $!";
    progress_message3 "Shorewall configuration compiled to $file";
}

#
# Enable writes to the script file
#
sub enable_script() {
    $script_enabled = 1;
}

#
# Disable writes to the script file
#
sub disable_script() {
    $script_enabled = 0;
}

#
# Set $config{CONFIG_PATH}
#
sub set_config_path( $ ) {
    $config{CONFIG_PATH} = shift;
}

#
# Set $debug
#
sub set_debug( $$ ) {
    $debug   = shift;
    $confess = shift;
    $confess ||= $debug;
}

#
# Search the CONFIG_PATH for the passed file
#
sub find_file($)
{
    my ( $filename, $nosearch ) = @_;

    return $filename if $filename =~ '/';

    for my $directory ( @config_path ) {
	my $file = "$directory$filename";
	return $file if -f $file;
    }

    "$config_path[0]$filename";
}

sub split_list( $$;$ ) {
    my ($list, $type, $origlist ) = @_;

    fatal_error( "Invalid $type list (" . ( $origlist ? $origlist : $list ) . ')' ) if $list =~ /^,|,$|,,|!,|,!$/;

    split /,/, $list;
}

sub split_list1( $$ ) {
    my ($list, $type ) = @_;

    fatal_error "Invalid $type list ($list)" if $list =~ /^,|,$|,,|!,|,!$/;

    my @list1 = split /,/, $list;
    my @list2;
    my $element = '';

    for ( @list1 ) {
	my $count;

	if ( ( $count = tr/(/(/ ) > 0 ) {
	    fatal_error "Invalid $type list ($list)" if $element || $count > 1;
	    s/\(//;
	    if ( ( $count = tr/)/)/ ) > 0 ) {
		fatal_error "Invalid $type list ($list)" if $count > 1;
		s/\)//;
		push @list2 , $_;
	    } else {
		$element = $_;
	    }
	} elsif ( ( $count =  tr/)/)/ ) > 0 ) {
	    fatal_error "Invalid $type list ($list)" unless $element && $count == 1;
	    s/\)//;
	    push @list2, join ',', $element, $_;
	    $element = '';
	} elsif ( $element ) {
	    $element = join ',', $element , $_;
	} else {
	    push @list2 , $_;
	}
    }

    @list2;
}

#
# Determine if a value has been supplied
#
sub supplied( $ ) {
    my $val = shift;

    defined $val && $val ne '';
}

#
# Pre-process a line from a configuration file.

#    ensure that it has an appropriate number of columns.
#    supply '-' in omitted trailing columns.
#    Handles all of the supported forms of column/pair specification
#
sub split_line1( $$;$$ ) {
    my ( $description, $columnsref, $nopad, $maxcolumns ) = @_;

    unless ( defined $maxcolumns ) {
	my @maxcolumns = ( keys %$columnsref );
	$maxcolumns = @maxcolumns;
    }
    #
    # First see if there is a semicolon on the line; what follows will be column/value paris
    #
    my ( $columns, $pairs, $rest ) = split( ';', $currentline );

    if ( supplied $pairs ) {
	#
	# Found it -- be sure there wasn't more than one.
	#
	fatal_error "Only one semicolon (';') allowed on a line" if defined $rest;
    } elsif ( $currentline =~ /(.*){(.*)}$/ ) {
	#
	# Pairs are enclosed in curly brackets.
	#
	$columns = $1;
	$pairs   = $2;
    } else {
	$pairs = '';
    }

    fatal_error "Shorewall Configuration file entries may not contain double quotes, single back quotes or backslashes" if $columns =~ /["`\\]/;
    fatal_error "Non-ASCII gunk in file" if $columns =~ /[^\s[:print:]]/;

    my @line = split( ' ', $columns );

    $nopad = { COMMENT => 0 } unless $nopad;

    my $first     = supplied $line[0] ? $line[0] : '-';
    my $npcolumns = $nopad->{$first};

    if ( defined $npcolumns ) {
	fatal_error "Invalid $first entry" if $npcolumns && @line != $npcolumns;
	return @line
    }

    fatal_error "Shorewall Configuration file entries may not contain single quotes" if $currentline =~ /'/;

    my $line = @line;

    fatal_error "Invalid $description entry (too many columns)" if $line > $maxcolumns;

    $line-- while $line > 0 && $line[$line-1] eq '-';

    push @line, '-' while @line < $maxcolumns;

    if ( supplied $pairs ) {
	$pairs =~ s/^\s*//;
	$pairs =~ s/\s*$//;

	my @pairs = split( /,?\s+/, $pairs );

	for ( @pairs ) {
	    fatal_error "Invalid column/value pair ($_)" unless /^(\w+)(?:=>?|:)(.+)$/;
	    my ( $column, $value ) = ( lc $1, $2 );
	    fatal_error "Unknown column ($1)" unless exists $columnsref->{$column};
	    $column = $columnsref->{$column};
	    fatal_error "Non-ASCII gunk in file" if $columns =~ /[^\s[:print:]]/;
	    $value = $1 if $value =~ /^"([^"]+)"$/;
	    fatal_error "Column values may not contain embedded double quotes, single back quotes or backslashes" if $columns =~ /["`\\]/;
	    fatal_error "Non-ASCII gunk in the value of the $column column" if $columns =~ /[^\s[:print:]]/;
	    $line[$column] = $value;
	}
    }

    @line;
}

sub split_line($$) {
    &split_line1( @_, {} );
}

#
# Open a file, setting $currentfile. Returns the file's absolute pathname if the file
# exists, is non-empty  and was successfully opened. Terminates with a fatal error
# if the file exists, is non-empty, but the open fails.
#
sub do_open_file( $ ) {
    my $fname = $_[0];
    open $currentfile, '<', $fname or fatal_error "Unable to open $fname: $!";
    $currentlinenumber = 0;
    $ifstack           = @ifstack;
    $currentfilename   = $fname;
}

sub open_file( $ ) {
    my $fname = find_file $_[0];

    assert( ! defined $currentfile );

    if ( -f $fname && -s _ ) {
	$first_entry = 0;
	do_open_file $fname;;
    } else {
	$ifstack = @ifstack;
	'';
    }
}

#
# Pop the include stack
#
sub pop_include() {
    my $arrayref = pop @includestack;

    unless ( $ifstack == @ifstack ) {
	my $lastref = $ifstack[-1];
	$currentlinenumber = 'EOF';
	fatal_error qq(Missing "?ENDIF" to match ?IF at line number $lastref->[2])
    }

    if ( $arrayref ) {
	( $currentfile, $currentfilename, $currentlinenumber, $ifstack ) = @$arrayref;
    } else {
	$currentfile       = undef;
	$currentlinenumber = 'EOF';
    }
}

#
# This function is normally called below in read_a_line() when EOF is reached. Clients of the
# module may also call the function to close the file before EOF
#
sub close_file() {
    if ( $currentfile ) {
	my $result = close $currentfile;

	pop_include;

	fatal_error "SHELL Script failed" unless $result;

	$first_entry = 0;

    }
}

#
# Process an ?IF, ?ELSIF, ?ELSE or ?END directive
#
sub have_capability( $ );

#
# Report an error from process_conditional()
#
sub cond_error( $$$ ) {
    $currentfilename   = $_[1];
    $currentlinenumber = $_[2];
    fatal_error $_[0];
}

#
# Evaluate an expression in an ?IF or ?ELSIF directive
#
sub evaluate_expression( $$$ ) {
    my ( $expression , $filename , $linenumber ) = @_;
    my $val;
    my $count = 0;

    #                         $1      $2   $3      -     $4
    while ( $expression =~ m( ^(.*?) \$({)? (\w+) (?(2)}) (.*)$ )x ) {
	my ( $first, $var, $rest ) = ( $1, $3, $4);

	$val = ( exists $ENV{$var}     ? $ENV{$var}    :
		 exists $params{$var}  ? $params{$var} :
		 exists $config{$var}  ? $config{$var} :
		 exists $renamed{$var} ? $config{$renamed{$var}} :
		 exists $capdesc{$var} ? have_capability( $var ) : 0 );
	$val = 0 unless defined $val;
	$val = "'$val'" unless $val =~ /^-?\d+$/;
	$expression = join( '', $first, $val || 0, $rest );
	cond_error( "Variable Expansion Loop" , $filename, $linenumber ) if ++$count > 100;
    }

    #                         $1      $2   $3      -     $4
    while ( $expression =~ m( ^(.*?) __({)? (\w+) (?(2)}) (.*)$ )x ) {
	my ( $first, $cap, $rest ) = ( $1, $3, $4);

	if ( exists $capdesc{$cap} ) {
	    $val = have_capability( $cap );
	    if ( defined $val ) {
		$val = "'$val'" unless $val =~ /^-?\d+$/;
	    } else {
		$val = 0;
	    }
	} elsif ( $cap =~ /^IPV([46])$/ ) {
	    $val = ( $family == $1 );
	} else {
	    cond_error "Unknown capability ($cap)", $filename, $linenumber;
	}

	$expression = join( '', $first, $val || 0, $rest );
    }

    $expression =~ s/^\s*(.+)\s*$/$1/;

    unless ( $expression =~ /^\d+$/ ) {
	#
	# Not a simple one-term expression -- compile it
	#
	$val = eval qq(package Shorewall::User;\nuse strict;\n# line $linenumber "$filename"\n$expression);

	unless ( $val ) {
	    cond_error( "Couldn't parse expression: $@" , $filename, $linenumber ) if $@;
	    cond_error( "Undefined expression" , $filename, $linenumber ) unless defined $val;
	}
    }

    $val;
}

#
# Each entry in @ifstack consists of a 4-tupple
#
# [0] = The keyword (IF,ELSIF or ELSE)
# [1] = True if we were already omitting at the last IF directive
# [2] = True if we have included any block of the current IF...ELSEIF....ELSEIF... sequence.
# [3] = The line number of the directive
#
sub process_conditional( $$$$ ) {
    my ( $omitting, $line, $filename, $linenumber ) = @_;

    print "CD===> $line\n" if $debug;

    cond_error( "Invalid compiler directive ($line)" , $filename, $linenumber ) unless $line =~ /^\s*\?(IF\s+|ELSE|ELSIF\s+|ENDIF)(.*)$/i;

    my ($keyword, $expression) = ( uc $1, $2 );

    if ( supplied $expression ) {
	$expression =~ s/#.*//;
	$expression =~ s/\s*$//;
    } else {
	$expression = '';
    }

    my ( $lastkeyword, $prioromit, $included, $lastlinenumber ) = @ifstack ? @{$ifstack[-1]} : ('', 0, 0, 0 );

    if ( $keyword =~ /^IF/ ) {
	cond_error( "Missing IF expression" , $filename, $linenumber ) unless supplied $expression;
	my $nextomitting = $omitting || ! evaluate_expression( $expression , $filename, $linenumber );
	push @ifstack, [ 'IF', $omitting, ! $nextomitting, $linenumber ];
	$omitting = $nextomitting;
    } elsif ( $keyword =~ /^ELSIF/ ) {
	cond_error( "?ELSIF has no matching ?IF" , $filename, $linenumber ) unless @ifstack > $ifstack && $lastkeyword =~ /IF/;
	cond_error( "Missing IF expression" , $filename, $linenumber ) unless $expression;
	if ( $omitting && ! $included ) {
	    #
	    # We can only change to including if we were previously omitting
	    #
	    $omitting = $prioromit || ! evaluate_expression( $expression , $filename, $linenumber );
	    $included = ! $omitting;
	} else {
	    #
	    # We have already included -- so we don't want to include this part
	    #
	    $omitting = 1;
	}
	$ifstack[-1] = [ 'ELSIF', $prioromit, $included, $lastlinenumber ];
    } elsif ( $keyword eq 'ELSE' ) {
	cond_error( "Invalid ?ELSE" , $filename, $linenumber ) unless $expression eq '';
	cond_error( "?ELSE has no matching ?IF" , $filename, $linenumber ) unless @ifstack > $ifstack && $lastkeyword =~ /IF/;
	$omitting = $included || ! $omitting unless $prioromit;
	$ifstack[-1] = [ 'ELSE', $prioromit, 1, $lastlinenumber ];
    } else {
	cond_error( "Invalid ?ENDIF" , $filename, $linenumber ) unless $expression eq '';
	cond_error( q(Unexpected "?ENDIF" without matching ?IF or ?ELSE) , $filename, $linenumber ) if @ifstack <= $ifstack;
	$omitting = $prioromit;
	pop @ifstack;
    }

    $omitting;
}

#
# Functions for copying a file into the script
#
sub copy( $ ) {
    assert( $script_enabled );

    if ( $script ) {
	my $file         = $_[0];
	my $omitting     = 0;
	my $save_ifstack = $ifstack;
	my $lineno       = 0;

	$ifstack = @ifstack;

	open IF , $file or fatal_error "Unable to open $file: $!";

	while ( <IF> ) {
	    chomp;

	    $lineno++;

	    if ( /^\s*\?/ ) {
		$omitting = process_conditional( $omitting, $_, $file, $lineno );
		next;
	    }

	    next if $omitting;

	    if ( /^\s*$/ ) {
		print $script "\n" unless $lastlineblank;
		$lastlineblank = 1;
	    } else {
		if  ( $indent ) {
		    s/^(\s*)/$indent1$1$indent2/;
		    s/        /\t/ if $indent2;
		}

		print $script $_;
		print $script "\n";
		$lastlineblank = 0;
	    }
	}

	if ( $ifstack < @ifstack ) {
	    $currentlinenumber = 'EOF';
	    $currentfilename   = $file;
	    fatal_error "Missing ?ENDIF to match the ?IF at line $ifstack[-1]->[3]";
	} else {
	    $ifstack = $save_ifstack;
	}

	close IF;
    }
}

#
# This variant of copy handles line continuation, 'here documents' and INCLUDE
#
sub copy1( $ ) {
    assert( $script_enabled );

    my $result = 0;

    if ( $script || $debug ) {
	my ( $do_indent, $here_documents ) = ( 1, '');

	open_file( $_[0] );

	while ( $currentfile ) {
	    while ( <$currentfile> ) {
		$currentlinenumber++;

		chomp;

		if ( /^\s*\?/ ) {
		    $omitting = process_conditional( $omitting, $_, $currentfilename, $currentlinenumber );
		    next;
		}

		if ( /^${here_documents}\s*$/ ) {
		    if ( $script ) {
			print $script $here_documents if $here_documents;
			print $script "\n";
		    }

		    if ( $debug ) {
			print "GS-----> $here_documents" if $here_documents;
			print "GS----->\n";
		    }

		    $do_indent = 1;
		    $here_documents = '';
		    next;
		}

		if ( $do_indent && /.*<<\s*([^ ]+)s*(.*)/ ) {
		    $here_documents = $1;
		    s/^(\s*)/$indent1$1$indent2/;
		    s/        /\t/ if $indent2;
		    $do_indent = 0;

		    if ( $script ) {
			print $script $_;
			print $script "\n";
		    }

		    if ( $debug ) {
			s/\n/\nGS-----> /g;
			print "GS-----> $_\n";
		    }

		    $result = 1;
		    next;
		}

		if ( $do_indent ) {
		    if ( /^\s*INCLUDE\b/ ) {
			my @line = split / /;

			fatal_error "Invalid INCLUDE command"    if @line != 2;
			fatal_error "INCLUDEs nested too deeply" if @includestack >= 4;

			my $filename = find_file $line[1];

			warning_message "Reserved filename ($1) in INCLUDE directive" if $filename =~ '/(.*)' && $config_files{$1};

			fatal_error "INCLUDE file $filename not found" unless -f $filename;
			fatal_error "Directory ($filename) not allowed in INCLUDE" if -d _;

			if ( -s _ ) {
			    push @includestack, [ $currentfile, $currentfilename, $currentlinenumber, $ifstack ];
			    $currentfile = undef;
			    do_open_file $filename;
			} else {
			    $currentlinenumber = 0;
			}

			next;
		    }

		    if ( $indent ) {
			s/^(\s*)/$indent1$1$indent2/;
			s/        /\t/ if $indent2;
		    }
		}

		if ( $script ) {
		    print $script $_;
		    print $script "\n";
		}

		$do_indent = ! ( $here_documents || /\\$/ );

		$result = 1 unless $result || /^\s*$/ || /^\s*#/;

		if ( $debug ) {
		    s/\n/\nGS-----> /g;
		    print "GS-----> $_\n";
		}
	    }

	    close_file;
	}
    }

    $lastlineblank = 0;

    $result;
}

#
# This one drops header comments and replaces them with a three-line banner
#
sub copy2( $$ ) {
    my ( $file, $trace ) = @_;

    assert( $script_enabled );
    my $empty = 1;

    if ( $script || $trace ) {
	my $file = $_[0];
	my $omitting     = 0;
	my $save_ifstack = $ifstack;
	my $lineno       = 0;

	open IF , $file or fatal_error "Unable to open $file: $!";

	while ( <IF> ) {
	    $lineno++;
	    $empty = 0, last unless /^#/;
	}

	unless ( $empty ) {
	    emit <<EOF;
################################################################################
#   Functions imported from $file
################################################################################
EOF
	    chomp;
	    emit( $_ ) unless /^\s*$/;

	    while ( <IF> ) {
		$lineno++;
		chomp;

		if ( /^\s*\?/ ) {
		    $omitting = process_conditional( $omitting, $_, $file, $lineno );
		    next;
		}

		next if $omitting;

		if ( /^\s*$/ ) {
		    unless ( $lastlineblank ) {
			print $script "\n" if $script;
			print "GS----->\n" if $trace;
		    }

		    $lastlineblank = 1;
		} else {
		    if  ( $indent ) {
			s/^(\s*)/$indent1$1$indent2/;
			s/        /\t/ if $indent2;
		    }

		    if ( $script ) {
			print $script $_;
			print $script "\n";
		    }

		    if ( $trace ) {
			s/\n/GS-----> \n/g;
			print "GS-----> $_\n";
		    }

		    $lastlineblank = 0;
		}
	    }

	    unless ( $lastlineblank ) {
		print $script "\n" if $script;
		print "GS----->\n" if $trace;
	    }

	    emit( '################################################################################',
		  "#   End of imports from $file",
		  '################################################################################' );
	}

	if ( $ifstack < @ifstack ) {
	    $currentfilename   = $file;
	    $currentlinenumber = 'EOF';
	    fatal_error "Missing ?ENDIF to match the ?IF at line $ifstack[-1]->[3]";
	} else {
	    $ifstack = $save_ifstack;
	}

	close IF;

    }
}

#
# The following two functions allow module clients to nest opens. This happens frequently
# in the Rules module.
#
sub push_open( $ ) {

    push @includestack, [ $currentfile, $currentfilename, $currentlinenumber, $ifstack ] if $currentfile;
    my @a = @includestack;
    push @openstack, \@a;
    @includestack = ();
    $currentfile = undef;
    open_file( $_[0] );

}

sub pop_open() {
    @includestack = @{pop @openstack};
    pop_include;
}

#
# This function is called by in-line PERL to generate a line of input for the current file.
# If the in-line PERL returns an indication of success, then the generated lines will be
# processed as regular file input.
#
sub shorewall {
    unless ( $perlscript ) {
	fatal_error "shorewall() may not be called in this context" unless $currentfile;

	$dir ||= '/tmp/';

	eval {
	    ( $perlscript, $perlscriptname ) = tempfile ( 'perlscriptXXXX' , DIR => $dir );
	};

	fatal_error "Unable to create temporary file in directory $dir" if $@;
    }

    print $perlscript "@_\n";
}

#
# We don't announce that we are checking/compiling a file until we determine that the file contains
# at least one non-blank, non-commentary line.
#
# The argument to this function may be either a scalar or a function reference. When the first
# non-blank/non-commentary line is reached:
#
# - if a function reference was passed to first_entry(), that function is called
# - otherwise, the argument to first_entry() is passed to progress_message2().
#
# We do this processing in read_a_line() rather than in the higher-level routines because
# Embedded Shell/Perl scripts are processed out of read_a_line(). If we were to defer announcement
# until we get back to the caller of read_a_line(), we could issue error messages about parsing and
# running scripts in the file before we'd even indicated that we are processing it.
#
sub first_entry( $ ) {
    $first_entry = $_[0];
    my $reftype = reftype $first_entry;
    assert( $reftype eq 'CODE' ) if $reftype;
}

sub read_a_line($);

sub embedded_shell( $ ) {
    my $multiline = shift;

    fatal_error "INCLUDEs nested too deeply" if @includestack >= 4;
    my ( $command, $linenumber ) = ( "/bin/sh -c '$currentline", $currentlinenumber );

    if ( $multiline ) {
	#
	# Multi-line script
	#
	fatal_error "Invalid BEGIN SHELL directive" unless $currentline =~ /^\s*$/;
	$command .= "\n";

	my $last = 0;

	while ( read_a_line( PLAIN_READ ) ) {
	    last if $last = $currentline =~ s/^\s*\??END(\s+SHELL)?\s*(?:;\s*)?$//;
	    $command .= "$currentline\n";
	}

	fatal_error ( "Missing END SHELL" ) unless $last;
	fatal_error ( "Invalid END SHELL directive" ) unless $currentline =~ /^\s*$/;
    }

    $command .= q(');

    push @includestack, [ $currentfile, $currentfilename, $currentlinenumber, $ifstack ];
    $currentfile = undef;
    open $currentfile , '-|', $command or fatal_error qq(Shell Command failed);
    $currentfilename = "SHELL\@$currentfilename:$currentlinenumber";
    $currentline = '';
    $currentlinenumber = 0;
    $ifstack = @ifstack;
}

sub embedded_perl( $ ) {
    my $multiline = shift;

    my ( $command , $linenumber ) = ( qq(package Shorewall::User;\nno strict;\nuse Shorewall::Config (qw/shorewall/);\n# line $currentlinenumber "$currentfilename"\n$currentline), $currentlinenumber );

    if ( $multiline ) {
	#
	# Multi-line script
	#
	fatal_error "Invalid BEGIN PERL directive" unless $currentline =~ /^\s*$/;
	$command .= "\n";

	my $last = 0;

	while ( read_a_line( PLAIN_READ ) ) {
	    last if $last = $currentline =~ s/^\s*\??END(\s+PERL)?\s*(?:;\s*)?//;
	    $command .= "$currentline\n";
	}

	fatal_error ( "Missing END PERL" ) unless $last;
	fatal_error ( "Invalid END PERL directive" ) unless $currentline =~ /^\s*$/;
    } else {
	$currentline = '';
    }

    $embedded++;

    unless (my $return = eval $command ) {
	#
	# Perl found the script offensive or the script itself died
	#
	if ( $@ ) {
	    $@ =~ s/, <\$currentfile> line \d+//g;
	    fatal_error1 "$@";
	}

	unless ( defined $return ) {
	    fatal_error "Perl Script failed: $!" if $!;
	    fatal_error "Perl Script failed";
	}

	fatal_error "Perl Script Returned False";
    }

    $embedded--;

    if ( $perlscript ) {
	fatal_error "INCLUDEs nested too deeply" if @includestack >= 4;

	assert( close $perlscript );

	$perlscript = undef;

	push @includestack, [ $currentfile, $currentfilename, $currentlinenumber , $ifstack ];
	$currentfile = undef;

	open $currentfile, '<', $perlscriptname or fatal_error "Unable to open Perl Script $perlscriptname";

	push @tempfiles, $perlscriptname unless unlink $perlscriptname; #unlink fails on Cygwin

	$perlscriptname = '';

	$currentfilename = "PERL\@$currentfilename:$linenumber";
	$currentline = '';
	$currentlinenumber = 0;
	$ifstack = @ifstack;
    }
}

#
# Push/pop action params
#
sub push_action_params( $$ ) {
    my @params = split /,/, $_[1];
    my @oldparams = @actparms;

    @actparms = ();

    $actparms[0] = $_[0];

    for ( my $i = 1; $i <= @params; $i++ ) {
	my $val = $params[$i - 1];

	$actparms[$i] = $val eq '-' ? '' : $val eq '--' ? '-' : $val;
    }

    \@oldparams;
}

sub pop_action_params( $ ) {
    my $oldparms = shift;
    @actparms = @$oldparms;
}

sub default_action_params {
    my $action = shift;
    my ( $val, $i );

    for ( $i = 1; 1; $i++ ) {
	last unless defined ( $val = shift );
	my $curval = $actparms[$i];
	$actparms[$i] = $val unless supplied( $curval );
    }

    fatal_error "Too Many arguments to action $action" if defined $actparms[$i];
}

sub get_action_params( $ ) {
    my $num = shift;

    fatal_error "Invalid argument to get_action_params()" unless $num =~ /^\d+$/ && $num > 0;

    my @return;

    for ( my $i = 1; $i <= $num; $i++ ) {
	my $val = $actparms[$i];
	push @return, defined $val ? $val eq '-' ? '' : $val eq '--' ? '-' : $val : $val;
    }

    @return;
}

sub get_action_chain() {
    $actparms[0];
}

sub set_action_param( $$ ) {
    my $i = shift;

    fatal_error "Parameter numbers must be numeric" unless $i =~ /^\d+$/ && $i > 0;
    $actparms[$i] = shift;
}

#
# Expand Shell Variables in the passed buffer using @actparms, %params, %shorewallrc and %config, 
#
sub expand_variables( \$ ) {
    my ( $lineref, $count ) = ( $_[0], 0 );
    #                         $1      $2   $3                  -     $4
    while ( $$lineref =~ m( ^(.*?) \$({)? (\d+|[a-zA-Z]\w*) (?(2)}) (.*)$ )x ) {

	my ( $first, $var, $rest ) = ( $1, $3, $4);

	my $val;

	if ( $var =~ /^\d+$/ ) {
	    fatal_error "Undefined parameter (\$$var)" if ( ! defined $actparms[$var] ) || ( length( $var ) > 1 && $var =~ /^0/ );
	    $val = $var ? $actparms[$var] : $actparms[0]->{name};
	} elsif ( exists $params{$var} ) {
	    $val = $params{$var};
	} elsif ( exists $shorewallrc{$var} ) {
	    $val = $shorewallrc{$var}
	} else {
	    fatal_error "Undefined shell variable (\$$var)" unless exists $config{$var};
	    $val = $config{$var};
	}

	$val = '' unless defined $val;
	$$lineref = join( '', $first , $val , $rest );
	fatal_error "Variable Expansion Loop" if ++$count > 100;
    }
}

#
# Handle first-entry processing
#
sub handle_first_entry() {
    #
    # $first_entry can contain either a function reference or a message. If it
    # contains a reference, call the function -- otherwise issue the message
    #
    reftype( $first_entry ) ? $first_entry->() : progress_message2( $first_entry );
    $first_entry = 0;
}

#
# Read a line from the current include stack. Based on the passed options, it will conditionally:
#
#   - Ignore blank or comment-only lines.
#   - Remove trailing comments.
#   - Handle Line Continuation
#   - Handle embedded SHELL and PERL scripts
#   - Expand shell variables from %params and %ENV.
#   - Handle INCLUDE <filename>
#   - Handle ?IF, ?ELSE, ?ENDIF
#

sub read_a_line($) {
    my $options = $_[0];

    while ( $currentfile ) {

	$currentline = '';
	$currentlinenumber = 0;

	while ( <$currentfile> ) {
	    chomp;
	    #
	    # Handle conditionals
	    #
	    if ( /^\s*\?(?:IF|ELSE|ELSIF|ENDIF)/i ) {
		$omitting = process_conditional( $omitting, $_, $currentfilename, $. );
		next;
	    }

	    if ( $omitting ) {
		print "OMIT=> $_\n" if $debug;
		next;
	    }

	    $currentlinenumber = $. unless $currentlinenumber;
	    #
	    # Suppress leading whitespace in certain continuation lines
	    #
	    s/^\s*// if $currentline =~ /[,:]$/ && $options & CONFIG_CONTINUATION;
	    #
	    # If this is a continued line with a trailing comment, remove comment. Note that
	    # the result will now end in '\'.
	    #
	    s/\s*#.*$// if ($options & STRIP_COMMENTS) && /[\\]\s*#.*$/;
	    #
	    # Continuation
	    #
	    chop $currentline, next if ($currentline .= $_) =~ /\\$/;
	    #
	    # Must check for shell/perl before doing variable expansion
	    #
	    if ( $options & EMBEDDED_ENABLED ) {
		if ( $currentline =~ s/^\s*\??(BEGIN\s+)SHELL\s*;?// || $currentline =~ s/^\s*\??SHELL\s*// ) {
		    handle_first_entry if $first_entry;
		    embedded_shell( $1 );
		    next;
		}

		if ( $currentline =~ s/^\s*\??(BEGIN\s+)PERL\s*;?// || $currentline =~ s/^\s*\??PERL\s*// ) {
		    handle_first_entry if $first_entry;
		    embedded_perl( $1 );
		    next;
		}
	    }
	    #
	    # Now remove concatinated comments if asked
	    #
	    $currentline =~ s/\s*#.*$// if $options & STRIP_COMMENTS;

	    if ( $options & SUPPRESS_WHITESPACE ) {
		#
		# Ignore (concatinated) blank lines
		#
		$currentline = '', $currentlinenumber = 0, next if $currentline =~ /^\s*$/;
		#
		# Eliminate trailing whitespace
		#
		$currentline =~ s/\s*$//;
	    }
	    #
	    # Line not blank -- Handle any first-entry message/capabilities check
	    #
	    handle_first_entry if $first_entry;
	    #
	    # Expand Shell Variables using %params and @actparms
	    #
	    expand_variables( $currentline ) if $options & EXPAND_VARIABLES;

	    if ( ( $options & DO_INCLUDE ) && $currentline =~ /^\s*\??INCLUDE\s/ ) {

		my @line = split ' ', $currentline;

		fatal_error "Invalid INCLUDE command"    if @line != 2;
		fatal_error "INCLUDEs/Scripts nested too deeply" if @includestack >= 4;

		my $filename = find_file $line[1];

		fatal_error "INCLUDE file $filename not found" unless -f $filename;
		fatal_error "Directory ($filename) not allowed in INCLUDE" if -d _;

		if ( -s _ ) {
		    push @includestack, [ $currentfile, $currentfilename, $currentlinenumber, $ifstack ];
		    $currentfile = undef;
		    do_open_file $filename;
		} else {
		    $currentlinenumber = 0;
		}

		$currentline = '';
	    } else {
		fatal_error "Non-ASCII gunk in file" if ( $options && CHECK_GUNK ) && $currentline =~ /[^\s[:print:]]/;
		print "IN===> $currentline\n" if $debug;
		return 1;
	    }
	}

	close_file;
    }
}

sub process_shorewallrc( $$ ) {
    my ( $shorewallrc , $product ) = @_;

    $shorewallrc{PRODUCT} = $product;

    if ( open_file $shorewallrc ) {
	while ( read_a_line( STRIP_COMMENTS | SUPPRESS_WHITESPACE | CHECK_GUNK ) ) {
	    if ( $currentline =~ /^([a-zA-Z]\w*)=(.*)$/ ) {
		my ($var, $val) = ($1, $2);
		$val = $1 if $val =~ /^\"([^\"]*)\"$/;
		expand_variables($val) if supplied $val;
		$shorewallrc{$var} = $val;
	    } else {
		fatal_error "Unrecognized shorewallrc entry";
	    }
	}
    } else {
	fatal_error "Failed to open $shorewallrc: $!";
    }

    if ( supplied $shorewallrc{VARDIR} ) {
	if ( ! supplied $shorewallrc{VARLIB} ) {
	    $shorewallrc{VARLIB} =  $shorewallrc{VARDIR};
	    $shorewallrc{VARDIR} = "$shorewallrc{VARLIB}/$product";
	}
    } elsif ( supplied $shorewallrc{VARLIB} ) {
	$shorewallrc{VARDIR} = "$shorewallrc{VARLIB}/$product" unless supplied $shorewallrc{VARDIR};
    }
}

#
# Provide the passed default value for the passed configuration variable
#
sub default ( $$ ) {
    my ( $var, $val ) = @_;

    $config{$var} = $val unless supplied( $config{$var} );
}

#
# Provide a default value for a yes/no configuration variable.
#
sub default_yes_no ( $$ ) {
    my ( $var, $val ) = @_;

    my $curval = $config{$var};

    if ( supplied $curval ) {
	$curval = lc $curval;

	if (  $curval eq 'no' ) {
	    $config{$var} = '';
	} else {
	    fatal_error "Invalid value for $var ($curval)" unless $curval eq 'yes';
	}
    } else {
	$config{$var} = $val;
    }
}

sub default_yes_no_ipv4 ( $$ ) {
    my ( $var, $val ) = @_;
    default_yes_no( $var, $val );
    warning_message "$var=Yes is ignored for IPv6" if $family == F_IPV6 && $config{$var};
}

sub numeric_option( $$$ ) {
    my ( $option, $default, $min ) = @_;

    my $value = $config{$option};

    my $val = $default;

    if ( supplied $value ) {
	$val = numeric_value $value;
	fatal_error "Invalid value ($value) for '$option'" unless defined $val && $val <= 32;
    }

    $val = $min if $val < $min;

    $config{$option} = $val;
}

sub make_mask( $ ) {
    0xffffffff >> ( 32 - $_[0] );
}

my @suffixes = qw(group range threshold nlgroup cprange qthreshold);

#
# Validate a log level -- Drop the trailing '!' and translate to numeric value if appropriate"
#
sub level_error( $ ) {
    fatal_error "Invalid log level ($_[0])";
}

my %logoptions = ( tcp_sequence         => '--log-tcp-sequence',
		   ip_options           => '--log-ip-options',
		   tcp_options          => '--log-tcp-options',
		   uid                  => '--log-uid',
		   macdecode            => '--log-macdecode',
		   #
		   # Because a level can pass through validate_level() more than once,
		   # the full option names are also included here.
		   #
		   '--log-tcp-sequence' => '--log-tcp-sequence',
		   '--log-ip-options'   => '--log-ip-options',
		   '--log-tcp-options'  => '--log-tcp-options',
		   '--log-uid'          => '--log-uid',
		   '--log-macdecode'    => '--log-macdecode',
		 );

sub validate_level( $ ) {
    my $rawlevel = $_[0];
    my $level    = uc $rawlevel;

    if ( supplied ( $level ) ) {
	$level =~ s/!$//;
	my $value = $level;
	my $qualifier;

	unless ( $value =~ /^[0-7]$/ ) {
	    } if ( $value =~ /^([0-7])(.*)$/ ) {
		$value = $1;
		$qualifier = $2;
	    } elsif ( $value =~ /^([A-Za-z0-7]+)(.*)$/ ) {
	        level_error( $level) unless defined( $value = $validlevels{$1} );
		$qualifier = $2;
	}

	if ( $value =~ /^[0-7]$/ ) {
	    #
	    # Syslog Level
	    #
	    if ( supplied $qualifier ) {
		my $options = '';
		my %options;

		level_error ( $rawlevel ) unless $qualifier =~ /^\((.*)\)$/;

		for ( split_list lc $1, "log options" ) {
		    my $option = $logoptions{$_};
		    fatal_error "Unknown LOG option ($_)" unless $option;

		    unless ( $options{$option} ) {
			if ( $options ) {
			    $options = join( ',', $options, $option );
			} else {
			    $options = $option;
			}

			$options{$option} = 1;
		    }
		}

		$value .= "($options)" if $options;
	    }

	    require_capability ( 'LOG_TARGET' , "Log level $level", 's' );

	    return $value;
	}

	return '' unless $value;

	require_capability( "${value}_TARGET", "Log level $level", 's' );

	if ( $value =~ /^(NFLOG|ULOG)$/ ) {
	    my $olevel  = $value;

	    if ( $qualifier =~ /^[(](.*)[)]$/ ) {
		my @options = split /,/, $1;
		my $prefix  = lc $olevel;
		my $index   = $prefix eq 'ulog' ? 3 : 0;

		level_error( $rawlevel ) if @options > 3;

		for ( @options ) {
		    if ( supplied( $_ ) ) {
			level_error( $rawlevel ) unless /^\d+/;
			$olevel .= " --${prefix}-$suffixes[$index] $_";
		    }

		    $index++;
		}

	    } elsif ( $qualifier =~ /^ --/ ) {
		return $rawlevel;
	    } else {
		level_error( $rawlevel ) if $qualifier;
	    }

	    return $olevel;
	}

	#
	# Must be LOGMARK
	#
	my $sublevel;

	if ( supplied $qualifier ) {
	    return $rawlevel if $qualifier =~ /^ --/;

	    if ( $qualifier =~ /[(](.+)[)]$/ ) {
		$sublevel = $1;

		$sublevel = $validlevels{$sublevel} unless $sublevel =~ /^[0-7]$/;
		level_error( $rawlevel ) unless defined $sublevel && $sublevel  =~ /^[0-7]$/;
	    } else {
		level_error( $rawlevel );
	    }
	} else {
	    $sublevel = 6; # info
	}

	return "LOGMARK --log-level $sublevel";
    }

    '';
}

#
# Validate a log level and supply default
#
sub default_log_level( $$ ) {
    my ( $level, $default ) = @_;

    my $value = $config{$level};

    unless ( supplied $value ) {
	$config{$level} = $default;
    } else {
	$config{$level} = validate_level $value;
    }
}

#
# Check a tri-valued variable
#
sub check_trivalue( $$ ) {
    my ( $var, $default) = @_;
    my $val = $config{$var};

    if ( defined $val ) {
	$val = lc $val;
	if ( $val eq 'yes' || $val eq 'on' ) {
	    $config{$var} = 'on';
	} elsif ( $val eq 'no' || $val eq 'off' ) {
	    $config{$var} = 'off';
	} elsif ( $val eq 'keep' ) {
	    $config{$var} = '';
	} elsif ( $val eq '' ) {
	    $config{$var} = $default
	} else {
	    fatal_error "Invalid value ($val) for $var";
	}
    } else {
	$config{$var} = $default
    }
}

#
# Produce a report of the detected capabilities
#
sub report_capability( $ ) {
    my $cap = $_[0];
    print "   $capdesc{$cap}: ";
    if ( $cap eq 'CAPVERSION' || $cap eq 'KERNELVERSION') {
	my $version = $capabilities{$cap};
	printf "%d.%d.%d\n", int( $version / 10000 ) , int ( ( $version % 10000 ) / 100 ) , int ( $version % 100 );
    } else {
	print $capabilities{$cap} ? "Available\n" : "Not Available\n";
    }
}

sub report_capabilities() {
    if ( $verbosity > 1 ) {
	print "Shorewall has detected the following capabilities:\n";

	for my $cap ( sort { $capdesc{$a} cmp $capdesc{$b} } keys %capabilities ) {
	    report_capability $cap;
	}
    }
}

#
# Search the current PATH for the passed executable
#
sub which( $ ) {
    my $prog = $_[0];

    for ( split /:/, $config{PATH} ) {
	return "$_/$prog" if -x "$_/$prog";
    }

    '';
}

#
# Load the kernel modules defined in the 'modules' file.
#
sub load_kernel_modules( ) {
    my $moduleloader = which( 'modprobe' ) || ( which 'insmod' );

    my $modulesdir = $config{MODULESDIR};

    unless ( $modulesdir ) {
	my $uname = `uname -r`;
	fatal_error "The command 'uname -r' failed" unless $? == 0;
	chomp $uname;
	$modulesdir = "/lib/modules/$uname/kernel/net/ipv4/netfilter:/lib/modules/$uname/kernel/net/ipv6/netfilter:/lib/modules/$uname/kernel/net/netfilter:/lib/modules/$uname/extra:/lib/modules/$uname/extra/ipset";
    }

    my @moduledirectories;

    for ( split /:/, $modulesdir ) {
	push @moduledirectories, $_ if -d $_;
    }

    if ( $moduleloader &&  @moduledirectories && open_file( $config{LOAD_HELPERS_ONLY} ? 'helpers' : 'modules' ) ) {
	my %loadedmodules;

	$loadedmodules{$_}++ for split_list( $config{DONT_LOAD}, 'module' );

	progress_message2 "Loading Modules...";

	open LSMOD , '-|', 'lsmod' or fatal_error "Can't run lsmod";

	while ( <LSMOD> ) {
	    my $module = ( split( /\s+/, $_, 2 ) )[0];
	    $loadedmodules{$module}++ unless $module eq 'Module'
	}

	close LSMOD;

	$config{MODULE_SUFFIX} = 'o gz ko o.gz ko.gz' unless $config{MODULE_SUFFIX};

	my @suffixes = split /\s+/ , $config{MODULE_SUFFIX};

	while ( read_a_line( NORMAL_READ ) ) {
	    fatal_error "Invalid modules file entry" unless ( $currentline =~ /^loadmodule\s+([a-zA-Z]\w*)\s*(.*)$/ );
	    my ( $module, $arguments ) = ( $1, $2 );
	    unless ( $loadedmodules{ $module } ) {
		for my $directory ( @moduledirectories ) {
		    for my $suffix ( @suffixes ) {
			my $modulefile = "$directory/$module.$suffix";
			if ( -f $modulefile ) {
			    if ( $moduleloader eq 'insmod' ) {
				system ("insmod $modulefile $arguments" );
			    } else {
				system( "modprobe $module $arguments" );
			    }

			    $loadedmodules{ $module } = 1;
			}
		    }
		}
	    }
	}
    }
}

#
# Q[uie]t version of system(). Returns true for success
#
sub qt( $ ) {
    if ( $debug ) {
	print "SYS----> @_\n";
	system( "@_ 2>&1" );
    } else {
	system( "@_ > /dev/null 2>&1 < /dev/null" ) == 0;
    }
}

sub qt1( $ ) {
    1 while qt( "@_" ) == 4;
    $? == 0;
}

#
# Get the current kernel version
#
sub determine_kernelversion() {
    my $kernelversion=`uname -r`;

    if ( $kernelversion =~ /^(\d+)\.(\d+).(\d+)/ ) {
	$capabilities{KERNELVERSION} = sprintf "%d%02d%02d", $1 , $2 , $3;
    } elsif ( $kernelversion =~ /^(\d+)\.(\d+)/ ) {
	$capabilities{KERNELVERSION} = sprintf "%d%02d00", $1 , $2;
    } else {
	fatal_error "Unrecognized Kernel Version Format ($kernelversion)";
    }
}

#
# Capability Reporting and detection.
#
sub Nat_Enabled() {
    $family == F_IPV4 ? qt1( "$iptables -t nat -L -n" ) : '';
}

sub Persistent_Snat() {
    have_capability 'NAT_ENABLED' || return '';

    my $result = '';

    if ( qt1( "$iptables -t nat -N $sillyname" ) ) {
	$result = qt1( "$iptables -t nat -A $sillyname -j SNAT --to-source 1.2.3.4 --persistent" );
	qt1( "$iptables -t nat -F $sillyname" );
	qt1( "$iptables -t nat -X $sillyname" );

    }

    $result;
}

sub Mangle_Enabled() {
    if ( qt1( "$iptables -t mangle -L -n" ) ) {
	system( "$iptables -t mangle -N $sillyname" ) == 0 || fatal_error "Cannot Create Mangle chain $sillyname";
    }
}

sub Conntrack_Match() {
    if ( $family == F_IPV4 ) {
	qt1( "$iptables -A $sillyname -m conntrack --ctorigdst 192.168.1.1 -j ACCEPT" );
    } else {
	qt1( "$iptables -A $sillyname -m conntrack --ctorigdst ::1 -j ACCEPT" );
    }
}

sub New_Conntrack_Match() {
    have_capability 'CONNTRACK_MATCH' && qt1( "$iptables -A $sillyname -m conntrack -p tcp --ctorigdstport 22 -j ACCEPT" );
}

sub Old_Conntrack_Match() {
    ! qt1( "$iptables -A $sillyname -m conntrack ! --ctorigdst 1.2.3.4" );
}

sub Multiport() {
    qt1( "$iptables -A $sillyname -p tcp -m multiport --dports 21,22 -j ACCEPT" );
}

sub Kludgefree1() {
    have_capability 'MULTIPORT' && qt1( "$iptables -A $sillyname -p tcp -m multiport --sports 60 -m multiport --dports 99 -j ACCEPT" );
}

sub Kludgefree2() {
    have_capability 'PHYSDEV_MATCH' && qt1( "$iptables -A $sillyname -m physdev --physdev-in eth0 -m physdev --physdev-out eth0 -j ACCEPT" );
}

sub Kludgefree3() {
    if ( $family == F_IPV4 ) {
	qt1( "$iptables -A $sillyname -m iprange --src-range 192.168.1.5-192.168.1.124 -m iprange --dst-range 192.168.1.5-192.168.1.124 -j ACCEPT" );
    } else {
	qt1( "$iptables -A $sillyname -m iprange --src-range ::1-::2 -m iprange --dst-range 192.168.1.5-192.168.1.124 -j ACCEPT" );
    }
}

sub Kludgefree() {
    Kludgefree1 || Kludgefree2 || Kludgefree3;
}

sub Xmultiport() {
    qt1( "$iptables -A $sillyname -p tcp -m multiport --dports 21:22 -j ACCEPT" );
}

sub Policy_Match() {
    qt1( "$iptables -A $sillyname -m policy --pol ipsec --mode tunnel --dir in -j ACCEPT" );
}

sub Physdev_Match() {
    qt1( "$iptables -A $sillyname -m physdev --physdev-in eth0 -j ACCEPT" );
}

sub Physdev_Bridge() {
    qt1( "$iptables -A $sillyname -m physdev --physdev-is-bridged --physdev-in eth0 --physdev-out eth1 -j ACCEPT" );
}

sub IPRange_Match() {
    if ( $family == F_IPV4 ) {
	qt1( "$iptables -A $sillyname -m iprange --src-range 192.168.1.5-192.168.1.124 -j ACCEPT" );
    } else {
	qt1( "$iptables -A $sillyname -m iprange --src-range ::1-::2 -j ACCEPT" );
    }
}

sub Recent_Match() {
    qt1( "$iptables -A $sillyname -m recent --update -j ACCEPT" );
}

sub Owner_Match() {
    qt1( "$iptables -A $sillyname -m owner --uid-owner 0 -j ACCEPT" );
}

sub Owner_Name_Match() {
    if ( my $name = `id -un 2> /dev/null` ) {
	qt1( "$iptables -A $sillyname -m owner --uid-owner $name -j ACCEPT" );
    }
}

sub Connmark_Match() {
    qt1( "$iptables -A $sillyname -m connmark --mark 2  -j ACCEPT" );
}

sub Xconnmark_Match() {
    have_capability 'CONNMARK_MATCH' && qt1( "$iptables -A $sillyname -m connmark --mark 2/0xFF -j ACCEPT" );
}

sub Ipp2p_Match() {
    qt1( "$iptables -A $sillyname -p tcp -m ipp2p --edk -j ACCEPT" );
}

sub Old_Ipp2p_Match() {
    qt1( "$iptables -A $sillyname -p tcp -m ipp2p --ipp2p -j ACCEPT" ) if $capabilities{IPP2P_MATCH};
}

sub Length_Match() {
    qt1( "$iptables -A $sillyname -m length --length 10:20 -j ACCEPT" );
}

sub Enhanced_Reject() {
    if ( $family == F_IPV6 ) {
	qt1( "$iptables -A $sillyname -j REJECT --reject-with icmp6-adm-prohibited" );
    } else {
	qt1( "$iptables -A $sillyname -j REJECT --reject-with icmp-host-prohibited" );
    }
}

sub Comments() {
    qt1( qq($iptables -A $sillyname -j ACCEPT -m comment --comment "This is a comment" ) );
}

sub Hashlimit_Match() {
    if ( qt1( "$iptables -A $sillyname -m hashlimit --hashlimit-upto 3/min --hashlimit-burst 3 --hashlimit-name $sillyname --hashlimit-mode srcip -j ACCEPT" ) ) {
	! ( $capabilities{OLD_HL_MATCH} = 0 );
    } else {
	have_capability 'OLD_HL_MATCH';
    }
}

sub Old_Hashlimit_Match() {
    qt1( "$iptables -A $sillyname -m hashlimit --hashlimit 3/min --hashlimit-burst 3 --hashlimit-name $sillyname --hashlimit-mode srcip -j ACCEPT" );
}

sub Mark() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -j MARK --set-mark 1" );
}

sub Xmark() {
    have_capability 'MARK' && qt1( "$iptables -t mangle -A $sillyname -j MARK --and-mark 0xFF" );
}

sub Exmark() {
    have_capability 'MARK' && qt1( "$iptables -t mangle -A $sillyname -j MARK --set-mark 1/0xFF" );
}

sub Connmark() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -j CONNMARK --save-mark" );
}

sub Xconnmark() {
    have_capability 'XCONNMARK_MATCH' && have_capability 'XMARK' && qt1( "$iptables -t mangle -A $sillyname -j CONNMARK --save-mark --mask 0xFF" );
}

sub Classify_Target() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -j CLASSIFY --set-class 1:1" );
}

sub IPMark_Target() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -j IPMARK --addr src" );
}

sub Tproxy_Target() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -p tcp -j TPROXY --on-port 0 --tproxy-mark 1" );
}

sub Mangle_Forward() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -L FORWARD -n" );
}

sub Raw_Table() {
    qt1( "$iptables -t raw -L -n" );
}

sub Rawpost_Table() {
    qt1( "$iptables -t rawpost -L -n" );
}

sub Old_IPSet_Match() {
    my $ipset  = $config{IPSET} || 'ipset';
    my $result = 0;

    $ipset = which $ipset unless $ipset =~ '/';

    if ( $ipset && -x $ipset ) {
	qt( "$ipset -X $sillyname" );

	if ( qt( "$ipset -N $sillyname iphash" ) ) {
	    if ( qt1( "$iptables -A $sillyname -m set --set $sillyname src -j ACCEPT" ) ) {
		qt1( "$iptables -F $sillyname" );
		$result = $capabilities{IPSET_MATCH} = 1;
	    }

	    qt( "$ipset -X $sillyname" );
	}
    }

    $result;
}

sub IPSet_Match() {
    my $ipset  = $config{IPSET} || 'ipset';
    my $result = 0;
    my $fam    = $family == F_IPV4 ? 'inet' : 'inet6';

    $ipset = which $ipset unless $ipset =~ '/';

    if ( $ipset && -x $ipset ) {
	qt( "$ipset -X $sillyname" );

	if ( qt( "$ipset -N $sillyname iphash" ) || qt( "$ipset -N $sillyname hash:ip family $fam") ) {
	    if ( qt1( "$iptables -A $sillyname -m set --match-set $sillyname src -j ACCEPT" ) ) {
		qt1( "$iptables -F $sillyname" );
		$result = ! ( $capabilities{OLD_IPSET_MATCH} = 0 );
	    } else {
		$result = have_capability 'OLD_IPSET_MATCH';
	    }

	    qt( "$ipset -X $sillyname" );
	}
    }

    $result;
}

sub IPSET_V5() {
    my $ipset  = $config{IPSET} || 'ipset';
    my $result = 0;

    $ipset = which $ipset unless $ipset =~ '/';

    if ( $ipset && -x $ipset ) {
	qt( "$ipset -X $sillyname" );

	if ( qt( "$ipset -N $sillyname hash:ip family inet" ) ) {
	    $result = 1;
	    qt( "$ipset -X $sillyname" );
	}
    }

    $result;
}

sub Usepkttype() {
    qt1( "$iptables -A $sillyname -m pkttype --pkt-type broadcast -j ACCEPT" );
}

sub Addrtype() {
    qt1( "$iptables -A $sillyname -m addrtype --src-type BROADCAST -j ACCEPT" );
}

sub Tcpmss_Match() {
    qt1( "$iptables -A $sillyname -p tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1000:1500 -j ACCEPT" );
}

sub Nfqueue_Target() {
    qt1( "$iptables -A $sillyname -j NFQUEUE --queue-num 4" );
}

sub Realm_Match() {
    qt1( "$iptables -A $sillyname -m realm --realm 1" );
}

sub Helper_Match() {
    qt1( "$iptables -A $sillyname -p tcp --dport 21 -m helper --helper ftp" );
}

sub have_helper( $$$ ) {
    my ( $helper, $proto, $port ) = @_;

    if ( $helpers_enabled{$helper} ) {
	if ( have_capability 'CT_TARGET' ) {
	    qt1( "$iptables -t raw -A $sillyname -p $proto --dport $port -j CT --helper $helper" );
	} else {
	    have_capability 'HELPER_MATCH';
	}
    }
}

sub Amanda_Helper() {
    have_helper( 'amanda', 'udp', 10080 );
}

sub FTP0_Helper() {
    have_helper( 'ftp-0', 'tcp', 21 ) and $helpers_aliases{ftp} = 'ftp-0';
}

sub FTP_Helper() {
    have_helper( 'ftp', 'tcp', 21 ) || FTP0_Helper;
}

sub H323_Helpers() {
    have_helper( 'RAS', 'udp', 1719 );
}

sub IRC0_Helper() {
    have_helper( 'irc-0', 'tcp', 6667 ) and $helpers_aliases{irc} = 'irc-0';
}

sub IRC_Helper() {
    have_helper( 'irc', 'tcp', 6667 ) || IRC0_Helper;
}

sub Netbios_ns_Helper() {
    have_helper( 'netbios-ns', 'udp', 137 );
}

sub PPTP_Helper() {
    have_helper( 'pptp', 'tcp', 1729 );
}

sub SANE0_Helper() {
    have_helper( 'sane-0', 'tcp', 6566 ) and $helpers_aliases{sane} = 'sane-0';
}

sub SANE_Helper() {
    have_helper( 'sane', 'tcp', 6566 ) || SANE0_Helper;
}

sub SIP0_Helper() {
    have_helper( 'sip-0', 'udp', 5060 ) and $helpers_aliases{sip} = 'sip-0';
}

sub SIP_Helper() {
    have_helper( 'sip', 'udp', 5060 ) || SIP0_Helper;
}

sub SNMP_Helper() {
    have_helper( 'snmp', 'udp', 161 );
}

sub TFTP0_Helper() {
    have_helper( 'tftp-0', 'udp', 69 ) and $helpers_aliases{tftp} = 'tftp-0';
}

sub TFTP_Helper() {
    have_helper( 'tftp', 'udp', 69 ) || TFTP0_Helper;
}

sub Connlimit_Match() {
    qt1( "$iptables -A $sillyname -m connlimit --connlimit-above 8" );
}

sub Time_Match() {
    qt1( "$iptables -A $sillyname -m time --timestart 11:00" );
}

sub Goto_Target() {
    qt1( "$iptables -A $sillyname -g $sillyname1" );
}

sub Log_Target() {
    qt1( "$iptables -A $sillyname -j LOG" );
}

sub Ulog_Target() {
    qt1( "$iptables -A $sillyname -j ULOG" );
}

sub NFLog_Target() {
    qt1( "$iptables -A $sillyname -j NFLOG" );
}

sub Logmark_Target() {
    qt1( "$iptables -A $sillyname -j LOGMARK" );
}

sub Flow_Filter() {
    $tc && system( "$tc filter add flow help 2>&1 | grep -q ^Usage" ) == 0;
}

sub Basic_Filter() {
    $tc && system( "$tc filter add basic help 2>&1 | grep -q ^Usage" ) == 0;
}

sub Fwmark_Rt_Mask() {
    $ip && system( "$ip rule add help 2>&1 | grep -q /MASK" ) == 0;
}

sub Mark_Anywhere() {
    qt1( "$iptables -A $sillyname -j MARK --set-mark 5" );
}

sub Header_Match() {
    qt1( "$iptables -A $sillyname -m ipv6header --header 255 -j ACCEPT" );
}

sub Account_Target() {
    if ( $family == F_IPV4 ) {
	qt1( "$iptables -A $sillyname -j ACCOUNT --addr 192.168.1.0/29 --tname $sillyname" );
    } else {
	qt1( "$iptables -A $sillyname -j ACCOUNT --addr 1::/122 --tname $sillyname" );
    }
}

sub Condition_Match() {
    qt1( "$iptables -A $sillyname -m condition --condition foo" );
}

sub Audit_Target() {
    qt1( "$iptables -A $sillyname -j AUDIT --type drop" );
}

sub Iptables_S() {
    qt1( "$iptables -S INPUT" )
}

sub Ct_Target() {
    my $ct_target;

    if ( have_capability 'RAW_TABLE' ) {
	qt1( "$iptables -t raw -N $sillyname" );
	$ct_target = qt1( "$iptables -t raw -A $sillyname -j CT --notrack" );
    }

    $ct_target;
}

sub Statistic_Match() {
    qt1( "$iptables -A $sillyname -m statistic --mode nth --every 2 --packet 1" );
}


sub Imq_Target() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -j IMQ --todev 0" );
}

sub Dscp_Match() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -m dscp --dscp 0" );
}

sub Dscp_Target() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -j DSCP --set-dscp 0" );
}

sub RPFilter_Match() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -m rpfilter" );
}

sub NFAcct_Match() {
    my $result;

    if ( qt1( "nfacct add $sillyname" ) ) {
	$result = qt1( "$iptables -A $sillyname -m nfacct --nfacct-name $sillyname" );
	qt( "$iptables -D $sillyname -m nfacct --nfacct-name $sillyname" );
	qt( "nfacct del $sillyname" );
    }

    $result;
}

sub GeoIP_Match() {
    qt1( "$iptables -A $sillyname -m geoip --src-cc US" );
}

sub Checksum_Target() {
    have_capability 'MANGLE_ENABLED' && qt1( "$iptables -t mangle -A $sillyname -j CHECKSUM --checksum-fill" );
}

our %detect_capability =
    ( ACCOUNT_TARGET =>\&Account_Target,
      AMANDA_HELPER => \&Amanda_Helper,
      AUDIT_TARGET => \&Audit_Target,
      ADDRTYPE => \&Addrtype,
      BASIC_FILTER => \&Basic_Filter,
      CHECKSUM_TARGET => \&Checksum_Target,
      CLASSIFY_TARGET => \&Classify_Target,
      CONDITION_MATCH => \&Condition_Match,
      COMMENTS => \&Comments,
      CONNLIMIT_MATCH => \&Connlimit_Match,
      CONNMARK => \&Connmark,
      CONNMARK_MATCH => \&Connmark_Match,
      CONNTRACK_MATCH => \&Conntrack_Match,
      CT_TARGET => \&Ct_Target,
      DSCP_MATCH => \&Dscp_Match,
      DSCP_TARGET => \&Dscp_Target,
      ENHANCED_REJECT => \&Enhanced_Reject,
      EXMARK => \&Exmark,
      FLOW_FILTER => \&Flow_Filter,
      FTP_HELPER => \&FTP_Helper,
      FTP0_HELPER => \&FTP0_Helper,
      FWMARK_RT_MASK => \&Fwmark_Rt_Mask,
      GEOIP_MATCH => \&GeoIP_Match,
      GOTO_TARGET => \&Goto_Target,
      H323_HELPER => \&H323_Helpers,
      HASHLIMIT_MATCH => \&Hashlimit_Match,
      HEADER_MATCH => \&Header_Match,
      HELPER_MATCH => \&Helper_Match,
      IMQ_TARGET => \&Imq_Target,
      IPMARK_TARGET => \&IPMark_Target,
      IPP2P_MATCH => \&Ipp2p_Match,
      IPRANGE_MATCH => \&IPRange_Match,
      IPSET_MATCH => \&IPSet_Match,
      IRC_HELPER => \&IRC_Helper,
      IRC0_HELPER => \&IRC0_Helper,
      OLD_IPSET_MATCH => \&Old_IPSet_Match,
      IPSET_V5 => \&IPSET_V5,
      IPTABLES_S => \&Iptables_S,
      KLUDGEFREE => \&Kludgefree,
      LENGTH_MATCH => \&Length_Match,
      LOGMARK_TARGET => \&Logmark_Target,
      LOG_TARGET => \&Log_Target,
      ULOG_TARGET => \&Ulog_Target,
      NFLOG_TARGET => \&NFLog_Target,
      MANGLE_ENABLED => \&Mangle_Enabled,
      MANGLE_FORWARD => \&Mangle_Forward,
      MARK => \&Mark,
      MARK_ANYWHERE => \&Mark_Anywhere,
      MULTIPORT => \&Multiport,
      NAT_ENABLED => \&Nat_Enabled,
      NETBIOS_NS_HELPER => \&Netbios_ns_Helper,
      NEW_CONNTRACK_MATCH => \&New_Conntrack_Match,
      NFACCT_MATCH => \&NFAcct_Match,
      NFQUEUE_TARGET => \&Nfqueue_Target,
      OLD_CONNTRACK_MATCH => \&Old_Conntrack_Match,
      OLD_HL_MATCH => \&Old_Hashlimit_Match,
      OLD_IPP2P_MATCH => \&Old_Ipp2p_Match,
      OWNER_MATCH => \&Owner_Match,
      OWNER_NAME_MATCH => \&Owner_Name_Match,
      PERSISTENT_SNAT => \&Persistent_Snat,
      PHYSDEV_BRIDGE => \&Physdev_Bridge,
      PHYSDEV_MATCH => \&Physdev_Match,
      POLICY_MATCH => \&Policy_Match,
      PPTP_HELPER => \&PPTP_Helper,
      RAW_TABLE => \&Raw_Table,
      RAWPOST_TABLE => \&Rawpost_Table,
      REALM_MATCH => \&Realm_Match,
      RECENT_MATCH => \&Recent_Match,
      RPFILTER_MATCH => \&RPFilter_Match,
      SANE_HELPER => \&SANE_Helper,
      SANE0_HELPER => \&SANE0_Helper,
      SIP_HELPER => \&SIP_Helper,
      SIP0_HELPER => \&SIP0_Helper,
      SNMP_HELPER => \&SNMP_Helper,
      STATISTIC_MATCH => \&Statistic_Match,
      TCPMSS_MATCH => \&Tcpmss_Match,
      TFTP_HELPER => \&TFTP_Helper,
      TFTP0_HELPER => \&TFTP0_Helper,
      TIME_MATCH => \&Time_Match,
      TPROXY_TARGET => \&Tproxy_Target,
      USEPKTTYPE => \&Usepkttype,
      XCONNMARK_MATCH => \&Xconnmark_Match,
      XCONNMARK => \&Xconnmark,
      XMARK => \&Xmark,
      XMULTIPORT => \&Xmultiport,
    );

sub detect_capability( $ ) {
    my $capability = shift;
    my $function = $detect_capability{ $capability };

    assert( ( reftype( $function ) || '' ) eq 'CODE' );
    $function->();
}

#
# Report the passed capability
#
sub have_capability( $ ) {
    my $capability = shift;
    our %detect_capability;

    my $setting = $capabilities{ $capability };

    $setting = $capabilities{ $capability } = detect_capability( $capability ) unless defined $setting;

    $setting;
}

#
# Determine which optional facilities are supported by iptables/netfilter
#
sub determine_capabilities() {

    my $pid     = $$;

    $capabilities{CAPVERSION} = $globals{CAPVERSION};

    determine_kernelversion;

    $sillyname  = "fooX$pid";
    $sillyname1 = "foo1X$pid";

    qt1( "$iptables -N $sillyname" );
    qt1( "$iptables -N $sillyname1" );

    fatal_error 'Your kernel/iptables do not include state match support. No version of Shorewall will run on this system'
	unless
	    qt1( "$iptables -A $sillyname -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT") ||
	    qt1( "$iptables -A $sillyname -m state --state ESTABLISHED,RELATED -j ACCEPT");;

    $globals{KLUDGEFREE} = $capabilities{KLUDGEFREE} = detect_capability 'KLUDGEFREE';

    unless ( $config{ LOAD_HELPERS_ONLY } ) {
	#
	# Using 'detect_capability()' is a bit less efficient than calling the individual detection
	# functions but it ensures that %detect_capability is initialized properly.
	#
	$capabilities{NAT_ENABLED}     = detect_capability( 'NAT_ENABLED' );
	$capabilities{PERSISTENT_SNAT} = detect_capability( 'PERSISTENT_SNAT' );
	$capabilities{MANGLE_ENABLED}  = detect_capability( 'MANGLE_ENABLED' );

	if ( $capabilities{CONNTRACK_MATCH} = detect_capability( 'CONNTRACK_MATCH' ) ) {
	    $capabilities{NEW_CONNTRACK_MATCH} = detect_capability( 'NEW_CONNTRACK_MATCH' );
	    $capabilities{OLD_CONNTRACK_MATCH} = detect_capability( 'OLD_CONNTRACK_MATCH' );
	} else {
	    $capabilities{NEW_CONNTRACK_MATCH} = '';
	    $capabilities{OLD_CONNTRACK_MATCH} = '';
	}

	$capabilities{ MULTIPORT } = detect_capability( 'MULTIPORT' );
	$capabilities{XMULTIPORT}   = detect_capability( 'XMULTIPORT' );
	$capabilities{POLICY_MATCH} = detect_capability( 'POLICY_MATCH' );

	if ( $capabilities{PHYSDEV_MATCH} = detect_capability( 'PHYSDEV_MATCH' ) ) {
	    $capabilities{PHYSDEV_BRIDGE} = detect_capability( 'PHYSDEV_BRIDGE' );
	} else {
	    $capabilities{PHYSDEV_BRIDGE} = '';
	}

	$capabilities{IPRANGE_MATCH}   = detect_capability( 'IPRANGE_MATCH' );
	$capabilities{RECENT_MATCH}    = detect_capability( 'RECENT_MATCH' );
	$capabilities{OWNER_MATCH}     = detect_capability( 'OWNER_MATCH' );
	$capabilities{OWNER_NAME_MATCH}
                                       = detect_capability( 'OWNER_NAME_MATCH' );
	$capabilities{CONNMARK_MATCH}  = detect_capability( 'CONNMARK_MATCH' );
	$capabilities{XCONNMARK_MATCH} = detect_capability( 'XCONNMARK_MATCH' );
	$capabilities{IPP2P_MATCH}     = detect_capability( 'IPP2P_MATCH' );
	$capabilities{OLD_IPP2P_MATCH} = detect_capability( 'OLD_IPP2P_MATCH' );
	$capabilities{LENGTH_MATCH}    = detect_capability( 'LENGTH_MATCH' );
	$capabilities{ENHANCED_REJECT} = detect_capability( 'ENHANCED_REJECT' );
	$capabilities{COMMENTS}        = detect_capability( 'COMMENTS' );
	$capabilities{OLD_HL_MATCH}    = detect_capability( 'OLD_HL_MATCH' );
	$capabilities{HASHLIMIT_MATCH} = detect_capability( 'HASHLIMIT_MATCH' );
	$capabilities{MARK}            = detect_capability( 'MARK' );
	$capabilities{XMARK}           = detect_capability( 'XMARK' );
	$capabilities{EXMARK}          = detect_capability( 'EXMARK' );
	$capabilities{CONNMARK}        = detect_capability( 'CONNMARK' );
	$capabilities{XCONNMARK}       = detect_capability( 'XCONNMARK' );
	$capabilities{CLASSIFY_TARGET} = detect_capability( 'CLASSIFY_TARGET' );
	$capabilities{IPMARK_TARGET}   = detect_capability( 'IPMARK_TARGET' );
	$capabilities{TPROXY_TARGET}   = detect_capability( 'TPROXY_TARGET' );
	$capabilities{MANGLE_FORWARD}  = detect_capability( 'MANGLE_FORWARD' );
	$capabilities{RAW_TABLE}       = detect_capability( 'RAW_TABLE' );
	$capabilities{RAWPOST_TABLE}   = detect_capability( 'RAWPOST_TABLE' );
	$capabilities{IPSET_MATCH}     = detect_capability( 'IPSET_MATCH' );
	$capabilities{USEPKTTYPE}      = detect_capability( 'USEPKTTYPE' );
	$capabilities{ADDRTYPE}        = detect_capability( 'ADDRTYPE' );
	$capabilities{TCPMSS_MATCH}    = detect_capability( 'TCPMSS_MATCH' );
	$capabilities{NFQUEUE_TARGET}  = detect_capability( 'NFQUEUE_TARGET' );
	$capabilities{REALM_MATCH}     = detect_capability( 'REALM_MATCH' );
	$capabilities{CONNLIMIT_MATCH} = detect_capability( 'CONNLIMIT_MATCH' );
	$capabilities{TIME_MATCH}      = detect_capability( 'TIME_MATCH' );
	$capabilities{GOTO_TARGET}     = detect_capability( 'GOTO_TARGET' );
	$capabilities{LOG_TARGET}      = detect_capability( 'LOG_TARGET' );
	$capabilities{ULOG_TARGET}     = detect_capability( 'ULOG_TARGET' );
	$capabilities{NFLOG_TARGET}    = detect_capability( 'NFLOG_TARGET' );
	$capabilities{LOGMARK_TARGET}  = detect_capability( 'LOGMARK_TARGET' );
	$capabilities{FLOW_FILTER}     = detect_capability( 'FLOW_FILTER' );
	$capabilities{FWMARK_RT_MASK}  = detect_capability( 'FWMARK_RT_MASK' );
	$capabilities{MARK_ANYWHERE}   = detect_capability( 'MARK_ANYWHERE' );
	$capabilities{ACCOUNT_TARGET}  = detect_capability( 'ACCOUNT_TARGET' );
	$capabilities{AUDIT_TARGET}    = detect_capability( 'AUDIT_TARGET' );
	$capabilities{IPSET_V5}        = detect_capability( 'IPSET_V5' );
	$capabilities{CONDITION_MATCH} = detect_capability( 'CONDITION_MATCH' );
	$capabilities{IPTABLES_S}      = detect_capability( 'IPTABLES_S' );
	$capabilities{BASIC_FILTER}    = detect_capability( 'BASIC_FILTER' );
	$capabilities{CT_TARGET}       = detect_capability( 'CT_TARGET' );
	$capabilities{STATISTIC_MATCH} = detect_capability( 'STATISTIC_MATCH' );
	$capabilities{IMQ_TARGET}      = detect_capability( 'IMQ_TARGET' );
	$capabilities{DSCP_MATCH}      = detect_capability( 'DSCP_MATCH' );
	$capabilities{DSCP_TARGET}     = detect_capability( 'DSCP_TARGET' );
	$capabilities{GEOIP_MATCH}     = detect_capability( 'GEOIP_MATCH' );
	$capabilities{RPFILTER_MATCH}  = detect_capability( 'RPFILTER_MATCH' );
	$capabilities{NFACCT_MATCH}    = detect_capability( 'NFACCT_MATCH' );
	$capabilities{CHECKSUM_TARGET} = detect_capability( 'CHECKSUM_TARGET' );
	
	if ( have_capability 'CT_TARGET' ) {
	    $capabilities{$_} = detect_capability $_ for ( values( %helpers_map ) );
	} else {
	    $capabilities{HELPER_MATCH} = detect_capability 'HELPER_MATCH';
	}

	qt1( "$iptables -F $sillyname" );
	qt1( "$iptables -X $sillyname" );
	qt1( "$iptables -F $sillyname1" );
	qt1( "$iptables -X $sillyname1" );

	if ( $capabilities{MANGLE_ENABLED} ) {
	    qt1( "$iptables -t mangle -F $sillyname" );
	    qt1( "$iptables -t mangle -X $sillyname" );
	}

	if ( $capabilities{NAT_ENABLED} ) {
	    qt1( "$iptables -t nat -F $sillyname" );
	    qt1( "$iptables -t nat -X $sillyname" );
	}

	if ( $capabilities{RAW_TABLE} ) {
	    qt1( "$iptables -t raw -F $sillyname" );
	    qt1( "$iptables -t raw -X $sillyname" );
	}

	$sillyname = $sillyname1 = undef;
    }
}

#
# Require the passed capability
#
sub require_capability( $$$ ) {
    my ( $capability, $description, $singular ) = @_;

    fatal_error "$description require${singular} $capdesc{$capability} in your kernel and iptables" unless have_capability $capability;
}

#
# Return Kernel Version
#
sub kernel_version() {
    $capabilities{KERNELVERSION}
}

#
# Set default config path
#
sub ensure_config_path() {

    my $f = "$globals{SHAREDIR}/configpath";

    $globals{CONFDIR} = "$shorewallrc{SHAREDIR}/$product/configfiles/" if $> != 0;

    unless ( $config{CONFIG_PATH} ) {
	fatal_error "$f does not exist" unless -f $f;

	open_file $f;

	add_param( CONFDIR => $globals{CONFDIR} );

	while ( read_a_line( NORMAL_READ ) ) {
	    if ( $currentline =~ /^\s*([a-zA-Z]\w*)=(.*?)\s*$/ ) {
		my ($var, $val) = ($1, $2);
		$config{$var} = ( $val =~ /\"([^\"]*)\"$/ ? $1 : $val ) if exists $config{$var};
	    } else {
		fatal_error "Unrecognized entry";
	    }
	}

	fatal_error "CONFIG_PATH not found in $f" unless $config{CONFIG_PATH};
    }

    @config_path = split /:/, $config{CONFIG_PATH};

    for ( @config_path ) {
	$_ .= '/' unless m|/$|;
    }

    if ( $shorewall_dir ) {
	$shorewall_dir = getcwd if $shorewall_dir =~ m|^(\./*)+$|;
	$shorewall_dir .= '/' unless $shorewall_dir =~ m|/$|;
	unshift @config_path, $shorewall_dir if $shorewall_dir ne $config_path[0];
	$config{CONFIG_PATH} = join ':', @config_path;
    }
}

#
# Set $shorewall_dir
#
sub set_shorewall_dir( $ ) {
    $shorewall_dir = shift;
    ensure_config_path;
}

#
# Update the configuration file
#

sub conditional_quote( $ ) {
    my $val = shift;

    unless ( $val =~ /^[-\w\/\.]*$/ ) {
	#
	# Funny characters (including whitespace) -- use double quotes unless the thing is single-quoted
	#
	$val = qq("$val") unless $val =~ /^'.+'$/;
    }

    $val;
}

#
# Update the shorewall[6].conf file. Save the current file with a .bak suffix.
#
sub update_config_file( $ ) {
    my $annotate = shift;

    sub is_set( $ ) {
	my $value = $_[0];
	defined( $value ) && lc( $value ) eq 'yes';
    }

    my $wide = is_set $config{WIDE_TC_MARKS};
    my $high = is_set $config{HIGH_ROUTE_MARKS};

    #
    # Establish default values for the mark layout items
    #
    $config{TC_BITS}         = ( $wide ? 14 : 8 )             unless defined $config{TC_BITS};
    $config{MASK_BITS}       = ( $wide ? 16 : 8 )             unless defined $config{MASK_BITS};
    $config{PROVIDER_OFFSET} = ( $high ? $wide ? 16 : 8 : 0 ) unless defined $config{PROVIDER_OFFSET};
    $config{PROVIDER_BITS}   = 8                              unless defined $config{PROVIDER_BITS};

    my $fn;

    unless ( -d "$globals{SHAREDIR}/configfiles/" ) {
	#
	# Debian or derivative
	#
	$fn = $annotate ? "$shorewallrc{SHAREDIR}/doc/${product}/default-config/${product}.conf.annotated" : "$shorewallrc{SHAREDIR}/doc/${product}/default-config/${product}.conf";
    } else {
	#
	# The rest of the World
	#
	$fn = $annotate ? "$globals{SHAREDIR}/configfiles/${product}.conf.annotated" : "$globals{SHAREDIR}/configfiles/${product}.conf";
    }
   if ( -f $fn ) {
	my ( $template, $output );

	open $template, '<' , $fn or fatal_error "Unable to open $fn: $!";

	unless ( open $output, '>', "$configfile.updated" ) {
	    close $template;
	    fatal_error "Unable to open $configfile.updated for output: $!";
	}

	while ( <$template> ) {
	    if ( /^(\w+)="?(.*?)"?$/ ) {
		#
		# Option assignment -- get value and default
		#
		my ($var, $val, $default ) = ( $1, $config{$1}, $2 );

		unless ( supplied $val ) {
		    #
		    # Value is either undefined (option not in config file) or is ''
		    #
		    if ( defined $val ) {
			#
			# OPTION='' - use default if 'Yes' or 'No'
			#
			$config{$var} = $val = $default if $default eq 'Yes' || $default eq 'No';
		    } else {
			#
			# Wasn't mentioned in old file - use default value
			#
			$config{$var} = $val = $default;

		    }

		}

		$val = conditional_quote $val;

		$_ = "$var=$val\n";
	    }

	    print $output "$_";
	}

	close $template;

	my $heading_printed;

	for ( grep ! $converted{$_} , keys %deprecated ) {
	    if ( supplied( my $val = $config{$_} ) ) {
		if ( lc $val ne $deprecated{$_} ) {
		    unless ( $heading_printed ) {
			print $output <<'EOF';

#################################################################################
#                            D E P R E C A T E D
#                               O P T I O N S
#################################################################################

EOF
			$heading_printed = 1;
		    }

		    $val = conditional_quote $val;

		    print $output "$_=$val\n\n";

		    warning_message "Deprecated option $_ is being set in your $product.conf file";
		}
	    }
	}

	close $output;

	fatal_error "Can't rename $configfile to $configfile.bak: $!"     unless rename $configfile, "$configfile.bak";
	fatal_error "Can't rename $configfile.updated to $configfile: $!" unless rename "$configfile.updated", $configfile;

	if ( system( "diff -q $configfile $configfile.bak > /dev/null" ) ) {
	    progress_message3 "Configuration file $configfile updated - old file renamed $configfile.bak";
	} else {
	    if ( unlink "$configfile.bak" ) {
		progress_message3 "No update required to configuration file $configfile; $configfile.bak not saved";
	    } else {
		warning_message "Unable to unlink $configfile.bak";
		progress_message3 "No update required to configuration file $configfile";
	    }

	    exit 0 unless -f find_file 'blacklist';
	}
    } else {
	fatal_error "$fn does not exist";
    }
}

#
# Small functions called by get_configuration. We separate them so profiling is more useful
#
sub process_shorewall_conf( $$ ) {
    my ( $update, $annotate ) = @_;
    my $file   = find_file "$product.conf";

    if ( -f $file ) {
	$globals{CONFIGDIR} =  $configfile = $file;
	$globals{CONFIGDIR} =~ s/$product.conf//;

	if ( -r _ ) {
	    open_file $file;

	    first_entry "Processing $file...";
	    #
	    # Don't expand shell variables or allow embedded scripting
	    #
	    while ( read_a_line( STRIP_COMMENTS | SUPPRESS_WHITESPACE  | CHECK_GUNK ) ) {
		if ( $currentline =~ /^\s*([a-zA-Z]\w*)=(.*?)\s*$/ ) {
		    my ($var, $val) = ($1, $2);

		    unless ( exists $config{$var} ) {
			if ( exists $renamed{$var} ) {
			    $var = $renamed{$var};
			} else {
			    warning_message "Unknown configuration option ($var) ignored";
			    next ;
			}
		    }

		    $config{$var} = ( $val =~ /\"([^\"]*)\"$/ ? $1 : $val );

		    warning_message "Option $var=$val is deprecated"
			if $deprecated{$var} && supplied $val && lc $config{$var} ne $deprecated{$var};
		} else {
		    fatal_error "Unrecognized $product.conf entry";
		}
	    }
	} else {
	    fatal_error "Cannot read $file (Hint: Are you root?)";
	}
    } else {
	fatal_error "$file does not exist!";
    }

    #
    # Now update the config file if asked
    #
    update_config_file( $annotate) if $update;
    #
    # Config file update requires that the option values not have
    # Shell variables expanded. We do that now.
    #
    for ( values  %config ) {
	if ( supplied $_ ) {
	    expand_variables( $_ ) unless /^'(.+)'$/;
	}
    }
}

#
# Process the records in the capabilities file
#
sub read_capabilities() {
    while ( read_a_line( STRIP_COMMENTS | SUPPRESS_WHITESPACE  | CHECK_GUNK ) ) {
	if ( $currentline =~ /^([a-zA-Z]\w*)=(.*)$/ ) {
	    my ($var, $val) = ($1, $2);
	    unless ( exists $capabilities{$var} ) {
		warning_message "Unknown capability ($var) ignored";
		next;
	    }

	    $val = $val =~ /^\"([^\"]*)\"$/ ? $1 : $val;
	    
	    $capabilities{$var} = $var =~ /VERSION$/ ? $val :  $val ne '';
	} else {
	    fatal_error "Unrecognized capabilities entry";
	}
    }

    if ( $capabilities{CAPVERSION} ) {
	warning_message "Your capabilities file is out of date -- it does not contain all of the capabilities defined by $Product version $globals{VERSION}"
	    unless $capabilities{CAPVERSION} >= $globals{CAPVERSION};
    } else {
	warning_message "Your capabilities file may not contain all of the capabilities defined by $Product version $globals{VERSION}";
    }

    unless ( $capabilities{KERNELVERSION} ) {
	warning_message "Your capabilities file does not contain a Kernel Version -- using 2.6.30";
	$capabilities{KERNELVERSION} = 20630;
    }

    for ( keys %capabilities ) {
	$capabilities{$_} = '' unless defined $capabilities{$_};
    }

    $globals{KLUDGEFREE} = $capabilities{KLUDGEFREE};

}

#
# Get the system's capabilities, either by probing or by reading a capabilities file
#
sub get_capabilities( $ ) {
    my $export = $_[0];

    if ( ! $export && $> == 0 ) { # $> == $EUID
	$iptables = $config{$toolNAME};

	if ( $iptables ) {
	    fatal_error "$toolNAME=$iptables does not exist or is not executable" unless -x $iptables;
	} else {
	    fatal_error "Can't find $toolname executable" unless $iptables = which $toolname;
	}

	my $iptables_restore=$iptables . '-restore';

	fatal_error "$iptables_restore does not exist or is not executable" unless -x $iptables_restore;

	$tc = $config{TC} || which 'tc';

	if ( $tc ) {
	    fatal_error "TC=$tc does not exist or is not executable" unless -x $tc;
	}

	$ip = $config{IP} || which 'ip';

	if ( $ip ) {
	    fatal_error "IP=$ip does not exist or is not executable" unless -x $ip;
	}

	load_kernel_modules;

	if ( open_file 'capabilities' ) {
	    read_capabilities;
	} else {
	    determine_capabilities;
	}
    } else {
	unless ( open_file 'capabilities' ) {
	    fatal_error "The -e compiler option requires a capabilities file" if $export;
	    fatal_error "Compiling under non-root uid requires a capabilities file";
	}

	read_capabilities;
    }
}

#
# Deal with options that we no longer support
#
sub unsupported_yes_no( $ ) {
    my $option = shift;

    default_yes_no $option, '';

    fatal_error "$option=Yes is not supported by Shorewall $globals{VERSION}" if $config{$option};
}

sub unsupported_yes_no_warning( $ ) {
    my $option = shift;

    default_yes_no $option, '';

    warning_message "$option=Yes is not supported by Shorewall $globals{VERSION}" if $config{$option};
}

#
# Process the params file
#
sub get_params() {
    my $fn = find_file 'params';

    my %reserved = ( COMMAND => 1, CONFDIR => 1, SHAREDIR => 1, VARDIR => 1 );

    if ( -f $fn ) {
	progress_message2 "Processing $fn ...";

	my $command = "$FindBin::Bin/getparams $fn " . join( ':', @config_path ) . " $family";
	#
	# getparams silently sources the params file under 'set -a', then executes 'export -p'
	#
	my @params = `$command`;

	fatal_error "Processing of $fn failed" if $?;

	if ( $debug ) {
	    print "Params:\n";
	    print $_ for @params;
	}

	my ( $variable , $bug );

	if ( $params[0] =~ /^declare/ ) {
	    #
	    # getparams was interpreted by bash
	    #
	    # - Variable names are preceded by 'declare -x '
	    # - Param values are delimited by double quotes
	    # - Embedded double quotes are escaped with '\\'
	    # - Valueless variables are supported (e.g., 'declare -x foo')
	    #
	    $shell = BASH;

	    for ( @params ) {
		if ( /^declare -x (.*?)="(.*[^\\])"$/ ) {
		    $params{$1} = $2 unless $1 eq '_';
		} elsif ( /^declare -x (.*?)="(.*)$/ ) {
		    $params{$variable=$1} = $2 eq '"' ? '' : "${2}\n";
		} elsif ( /^declare -x (.*)\s+$/ || /^declare -x (.*)=""$/ ) {
		    $params{$1} = '';
		} else {
		    chomp;
		    if ($variable) {
			s/"$//;
			$params{$variable} .= $_;
		    } else {
			warning_message "Param line ($_) ignored" unless $bug++;
		    }
		}
	    }
	} elsif ( $params[0] =~ /^export .*?="/ || $params[0] =~ /^export [^\s=]+\s*$/ ) {
	    #
	    # getparams interpreted by older (e.g., RHEL 5) Bash
	    #
	    # - Variable names preceded by 'export '
	    # - Variable values are delimited by double quotes
	    # - Embedded double quotes are escaped with '\'
	    # - Valueless variables ( e.g., 'export foo') are supported
	    #
	    $shell = OLDBASH;

	    for ( @params ) {
		if ( /^export (.*?)="(.*[^\\])"$/ ) {
		    $params{$1} = $2 unless $1 eq '_';
		} elsif ( /^export (.*?)="(.*)$/ ) {
		    $params{$variable=$1} = $2 eq '"' ? '' : "${2}\n";
		} elsif ( /^export ([^\s=]+)\s*$/ || /^export (.*)=""$/ ) {
		    $params{$1} = '';
		} else {
		    chomp;
		    if ($variable) {
			s/"$//;
			$params{$variable} .= $_;
		    } else {
			warning_message "Param line ($_) ignored" unless $bug++;
		    }
		}
	    }
	} else {
	    #
	    # getparams was interpreted by dash/ash/busybox
	    #
	    # - Variable name preceded by 'export '
	    # - Param values are delimited by single quotes.
	    # - Embedded single quotes are transformed to the five characters '"'"'
	    #
	    $shell = ASH;

	    for ( @params ) {
		if ( /^export (.*?)='(.*'"'"')$/ ) {
		    $params{$variable=$1}="${2}\n";
		} elsif ( /^export (.*?)='(.*)'$/ ) {
		    $params{$1} = $2 unless $1 eq '_';
		} elsif ( /^export (.*?)='(.*)$/ ) {
		    $params{$variable=$1}="${2}\n";
		} else {
		    chomp;
		    if ($variable) {
			s/'$//;
			$params{$variable} .= $_;
		    } else {
			warning_message "Param line ($_) ignored" unless $bug++;
		    }
		}
	    }
	}

	for ( keys %params ) {
	    unless ( $_ eq 'SHOREWALL_INIT_SCRIPT' ) {
		fatal_error "The variable name $_ is reserved and may not be set in the params file"
		    if /^SW_/ || /^SHOREWALL_/ || ( exists $config{$_} && ! exists $ENV{$_} ) || exists $reserved{$_};
	    }
	}

	if ( $debug ) {
	    print "PARAMS:\n";
	    my $value;
	    while ( ($variable, $value ) = each %params ) {
		print "   $variable='$value'\n" unless $compiler_params{$variable};
	    }
	}
    }
}

#
# Add an entry to %params and to %compiler_params
#
sub add_param( $$ ) {
    my ( $param, $value ) = @_;

    $params{$param} = $value;
    $compiler_params{$param} = 1;
}

#
# emit param=value for each param set in the params file
#
sub export_params() {
    my $count = 0;

    for my $param ( sort keys %params ) {
	#
	# Don't export params added by the compiler
	#
	next if exists $compiler_params{$param};

	my $value = $params{$param};
	#
	# Values in %params are generated from the output of 'export -p'.
	# The different shells have different conventions for delimiting
	# the value and for escaping embedded instances of the delimiter.
	# The following logic removes the escape characters.
	#
	if ( $shell == BASH ) {
	    $value =~ s/\\"/"/g;
	} elsif ( $shell == OLDBASH ) {
	    $value =~ s/\\'/'/g;
	} else {
	    $value =~ s/'"'"'/'/g;
	}
	#
	# Don't export pairs from %ENV
	#
	next if defined $ENV{$param} && $value eq $ENV{$param};

	emit "#\n# From the params file\n#" unless $count++;
	#
	# We will use double quotes and escape embedded quotes with \.
	#
	if ( $value =~ /[\s()['"]/ ) {
	    $value =~ s/"/\\"/g;
	    emit "$param='$value'";
	} else {
	    emit "$param=$value";
	}
    }
}

#
# - Process the params file
# - Read the shorewall.conf file
# - Read the capabilities file, if any
# - establish global hashes %params, %config , %globals and %capabilities
#
sub get_configuration( $$$ ) {

    my ( $export, $update, $annotate ) = @_;

    $globals{EXPORT} = $export;

    our ( $once, @originalinc );

    @originalinc = @INC unless $once++;

    ensure_config_path;

    get_params;

    process_shorewall_conf( $update, $annotate );

    ensure_config_path;

    @INC = @originalinc;

    unshift @INC, @config_path;

    default 'PATH' , '/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin';
    #
    # get_capabilities requires that the true settings of these options be established
    #
    default 'MODULE_PREFIX', 'ko ko.gz o o.gz gz';
    default_yes_no 'LOAD_HELPERS_ONLY'          , '';

    get_capabilities( $export );

    report_capabilities unless $config{LOAD_HELPERS_ONLY};

    $helpers_aliases{ftp}  = 'ftp-0',  $capabilities{FTP_HELPER}  = 1 if $capabilities{FTP0_HELPER};
    $helpers_aliases{irc}  = 'irc-0',  $capabilities{IRC_HELPER}  = 1 if $capabilities{IRC0_HELPER};
    $helpers_aliases{sane} = 'sane-0', $capabilities{SANE_HELPER} = 1 if $capabilities{SANE0_HELPER};
    $helpers_aliases{sip}  = 'sip-0',  $capabilities{SIP_HELPER}  = 1 if $capabilities{SIP0_HELPER};
    $helpers_aliases{tftp} = 'tftp-0', $capabilities{TFTP_HELPER} = 1 if $capabilities{TFTP0_HELPER};

    $globals{STATEMATCH} = '-m conntrack --ctstate' if have_capability 'CONNTRACK_MATCH';

    #
    # The following is not documented as it is not likely useful to the user base in general 
    # Going forward, it allows me to create a configuration that will work on multiple
    # Shorewall versions.        TME
    #
    $config{VERSION} = sprintf "%d%02d%02d", $1, $2, $3 if $globals{VERSION} =~ /^(\d+)\.(\d+)\.(\d+)/;

    if ( my $rate = $config{LOGLIMIT} ) {
	my $limit;

	if ( $rate =~ /^[sd]:/ ) {
	    require_capability 'HASHLIMIT_MATCH', 'Per-ip log rate limiting' , 's';

	    $limit = "-m hashlimit ";

	    my $match = have_capability( 'OLD_HL_MATCH' ) ? 'hashlimit' : 'hashlimit-upto';
	    my $units;

	    if ( $rate =~ /^[sd]:((\d+)(\/(sec|min|hour|day))):(\d+)$/ ) {
		fatal_error "Invalid rate ($1)" unless $2;
		fatal_error "Invalid burst value ($5)" unless $5;

		$limit .= "--$match $1 --hashlimit-burst $5 --hashlimit-name lograte --hashlimit-mode ";
		$units = $4;
	    } elsif ( $rate =~ /^[sd]:((\d+)(\/(sec|min|hour|day))?)$/ ) {
		fatal_error "Invalid rate ($1)" unless $2;
		$limit .= "--$match $1 --hashlimit-name lograte --hashlimit-mode ";
		$units = $4;
	    } else {
		fatal_error "Invalid rate ($rate)";
	    }

	    $limit .= $rate =~ /^s:/ ? 'srcip ' : 'dstip ';

	    if ( $units && $units ne 'sec' ) {
		my $expire = 60000; # 1 minute in milliseconds

		if ( $units ne 'min' ) {
		    $expire *= 60; #At least an hour
		    $expire *= 24 if $units eq 'day';
		}

		$limit .= "--hashlimit-htable-expire $expire ";
	    }
	} elsif ( $rate =~ /^((\d+)(\/(sec|min|hour|day))):(\d+)$/ ) {
	    fatal_error "Invalid rate ($1)" unless $2;
	    fatal_error "Invalid burst value ($5)" unless $5;
	    $limit = "-m limit --limit $1 --limit-burst $5 ";
	} elsif ( $rate =~ /^(\d+)(\/(sec|min|hour|day))?$/ )  {
	    fatal_error "Invalid rate (${1}${2})" unless $1;
	    $limit = "-m limit --limit $rate ";
	} else {
	    fatal_error "Invalid rate ($rate)";
	}

	$globals{LOGLIMIT} = $limit;

	warning_message "LOGRATE Ignored when LOGLIMIT is specified"  if $config{LOGRATE};
	warning_message "LOGBURST Ignored when LOGLIMIT is specified" if $config{LOGBURST};

    } elsif ( $config{LOGRATE} || $config{LOGBURST} ) {
	if ( supplied $config{LOGRATE} ) {
	    fatal_error"Invalid LOGRATE ($config{LOGRATE})" unless $config{LOGRATE}  =~ /^\d+\/(second|minute)$/;
	}

	if ( supplied $config{LOGBURST} ) {
	    fatal_error"Invalid LOGBURST ($config{LOGBURST})" unless $config{LOGBURST} =~ /^\d+$/;
	}

	$globals{LOGLIMIT}  = '-m limit ';
	$globals{LOGLIMIT} .= "--limit $config{LOGRATE} "        if supplied $config{LOGRATE};
	$globals{LOGLIMIT} .= "--limit-burst $config{LOGBURST} " if supplied $config{LOGBURST};
    } else {
	$globals{LOGLIMIT} = '';
    }

    check_trivalue ( 'IP_FORWARDING', 'on' );

    my $val;

    if ( have_capability( 'KERNELVERSION' ) < 20631 ) {
	check_trivalue ( 'ROUTE_FILTER',  '' );
    } else {
	$val = $config{ROUTE_FILTER};
	if ( supplied $val ) {
	    if ( $val =~ /\d+/ ) {
		fatal_error "Invalid value ($val) for ROUTE_FILTER" unless $val < 3;
	    } else {
		check_trivalue( 'ROUTE_FILTER', '' );
	    }
	} else {
	    check_trivalue( 'ROUTE_FILTER', '' );
	}
    }

    if ( $family == F_IPV6 ) {
	$val = $config{ROUTE_FILTER};
	fatal_error "ROUTE_FILTER=$val is not supported in IPv6" if $val && $val ne 'off';
    }

    if ( $family == F_IPV4 ) {
	check_trivalue ( 'LOG_MARTIANS',  'on' );
    } else {
	check_trivalue ( 'LOG_MARTIANS',  'off' );
	fatal_error "LOG_MARTIANS=On is not supported in IPv6" if $config{LOG_MARTIANS} eq 'on';
    }

    default 'STARTUP_LOG'   , '';

    if ( $config{STARTUP_LOG} ne '' ) {
	if ( supplied $config{LOG_VERBOSITY} ) {
	    if ( $config{LOG_VERBOSITY} eq '' ) {
		$config{LOG_VERBOSITY} = 2;
	    } else {
		my $val = numeric_value( $config{LOG_VERBOSITY} );
		fatal_error "Invalid LOG_VERBOSITY ($config{LOG_VERBOSITY} )" unless defined( $val ) && ( $val >= -1 ) && ( $val <= 2 );
		$config{STARTUP_LOG} = '' if $config{LOG_VERBOSITY} < 0;
		$config{LOG_VERBOSITY} = $val;
	    }
	} else {
	    $config{LOG_VERBOSITY} = 2;
	}
    } else {
	$config{LOG_VERBOSITY} = -1;
    }

    default_yes_no 'ADD_IP_ALIASES'             , 'Yes';
    default_yes_no 'ADD_SNAT_ALIASES'           , '';
    default_yes_no 'DETECT_DNAT_IPADDRS'        , '';
    default_yes_no 'DETECT_DNAT_IPADDRS'        , '';
    default_yes_no 'CLEAR_TC'                   , $family == F_IPV4 ? 'Yes' : '';

    if ( supplied $config{CLAMPMSS} ) {
	default_yes_no 'CLAMPMSS'                   , '' unless $config{CLAMPMSS} =~ /^\d+$/;
    } else {
	$config{CLAMPMSS} = '';
    }

    unless ( $config{ADD_IP_ALIASES} || $config{ADD_SNAT_ALIASES} ) {
	$config{RETAIN_ALIASES} = '';
    } else {
	default_yes_no_ipv4 'RETAIN_ALIASES'             , '';
    }

    default_yes_no 'ADMINISABSENTMINDED'        , '';
    default_yes_no 'BLACKLISTNEWONLY'           , '';
    default_yes_no 'DISABLE_IPV6'               , '';

    unsupported_yes_no_warning 'DYNAMIC_ZONES';
    unsupported_yes_no         'BRIDGING';
    unsupported_yes_no_warning 'RFC1918_STRICT';

    default_yes_no 'SAVE_IPSETS'                , '';
    default_yes_no 'STARTUP_ENABLED'            , 'Yes';
    default_yes_no 'DELAYBLACKLISTLOAD'         , '';
    default_yes_no 'MAPOLDACTIONS'              , 'Yes';

    warning_message 'DELAYBLACKLISTLOAD=Yes is not supported by Shorewall ' . $globals{VERSION} if $config{DELAYBLACKLISTLOAD};

    default_yes_no 'LOGTAGONLY'                 , ''; $globals{LOGTAGONLY} = $config{LOGTAGONLY};

    default_yes_no 'FASTACCEPT'                 , '';

    fatal_error "BLACKLISTNEWONLY=No may not be specified with FASTACCEPT=Yes" if $config{FASTACCEPT} && ! $config{BLACKLISTNEWONLY};

    default_yes_no 'IMPLICIT_CONTINUE'          , '';
    default_yes_no 'HIGH_ROUTE_MARKS'           , '';
    default_yes_no 'TC_EXPERT'                  , '';
    default_yes_no 'USE_ACTIONS'                , 'Yes';

    warning_message 'USE_ACTIONS=No is not supported by Shorewall ' . $globals{VERSION} unless $config{USE_ACTIONS};

    default_yes_no 'EXPORTPARAMS'               , '';
    default_yes_no 'EXPAND_POLICIES'            , '';
    default_yes_no 'KEEP_RT_TABLES'             , '';
    default_yes_no 'DELETE_THEN_ADD'            , 'Yes';
    default_yes_no 'AUTO_COMMENT'               , 'Yes';
    default_yes_no 'MULTICAST'                  , '';
    default_yes_no 'MARK_IN_FORWARD_CHAIN'      , '';
    default_yes_no 'MANGLE_ENABLED'             , have_capability 'MANGLE_ENABLED' ? 'Yes' : '';
    default_yes_no 'NULL_ROUTE_RFC1918'         , '';
    default_yes_no 'USE_DEFAULT_RT'             , '';
    default_yes_no 'RESTORE_DEFAULT_ROUTE'      , 'Yes';
    default_yes_no 'AUTOMAKE'                   , '';
    default_yes_no 'WIDE_TC_MARKS'              , '';
    default_yes_no 'TRACK_PROVIDERS'            , '';

    default_yes_no 'ACCOUNTING'                 , 'Yes';
    default_yes_no 'OPTIMIZE_ACCOUNTING'        , '';

    if ( supplied $config{ACCOUNTING_TABLE} ) {
	my $value = $config{ACCOUNTING_TABLE};
	fatal_error "Invalid ACCOUNTING_TABLE setting ($value)" unless $value eq 'filter' || $value eq 'mangle';
    } else {
	$config{ACCOUNTING_TABLE} = 'filter';
    }

    default_yes_no 'DYNAMIC_BLACKLIST'          , 'Yes';
    default_yes_no 'REQUIRE_INTERFACE'          , '';
    default_yes_no 'FORWARD_CLEAR_MARK'         , have_capability 'MARK' ? 'Yes' : '';
    default_yes_no 'COMPLETE'                   , '';
    default_yes_no 'EXPORTMODULES'              , '';
    default_yes_no 'LEGACY_FASTSTART'           , 'Yes';
    default_yes_no 'USE_PHYSICAL_NAMES'         , '';
    default_yes_no 'IPSET_WARNINGS'             , 'Yes';
    default_yes_no 'AUTOHELPERS'                , 'Yes';
    default_yes_no 'RESTORE_ROUTEMARKS'         , 'Yes';

    $config{IPSET} = '' if supplied $config{IPSET} && $config{IPSET} eq 'ipset'; 

    if ( supplied $config{HELPERS} ) {
	my %helpers_temp = %helpers_enabled;

	$helpers_temp{$_} = 0 for keys %helpers_temp;

	for ( split_list $config{HELPERS} , 'helper' ) {
	    my $name = $_;
	    if ( exists $helpers_enabled{$name} ) {
		s/-/_/;
		require_capability( uc( $_ ) . '_HELPER' , "The $name helper", 's' );
		$helpers_temp{$name} = 1;
	    } else {
		fatal_error "Unknown Helper ($_)";
	    }
	}
	
	%helpers_enabled = %helpers_temp;

	while ( my ( $helper, $enabled ) = each %helpers_enabled ) {
	    $capabilities{uc($helper) . '_HELPER'} = 0 unless $enabled; 
	}
    }

    require_capability 'MARK' , 'FORWARD_CLEAR_MARK=Yes', 's', if $config{FORWARD_CLEAR_MARK};

    numeric_option 'TC_BITS',          $config{WIDE_TC_MARKS} ? 14 : 8 , 0;
    numeric_option 'MASK_BITS',        $config{WIDE_TC_MARKS} ? 16 : 8,  $config{TC_BITS};
    numeric_option 'PROVIDER_BITS' ,   8, 0;
    numeric_option 'PROVIDER_OFFSET' , $config{HIGH_ROUTE_MARKS} ? $config{WIDE_TC_MARKS} ? 16 : 8 : 0, 0;
    numeric_option 'ZONE_BITS'       , 0, 0;

    require_capability 'MARK_ANYWHERE', 'A non-zero ZONE_BITS setting', 's' if $config{ZONE_BITS};

    if ( $config{PROVIDER_OFFSET} ) {
	$config{PROVIDER_OFFSET}  = $config{MASK_BITS} if $config{PROVIDER_OFFSET} < $config{MASK_BITS};
	$globals{ZONE_OFFSET}     = $config{PROVIDER_OFFSET} + $config{PROVIDER_BITS};
    } elsif ( $config{MASK_BITS} >= $config{PROVIDER_BITS} ) {
	$globals{ZONE_OFFSET}     = $config{MASK_BITS};
    } else {
	$globals{ZONE_OFFSET}     = $config{PROVIDER_BITS};
    }

    fatal_error 'Invalid Packet Mark layout' if $config{ZONE_BITS} + $globals{ZONE_OFFSET} > 30;

    $globals{EXCLUSION_MASK} = 1 << ( $globals{ZONE_OFFSET} + $config{ZONE_BITS} );
    $globals{TPROXY_MARK}    = $globals{EXCLUSION_MASK} << 1;
    $globals{PROVIDER_MIN}   = 1 << $config{PROVIDER_OFFSET};

    $globals{TC_MAX}         = make_mask( $config{TC_BITS} );
    $globals{TC_MASK}        = make_mask( $config{MASK_BITS} );
    $globals{PROVIDER_MASK}  = make_mask( $config{PROVIDER_BITS} ) << $config{PROVIDER_OFFSET};

    if ( $config{ZONE_BITS} ) {
	$globals{ZONE_MASK} = make_mask( $config{ZONE_BITS} ) << $globals{ZONE_OFFSET};
    } else {
	$globals{ZONE_MASK} = 0;
    }

    if ( ( my $userbits = $config{PROVIDER_OFFSET} - $config{TC_BITS} ) > 0 ) {
	$globals{USER_MASK} = make_mask( $userbits ) << $config{TC_BITS};
	$globals{USER_BITS} = $userbits;
    } else {
	$globals{USER_MASK} = $globals{USER_BITS} = 0;
    }

    if ( supplied ( $val = $config{ZONE2ZONE} ) ) {
	fatal_error "Invalid ZONE2ZONE value ( $val )" unless $val =~ /^[2-]$/;
    } else {
	$config{ZONE2ZONE} = '2';
    }

    default 'BLACKLIST_DISPOSITION'    , 'DROP';

    unless ( ( $val = $config{BLACKLIST_DISPOSITION} ) =~ /^(?:A_)?DROP$/ || $config{BLACKLIST_DISPOSITION} =~ /^(?:A_)?REJECT/ ) {
	fatal_error q(BLACKLIST_DISPOSITION must be 'DROP', 'A_DROP', 'REJECT' or 'A_REJECT');
    }

    require_capability 'AUDIT_TARGET', "BLACKLIST_DISPOSITION=$val", 's' if $val =~ /^A_/;

    default 'SMURF_DISPOSITION'    , 'DROP';

    unless ( ( $val = $config{SMURF_DISPOSITION} ) =~ /^(?:A_)?DROP$/ ) {
	fatal_error q(SMURF_DISPOSITION must be 'DROP' or 'A_DROP');
    }

    require_capability 'AUDIT_TARGET', "SMURF_DISPOSITION=$val", 's' if $val =~ /^A_/;

    default_log_level 'BLACKLIST_LOGLEVEL',  '';
    default_log_level 'MACLIST_LOG_LEVEL',   '';
    default_log_level 'TCP_FLAGS_LOG_LEVEL', '';
    default_log_level 'RFC1918_LOG_LEVEL',   '';
    default_log_level 'RELATED_LOG_LEVEL',   '';

    warning_message "RFC1918_LOG_LEVEL=$config{RFC1918_LOG_LEVEL} ignored. The 'norfc1918' interface/host option is no longer supported" if $config{RFC1918_LOG_LEVEL};

    default_log_level 'SMURF_LOG_LEVEL',     '';
    default_log_level 'LOGALLNEW',           '';

    default_log_level 'SFILTER_LOG_LEVEL', 'info';

    if ( $val = $config{SFILTER_DISPOSITION} ) {
	fatal_error "Invalid SFILTER_DISPOSITION setting ($val)" unless $val =~ /^(A_)?(DROP|REJECT)$/;
	require_capability 'AUDIT_TARGET' , "SFILTER_DISPOSITION=$val", 's' if $1;
    } else {
	$config{SFILTER_DISPOSITION} = 'DROP';
    }

    default_log_level 'RPFILTER_LOG_LEVEL', 'info';

    if ( $val = $config{RPFILTER_DISPOSITION} ) {
	fatal_error "Invalid RPFILTER_DISPOSITION setting ($val)" unless $val =~ /^(A_)?(DROP|REJECT)$/;
	require_capability 'AUDIT_TARGET' , "RPFILTER_DISPOSITION=$val", 's' if $1;
    } else {
	$config{RPFILTER_DISPOSITION} = 'DROP';
    }

    if ( $val = $config{MACLIST_DISPOSITION} ) {
	if ( $val =~ /^(?:A_)?DROP$/ ) {
	    $globals{MACLIST_TARGET} = $val;
	} elsif ( $val eq 'REJECT' ) {
	    $globals{MACLIST_TARGET} = 'reject';
	} elsif ( $val eq 'A_REJECT' ) {
	    $globals{MACLIST_TARGET} = $val;
	} elsif ( $val eq 'ACCEPT' ) {
	    $globals{MACLIST_TARGET} = 'RETURN';
	} else {
	    fatal_error "Invalid value ($config{MACLIST_DISPOSITION}) for MACLIST_DISPOSITION"
	}

	require_capability 'AUDIT_TARGET' , "MACLIST_DISPOSITION=$val", 's' if $val =~ /^A_/;
    } else {
	$config{MACLIST_DISPOSITION}  = 'REJECT';
	$globals{MACLIST_TARGET}      = 'reject';
    }

    if ( $val = $config{RELATED_DISPOSITION} ) {
	if ( $val =~ /^(?:A_)?(?:DROP|ACCEPT)$/ ) {
	    $globals{RELATED_TARGET} = $val;
	} elsif ( $val eq 'REJECT' ) {
	    $globals{RELATED_TARGET} = 'reject';
	} elsif ( $val eq 'A_REJECT' ) {
	    $globals{RELATED_TARGET} = $val;
	} else {
	    fatal_error "Invalid value ($config{RELATED_DISPOSITION}) for RELATED_DISPOSITION"
	}

	require_capability 'AUDIT_TARGET' , "MACLIST_DISPOSITION=$val", 's' if $val =~ /^A_/;
    } else {
	$config{RELATED_DISPOSITION}  =
	$globals{RELATED_TARGET}      = 'ACCEPT';
    }

    if ( $val = $config{MACLIST_TABLE} ) {
	if ( $val eq 'mangle' ) {
	    fatal_error 'MACLIST_DISPOSITION=$1 is not allowed with MACLIST_TABLE=mangle' if $config{MACLIST_DISPOSITION} =~ /^((?:A)?REJECT)$/;
	} else {
	    fatal_error "Invalid value ($val) for MACLIST_TABLE option" unless $val eq 'filter';
	}
    } else {
	default 'MACLIST_TABLE' , 'filter';
    }

    if ( $val = $config{TCP_FLAGS_DISPOSITION} ) {
	fatal_error "Invalid value ($config{TCP_FLAGS_DISPOSITION}) for TCP_FLAGS_DISPOSITION" unless $val =~ /^(?:(A_)?(?:REJECT|DROP))|ACCEPT$/;
	require_capability 'AUDIT_TARGET' , "TCP_FLAGS_DISPOSITION=$val", 's' if $1;
    } else {
	$val = $config{TCP_FLAGS_DISPOSITION} = 'DROP';
    }


    default 'TC_ENABLED' , $family == F_IPV4 ? 'Internal' : 'no';

    $val = "\L$config{TC_ENABLED}";

    if ( $val eq 'yes' ) {
	my $file = find_file 'tcstart';
	fatal_error "Unable to find tcstart file" unless -f $file;
	$globals{TC_SCRIPT} = $file;
    } elsif ( $val eq 'internal' ) {
	$config{TC_ENABLED} = 'Internal';
     } elsif ( $val eq 'shared' ) {
	$config{TC_ENABLED} = 'Shared';
    } elsif ( $val eq 'simple' ) {
	$config{TC_ENABLED} = 'Simple';
    } else {
	fatal_error "Invalid value ($config{TC_ENABLED}) for TC_ENABLED" unless $val eq 'no';
	$config{TC_ENABLED} = '';
    }

    if ( $config{TC_ENABLED} ) {
	fatal_error "TC_ENABLED=$config{TC_ENABLED} is not allowed with MANGLE_ENABLED=No" unless $config{MANGLE_ENABLED};
	require_capability 'MANGLE_ENABLED', "TC_ENABLED=$config{TC_ENABLED}", 's';
    }

    if ( $val = $config{TC_PRIOMAP} ) {
	my @priomap = split ' ',$val;
	fatal_error "Invalid TC_PRIOMAP ($val)" unless @priomap == 16;
	for ( @priomap ) {
	    fatal_error "Invalid TC_PRIOMAP entry ($_)" unless /^[1-3]$/;
	    $_--;
	}

	$config{TC_PRIOMAP} = join ' ', @priomap;
    } else {
	$config{TC_PRIOMAP} = '1 2 2 2 1 2 0 0 1 1 1 1 1 1 1 1';
    }

    default 'RESTOREFILE'           , 'restore';
    default 'IPSECFILE'             , 'zones';
    default 'DROP_DEFAULT'          , 'Drop';
    default 'REJECT_DEFAULT'        , 'Reject';
    default 'QUEUE_DEFAULT'         , 'none';
    default 'NFQUEUE_DEFAULT'       , 'none';
    default 'ACCEPT_DEFAULT'        , 'none';
    default 'OPTIMIZE'              , 0;

    fatal_error 'IPSECFILE=ipsec is not supported by Shorewall ' . $globals{VERSION} if $config{IPSECFILE} eq 'ipsec';
    fatal_error "Invalid IPSECFILE value ($config{IPSECFILE}"                    unless $config{IPSECFILE} eq 'zones';

    for my $default ( qw/DROP_DEFAULT REJECT_DEFAULT QUEUE_DEFAULT NFQUEUE_DEFAULT ACCEPT_DEFAULT/ ) {
	$config{$default} = 'none' if "\L$config{$default}" eq 'none';
    }

    $val = numeric_value $config{OPTIMIZE};

    fatal_error "Invalid OPTIMIZE value ($config{OPTIMIZE})" unless supplied( $val ) && $val >= 0 && ( $val & ( 4096 ^ -1 ) ) <= 31;

    require_capability 'XMULTIPORT', 'OPTIMIZE level 16', 's' if $val & 16;

    $globals{MARKING_CHAIN} = $config{MARK_IN_FORWARD_CHAIN} ? 'tcfor' : 'tcpre';

    if ( $val = $config{LOGFORMAT} ) {
	my $result;

	eval {
	    if ( $val =~ /%d/ ) {
		$globals{LOGRULENUMBERS} = 'Yes';
		$result = sprintf "$val", 'fooxx2barxx', 1, 'ACCEPT';
	    } else {
		$result = sprintf "$val", 'fooxx2barxx', 'ACCEPT';
	    }
	};

	fatal_error "Invalid LOGFORMAT ($val)" if $@;

	fatal_error "LOGFORMAT string is longer than 29 characters ($val)" if length $result > 29;

	$globals{MAXZONENAMELENGTH} = int ( 5 + ( ( 29 - (length $result ) ) / 2) );
    } else {
	$config{LOGFORMAT}='Shorewall:%s:%s:';
	$globals{MAXZONENAMELENGTH} = 5;
    }

    if ( $config{LOCKFILE} ) {
	my ( $file, $dir, $suffix );

	eval {
	    ( $file, $dir, $suffix ) = fileparse( $config{LOCKFILE} );
	};

	cleanup, die $@ if $@;

	fatal_error "LOCKFILE=$config{LOCKFILE}: Directory $dir does not exist" unless $export or -d $dir;
    } else {
	$config{LOCKFILE} = '';
    }

    require_capability( 'MULTIPORT'       , "Shorewall $globals{VERSION}" , 's' );
    require_capability( 'RECENT_MATCH'    , 'MACLIST_TTL' , 's' )           if $config{MACLIST_TTL};
    require_capability( 'XCONNMARK'       , 'HIGH_ROUTE_MARKS=Yes' , 's' )  if $config{PROVIDER_OFFSET} > 0;
    require_capability( 'MANGLE_ENABLED'  , 'Traffic Shaping' , 's'      )  if $config{TC_ENABLED};
}

#
# The values of the options in @propagateconfig are copied to the script file in OPTION=<value> format.
#
sub propagateconfig() {
    for my $option ( @propagateconfig ) {
	my $value = $config{$option};
	$value = '' unless defined $value;
	emit "$option=\"$value\"";
    }
}

#
# Add a shell script file to the output script -- Return true if the
# file exists and is not in /usr/share/shorewall/ and is non-empty.
#
sub append_file( $;$$ ) {
    my ( $file, $nomsg, $unindented ) = @_;
    my $user_exit = find_file $file;
    my $result = 0;
    my $save_indent = $indent;

    $indent = '' if $unindented;

    unless ( $user_exit =~ m(^$shorewallrc{SHAREDIR}/shorewall6?/) ) {
	if ( -f $user_exit ) {
	    if ( $nomsg ) {
		#
		# Suppress progress message
		#
		$result = copy1 $user_exit;
	    } else {
		#
		# Include progress message -- Pretend progress_message call was in the file
		#
		my $name = $globals{EXPORT} ? "$file user exit" : $user_exit;
		$result = 1;
		save_progress_message "Processing $name ...";
		copy1 $user_exit;
	    }
	}
    }

    $indent = $save_indent;

    $result;
}

#
# Run a Perl extension script
#
sub run_user_exit( $ ) {
    my $chainref = $_[0];
    my $file = find_file $chainref->{name};

    if ( -f $file ) {
	progress_message2 "Running $file...";

	my $command = qq(package Shorewall::User;\nno strict;\n# line 1 "$file"\n) . `cat $file`;

	unless (my $return = eval $command ) {
	    fatal_error "Couldn't parse $file: $@" if $@;

	    unless ( defined $return ) {
		fatal_error "Couldn't do $file: $!" if $!;
		fatal_error "Couldn't do $file";
	    }

	    fatal_error "$file returned a false value";
	}
    }
}

sub run_user_exit1( $ ) {
    my $file = find_file $_[0];

    if ( -f $file ) {
	progress_message2 "Running $file...";
	#
	# File may be empty -- in which case eval would fail
	#
	push_open $file;

	if ( read_a_line( STRIP_COMMENTS | SUPPRESS_WHITESPACE  | CHECK_GUNK ) ) {
	    close_file;
	    pop_open;

	    my $command = qq(package Shorewall::User;\n# line 1 "$file"\n) . `cat $file`;

	    unless (my $return = eval $command ) {
		fatal_error "Couldn't parse $file: $@" if $@;

		unless ( defined $return ) {
		    fatal_error "Couldn't do $file: $!" if $!;
		    fatal_error "Couldn't do $file";
		}

		fatal_error "$file returned a false value";
	    }
	} else {
	    pop_open;
	}
    }
}

sub run_user_exit2( $$ ) {
    my ($file, $chainref) = ( find_file $_[0], $_[1] );

    if ( -f $file ) {
	progress_message2 "Running $file...";
	#
	# File may be empty -- in which case eval would fail
	#
	push_open $file;

	if ( read_a_line( STRIP_COMMENTS | SUPPRESS_WHITESPACE  | CHECK_GUNK ) ) {
	    close_file;
	    pop_open;

	    unless (my $return = eval `cat $file` ) {
		fatal_error "Couldn't parse $file: $@" if $@;

		unless ( defined $return ) {
		    fatal_error "Couldn't do $file: $!" if $!;
		    fatal_error "Couldn't do $file";
		}

		fatal_error "$file returned a false value";
	    }
	}

	pop_open;

    }
}

#
# Generate the aux config file for Shorewall Lite
#
sub generate_aux_config() {
    sub conditionally_add_option( $ ) {
	my $option = $_[0];

	my $value = $config{$option};

	emit "[ -n \"\${$option:=$value}\" ]" if supplied $value;
    }

    sub conditionally_add_option1( $ ) {
	my $option = $_[0];

	my $value = $config{$option};

	emit "$option=\"$value\"" if $value;
    }

    create_temp_aux_config;

    my $date = localtime;

    emit "#\n# Shorewall auxiliary configuration file created by Shorewall version $globals{VERSION} - $date\n#";

    for my $option ( qw(VERBOSITY LOGFILE LOGFORMAT IPTABLES IP6TABLES IP TC IPSET PATH SHOREWALL_SHELL SUBSYSLOCK LOCKFILE RESTOREFILE) ) {
	conditionally_add_option $option;
    }

    conditionally_add_option1 'TC_ENABLED';

    my $fn = find_file 'scfilter';

    if ( -f $fn ) {
	emit( '',
	      'show_connections_filter() {' );
	push_indent;
	append_file( $fn,1 ) or emit 'cat -';
	pop_indent;
	emit '}';
    }

    $fn = find_file 'dumpfilter';

    if ( -f $fn ) {
	emit( '',
	      'dump_filter() {' );
	push_indent;
	append_file( $fn,1 ) or emit 'cat -';
	pop_indent;
	emit '}';
    }

    finalize_aux_config;
}

sub dump_mark_layout() {
    sub dumpout( $$$$$ ) {
	my ( $name, $bits, $min, $max, $mask ) = @_;

	if ( $bits ) {
	    if ( $min == $max ) {
		emit_unindented "$name:" . $min . ' mask ' . in_hex( $mask );
	    } else {
		emit_unindented "$name:" . join('-', $min, $max ) . ' (' . join( '-', in_hex( $min ), in_hex( $max ) ) . ') mask ' . in_hex( $mask );
	    }
	} else {
	    emit_unindented "$name: Not Enabled";
	}
    }

    dumpout( "Traffic Shaping",
	     $config{TC_BITS},
	     0,
	     $globals{TC_MAX},
	     $globals{TC_MASK} );

    dumpout( "User",
	     $globals{USER_BITS},
	     $globals{TC_MAX} + 1,
	     $globals{USER_MASK},
	     $globals{USER_MASK} );

    dumpout( "Provider",
	     $config{PROVIDER_BITS},
	     $globals{PROVIDER_MIN},
	     $globals{PROVIDER_MASK},
	     $globals{PROVIDER_MASK} );

    dumpout( "Zone",
	     $config{ZONE_BITS},
	     1 << $globals{ZONE_OFFSET},
	     $globals{ZONE_MASK},
	     $globals{ZONE_MASK} );

    dumpout( "Exclusion",
	     1,
	     $globals{EXCLUSION_MASK},
	     $globals{EXCLUSION_MASK},
	     $globals{EXCLUSION_MASK} );

    dumpout( "TProxy",
	     1,
	     $globals{TPROXY_MARK},
	     $globals{TPROXY_MARK},
	     $globals{TPROXY_MARK} );
}

END {
    cleanup;
}

1;
