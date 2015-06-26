#!/usr/bin/perl
#
# Try to build configuration files for all the routers in the WAN,
# by recursively scanning them.  Can take a long time to run!
# call with parameter '-h' for syntax help.
##########################################################################
#
# buildwan.pl
#
# THIS IS RELEASED IN THE PUBLIC DOMAIN:
# Do what you want with it, how you want.  You are free to modify,
# distribute or even sell this script.
#
##########################################################################

use strict;
use Net::SNMP;
use FileHandle;
use vars qw($opt_L $opt_h $opt_s $opt_c $opt_D $opt_w $opt_N $opt_A);
use Getopt::Std;

my( $conffile, %config,@cfgfiles, $pathsep );
my($SHDESC ) = "1.3.6.1.2.1.2.2.1.2";
my($DESC   ) = "1.3.6.1.2.1.31.1.1.1.18";
my($SYSDESC) = "1.3.6.1.2.1.1.1.0";
my($IFINDEX) = "1.3.6.1.2.1.2.2.1.1";
my($IFDESCR) = "1.3.6.1.2.1.2.2.1.2";
my($IFSPEED) = "1.3.6.1.2.1.2.2.1.5";
my($IFADMINSTATUS) = "1.3.6.1.2.1.2.2.1.7";
my($IFOPERSTATUS) = "1.3.6.1.2.1.2.2.1.8";
my($IFINOCTETS) = "1.3.6.1.2.1.2.2.1.10";
my($IPIFINDEX) = "1.3.6.1.2.1.4.20.1.2";
my($IPROUTEGW) = "1.3.6.1.2.1.4.21.1.7";
my($CPUOID) = "1.3.6.1.4.1.9.2.1.58.0";
my($MEMOID) = "1.3.6.1.4.1.9.9.48.1.1.1.5.1"; # have to find out
# Cisco 7200 Series Temperature
my($CISCOTEMP) = "1.3.6.1.4.1.9.9.13.1.3.1";

my( $includelans ) = 0;
my( $includealllan ) = 0;
my( $router, $routerip, $routerhostname, $routerdesc, $routeraddr );
my( $showall ) = 0;
my( $fname );

my( $script ) = "/cgi-bin/routers2.cgi";
my( $pathsep ) = "/";
my( $domain ) = "...\.adsw\.com";
my( @community ) = ( "public" );
my( $community );
my( $workdir ) = "/var/rrdtool/auto";
my( @queue ) = ( );
my( $subdir ) = "";
my( @filelist ) = ();

my( %routers, %done );

##########################################################################

my($spinindex) = 0;
sub spin($)
{
print "\r".(substr "\\|/-",$spinindex,1)." ".$_[0]."                     \r";
$spinindex += 1;
$spinindex = 0 if($spinindex > 3);
}

sub escape($)
{
	my($rv);
	$rv = $_[0];
	$rv =~ s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
	return $rv;
}


# $interfaces{ifno} = \{ desc=>"", shdesc=>"", ip=>"" }
my( %interfaces ) = ();

sub process_rtr($)
{
	my($snmp, $resp, $snmperr, $k);
	my($n,$v,$ip);
	my($cpuok,$memok) ;
	my($rcomm) = "";
	
	$router = $_[0];
	$cpuok = $memok = "";

	if(defined $done{$router} ) {
		print "No need to do $router again (".$done{$router}[0].")                  \r";
		return;
	}


	%interfaces = ();

	foreach $community  ( @community ) {
		print "\r**** Let's check $community\@$router ****               ";
		($snmp, $snmperr) = Net::SNMP->session(
			-hostname=>$router, -community=>$community,
			-timeout=>4 );
		if($snmperr) {
			print  "Error: ".$snmperr."\n";
			$done{$router} =[ "Error","",""];
			return;
		}
		$rcomm = $community;

		# get the interfaces list
		$resp = $snmp->get_next_request( $IFINDEX );
		last if($resp);
	}
	print "\n";
	if(!defined $resp ) {
		print "Error: ". $snmp->error()."\n";
		$snmp->close();
		$done{$router} = ["Error","",""];
		return;
	}

	print "If: ";
	while( defined $resp ) {
		$n = (keys %$resp)[0];
		foreach $k ( keys %$resp ) {
			$v = $resp->{$k};
			last if ( $v !~ /^\d+$/ );
			spin "If $v";
			$interfaces{$v}{ifno} = $v ;
		}
		last if ( $v !~ /^\d+$/ );
		$resp = $snmp->get_next_request( $n );
	}
	# Get IP interface list
	print "\rIP:                                                  \r";
	$resp = $snmp->get_next_request( $IPIFINDEX );
	if(!defined $resp ) {
		print "\nError: ". $snmp->error()."\n";
		$done{$router} = ["Error","",""];
		$snmp->close();
		return;
	}
	while( defined $resp ) {
		$n = (keys %$resp)[0];
		foreach $k ( keys %$resp ) {
			$v = $resp->{$k};
			last if ( $v !~ /^\d+$/ );	
			if( $k =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)$/
				and defined $interfaces{$v} ) {
				$ip = "$1.$2.$3.$4";
				$interfaces{$v}{ip} = $ip 
					if(($ip =~ /^10/) or !$interfaces{$v}{ip});
				spin "IP ".$interfaces{$v}{ip};
				if($done{$interfaces{$v}{ip}} 
					and $done{$interfaces{$v}{ip}}[0] !~ /Error/i) {
					print "\rOops, done this one before ("
						.$interfaces{$v}{ip}.")(" 
						.$done{$interfaces{$v}{ip}}[0].")\n";
					$done{$router} = [ @{$done{$interfaces{$v}{ip}}} ];
					return;
				}
			}
		}
		last if ( $v !~ /^\d+$/ );
		$resp = $snmp->get_next_request( $n );
	}

	# get their descriptions and activity
	print "\rDt:                                                       \r";
	foreach $k ( keys %interfaces ) {
		$resp = $snmp->get_request(
			"$IFDESCR.$k",
			"$IFADMINSTATUS.$k",
			"$IFOPERSTATUS.$k",
			"$IFSPEED.$k",
			"$IFINOCTETS.$k"
		);
		# XXX: ici a faire :)
		if ($includealllan) {
			if( 
			 $resp->{"$IFDESCR.$k"} =~ /^lo/i
			 or $resp->{"$IFDESCR.$k"} =~ /^nul/i
			 or $resp->{"$IFDESCR.$k"} =~ /^Nul.*/i
			 or $resp->{"$IFDESCR.$k"} =~ /^VLAN.*/i
			) {
				$interfaces{$k}{state} = "X";
				delete $interfaces{$k} unless($showall);
				spin "$k X";
			} else {
				spin "$k .";
				$interfaces{$k}{state} = " ";
				$interfaces{$k}{descr} = $resp->{"$IFDESCR.$k"};
			 	$interfaces{$k}{ifinoctets} = $resp->{"$IFINOCTETS.$k"};
			 	$interfaces{$k}{speed} = $resp->{"$IFSPEED.$k"};
			}
		} else {
			if( 
       		         $resp->{"$IFDESCR.$k"} =~ /^lo/i
	       	         or $resp->{"$IFDESCR.$k"} =~ /^nul/i
	                 or $resp->{"$IFDESCR.$k"} =~ /^Nul.*/i
	                 or $resp->{"$IFDESCR.$k"} =~ /^VLAN.*/i
	                 or $resp->{"$IFADMINSTATUS.$k"} != 1
	                 or $resp->{"$IFOPERSTATUS.$k"} != 1
	                ) {
	                        $interfaces{$k}{state} = "X";
	                        delete $interfaces{$k} unless($showall);
	                        spin "$k X";
	                } else {
	                        spin "$k .";
	                        $interfaces{$k}{state} = " ";
	                        $interfaces{$k}{descr} = $resp->{"$IFDESCR.$k"};
	                        $interfaces{$k}{ifinoctets} = $resp->{"$IFINOCTETS.$k"};
	                        $interfaces{$k}{speed} = $resp->{"$IFSPEED.$k"};
	                }
		}
	}

	
	$routerip = "$router";
	$routerhostname = "";
	my($hn, $a,$b,$c,$d);
	foreach $k ( keys %interfaces ) {
		if($done{$interfaces{$k}{ip}} 
			and $done{$interfaces{$k}{ip}}[0] !~ /Error/i) {
			print "\rOops, done this one before (".$interfaces{$k}{ip}.")("
				.$done{$interfaces{$k}{ip}}[0].")\n";
			$done{$router} = [ @{$done{$interfaces{$k}{ip}}} ];

			$snmp->close;
			return;
		}
		if($interfaces{$k}{ip} =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)/) {
			($a,$b,$c,$d) = ($1,$2,$3,$4);
			if( $routerip !~ /^10\./ and $a eq "10") {
				$routerip = $interfaces{$k}{ip};
				next;
			}
			if(!$routeraddr or !$routerhostname or $a eq "10") {
				$routeraddr = pack 'C4',$a,$b,$c,$d;
				$hn = gethostbyaddr($routeraddr,2);
				if($hn) {
					$routerip = $interfaces{$k}{ip};
					$routerhostname = $hn;
				}
			}
		}
	}
	if(!$routerhostname) {
		$routerip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)/;
		$routeraddr = pack 'C4',$1,$2,$3,$4;
		$routerhostname = gethostbyaddr($routeraddr,2);
	}
	$routerdesc = $routerhostname;
	$routerdesc = $routerip if(!$routerdesc);
	$routerdesc =~ s/\.$domain//o;
	$routerdesc =~ s/^router\.//;
	$routerdesc =~ s/\.uk$//;
	$routerdesc =~ s/^router(\d+)\.(.*)/\2 \1/;
#	$routerdesc = ucfirst $routerdesc if( $routerdesc !~ /\./ );

	if( $router ne $routerip and $done{$routerip} 
			and $done{$routerip}!~/Error/i ) {
		print "\rOops, done this one before ($routerip)(".$done{$routerip}[0].")\n";
		$snmp->close;
		$done{$router} = [ @{$done{$routerip}} ];
		return;
	}

	$routerhostname = $routerip if(!$routerhostname);

	# now check to see if the router has an OID for CPU and mem 
	$resp = $snmp->get_request( $CPUOID, $MEMOID );
	if( $resp ) {
		$cpuok = $CPUOID if( $resp->{$CPUOID} );
		$memok = $MEMOID if( $resp->{$MEMOID} );
	}

	$routers{$router} = { interfaces=>{%interfaces}, name=>$routerdesc,
		ip=>$routerip, hostname=>$routerhostname, community=>$rcomm,
		cpu=>$cpuok, mem=>$memok };

	print "\rFinished router $routerhostname at address $routerip\n";

	$done{$router} = [ $routerdesc, (lc $routerdesc).".cfg", "" ];

	my($nextip, $t);
	foreach $k ( keys %interfaces ) {
		next if(!$interfaces{$k}{ip});
		$t = $routerhostname.".".$interfaces{$k}{descr};
		$t =~ s/[\[\]#\/\\\s]+/./g;
		$t =~ s/\.+/./g;
		$t = lc $t;
		$done{$interfaces{$k}{ip}} 
			= [ $routerdesc, (lc $routerdesc).".cfg", $t ];
	}

	# check routing table and queue each agteway for next scan
	
	$resp = $snmp->get_next_request( $IPROUTEGW );
	if(!defined $resp ) {
		print "\nError: ". $snmp->error()."\n";
		$snmp->close();
		return;
	}
	if(!$opt_N) {
	print "\rChecking routing table .....                         \r";
	while( defined $resp ) {
		$n = (keys %$resp)[0];
		last if( $n !~ /^$IPROUTEGW/ );
		$nextip = $resp->{$n};
		spin "Route $nextip                                 ";
		if(!defined $done{$nextip}
			and $nextip =~ /[123456789]\d*\.\d+\.\d+\.\d+/ ) {
			push @queue, $nextip ;
			print "Queueing $nextip (route)                                 \r";
		}
		$resp = $snmp->get_next_request( $n );
	}
	$snmp->close;

	writefile($router);
	print "\n";
	} else {
		print "\rRouting table is ignored....\n";
	}
}

##########################################################################
# pass hostname, comm, a hash ref for the interfaces
sub print_if($$$$)
{
	my($h,$c,$n,$ifp) = @_;
	my($k,$nextip,$icon);
	my($t,$d,$f);
	my($mb,$pfx);

	$n = ucfirst $n if($n !~ /\./);

	foreach $k ( keys %$ifp ) {
		$icon = "interface-sm.gif";
		$pfx = "";
		$d = "";
		$t = $h.".".$k;
		$t = $h.".".$ifp->{$k}->{descr} if($ifp->{$k}->{descr});
		$t =~ s/[\[\]#\/\\\s]+/./g;
		$t =~ s/\.+/./g;
		$t = lc $t;

		# print it out
		if(!$ifp->{$k}->{speed} or !$c or !$h) {
			$pfx = "# ";
		}
		if(!$includelans and $ifp->{$k}->{descr} =~ /(ether|token)/i) {
			$pfx = "# ";
		}
#		print "$k".$ifp->{$k}{state}.": ".$ifp->{$k}{descr}
#			." [".$ifp->{$k}{ip}."] "
#			.($ifp->{$k}{speed}/8)."bytes/s "
#			.$ifp->{$k}{ifinoctets}."\n";
#		print "ifp=$ifp k=$k ifp->{k}=".$ifp->{$k}."\n";
#		print "ifp->{k}->{ip}=".$ifp->{$k}->{ip}."\n";
		if( $ifp->{$k}->{ip} ) {
			print CFG $pfx."Target[".$t."]: /".$ifp->{$k}->{ip}.":$c\@$h\n";
		} else {
			print CFG $pfx."Target[".$t."]: $k:$c\@$h\n";
		}
		if(!$ifp->{$k}->{speed}) {
			print CFG $pfx."#MaxBytes[".$t."]: unknown (Defaulting to 1G)\n";
			print CFG $pfx."MaxBytes[".$t."]: 12500000\n";
		} else {
			$mb = $ifp->{$k}->{speed} / 8;
			print CFG $pfx."MaxBytes[".$t."]: $mb\n";
		}
		if($ifp->{$k}->{destination}[0]) {
			$d = " (To ".(ucfirst $ifp->{$k}{destination}[0]).")"
				if($ifp->{$k}{destination}[0] !~ /Error/i);
		} else {
			$ifp->{$k}->{ip} =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
			$nextip = "$1.$2.$3.".($4^3);
			if(defined $done{$nextip}) {
				$ifp->{$k}->{destination} = $done{$nextip};
				$d = " (To ".(ucfirst $done{$nextip}[0]).")"
					if($done{$nextip}[0] !~ /Error/i);
#			} else {
#				print CFG "# unable to find info for $nextip\n";
			}
		}
		$icon = "interface2-sm.gif" if($d);

		print CFG $pfx."Title[".$t."]: $n";
		print CFG " (".$ifp->{$k}->{ip}.")" if($ifp->{$k}->{ip});
		print CFG ": ".$ifp->{$k}->{descr}." $d\n";
		print CFG $pfx."PageTop[".$t."]: <H1>Traffic analysis for "
			.$ifp->{$k}->{descr}."</H1>\n";
		print CFG $pfx."SetEnv[".$t."]: MRTG_INT_DESCR=\"".$ifp->{$k}->{descr}
			."\" MRTG_INT_IP=\"".$ifp->{$k}->{ip}."\"\n";
		if($mb > 1000000) {
			print CFG $pfx."routers.cgi*UnScaled[$t]: none\n" 
		} else {
			print CFG $pfx."UnScaled[$t]: dwmy\n";
		}

		if( $ifp->{$k}->{destination}[2]
			and ($ifp->{$k}->{destination}[0] !~ /Error/i) ) {
			$f =  $ifp->{$k}->{destination}[1];
			$f =~ s/[\s\\\/]+/./g;
	print CFG $pfx."routers.cgi*Link[$t]: \"Remote end of P-t-P link on "
	.$ifp->{$k}->{destination}[0]."\" $subdir$f "
	.$ifp->{$k}->{destination}[2]." router-sm.gif\n";
		}
		print CFG $pfx."routers.cgi*ShortDesc[$t]: "
			.$ifp->{$k}->{descr}." (".(ucfirst $ifp->{$k}->{destination}[0])
			.")\n"
		if( $ifp->{$k}->{destination}[0]
#			and ($ifp->{$k}->{destination}[0] !~ /^\d/i) 
			and ($ifp->{$k}->{destination}[0] !~ /Error/i) );

		print CFG $pfx."routers.cgi*Icon[$t]: $icon\n" if($icon);
		
		print CFG "#----------------------------------------------------------------------------\n";

	}
}

sub writefile($)
{
	my($rk) = $_[0];

	$fname = $routers{$rk}{name}.".cfg";
	$fname =~ s/[\s\\\/]+/./g;
	print "Writing config for ".$routers{$rk}{name}."         \r";
	open CFG, ">$fname";
	print CFG "# MRTG config for router ".$routers{$rk}{hostname}
		." community ".$routers{$rk}{community}
		."\n\nWorkdir: $workdir\nLogformat: rrdtool\nOptions[_]: growright bits \n";
	
	print CFG "routers.cgi*Icon: router-sm.gif\n"
		."routers.cgi*ShortDesc: ".$routers{$rk}{name}."\n\n";

	print_if($routers{$rk}{hostname}, $routers{$rk}{community},
		$routers{$rk}{name},$routers{$rk}{interfaces});

	if( $routers{$rk}{cpu} ) {
	print CFG "# CPU calculations\n";
	print CFG "Target[".$routers{$rk}{hostname}.".CPU]: "
		.$routers{$rk}{cpu}."&".$routers{$rk}{cpu}.":"
		.$routers{$rk}{community}."\@".$routers{$rk}{hostname}."\n";
	print CFG "MaxBytes[".$routers{$rk}{hostname}.".CPU]: 100\n";
	print CFG "Options[".$routers{$rk}{hostname}.".CPU]: integer gauge noo\n";
	print CFG "UnScaled[".$routers{$rk}{hostname}.".CPU]: dwmy\n";
	print CFG "Title[".$routers{$rk}{hostname}.".CPU]: "
		.$routers{$rk}{name}." CPU Load\n";
	print CFG "PageTop[".$routers{$rk}{hostname}.".CPU]: CPU Stats\n";
	print CFG "routers.cgi*Mode[".$routers{$rk}{hostname}.".CPU]: cpu\n";
	print CFG "routers.cgi*ShortDesc[".$routers{$rk}{hostname}
		.".CPU]: CPU Stats\n";
	} else {
		print CFG "# Unable to identify a CPU usage OID in MIB\n";
	}
	if( $routers{$rk}{mem} ) {
	print CFG "# Memory calculations\n";
	print CFG "Target[".$routers{$rk}{hostname}.".MEM]: "
		.$routers{$rk}{mem}."&".$routers{$rk}{mem}.":"
		.$routers{$rk}{community}."\@".$routers{$rk}{hostname}."\n";
	print CFG "MaxBytes[".$routers{$rk}{hostname}.".MEM]: 64000000\n";
	print CFG "Options[".$routers{$rk}{hostname}.".MEM]: "
		."nopercent integer gauge noo\n";
	print CFG "routers.cgi*UnScaled[".$routers{$rk}{hostname}.".MEM]: none\n";
	print CFG "Title[".$routers{$rk}{hostname}.".MEM]: "
		.$routers{$rk}{name}." Memory usage\n";
	print CFG "YLegend[".$routers{$rk}{hostname}.".MEM]: Bytes used\n";
	print CFG "PageTop[".$routers{$rk}{hostname}.".MEM]: Memory Stats\n";
	print CFG "LegendI[".$routers{$rk}{hostname}.".MEM]: Mem:\n";
	print CFG "Legend1[".$routers{$rk}{hostname}.".MEM]: Memory used\n";
	print CFG "Legend3[".$routers{$rk}{hostname}.".MEM]: Peak Memory used\n";
	print CFG "routers.cgi*Mode[".$routers{$rk}{hostname}.".MEM]: memory\n";
	print CFG "routers.cgi*ShortDesc[".$routers{$rk}{hostname}
		.".MEM]: Memory\n";
	print CFG "routers.cgi*UnScaled[".$routers{$rk}{hostname}
		.".MEM]: none\n";
	} else {
		print CFG "# Unable to identify a Memory usage OID in MIB\n";
	}
	
	close CFG;

	push @filelist, $fname;
}
##########################################################################
# Main code starts here

autoflush STDOUT 1;

if( $^O =~ /win|dos/i) {
	$pathsep = "\\" ;
	$script = "/cgi-bin/routers2.pl";
}

getopts('hc:D:s:Lw:NA');

if($opt_h or $#ARGV<0) {
	print "Usage: buildwan -h\n       buildwan [-L][-A][-N][-s <subdir>][-c <communitylist>][-D <domainname>] -w <workdir> <router>...\n";
	print "-L: Include ethernet/token ring Lan interfaces\n";
	print "-A: Include ethernet/token ring Lan interfaces even if they are down\n";
	print "-N: Don't browse network neighors.\n";
	print "-s: Specify subdir of cfgpath holding .cfg files\n";
	print "-D: Specify domain name to be stripped from hostnames in descriptions\n";
	print "-c: Specify SNMP community string (default is 'public'), separate with commas\n";
	print "-w: Specify Work directory where the .rrd files go.\n";
	
	exit 1;
}

push @queue, @ARGV if(@ARGV);
$subdir = $opt_s.$pathsep if($opt_s);
$includelans = 1 if($opt_L);
$includealllan = 1 if($opt_A);
$workdir = $opt_w if($opt_w);
@community = split /,\s*/,$opt_c if($opt_c); 
@community = ( 'public' ) if(!@community);
if($opt_D) {
	$domain = $opt_D;
	$domain =~ s/\./\\./g;
}

while( @queue ) {
	$router = shift @queue;
	%interfaces = ();
	process_rtr($router);
}

print "Writing files....\n";
foreach ( keys %routers ) {	
	writefile($_);
}
open CFG, ">summary.cfg";
print CFG "# This file is not intended to be used by routers.cgi\n";
print CFG "# It is intended to be called by mrtg in order to update all of\n";
print CFG "# the targets in one pass.\n\n";
print CFG "routers.cgi*Ignore: yes\n";
print CFG "routers.cgi*RoutingTable: no\n";
print CFG "routers.cgi*Icon: unknown-sm.gif\n";
foreach ( @filelist ) {
	print CFG "Include: $_\n";
}
close CFG;
print "All done.                                               \n";


exit 0;
