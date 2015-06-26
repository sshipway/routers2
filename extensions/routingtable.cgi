#!/usr/local/bin/perl -w
# CHANGE ABOVE PATH TO MATCH YOUR PERL LOCATION! You may remove the -w
##############################################################################.
# routingtable.cgi : Version v1.5
#
# Display the routing table for a specifiecd router
#
# This code is covered by the Gnu GPL.  See the README file, or the Gnu
# web site for more details.
# Developed and tested with RRDTool v1.0.28, Perl 5.005_03, under Linux (RH6.1)
# Also tested with ActivePerl 5.6 with Apache under NT
#
# This requires Net::SNMP to be installed.
# First read the information in INSTALL and README about the security 
# issues of using this extension.
#
# Only Netscape appears to correctly support server push with MIME
# multipart/replace - so, this script detects Netscape, and uses normal 
# delivery if Netscape is not sensed.
#
##############################################################################.
use strict;
use CGI;        # for CGI
use Net::SNMP;  # ActivePerl users may need this uncommented
##############################################################################.
my ($VERSION) = "v1.5";
my ($APPURL ) = "http://www.steveshipway.org/software/";
my ($APPMAIL) = "mailto:steve\@steveshipway.org";
##############################################################################
my( %protocol ) = ( 1=>"Other", 2=>"Local", 3=>"Net Mgmt",
	4=>"ICMP", 5=>"EGP", 6=>"GGP", 7=>"Hello", 8=>"RIP", 9=>"IS-IS",
	10=>"ES-IS", 11=>"IGRP", 12=>"bbnSpfIgp", 13=>"OSPF", 14=>"BGP",
	15=>"15", 16=>"16", 17=>"17", 18=>"18", 19=>"19", 20=>"20" );
my( %types    ) = ( 1=>"Other", 2=>"Invalid", 3=>"Direct", 4=>"Indirect" );

my( $Netscape ) = 0;
my( $agent, $back, $router, $community, %headeropts );
my( %table ) = ();
my( $IP    ) = "1.3.6.1.2.1.4"; # oid of ip in mib 
my( $ROUTEENTRY ) = "$IP.21.1";
my( $message ) = "";
my( $BOUNDARY ) = "boundary--fhdsjkgfdrfy78975j0fhnrdhsdh";
my( $UPDATE ) = 4; # refresh 'working' page in this many seconds
my( $thishost , $javascript, $file, $routersurl );

# initialize CGI
use vars qw($q);
$q = new CGI;
$q->import_names('CGI');

my $meurl = $q->url();

##########################
# for parts
sub start_section()
{
print "Content-Type: text/html\n\n";
}
sub end_section()
{
print "\n--$BOUNDARY\n";
}
sub end_multipart()
{
print "\n--$BOUNDARY--\n";
}
##########################
# show progress of table load...
sub progress($$)
{
	return if(!$Netscape);

	start_section();
	print $q->start_html();
	print $q->h1("<BLINK>Working...</BLINK>");

	print $q->p("Loaded ".$_[0]." MIB entries, and ".$_[1]." routes...")."\n"
		if($_[0]);
	print $q->p("If you have a large routing table, or the remote router is on a distant or slow network, this may take a long time to complete.  There will be approximately 12 MIB entries for each defined route.")."\n";
	print $q->end_html();
	end_section();
}

##########################
# An entry in the table list is a hash:
# dest, mask, cost, gw
##########################
# collect the snmp data into %table
# we snmpwalk ipRouteMetric1, ipRouteNextHop, ipRouteType, ipRouteProto,
# and ipRouteMask, loading the data into the hash as we go.
my( $ROUTEDEST ) = 1;
my( $ROUTEMETRIC ) = 3;
my( $ROUTENEXTHOP ) = 7;
my( $ROUTETYPE ) = 8;
my( $ROUTEPROTO ) = 9;
my( $ROUTEAGE ) = 10;
my( $ROUTEMASK ) = 11;
sub fetch_table()
{
	my($snmp, $snmperr, $resp);
	my( $k, $ip, $mib,$sec, $c, $u, $r );
	my( $lasttime, $thistime );

	($snmp, $snmperr) = Net::SNMP->session(
		-hostname=>$router, -community=>$community,
		-timeout=>4 );
	if($snmperr) {
		$message = $snmperr;
		return;
	}

	$c = $r = 0;
	progress(0,0);
	$lasttime = time;
	$resp = $snmp->get_next_request( $ROUTEENTRY );
	if(!defined $resp ) {
		$message = $snmp->error();
		$snmp->close();
		return;
	}
	while( defined $resp ) {
		foreach $k ( keys %$resp ) {
			$k =~ /^(.+)\.(\d+)\.(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
			$ip = "$3.$4.$5.$6";
			$sec = $1;
			$mib = $2;
			last if( $sec ne $ROUTEENTRY );
			$c++; 
			if( $Netscape and (time - $lasttime) > $UPDATE ) 
				{ progress($c,$r); $lasttime = time; };
			if( $mib == $ROUTEDEST ) { 	
				if($resp->{$k} eq "0.0.0.0" ) {
					$table{$ip}{dest} = "default"; 
				} else {
					$table{$ip}{dest} = $resp->{$k}; 
				}
				$r++;
				next; 
			}
			if( $mib == $ROUTEMETRIC ) { 
				$table{$ip}{metric} = $resp->{$k}; next; }
			if( $mib == $ROUTENEXTHOP ) { 
				$table{$ip}{gw} = $resp->{$k}; next; }
			if( $mib == $ROUTETYPE ) { 
				$table{$ip}{type} = $types{$resp->{$k}}; next; }
			if( $mib == $ROUTEPROTO ) { 
				$table{$ip}{proto} = $protocol{$resp->{$k}}; next; }
			if( $mib == $ROUTEAGE ) { 
				$table{$ip}{age} = $resp->{$k}; next; }
			if( $mib == $ROUTEMASK ) { 
				$table{$ip}{mask} = $resp->{$k}; next; }
		}
		last if( $sec ne $ROUTEENTRY );
		$resp = $snmp->get_next_request( keys %$resp );
	}
	$snmp->close;
}
##########################
# print it out in HTML
sub print_table()
{
	my( $bg, $fg, %c, $s, $e );

	print "<TABLE width=100% align=center border=1 cellspacing=1 cellpadding=1>\n";
	%c = (bgcolor=>"#ccccff");

	print $q->Tr(
		$q->th(\%c,"Destination").$q->th(\%c,"Netmask")
		.$q->th(\%c,"Gateway").$q->th(\%c,"Metric")
		.$q->th(\%c,"Source").$q->th(\%c,"Type")
	)."\n";
	
	foreach ( sort keys %table ) {
		($bg,$fg) = ( "#ffffff","#000000" );
		$s = $e = "";
		$fg = "#0000ff" if( $table{$_}{proto} eq $protocol{2} ); # Local
		$fg = "#00cc00" if( $table{$_}{proto} eq $protocol{3} ); # netmgmt
		$bg = "#cccccc" if( $table{$_}{type} eq $types{2} ); # inactive
		$bg = "#ffffcc" if( $table{$_}{type} eq $types{3} ); # direct
		# lets support everything
		%c = ( bgcolor=>$bg, color=>$fg, fgcolor=>$fg ); 
		$s = "<FONT color=$fg>";
		$e = "</FONT>";
		print $q->Tr(
			$q->td(\%c,$s.$table{$_}{dest}.$e)
			.$q->td(\%c,$s.$table{$_}{mask}.$e)
			.$q->td(\%c,$s.$table{$_}{gw}.$e)
			.$q->td(\%c,$s.$table{$_}{metric}.$e)
			.$q->td(\%c,$s.$table{$_}{proto}.$e)
			.$q->td(\%c,$s.$table{$_}{type}.$e)
		),"\n";
	}

	print "</TABLE>";
	if($message) { print $q->p($q->b($message)); }
}
##########################
sub do_footer()
{
	print $q->hr,$q->small("routingtable.cgi Version $VERSION : &copy; "
		.$q->a({href=>$APPMAIL},"Steve Shipway")
		." 2001,2002 : ".$q->a({ href=>$APPURL, target=>"_top" },$APPURL)
	),"\n";
}

##########################
# If we get a bad page request

sub do_bad()
{
	print $q->start_html({title=>"Error"});
	print $q->h1("Error");
	print $q->p("Sorry - unable to show the routing table for this router.");
	do_footer();
	print $q->end_html();
}

########################################################################
# Initialise parameters

# are we netscape??
$agent = $ENV{HTTP_USER_AGENT};
$Netscape = 1 if( $agent =~ /Mozilla/ and $agent !~ /MS|Microsoft|Chrome/ );

$file = $q->param("fi");
$router = $q->param("r");
$router = $q->param("h") if(!$router);
$router = $q->param("ip") if(!$router);
$community = $q->param("c");
$back = "";
$back = $q->param("b") if(defined $q->param("b"));
$meurl =~ /http:\/\/([^\/]+)\//;
$thishost = $1;
if($thishost) {
	$routersurl = "http://$thishost/cgi-bin/routers2.cgi";
} else {
	$routersurl = "routers2.cgi";
}
$routersurl = $q->param("url") if ( defined $q->param('url') );
%headeropts = (-expires=>"+5min");
$headeropts{-target} = $q->param("t") if( $q->param("t") );
if($Netscape) {
$headeropts{-type} = 'multipart/x-mixed-replace; boundary="'.$BOUNDARY.'"';
} else {
$headeropts{-type} = 'text/html';
}
$| = 1; $CGI::DISABLE_UPLOADS = 1;
print $q->header( %headeropts );
print "\n--$BOUNDARY\n" if($Netscape);

eval { require Net::SNMP; } ;
if($@) {
	start_section() if($Netscape);
	print $q->start_html({title=>"Error"});
	print $q->h1("Net::SNMP missing");
	print "Unable to run routingtable extension because the Perl module "
		.$q->b("Net::SNMP")." was not found.<p>"
		.$q->code($@)."\n";
	print $q->p($q->a({href=>$back,target=>"_self"},"Return to previous")),"\n"
		if($back);
	do_footer;
	print $q->end_html();
	end_multipart() if($Netscape);
	exit(0);
}

if( !$router or !$community ) {
	start_section() if($Netscape);
	do_bad();
	end_multipart() if($Netscape);
	exit(0);
}

fetch_table();

# This assumes that the routingtable and routers2 scripts are on the same 
# server, and that the routers2.cgi script has not been renamed.  This may
# not be the case.  It may be better to parse the URL up to the ? and add
# different options?
$javascript = "function RefreshMenu()
	{
		var mwin;
		var uopts;
		uopts = 'T';
		mwin = parent.menu;
		if( parent.menub ) { mwin = parent.menub; uopts = 't'; }
		mwin.location = '".$routersurl."?if=__none&rtr="
		.$q->escape($file)."&page=menu&xmtype=options&uopts='+uopts;
	}";
start_section() if($Netscape);
print $q->start_html({title=>"Routing table for $router",
	script=>$javascript,onLoad=>"RefreshMenu()"});
print $q->h1("Routing table: $router"),"\n";
print_table();
if($back) {
	print $q->p($q->a({href=>$back,target=>"_self"},"Return to previous")),"\n";
}
do_footer();
print "\n<!-- version $VERSION -->\n";
print $q->end_html();
end_multipart() if($Netscape);
exit(0);
