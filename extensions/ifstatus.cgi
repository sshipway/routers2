#!/usr/bin/perl
# vim:ts=4
# ifstatus.pl v1.0
#
# This is an Extension script for the routers.cgi program.  Install it
# in your cgi-bin directory, and modify your MRTG .cfg files to call it:
#
# routers.cgi*Extension[targetname]: "Show current interface status" /cgi-bin/ifstatus.cgi camera2-sm.gif
#
# See the routers.cgi documentation for how to link this script in to your
# MRTG .cfg files.  This does not require 'insecure' mode in most cases.
#
# Remember to change the first line and the default .conf file location below
#
# Steve Shipway Jan 2006
# This script is covered by the terms of the GNU GPL.
###########################################################################
# Version 1.0: corrected bug, added number formatting
###########################################################################

use strict;
use CGI;
use Net::SNMP;

my($VERSION) = "v1.0";

# Variables
my( $conffile ) = '/u01/etc/routers2.conf';

my( $device, $community, $targetwindow, $target, $file, $backurl, $ifno )
	= ( "","","graph","","","","");
my( $routersurl, $msg );
my( $q ) = new CGI;
my( %config, %headeropts );
my( $thishost ) = $q->url();
my( $NT, $pathsep) = ( 0, '/' );
my( %portstat ) = ();

my($SHDESC ) = "1.3.6.1.2.1.2.2.1.2";
my($DESC   ) = "1.3.6.1.2.1.31.1.1.1.18";
my($SYSDESC) = "1.3.6.1.2.1.1.1.0";
my($IFINDEX) = "1.3.6.1.2.1.2.2.1.1";
my($IFDESCR) = "1.3.6.1.2.1.2.2.1.2";
my($IFTYPE ) = "1.3.6.1.2.1.2.2.1.3";
my($IFMTU  ) = "1.3.6.1.2.1.2.2.1.4";
my($IFSPEED) = "1.3.6.1.2.1.2.2.1.5";
my($IFADMINSTATUS) = "1.3.6.1.2.1.2.2.1.7";
my($IFOPERSTATUS) = "1.3.6.1.2.1.2.2.1.8";
my($IFINOCTETS) = "1.3.6.1.2.1.2.2.1.10";
my($IFOUTOCTETS) = "1.3.6.1.2.1.2.2.1.16";
my($IFINERRORS) = "1.3.6.1.2.1.2.2.1.14";
my($IFOUTERRORS) = "1.3.6.1.2.1.2.2.1.20";
my($IPIFINDEX) = "1.3.6.1.2.1.4.20.1.2";
my($IPROUTEGW) = "1.3.6.1.2.1.4.21.1.7";
my($IFDUPLEX) = "1.3.6.1.4.1.9.5.1.4.1.1.10";
my($IFNAME) = "1.3.6.1.2.1.31.1.1.1.1";

my(%DUPLEX) = ( 1=>"Force half duplex", 2=>"Force full duplex", 3=>"Disagreement with device", 4=>"Autonegotiate" );
my(%ADMINSTATUS) = ( 1=>"Up", 2=>"Down", 3=>"Testing" );
my(%OPERSTATUS) = ( 1=>"Up", 2=>"Down", 3=>"Testing" );

$thishost =~ /http:\/\/([^\/]+)\//;
$thishost = $1;

sub fmt($$) {
	my($n,$d) = @_;
	my($s) = '';

	if($n >= 1000000000 ) {
		$n /= 1000000000;
		$s = 'G';
	} elsif($n >= 1000000 ) {
		$n /= 1000000;
		$s = 'M';
	} elsif($n >= 1000 ) {
		$n /= 1000;
		$s = 'K';
	}

	return sprintf('%.'.$d.'f %s',$n,$s);
}

#######################################################################
# readconf: pass it a list of section names
sub readconf(@)
{
	my ($inlist, $i, @secs, $sec);
	
	@secs = @_;
	%config = ();

	# set defaults
	%config = ( 'routers.cgi-confpath' => ".",);

	( open CFH, "<".$conffile ) || do {
		errorpage( "Error: unable to open file $conffile");
		exit 0;
	};

	$inlist=0;
	$sec = "";
	while( <CFH> ) {
		/^\s*#/ && next;
		/^\s*\[(\S*)\]/ && do { 
			$sec = $1; $inlist=0;	
			foreach $i ( @secs ) { if ( $i eq $1 ) { $inlist=1; last; } }
			next;
		};
		if ( $inlist ) { /(\S+)\s*=\s*(\S.*?)\s*$/ and $config{"$sec-$1"}=$2; }
	}
	close CFH;
	
	# Activate NT compatibility options.
	# $^O is the OS name, NT usually produces 'MSWin32'.  By checking for 'Win'
	# we should be able to cover most possibilities.
	if ( (defined $config{'web-NT'} and $config{'web-NT'}=~/[1y]/i) 
		or $^O =~ /Win/ or $^O =~ /DOS/i  ) {
		$pathsep = "\\";
		$NT = 1;
	}

	# some path corrections: remove trailing path separators on f/s paths
	foreach ( qw/dbpath confpath graphpath graphurl/ ) {
		$config{"routers.cgi-$_"} =~ s/[\/\\]$//;
	}
	$config{"routers.cgi-iconurl"}.= '/'
		if( $config{"routers.cgi-iconurl"} !~ /\/$/);

}
#######################################################################
# read $file and get the interface details for $target
sub read_file()
{
	my( $c, $i, $f );
	if( $ifno != "" ) { # we already know it
		$portstat{'Interface Number'} = $ifno;
		return if($community) ;
	}
	$f = $config{"routers.cgi-confpath"}."$pathsep$file";
	if(! -r $f or !$target) {
		errorpage("Cannot read file $f");
		return;
	}
	open CFG, "<$f" or return;
	while( <CFG> ) {
		if( /^\s*Target\[(\S+)\]\s*:\s*(\S+):(\S+)@([^:\s]+)/i ) {
			next if($1 ne $target);
			$c = $3; $i = $2;
			$community = $c if($c);
			if( !$ifno and $i =~ /\d+/ ) { $ifno = $i;
				$portstat{'Interface Number'} = $i; last; }
			if( $i =~ /^\/([\d\.]+)/ ) {  
				$portstat{'IP Address'} = $1; last; }
			if( $i =~ /^#(\S+)/ ) {  
				$portstat{'Interface Name'} = $1; last; }
			last if($ifno);
		} elsif( /^\s*routers2?\.cgi\*Ifno\[(\S+)\]\s*:\s*(\d+)/i ) {
			next if($1 ne $target);
			$ifno = $2; 
			last;
		}
	}
	close CFG;
	return;
}
#######################################################################
# return error message if there was an error
# load up the $portstat hash, keyed on description
sub snmpquery()
{
	my( $tick, $cross );
	my( $snmp, $snmperr, $resp, $resp2 );
	$tick = $q->img({ src=>($config{'routers.cgi-iconurl'}."tick-sm.gif"),
		alt=>"Yes", border=>0});
	$cross = $q->img({ src=>($config{'routers.cgi-iconurl'}."cross-sm.gif"),
		alt=>"No", border=>0});

	($snmp, $snmperr) = Net::SNMP->session(
		-hostname=>$device, -community=>$community,
		-timeout=>4 );
	if($snmperr) { return $snmperr; }

	$resp = $snmp->get_request(
			"$IFDESCR.$ifno",
			"$IFADMINSTATUS.$ifno",
			"$IFOPERSTATUS.$ifno",
			"$IFSPEED.$ifno",
			"$IFMTU.$ifno",
			"$IFTYPE.$ifno",
			"$IFINOCTETS.$ifno",
			"$IFOUTOCTETS.$ifno",
			"$IFINERRORS.$ifno",
			"$IFOUTERRORS.$ifno"
	);
	if(!$resp) { $snmp->close; return "Unable to read device details"; }
	$portstat{"Description"} = $resp->{"$IFDESCR.$ifno"};
 	$portstat{"Errors total IN"} = $resp->{"$IFINERRORS.$ifno"};
 	$portstat{"Errors total OUT"} = $resp->{"$IFOUTERRORS.$ifno"};
 	$portstat{"Traffic total IN"} = fmt($resp->{"$IFINOCTETS.$ifno"},2)."B";
 	$portstat{"Traffic total OUT"} = fmt($resp->{"$IFOUTOCTETS.$ifno"},2)."B";
 	$portstat{"Interface Speed"} = fmt($resp->{"$IFSPEED.$ifno"},0)."bps";
 	$portstat{"MTU"} = $resp->{"$IFMTU.$ifno"}." bytes";
	$portstat{"Admin status"} = 
		($resp->{"$IFADMINSTATUS.$ifno"}==1?$tick:$cross)
		." (".$ADMINSTATUS{$resp->{"$IFADMINSTATUS.$ifno"}}.")";
	$portstat{"Operational status"} = 
		($resp->{"$IFOPERSTATUS.$ifno"}==1?$tick:$cross)
		." (".$OPERSTATUS{$resp->{"$IFOPERSTATUS.$ifno"}}.")";
	if( !defined $portstat{"Interface Name"} ) {
		$resp2 = $snmp->get_request( "$IFNAME.$ifno" );
 		$portstat{"Interface Name"} = $DUPLEX{$resp2->{"$IFNAME.ifno"}} 
			if($resp2);
	}
	if( $portstat{"Interface Name"} =~ /(\d+).*\/(\d+)$/ ) {
		$resp2 = $snmp->get_request( "$IFDUPLEX.$1.$2" );
 		$portstat{"Duplex"} = $DUPLEX{$resp2->{"$IFDUPLEX.$1.$2"}} if($resp2);
	}

	$snmp->close;
	return 0;
}
#######################################################################
sub do_footer() 
{
	print $q->hr."\n";
	print $q->a({ href=>"javascript:location.reload(true);" },
		$q->img({alt=>"Refresh", border=>0,
		src=>$config{'routers.cgi-iconurl'}."refresh.gif" }))."\n";
	print $q->hr.$q->small("$VERSION: Interface Status extension script for routers.cgi")."\n";
	print $q->end_html();
}
#######################################################################
# at this point, %portstat should hold the interface number that we query.
sub mypage()
{
	my( $javascript ) = "function RefreshMenu()
	{
	var mwin; var uopts;
	mwin = parent.menu;
	uopts = 'T';
	if( parent.menub ) { mwin = parent.menub; uopts = 't'; }
	mwin.location = '".$routersurl."?if=__none&rtr="
		.$q->escape($file)."&page=menu&xmtype=options&uopts='+uopts;
	}";

	print $q->start_html({-title=>"Current Interface Status",
		-script=>$javascript, -onLoad=>"RefreshMenu()"});

	print $q->h1("Current Interface Status");

	print "<TABLE border=2 align=center>\n";
	foreach ( sort keys %portstat ) {
		print "<TR><TD>$_</TD><TD>".$portstat{$_}."</TD></TR>\n";
	}

	print "</TABLE>\n";

	do_footer();
}

#######################################################################
sub errorpage($)
{
	my( $javascript ) = "function RefreshMenu()
	{
	var mwin; var uopts;
	mwin = parent.menu;
	uopts = 'T';
	if( parent.menub ) { mwin = parent.menub; uopts = 't'; }
	mwin.location = '".$routersurl."?if=__none&rtr="
		.$q->escape($file)."&page=menu&xmtype=options&uopts='+uopts;
	}";

	print $q->start_html({-title=>"Error",
		-script=>$javascript, -onLoad=>"RefreshMenu()"});

	print $q->h1("Unable to retrieve interface status");

	print $q->p($_[0])."\n";
	do_footer();

}
#######################################################################

# Process parameters
$device = $q->param('h') if(defined $q->param('h'));
$file   = $q->param('fi') if(defined $q->param('fi'));
$target = $q->param('ta') if(defined $q->param('ta'));
$ifno = $q->param('ifno') if(defined $q->param('ifno'));
$community = $q->param('c') if(defined $q->param('c'));
$backurl = $q->param('b') if(defined $q->param('b'));
$targetwindow = $q->param('t') if(defined $q->param('t'));
$conffile = $q->param('conf') if(defined $q->param('conf'));
$routersurl = $q->param('url') if(defined $q->param('url'));
$routersurl = "http://$thishost/cgi-bin/routers2.cgi" if(!$routersurl);

readconf('routers.cgi','web');

# HTTP headers
%headeropts = ( -expires=>"now" );
$headeropts{target} = $targetwindow if($targetwindow);
print $q->header(\%headeropts);

read_file;

if(!$target) {
	errorpage("No target given");
} elsif(!$community) {
	errorpage("Unable to identify an SNMP community for the device.");
} elsif($ifno == "") {
	errorpage("Unable to identify a valid interface on the device.");
} else {
	if( $msg = snmpquery() ) {
		errorpage("Unable to SNMP query the device.\n$msg");
	} else {
		mypage();
	}
}

# End
exit(0);
