#!/usr/bin/perl
#
# Create a MRTG .cfg file for a given host.  Include routers.cgi
# extensions.  Check for different SNMP options available.
# Uses BER, SNMP_Session, SNMP_util shipped with MRTG.
# Optimised for use with the routers2.cgi frontend!
#
# Usage:  cfgmaker_host [--community=xxx] [--libadd=/path] [--workdir=/path] <hostnamelist>....
# Creates files mrtg-<hostname>.cfg in the current directory.
#
# Steve Shipway, June 2003, Auckland University s.shipway@auckland.ac.nz
#
# Version: 0.1, Needs some tidying up
#          0.2, addons by Xavier
#
# Can recognise: host MIB, ucd-snmp MIB, Linux (ucd), Solaris (Sun-MIB)
# Send me the MIB files for other SNMP agents to have them supported.
#
# Public domain: do what you want with it.  No support provided.
####################################################################
use strict;
use Getopt::Long;
use BER;
use SNMP_util;
use SNMP_Session;
#######################################################################
# Globals
my($community) = 'public';
my($workdir) = '/var/db/rrdtool';
my(@hosts) = 'localhost';
my($pathadd) = '/usr/local/bin/';
my($libadd) = '';
my($h);
my($PS) = '/';
my($TIMEOUT) = 4;
my($RETRIES) = 2;
my($pingprobe) = "/usr/local/bin/mrtg-ping-probe";

$|=1;
#######################################################################
# OIDS
my(%OID) = (
	# host MIB
	users    =>'internet.2.1.25.1.5.0',
	procs    =>'internet.2.1.25.1.6.0',
	storageentry =>'internet.2.1.25.2.3.1',
	# UCD MIB
	loadavg  =>'enterprises.2021.10.1.5.1',
	loadavg15=>'enterprises.2021.10.1.5.3',
	cpuuser  =>'enterprises.2021.11.9.0',
	cpusys   =>'enterprises.2021.11.10.0',
	cpuidle  =>'enterprises.2021.11.11.0',
	totalswap=>'enterprises.2021.4.3.0',
	availswap=>'enterprises.2021.4.4.0',
	totalreal=>'enterprises.2021.4.5.0',
	availreal=>'enterprises.2021.4.6.0',
	diskentry=>'enterprises.2021.9.1',
	swapin   =>'enterprises.2021.11.3.0',
	swapout  =>'enterprises.2021.11.4.0',
	# Standard MIB
	sysdesc  =>'sysDescr',
	sysname  =>'sysName',
	ifentry  =>'ifEntry',
	ipadentifindex=>'ipAdEntIfIndex',
	# Sun MIB
	sunswapin   =>'enterprises.42.3.13.11.0',
	sunswapout  =>'enterprises.42.3.13.12.0',
	suntotalswap=>'enterprises.42.2.12.2.2.12.7.5.0',
	sunavailswap=>'enterprises.42.2.12.2.2.12.7.1.0',
	suntotalreal=>'enterprises.42.2.12.2.2.12.6.1.0',
	sunavailreal=>'enterprises.42.2.12.2.2.12.6.4.0',
	sunusers    =>'enterprises.42.2.12.2.2.12.1.2.0',
	sunloadavg  =>'enterprises.42.2.12.2.2.12.2.1.0',
	sunloadavg15=>'enterprises.42.2.12.2.2.12.2.3.0',
	# Netopia MIB
	netopiasysstat  => 'enterprises.304.1.3.1.3',
	netopiaavailmem => 'enterprises.304.1.3.1.3.5.0',
	netopiausedmem  => 'enterprises.304.1.3.1.3.6.0',
	netopiacurcpu   => 'enterprises.304.1.3.1.3.1.0',
	netopiaavgcpu   => 'enterprises.304.1.3.1.3.2.0',
	# Fortynet
	fortycpuusage	=> 'enterprises.12356.1.1.6.1.0',
	fortycpuidle	=> 'enterprises.12356.1.1.6.2.0',
	fortycpuint	=> 'enterprises.12356.1.1.6.3.0',
	fortymemusage	=> 'enterprises.12356.1.1.6.4.0',
	fortysessions	=> 'enterprises.12356.1.1.6.6.0',
);

#######################################################################
# Subroutines
sub process_host($) {
	my($cfgfile);
	my($snmp,$rv);
	my($hostname) = shift;
	my($sicon,$sname,$sdesc) = ("","","");
	my($mbr,$mbs);
	my($aroid,$asoid) = ('','');
	my($targ);
	my($factor) = 0;
	my(%ip) = ();
	my(@ret,$ifentry);
	my(%ifname,%ifspeed,%ifok);
	my($ifno);
	my($na, @ifids);

	# open the file
	$cfgfile = "mrtg-$hostname.cfg";
	open CFG, ">$cfgfile" or do {
		print "Unable to open $cfgfile: $!\n";
		return;
	};

	# start SNMP
	$SNMP_Session::suppress_warnings = 3;
	$snmp = $community.'@'.$hostname;
# ."::".$TIMEOUT;

	# get details on this server
	($sname) = snmpget($snmp,$OID{sysname});
	($sdesc) = snmpget($snmp,$OID{sysdesc});
	$sname =~ s/\n/<BR>/g;
	$sdesc =~ s/\n/<BR>/g;
	$sicon = 'server-sm.gif';
	$sicon = 'sun-sm.gif' if($sdesc =~ /solaris/i or $sdesc=~ /sun/i);
	$sicon = 'win2-sm.gif' if($sdesc =~ /windows/i);
	$sicon = 'win2-sm.gif' if($sdesc =~ /microsoft/i);
	$sicon = 'ibm-sm.gif' if($sdesc =~ /aix/i);
	$sicon = 'linux-sm.gif' if($sdesc =~ /linux/i);
	$sicon = 'bsd-sm.gif' if($sdesc =~ /bsd/i);
	$sicon = 'freebsd-sm.gif' if($sdesc =~ /freebsd/i);
	$sicon = 'mandrake-sm.gif' if($sdesc =~ /mandrake/i);
	$sicon = 'hp-sm.gif' if($sdesc =~ /hp.?ux/i);
	$sicon = 'modem-sm.gif' if($sdesc =~ /netopia/i);
	if(!$sname) {
		print CFG "# Unable to connect to $hostname\n";
		print CFG "# ".$SNMP_Session::errmsg."\n";
		close CFG;
		print "Unable to conenct to SNMP agent.\n".$SNMP_Session::errmsg."\n";
		return;
	}

	# heading
	print CFG "# MRTG config file for server $sname\n";
	print CFG "# Generated by cfgmaker_host.pl\n";
	print CFG "#\n# $sname\n# $sdesc\n";
	print CFG "#\n\n";
	print CFG "LogFormat: rrdtool\n";
	print CFG "WorkDir: $workdir\n";
	print CFG "PathAdd: $pathadd\n";
	print CFG "routers.cgi*Icon: $sicon\n" if($sicon);
	print CFG "routers.cgi*ShortDesc: $sname\n";
	print CFG "routers.cgi*Description: $sdesc\n" if($sdesc);
	print CFG "\nOptions[\$]: growright\n";
	print CFG "routers.cgi*Options[\$]: available\n";
	print CFG "\n";

	# ping response time
	if( $pingprobe ) {
		print "* Ping response time available\n";
		print CFG "\n#######################################\n";
		print CFG "# Response time\n";
		print CFG "Target[$hostname-ping]: `$pingprobe -p '1000*max/1000*min' -s $hostname`\n";
		print CFG "PageTop[$hostname-ping]: $sdesc<BR>Response time\n";
		print CFG "Title[$hostname-ping]: Ping RTT to $sname\n";
		print CFG "Maxbytes[$hostname-ping]: 5000000\n";
		print CFG "AbsMax[$hostname-ping]: 10000000\n";
		print CFG "Options[$hostname-ping]: gauge\n";
		print CFG "YLegend[$hostname-ping]: microseconds\n";
		print CFG "ShortLegend[$hostname-ping]: us\n";
		print CFG "LegendO[$hostname-ping]: Low:&nbsp;\n";
		print CFG "LegendI[$hostname-ping]: High:\n";
		print CFG "Legend1[$hostname-ping]: Ping response time range\n";
		print CFG "Legend2[$hostname-ping]: Ping response time range\n";
		print CFG "Legend4[$hostname-ping]: Peak low response RTT\n";
		print CFG "Legend3[$hostname-ping]: Peak high response RTT\n";
		print CFG "routers.cgi*WithPeak[$hostname-ping]: none\n";
		print CFG "routers.cgi*Options[$hostname-ping]: nomax, nopercent, nototal, fixunit, scaled\n";
		print CFG "routers.cgi*InOut[$hostname-ping]: no\n";
		print CFG "routers.cgi*InCompact[$hostname-ping]: no\n";
		print CFG "routers.cgi*Mode[$hostname-ping]: range\n";
		print CFG "routers.cgi*Icon[$hostname-ping]: clock-sm.gif\n";
		print CFG "routers.cgi*ShortName[$hostname-ping]: Response\n";
	}


	# CPU
	# for CPU, we create *three* noo .rrds, make them not in menu, then
	# define a userdefined that summarises them. user/sys/wait
	print CFG "\n#######################################\n";
	print CFG "# CPU load\n";
	$rv = undef;
	($rv) = snmpget($snmp, $OID{cpuuser} );
	if(defined $rv) {
		print "* CPU utilisation available (host-MIB).\n";
		#USER
		print CFG "Target[$hostname-cpu-user]: $OID{cpuuser}&$OID{cpuuser}:$snmp\n";
		print CFG "PageTop[$hostname-cpu-user]: $sdesc<BR>User CPU usage\n";
		print CFG "Title[$hostname-cpu-user]: User CPU on $sname\n";
		print CFG "Maxbytes[$hostname-cpu-user]: 100\n";
		print CFG "Options[$hostname-cpu-user]: gauge\n";
		print CFG "YLegend[$hostname-cpu-user]: percent\n";
		print CFG "ShortLegend[$hostname-cpu-user]: %\n";
		print CFG "LegendI[$hostname-cpu-user]: user:\n";
		print CFG "Legend1[$hostname-cpu-user]: User Processes\n";
		print CFG "Legend3[$hostname-cpu-user]: Peak user processes\n";
		print CFG "routers.cgi*WithPeak[$hostname-cpu-user]: none\n";
		print CFG "routers.cgi*Options[$hostname-cpu-user]: noo, nopercent, nototal\n";
		print CFG "routers.cgi*Graph[$hostname-cpu-user]: $hostname-CPU \"CPU usage\" noo\n";
		print CFG "routers.cgi*InMenu[$hostname-cpu-user]: no\n";
		print CFG "routers.cgi*InOut[$hostname-cpu-user]: no\n";
		print CFG "routers.cgi*InSummary[$hostname-cpu-user]: no\n";
		# SYSTEMS
		print CFG "Target[$hostname-cpu-sys]: $OID{cpusys}&$OID{cpusys}:$snmp\n";
		print CFG "PageTop[$hostname-cpu-sys]: $sdesc<BR>System CPU usage\n";
		print CFG "Title[$hostname-cpu-sys]: System CPU on $sname\n";
		print CFG "Maxbytes[$hostname-cpu-sys]: 100\n";
		print CFG "Options[$hostname-cpu-sys]: gauge\n";
		print CFG "YLegend[$hostname-cpu-sys]: percent\n";
		print CFG "ShortLegend[$hostname-cpu-sys]: %\n";
		print CFG "LegendI[$hostname-cpu-sys]: sys&nbsp;:\n";
		print CFG "Legend1[$hostname-cpu-sys]: System Processes\n";
		print CFG "Legend3[$hostname-cpu-sys]: Peak system processes\n";
		print CFG "routers.cgi*WithPeak[$hostname-cpu-sys]: none\n";
		print CFG "routers.cgi*Options[$hostname-cpu-sys]: noo, nopercent, nototal\n";
		print CFG "routers.cgi*Graph[$hostname-cpu-sys]: $hostname-CPU\n";
		print CFG "routers.cgi*InMenu[$hostname-cpu-sys]: no\n";
		print CFG "routers.cgi*InOut[$hostname-cpu-sys]: no\n";
		print CFG "routers.cgi*InSummary[$hostname-cpu-sys]: no\n";
		# WAIT
		print CFG "Target[$hostname-cpu-wait]: 100 - $OID{cpuuser}&$OID{cpuuser}:$snmp - $OID{cpusys}&$OID{cpusys}:$snmp - $OID{cpuidle}&$OID{cpuidle}:$snmp\n";
		print CFG "PageTop[$hostname-cpu-wait]: $sdesc<BR>IO Wait CPU usage\n";
		print CFG "Title[$hostname-cpu-wait]: IO Wait CPU on $sname\n";
		print CFG "Maxbytes[$hostname-cpu-wait]: 100\n";
		print CFG "Options[$hostname-cpu-wait]: gauge\n";
		print CFG "YLegend[$hostname-cpu-wait]: percent\n";
		print CFG "ShortLegend[$hostname-cpu-wait]: %\n";
		print CFG "LegendI[$hostname-cpu-wait]: wait:\n";
		print CFG "Legend1[$hostname-cpu-wait]: IO Wait\n";
		print CFG "Legend3[$hostname-cpu-wait]: Peak IO wait processes\n";
		print CFG "routers.cgi*WithPeak[$hostname-cpu-wait]: none\n";
		print CFG "routers.cgi*Options[$hostname-cpu-wait]: noo, nopercent, nototal\n";
		print CFG "routers.cgi*Graph[$hostname-cpu-wait]: $hostname-CPU\n";
		print CFG "routers.cgi*InMenu[$hostname-cpu-wait]: no\n";
		print CFG "routers.cgi*InOut[$hostname-cpu-wait]: no\n";
		print CFG "routers.cgi*InSummary[$hostname-cpu-wait]: no\n";
		# TOTAL
		# GRAPH
		print CFG "routers.cgi*ShortName[$hostname-CPU]: CPU Utilisation\n";
		print CFG "routers.cgi*Description[$hostname-CPU]: $hostname CPU Utilisation\n";
		print CFG "routers.cgi*GraphStyle[$hostname-CPU]: stack\n";
		print CFG "routers.cgi*Options[$hostname-CPU]: total, available\n";
		print CFG "routers.cgi*LegendTI[$hostname-CPU]: Total usage\n";
		print CFG "routers.cgi*MBLegend[$hostname-CPU]: 100% Utilisation\n";
		print CFG "routers.cgi*Icon[$hostname-CPU]: cpu-sm.gif\n";
		print CFG "routers.cgi*Title[$hostname-CPU]: CPU Usage on $hostname\n";
		print CFG "routers.cgi*InSummary[$hostname-CPU]: yes\n";
	} else {
		$rv = undef;
		($rv) = snmpget ($snmp, $OID{netopiacurcpu});
		if (defined $rv and ($rv > 0)) {
			print "* CPU usage statistic available (Netopia MIB).\n";
			# Current CPU
               		print CFG "Target[$hostname-cpu-cur]: $OID{netopiacurcpu}&$OID{netopiacurcpu}:$snmp\n";
                	print CFG "PageTop[$hostname-cpu-cur]: $sdesc<BR>Current CPU usage\n";
                	print CFG "Title[$hostname-cpu-cur]: Current CPU on $sname\n";
                	print CFG "Maxbytes[$hostname-cpu-cur]: 100\n";
                	print CFG "Options[$hostname-cpu-cur]: gauge\n";
                	print CFG "YLegend[$hostname-cpu-cur]: percent\n";
                	print CFG "ShortLegend[$hostname-cpu-cur]: %\n";
                	print CFG "LegendI[$hostname-cpu-cur]: user:\n";
                	print CFG "Legend1[$hostname-cpu-cur]: Current CPU Usage\n";
                	print CFG "Legend3[$hostname-cpu-cur]: Current CPU Usage Peak\n";
                	print CFG "routers.cgi*WithPeak[$hostname-cpu-cur]: none\n";
                	print CFG "routers.cgi*Options[$hostname-cpu-cur]: noo, nopercent, nototal\n";
                	print CFG "routers.cgi*Graph[$hostname-cpu-cur]: $hostname-CPU \"CPU usage\" noo\n";
                	print CFG "routers.cgi*InMenu[$hostname-cpu-cur]: no\n";
                	print CFG "routers.cgi*InOut[$hostname-cpu-cur]: no\n";
                	print CFG "routers.cgi*InSummary[$hostname-cpu-cur]: no\n";
			# Average CPU
	                print CFG "Target[$hostname-cpu-avg]: $OID{netopiaavgcpu}&$OID{netopiaavgcpu}:$snmp\n";
                	print CFG "PageTop[$hostname-cpu-avg]: $sdesc<BR>Average CPU usage\n";
                	print CFG "Title[$hostname-cpu-avg]: Average CPU on $sname\n";
                	print CFG "Maxbytes[$hostname-cpu-avg]: 100\n";
                	print CFG "Options[$hostname-cpu-avg]: gauge\n";
                	print CFG "YLegend[$hostname-cpu-avg]: percent\n";
                	print CFG "ShortLegend[$hostname-cpu-avg]: %\n";
                	print CFG "LegendI[$hostname-cpu-avg]: sys&nbsp;:\n";
                	print CFG "Legend1[$hostname-cpu-avg]: Average CPU usage\n";
                	print CFG "Legend3[$hostname-cpu-avg]: Average CPU usage Peak\n";
                	print CFG "routers.cgi*WithPeak[$hostname-cpu-avg]: none\n";
                	print CFG "routers.cgi*Options[$hostname-cpu-avg]: noo, nopercent, nototal\n";
                	print CFG "routers.cgi*Graph[$hostname-cpu-avg]: $hostname-CPU\n";
                	print CFG "routers.cgi*InMenu[$hostname-cpu-avg]: no\n";
                	print CFG "routers.cgi*InOut[$hostname-cpu-avg]: no\n";
                	print CFG "routers.cgi*InSummary[$hostname-cpu-avg]: no\n";
			# Total & Graph
                	print CFG "routers.cgi*ShortName[$hostname-CPU]: CPU Utilisation\n";
                	print CFG "routers.cgi*Description[$hostname-CPU]: $hostname CPU Utilisation\n";
                	print CFG "routers.cgi*GraphStyle[$hostname-CPU]: normal\n";
                	print CFG "routers.cgi*Options[$hostname-CPU]: total, available\n";
                	print CFG "routers.cgi*LegendTI[$hostname-CPU]: Total usage\n";
                	print CFG "routers.cgi*MBLegend[$hostname-CPU]: 100% Utilisation\n";
                	print CFG "routers.cgi*Icon[$hostname-CPU]: cpu-sm.gif\n";
                	print CFG "routers.cgi*Title[$hostname-CPU]: CPU Usage on $hostname\n";
                	print CFG "routers.cgi*InSummary[$hostname-CPU]: yes\n";
		} else {
			print CFG "#\n# Not available.\n";
			print "CPU usage statistics not available.\n";
		}
	}

	# memory
	# physical and virtual
	print CFG "\n#######################################\n";
	print CFG "# Memory used\n";
	$rv = undef;
	($rv) = snmpget($snmp, $OID{totalswap} );
	if(defined $rv and ($rv > 0)) {
		print "* Memory utilisation available (UCD-MIB).\n";
		($mbr, $mbs ) = snmpget($snmp, $OID{totalreal}, $OID{totalswap});
		$aroid = $OID{availreal};
		$asoid = $OID{availswap};
		$targ = "$aroid&$asoid:$snmp";
		$factor = 1024;
	} else {
		$rv = undef;
		($rv) = snmpget($snmp, $OID{storageentry}.".5.101" );
		if($rv>0) {
			print "* Memory utilisation available (host-MIB).\n";
			$aroid = $OID{storageentry}.".6.101";
			$asoid = $OID{storageentry}.".6.102";
			($mbr, $mbs) = snmpget($snmp, $OID{storageentry}.".5.101", 
				$OID{storageentry}.".5.102");
			$targ = $OID{storageentry}.".5.101&".$OID{storageentry}
				.".5.102:$snmp - $aroid&$asoid:$snmp";
			$factor = 1024;
		} else {
			$rv = undef;
			($rv) = snmpget($snmp, $OID{suntotalswap} );
			if($rv>0) {
				print "* Memory utilisation available (Sun-MIB).\n";
				($mbr, $mbs) = snmpget($snmp, $OID{suntotalreal}, 
					$OID{suntotalswap});
				$aroid = $OID{sunavailreal};
				$asoid = $OID{sunavailswap};
				$targ = "$aroid&$asoid:$snmp";
				$factor = 1024;
			} else {
				$rv = undef; 
				($rv) = snmpget($snmp, $OID{netopiaavailmem} );
				if ($rv>0) {
					print "* Memory utilisation available (Netopia-MIB).\n";
					($mbr, $mbs) = snmpget($snmp, $OID{netopiaavailmem}, $OID{netopiaavailmem});
					$aroid = $OID{netopiausedmem};
					$asoid = $OID{netopiausedmem};
					$targ = "$aroid&$asoid:$snmp";
					$factor = 1;
				} else {
					print "Memory stats not available.\n";
				}
			}
		}
	}

	if($targ) {
		print CFG "Target[$hostname-memory]: $targ\n";
		print CFG "PageTop[$hostname-memory]: $sdesc<BR>Memory Available\n";
		print CFG "Title[$hostname-memory]: Available Memory on $sname\n";
		print CFG "SetEnv[$hostname-memory]: MRTG_INT_DESCR=\"Memory\"\n";
		print CFG "Factor[$hostname-memory]: $factor\n";
		print CFG "MaxBytes1[$hostname-memory]: $mbr\n";
		print CFG "MaxBytes2[$hostname-memory]: $mbs\n";
		print CFG "Options[$hostname-memory]: gauge\n";
		print CFG "YLegend[$hostname-memory]: Bytes\n";
		print CFG "ShortLegend[$hostname-memory]: b\n";
		print CFG "LegendI[$hostname-memory]: real:\n";
		print CFG "LegendO[$hostname-memory]: swap:\n";
		print CFG "Legend1[$hostname-memory]: Available real memory\n";
		print CFG "Legend2[$hostname-memory]: Available swap space\n";
		print CFG "Legend3[$hostname-memory]: Peak available real\n";
		print CFG "Legend4[$hostname-memory]: Peak available swap\n";
		print CFG "routers.cgi*Options[$hostname-memory]: nototal\n";
		print CFG "routers.cgi*Mode[$hostname-memory]: memory\n";
		print CFG "routers.cgi*ShortDesc[$hostname-memory]: Memory\n";
		print CFG "routers.cgi*Description[$hostname-memory]: Memory available: $sname\n";
		print CFG "routers.cgi*InOut[$hostname-memory]: no\n";
		print CFG "routers.cgi*InSummary[$hostname-memory]: yes\n";
		print CFG "routers.cgi*InCompact[$hostname-memory]: yes\n";
		print CFG "routers.cgi*Icon[$hostname-memory]: chip-sm.gif\n";
		print CFG "routers.cgi*MBLegend[$hostname-memory]: 100% usage\n";
	} else {
		print CFG "#\n# Not available.\n";
	}

	# paging activity
	# pagein/out
	my($options);
	print CFG "\n#######################################\n";
	print CFG "# Paging activity\n";
	$rv = undef;
	$targ = "";
	($rv) = snmpget($snmp, $OID{swapin} );
	if(defined $rv) {
		$targ = "$OID{swapin}&$OID{swapout}:$snmp";
		print "* Paging activity available.\n";
		$options = "nopercent, gauge";
	} else {
		($rv) = snmpget($snmp, $OID{sunswapin} );
		if(defined $rv) {
			$targ = "$OID{sunswapin}&$OID{sunswapout}:$snmp";
			print "Paging activity available (Sun-MIB).\n";
			$options = "nopercent";
		}
	}

	if($targ) {
		print CFG "Target[$hostname-page]: $targ\n";
		print CFG "PageTop[$hostname-page]: $sdesc<BR>Paging activity\n";
		print CFG "Title[$hostname-page]: Paging activity on $sname\n";
		print CFG "SetEnv[$hostname-page]: MRTG_INT_DESCR=\"Paging\"\n";
		print CFG "MaxBytes[$hostname-page]: 100000\n";
		print CFG "Options[$hostname-page]: $options\n";
		print CFG "YLegend[$hostname-page]: per second\n";
		print CFG "ShortLegend[$hostname-page]: pps\n";
		print CFG "LegendI[$hostname-page]: in&nbsp;:\n";
		print CFG "LegendO[$hostname-page]: out:\n";
		print CFG "Legend1[$hostname-page]: Pages in per seoncd\n";
		print CFG "Legend2[$hostname-page]: Pages out per second\n";
		print CFG "Legend3[$hostname-page]: Peak pages in\n";
		print CFG "Legend4[$hostname-page]: Peak pages out\n";
		print CFG "routers.cgi*Options[$hostname-page]: nomax, nototal, fixunit\n";
		print CFG "routers.cgi*Mode[$hostname-page]: general\n";
		print CFG "routers.cgi*ShortDesc[$hostname-page]: Paging\n";
		print CFG "routers.cgi*Description[$hostname-page]: Paging activity: $sname\n";
		print CFG "routers.cgi*UnScaled[$hostname-page]: none\n";
		print CFG "routers.cgi*InOut[$hostname-page]: no\n";
		print CFG "routers.cgi*InSummary[$hostname-page]: yes\n";
		print CFG "routers.cgi*InCompact[$hostname-page]: no\n";
		print CFG "routers.cgi*Icon[$hostname-page]: disk-sm.gif\n";
	} else {
		print CFG "#\n# Not available.\n";
		print "Paging statistics not available.\n";
	}

	# Disk
	# individual disk spaces, and one userdefined summary
	# this can be done either through the UCD or host mibs
	print CFG "\n#######################################\n";
	print CFG "# Filesystems\n";
	my(%diskname) = ();
	my(%disksize) = ();
	my(%mult) = ();
	my($t,$c,$v,$r,$mult);
	my($pfx) = "";
	$rv = undef;
	($rv) = snmpget($snmp, $OID{diskentry}.".2.1" );
	if(defined $rv) {
		print "* Disk usage stats available. (UCD-MIB)\n";
		my(@oids) = snmpwalk($snmp, $OID{diskentry});
		while(@oids) {
			$r = shift @oids;
			$r =~ /(\d+)\.(\d+):(.*)/;
			($t,$c,$v)=($1,$2,$3);
			next if(!$t);
			$diskname{$c} = $v if($t == 2);
			$disksize{$c} = $v if($t == 6);
			$mult{$c} = 1024;
		}
		$pfx = $OID{diskentry}.".8";
	} else {
		print CFG "#\n# UCD MIB not available.\n";
		($rv) = snmpget($snmp, $OID{storageentry}.".3.1" );
		if(defined $rv) {
			print "* Disk usage stats available. (host-MIB)\n";
			my(@oids) = snmpwalk($snmp, $OID{storageentry});
			while(@oids) {
				$r = shift @oids;
				$r =~ /(\d+)\.(\d+):(.*)/;
				($t,$c,$v)=($1,$2,$3);
				next if($t eq "");
				$diskname{$c} = $v if($t == 3 and $v!~/\s/);
				$disksize{$c} = $v if($t == 5 and $c<101);
				$mult{$c}     = $v if($t == 4 and $c<101);
			}
			$pfx = $OID{storageentry}.".6";
		} else {
			print CFG "#\n# Host MIB not available.\n";
		}
	}
	if( $pfx ) {
		# we have some!
		my($l);
		foreach $c ( keys %diskname ) {
			next if(!$disksize{$c} or !$mult{$c} or !$diskname{$c});
		$l = $diskname{$c};
		next if($l !~ /^\// and $l !~ /^[a-z]:/i);
		print "$l ";
		$l=~ s/[\s\\\/:]/-/g;
		print CFG "Target[$hostname-disk-$l]: $pfx.$c&$pfx.$c:$snmp\n";
		print CFG "PageTop[$hostname-disk-$l]: $sdesc<BR>Disk space used ("
			.$diskname{$c}.")\n";
		print CFG "Title[$hostname-disk-$l]: Disk space used on $sname ("
			.$diskname{$c}.")\n";
		print CFG "SetEnv[$hostname-disk-$l]: MRTG_INT_DESCR=\""
			.$diskname{$c}."\"\n";
		print CFG "MaxBytes[$hostname-disk-$l]: ".$disksize{$c}."\n";
		print CFG "Factor[$hostname-disk-$l]: ".$mult{$c}."\n";
		print CFG "Options[$hostname-disk-$l]: gauge\n";
		print CFG "YLegend[$hostname-disk-$l]: Bytes\n";
		print CFG "ShortLegend[$hostname-disk-$l]: b\n";
		print CFG "LegendI[$hostname-disk-$l]: used:\n";
		print CFG "Legend1[$hostname-disk-$l]: Space used\n";
		print CFG "Legend3[$hostname-disk-$l]: Peak used\n";
		print CFG "routers.cgi*Options[$hostname-disk-$l]: nototal, noo\n";
		print CFG "routers.cgi*Mode[$hostname-disk-$l]: general\n";
		print CFG "routers.cgi*ShortDesc[$hostname-disk-$l]: "
			.$diskname{$c}."\n";
		print CFG "routers.cgi*Description[$hostname-disk-$l]: $sname space used on "
			.$diskname{$c}."\n";
		print CFG "routers.cgi*InOut[$hostname-disk-$l]: no\n";
		print CFG "routers.cgi*InMenu[$hostname-disk-$l]: no\n";
		print CFG "routers.cgi*InSummary[$hostname-disk-$l]: yes\n";
		print CFG "routers.cgi*InCompact[$hostname-disk-$l]: yes\n";
		print CFG "routers.cgi*Icon[$hostname-disk-$l]: dir-sm.gif\n";
		print CFG "routers.cgi*Graph[$hostname-disk-$l]: $hostname-filesystems \"Disk space\" withtotal noo\n";
		}
		print CFG "routers.cgi*Options[$hostname-filesystems]: available\n";
		print CFG "routers.cgi*Icon[$hostname-filesystems]: dir-sm.gif\n";
		print CFG "routers.cgi*ShortDesc[$hostname-filesystems]: Filesystems\n";
		print CFG "routers.cgi*Title[$hostname-filesystems]: Filesystems on $hostname\n";
		print "\n";
	} else {
		print "Disk usage stats not availble.\n";
	}

	# load average
	print CFG "\n#######################################\n";
	print CFG "# Load average\n";
	$rv = undef;
	($rv) = snmpget($snmp, $OID{loadavg} );
	$targ = "";
	if(defined $rv) {
		print "* Load Average available.\n";
		$targ = "$OID{loadavg}&$OID{loadavg15}:$snmp / 100";
	} else {
		($rv) = snmpget($snmp, $OID{sunloadavg} );
		if(defined $rv) {
			print "* Load Average available (Sun-MIB).\n";
			$targ = "$OID{sunloadavg}&$OID{sunloadavg15}:$snmp";
		}
	}

	if($targ) {
		print CFG "Target[$hostname-lavg]: $targ\n";
		print CFG "PageTop[$hostname-lavg]: $sdesc<BR>Load Average\n";
		print CFG "Title[$hostname-lavg]: Load Average on $sname\n";
		print CFG "SetEnv[$hostname-lavg]: MRTG_INT_DESCR=\"Load Average\"\n";
		print CFG "MaxBytes[$hostname-lavg]: 1000\n";
		print CFG "Options[$hostname-lavg]: nopercent, gauge\n";
		print CFG "YLegend[$hostname-lavg]: Processes\n";
		print CFG "ShortLegend[$hostname-lavg]: &nbsp;\n";
		print CFG "LegendI[$hostname-lavg]: 1min avg:\n";
		print CFG "LegendO[$hostname-lavg]: 15min avg:\n";
		print CFG "Legend1[$hostname-lavg]: 1-min load average\n";
		print CFG "Legend2[$hostname-lavg]: 15-min load average\n";
		print CFG "Legend3[$hostname-lavg]: Peak 1-min load average\n";
		print CFG "Legend4[$hostname-lavg]: Peak 15-min load average\n";
		print CFG "routers.cgi*Options[$hostname-lavg]: nomax, nototal, fixunit, noo\n";
		print CFG "routers.cgi*Mode[$hostname-lavg]: general\n";
		print CFG "routers.cgi*ShortDesc[$hostname-lavg]: Load Avg\n";
		print CFG "routers.cgi*Description[$hostname-lavg]: Load average: $sname\n";
		print CFG "routers.cgi*UnScaled[$hostname-lavg]: none\n";
		print CFG "routers.cgi*WithPeak[$hostname-lavg]: none\n";
		print CFG "routers.cgi*InOut[$hostname-lavg]: no\n";
		print CFG "routers.cgi*InSummary[$hostname-lavg]: yes\n";
		print CFG "routers.cgi*InCompact[$hostname-lavg]: no\n";
		print CFG "routers.cgi*Icon[$hostname-lavg]: load-sm.gif\n";
	} else {
		print CFG "#\n# Not available.\n";
		print "Load average counters not available.\n";
	}

	# users
	print CFG "\n#######################################\n";
	print CFG "# User count\n";
	$rv = undef;
	$targ = "";
	($rv) = snmpget($snmp, $OID{users} );
	if(defined $rv) {
		print "* User counter available (host-MIB).\n";
		$targ = "$OID{users}&$OID{users}:$snmp";
	} else {
		($rv) = snmpget($snmp, $OID{sunusers} );
		if(defined $rv) {
			print "* User counter available (Sun-MIB).\n";
			$targ = "$OID{sunusers}&$OID{sunusers}:$snmp";
		}
	}

	if($targ) {
		print CFG "Target[$hostname-users]: $targ\n";
		print CFG "PageTop[$hostname-users]: $sdesc<BR>Active users\n";
		print CFG "Title[$hostname-users]: Active Users on $sname\n";
		print CFG "MaxBytes[$hostname-users]: 1000\n";
		print CFG "SetEnv[$hostname-users]: MRTG_INT_DESCR=\"Users\"\n";
		print CFG "Options[$hostname-users]: nopercent, gauge\n";
		print CFG "YLegend[$hostname-users]: Users\n";
		print CFG "ShortLegend[$hostname-users]: &nbsp;\n";
		print CFG "LegendI[$hostname-users]: Users\n";
		print CFG "Legend1[$hostname-users]: Active Users\n";
		print CFG "Legend3[$hostname-users]: Peak Active Users\n";
		print CFG "routers.cgi*Options[$hostname-users]: nomax, nototal, fixunit, noo\n";
		print CFG "routers.cgi*Mode[$hostname-users]: general\n";
		print CFG "routers.cgi*ShortDesc[$hostname-users]: Users\n";
		print CFG "routers.cgi*Description[$hostname-users]: Users on $sname\n";
		print CFG "routers.cgi*UnScaled[$hostname-users]: none\n";
		print CFG "routers.cgi*InOut[$hostname-users]: no\n";
		print CFG "routers.cgi*InSummary[$hostname-users]: yes\n";
		print CFG "routers.cgi*InCompact[$hostname-users]: no\n";
		print CFG "routers.cgi*Icon[$hostname-users]: user-sm.gif\n";
	} else {
		print CFG "#\n# Not available.\n";
		print "User count not available.\n";
	}

	# processes
	print CFG "\n#######################################\n";
	print CFG "# Process count\n";
	$rv = undef;
	($rv) = snmpget($snmp, $OID{procs} );
	if(defined $rv) {
		print "* Processes counter available (host-MIB).\n";
		print CFG "Target[$hostname-procs]: $OID{procs}&$OID{procs}:$snmp\n";
		print CFG "PageTop[$hostname-procs]: $sdesc<BR>Processes\n";
		print CFG "Title[$hostname-procs]: Processes on $sname\n";
		print CFG "MaxBytes[$hostname-procs]: 1000000\n";
		print CFG "SetEnv[$hostname-procs]: MRTG_INT_DESCR=\"Procs\"\n";
		print CFG "Options[$hostname-procs]: nopercent, gauge\n";
		print CFG "YLegend[$hostname-procs]: Processes\n";
		print CFG "ShortLegend[$hostname-procs]: &nbsp;\n";
		print CFG "LegendI[$hostname-procs]: Procs\n";
		print CFG "Legend1[$hostname-procs]: Processes\n";
		print CFG "Legend3[$hostname-procs]: Peak Processes\n";
		print CFG "routers.cgi*Options[$hostname-procs]: nomax, nototal, fixunit, noo\n";
		print CFG "routers.cgi*Mode[$hostname-procs]: general\n";
		print CFG "routers.cgi*ShortDesc[$hostname-procs]: Processes\n";
		print CFG "routers.cgi*Description[$hostname-procs]: Processes on $sname\n";
		print CFG "routers.cgi*UnScaled[$hostname-procs]: none\n";
		print CFG "routers.cgi*InOut[$hostname-procs]: no\n";
		print CFG "routers.cgi*InSummary[$hostname-procs]: yes\n";
		print CFG "routers.cgi*InCompact[$hostname-procs]: no\n";
		print CFG "routers.cgi*Icon[$hostname-procs]: list-sm.gif\n";
	} else {
		print CFG "#\n# Not available.\n";
		print "Process counter not available.\n";
	}

	# network
	# each network adapter.  Incoming.outgoing is made automatically.
	# do it by IP address. We need to walk the tree, and get maxbytes

	@ret = snmpwalk($snmp,'ifIndex');
	@ifids = ();
	foreach $ifentry ( @ret ) {
		$ifentry =~ /(\d+):(\d+)/;
		push @ifids,$2;
	}
#	@ifids = ( 1,2);
	foreach $ifentry ( @ifids ) {
		next if( $ifentry !~ /\d+/ );
		($rv) = snmpget($snmp,	"ifDescr.$ifentry" );
		next if(!$rv);
		$na = $rv;
		$na =~ /([a-zA-Z\/\-:#\+\d]+)/;
		$na = $1 if($1);
		$ifname{$ifentry}=$na ;
		($rv) = snmpget($snmp, "ifSpeed.$ifentry" );
		$ifspeed{$ifentry} = $rv/8;
		($rv) = snmpget($snmp,	"ifOperStatus.$ifentry" );
		$ifok{$ifentry} = $rv;
	}
	@ret = snmpwalk($snmp,$OID{ipadentifindex} );
	foreach $ifentry ( @ret ) {
		if( $ifentry =~ /(\d+\.\d+\.\d+\.\d+):(\d+)/ ) {
		$ip{$2} = $1;
		}
	}
	my($ifc) = 0;
	foreach ( keys %ifname ) {	
		if( $ifname{$_} =~ /^lo/ or !$ifname{$_}
			or $ifspeed{$_} < 1
			or $ifok{$_} != 1 ) {
#			print "(".$ifname{$_}.") ";
			undef $ifname{$_};
		} else { $ifc++; }
	}
	print CFG "\n#######################################\n";
	print CFG "# Network interfaces\n";
	if( $ifc ) {
	print "* Network interfaces\n";
	foreach $ifentry ( keys %ifname ) {
		next if(!$ifentry or !$ifname{$ifentry});
		print $ifname{$ifentry}."(".$ip{$ifentry}.") ";
		if( $ip{$ifentry} ) {
		print CFG "Target[$hostname-if-$ifentry]: /".$ip{$ifentry}.":$snmp\n";
		} else {
		print CFG "Target[$hostname-if-$ifentry]: $ifentry:$snmp\n";
		}
		print CFG "PageTop[$hostname-if-$ifentry]: $sdesc<BR>Interface "
			.$ifname{$ifentry}."\n";
		print CFG "Title[$hostname-if-$ifentry]: $sname: traffic on "
			.$ifname{$ifentry}."\n";
		print CFG "SetEnv[$hostname-if-$ifentry]: MRTG_INT_DESCR=\""
			.$ifname{$ifentry}."\" MRTG_INT_IP=\"".$ip{$ifentry}
			."\"\n";
		print CFG "MaxBytes[$hostname-if-$ifentry]: ".$ifspeed{$ifentry}."\n";
		print CFG "Options[$hostname-if-$ifentry]: bits\n";
		print CFG "routers.cgi*Mode[$hostname-if-$ifentry]: interface\n";
		print CFG "routers.cgi*ShortDesc[$hostname-if-$ifentry]: "
			.$ifname{$ifentry}." (".$ip{$ifentry}.")\n";
	}
	print "\n";
	} else {
		print "Network interfaces not available.\n";
		print CFG "# Not available\n#\n";
	}
	

	# finish up
	close CFG;
}

#######################################################################
# Main code

# Options
GetOptions("community=s"=>\$community,
	"workdir=s"=>\$workdir,
	"libadd=s"=>\$libadd,
	"pathadd=s"=>\$pathadd,
	"pingprobe=s"=>\$pingprobe);
	
if($libadd) { push @INC, $libadd; }
eval { require SNMP_util; require SNMP_Session; };
if($@) {
	print "# Unable to find SNMP_util.pm or dependent modules.\n";
	print "# Make sure they are in the perl library, or the current directory,\n";
	print "# Or use the --libadd option.\n";
	exit 1;
}
if(@ARGV) { @hosts = @ARGV; }
$PS="\\" if($^ =~ /win/i);

# do we have pingprobe?
$pingprobe = "" if ( ! -f $pingprobe );

foreach $h ( @hosts ) {
	# process hosts in turn
	print "########################################\n";
	print "# Processing host $h\n";
	print "########################################\n";
	process_host($h);
}
exit 0;
