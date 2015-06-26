#!/usr/bin/perl -w
# vim:ts=4
#
# mrtg-pnsclient v0.7
#
# S Shipway - www.steveshipway.org
# This is released under the GNU GPL.  See nsclient.ready2run.nl
# to obtain the NetSaint client for your Windows server!
#
# Perl script to collect information from remote pNSclient NetSaint
# client, and output in format suitable for MRTG.
#
# Usage:
#   mrtg-pnsclient -H host [ -p port ]
#       -v <module> [ -l <options> ] [ -o <offset> ]
#       [ -v <module> [ -l <option> ] [ -o <offset> ] [ -t timeout ]
#
# If only one module specified, then both output values are identical.
# If the module returns more than one value
# Modules: COUNTER, DISKSPACE, SERVICE, MEMORY, PROCESS, VERSION, INSTANCES
#
# Now works with Windows -- but dont forget to use double-quotes around the
# parameter when using COUNTER.

# 0.5a : windows corrections for locale
# 0.5b : corrections for 0% CPU use appearing as UNKNOWN
# 0.6  : fix for activeperl 5.8
# 0.7  : Fix for NC_NET which cannot accept a sequence of commands 

use strict;
use Socket;
use Getopt::Long;

my($VERSION) = "v0.7";

my($PORT) = 1248;
my($HOST) = "";
my(@offset,@rv,@rcmd,@resp);
my(%opts);
my($mesg) = "Null";
my($DEBUG) = 0;
my($TIMEOUT) = 15;

my($PASS) = "None";
my($cmd,$cstr);
my(%cmds) = ( 
"NONE"=>0, "CLIENTVERSION" => 1, "VERSION" =>1, "CPULOAD" =>2, "CPU" =>2,
"UPTIME"=>3, "USEDDISKSPACE"=>4, "DISKSPACE"=>4,
"SERVICESTATE"=>5, "SERVICE"=>5, "PROCSTATE"=>6,
"PROCESS"=>6, "MEMUSE"=>7, "MEMORY"=>7, "COUNTER"=>8, "FILEAGE"=>9,
"INSTANCES", 10
	);
######################################################################

sub outputresp {
	if($#resp<0) {
		print "UNKNOWN\nUNKNOWN\n\n$mesg\n";
		return;
	}
	if(!defined $resp[0]) {
		$resp[0] = 'UNKNOWN' ;
	} else {
		$resp[0] =~ s/,/./; # some places use comma decimal separator
		$resp[0] = 'UNKNOWN' if($resp[0]!~/^[0-9\.]+$/);
	}

	print $resp[0]."\n";
	if($#resp>0) {
		if(!defined $resp[1]) {
			$resp[1] = 'UNKNOWN' ;
		} else {
			$resp[1] =~ s/,/./; # some places use comma decimal separator
			$resp[1] = 'UNKNOWN' if($resp[1]!~/^[0-9\.]+$/);
		}
		print $resp[1]."\n";
	} else {
		print $resp[0]."\n";
	}
	print "\n";
	print "$mesg\n";
}

######################################################################
sub ask($) {
	my($a,$r);
	my($fn,$rfd,$wfd,$xfd,$n,$t);

	makesocket();

	$a = $_[0];
	send SOCK, "$a\n", 0;
	print "Sent $a\n" if($DEBUG);

	#wait for reply
	$fn = fileno SOCK;
	$rfd = $wfd = $xfd = "0";
	vec($rfd,$fn,1)=1;
	($n,$t) = select $rfd,$wfd,$xfd,$TIMEOUT; # 10 sec timeout
	if(!$n or !$rfd) { print "ERROR\n" if($DEBUG); close SOCK; return undef; }
	
	# read it
	print "Reading\n" if($DEBUG);
	$r = '';
	eval { if($^O!~/Win/) { $SIG{ALRM} = \&timeout; alarm($TIMEOUT);}
		recv SOCK, $r, 512,0;
		alarm(0);
	};
	$r= 'ERROR: Timeout' if($@ =~ /TIMEOUT/);
	print "Read [$r]\n" if($DEBUG);
	$r =~ s/\n/~/g;

	close SOCK;

	return $r;
}
sub timeout { die "TIMEOUT"; }

######################################################################
# make $sock, the socket...

sub makesocket {
	my($iaddr,$paddr,$proto);

	$iaddr = inet_aton($HOST);
	if(!$iaddr) {
		$mesg = "Unable to resolve $HOST: $!";
		outputresp(); exit 1;
	};
	$paddr = sockaddr_in($PORT,$iaddr);
	if(!$paddr) {
		$mesg = "Creating socket failed: $!";
		outputresp(); exit 1;
	};
	$proto = getprotobyname('tcp');

	socket(SOCK,PF_INET,SOCK_STREAM,$proto) or do {
		$mesg = "Socket failed: $!";
		outputresp(); exit 1;
	};
	connect(SOCK,$paddr) or do {
		$mesg = "Connect failed to $HOST:$PORT: $!";
		outputresp(); exit 1;
	};
	
	setsockopt(SOCK,SOL_SOCKET,SO_REUSEADDR,1);
}

######################################################################


$|=1;

GetOptions(\%opts, "host|H|s|server=s", "port|p=s", "offset|o|n=i@",
	"module|command|cmd|c|v=s@", "arg|l|a=s@", "debug|d", "timeout|t=i",
	"ratio|r" );

$DEBUG = 1 if($opts{debug});
$HOST = $opts{host} if($opts{host});
$PORT = $opts{port} if($opts{port});
$PORT = getservbyname($PORT,'tcp') if($PORT=~/\D/);
$TIMEOUT = $opts{timeout} if($opts{timeout});

if( !$PORT or !$HOST ) {
	$mesg = "Incorrect host/port parameter";
	outputresp;
	exit 1;
}

if( ! $opts{module} ) {
	$mesg = "No command parameter";
	outputresp; exit 1;
}
$opts{module}[1] = $opts{module}[0] if(!$opts{module}[1] and $opts{arg}[1]);
$cmd = $opts{module}[0];
if(!$cmds{$cmd}) {
	$mesg = "Incorrect command parameter $cmd";
	outputresp;
	exit 1;
}
$opts{arg}[0] =~ s/,/&/g  if( $opts{arg}[0] );
$opts{arg}[1] =~ s/,/&/g  if( $opts{arg}[1] );
$rcmd[0] = "$PASS&".$cmds{$cmd}."&";
$rcmd[0] .= $opts{arg}[0]."&" if( $opts{arg}[0] );
$cmd = $opts{module}[1];
if( $cmd ) {
	if(!$cmds{$cmd}) {
		$mesg = "Incorrect command parameter $cmd";
		outputresp;
		exit 1;
	}
	$rcmd[1] = "$PASS&".$cmds{$cmd}."&";
	$rcmd[1] .= $opts{arg}[1]."&" if( $opts{arg}[1] );
}
	
# Now we have one or two command to pass to the agent.
# We connect, and send, then listen for the response.
# Repeat for second argument if necessary


# get responses
$resp[0] = ask($rcmd[0]);
print "Response 1 was: ".$resp[0]."\n" if($DEBUG);
@rv = split /&/,$resp[0];
if( defined $offset[0] ) {
	$resp[0] = $rv[$offset[0]];
} elsif( defined $opts{ratio} ) {
	if( $rv[0] < $rv[1] ) {
	$resp[0] = $rv[0] / $rv[1] * 100.0;
	} else {
	$resp[0] = $rv[1] / $rv[0] * 100.0;
	}
	$resp[1] = $resp[0] if(!$rcmd[1]);
} else {
	$resp[0] = $rv[0];
	if( $#rv > 0 and ! $rcmd[1] ) {
		$resp[1] = $rv[1];
	}
}
if($rcmd[1] and !defined $resp[1]) {
	$resp[1] = ask($rcmd[1]);
	print "Response 2 was: ".$resp[1]."\n" if($DEBUG);
	@rv = split /&/,$resp[1];
	if( defined $offset[1] ) {
		$resp[1] = $rv[$offset[1]];
	} elsif( defined $opts{ratio} ) {
		if( $rv[0] < $rv[1] ) {
			$resp[1] = $rv[0] / $rv[1] * 100.0;
		} else {
			$resp[1] = $rv[1] / $rv[0] * 100.0;
		}
	} else {
		$resp[1] = $rv[0];
	}
}

#output responses
$mesg = '';
$mesg .= "Nagios agent version ".ask("$PASS&1&")."; ";
$mesg .= "Nagios query agent version $VERSION";

# be nice
close SOCK;

# and leave
outputresp();
exit(0);
