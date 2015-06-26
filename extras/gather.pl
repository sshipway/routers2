#!/usr/bin/perl 
#
# gather.pl
#
# Collect all the data from servers in the  .conf file, and update the 
# rrd files.  Run this script every 5 minutes via the cron daemon.  It can be
# run as any user with write permission to the rrd files and directory.
#
# For backwards compatibility here, this requires RRDTool v1.0.25 or later
# If this is a problem, remove the RRDs::info test and just use the full 
# update.
#
# To use this, you need to enable the stuff at the end of the routers.conf
# and also install the getstats.sh on the monitored systems.  Only monitors
# UNIX servers at the moment.
#
# DONT FORGET TO CHANGE THE CONF LINE BELOW!!

use strict;
use RRDs;
use IO::Socket;

my ( @servers, $us, $sy, $wa, $pa, $au );
my ( %config, $conffile, $pid );

############################################################################
# YOU MUST CHANGE THIS LINE!!!
$conffile = "/usr/local/etc/routers2.conf";
############################################################################

my ( $DATAVER ) = 1;

#################################
# Read in confgiuration file

# readconf: pass it a list of section names
sub readconf(@)
{
	my ($inlist, $i, @secs, $sec);
	
	@secs = @_;
	%config = ();
	@servers = ();

	( open CFH, "<".$conffile ) || return;

	$inlist=0;
	$sec = "";
	while( <CFH> ) {
		/^\s*#/ && next;
		/\[(\S*)\]/ && do { 
			$sec = $1;
			$inlist=0;	
			foreach $i ( @secs ) {
				if ( $i eq $1 ) { $inlist=1; last; }
			}
			next;
		};
		if ( $inlist and /(\S+)\s*=\s*(\S.*)$/ ) {
			$config{"$sec-$1"}=$2; 
			push @servers, $1 if( $sec eq "servers" );
		}
	}
}

############################
# Create and update RRD files

sub create_rrd($)
{
	my($err);
	
	print "Creating RRD database for $_[0].\n";

	RRDs::create( "$config{'routers.cgi-dbpath'}/$_[0].rrd",
		qw/RRA:AVERAGE:0.5:1:400 RRA:AVERAGE:0.25:6:400 RRA:AVERAGE:0.25:24:400 RRA:AVERAGE:0.25:288:400 RRA:MAX:0.5:1:400 RRA:MAX:0.25:6:400 RRA:MAX:0.25:24:400 RRA:MAX:0.25:288:400/,
		qw/DS:user:GAUGE:600:0:100 DS:system:GAUGE:600:0:100 DS:wait:GAUGE:600:0:100 DS:page:GAUGE:600:0:10000 DS:total:GAUGE:600:0:100 DS:usercount:GAUGE:600:0:500/ );

	$err = RRDs::error;

	print "Error creating $_[0] RRD: $err\n" if($err);
}

sub fetch_data($)
{
	my( $os, $v, $sock, $rv, $buf, $svr, $port );

#	print "Fetching data\n";

	$svr = $_[0];

	$us = $sy = $wa = $pa = $au = "U"; # set unknown default

	$port = getservbyname 'stat', 'tcp';
	$port = 3030 if(!$port);
	
	$sock = new IO::Socket::INET(PeerAddr=>$svr,PeerPort=>$port,Proto=>'tcp');
	if( ! $sock ) {
		print "Failed to connect to $svr.\n";
		return;
	}
	
	$rv = "";
	if ( defined ( $buf = <$sock> ) ) { 
		chomp $buf;
#		print "[$buf]";
		$rv .= $buf; 
	}
	close( $sock );
#	print "Received [$rv] from $svr\n";

	( $v, $os, $pa, $us, $sy, $wa, $au, $buf ) = split /:/, $rv, 8;

	print "$svr: $buf\n" if($buf);
	if( !$v or $v > $DATAVER ) {
		print "Bad version received from $svr: $v\n";
		$us = $sy = $wa = $pa = $au = "U"; # set unknown default
	} elsif ( $au =~ /U/ ) { $au = 'U'; } else { $au = 0 + $au ; }
}

sub update_rrd($)
{
	my($err,$tot);
	my( $hash, $svr );

	$svr = $_[0];

#	print "Updating RRD\n";

	if( $us eq "U" or $sy eq "U" or $wa eq "U" ) {
		$tot="U";
	} else {
		$tot = $us + $sy + $wa;
	}

#	print "[$config{'routers.cgi-dbpath'}/$svr.rrd]" ;
	$hash = RRDs::info  "$config{'routers.cgi-dbpath'}/$svr.rrd" ;
	
	if ( $$hash{'ds[usercount].type'} ) {
		RRDs::update ( "$config{'routers.cgi-dbpath'}/$svr.rrd",
		 "--template", "user:system:wait:total:page:usercount",
		 "N:$us:$sy:$wa:$tot:$pa:$au" );
	} else {
		print "Warning: $svr has old format RRD records.\n";
		RRDs::update ( "$config{'routers.cgi-dbpath'}/$svr.rrd",
		 "--template", "user:system:wait:total:page",
		 "N:$us:$sy:$wa:$tot:$pa" );
	}

	$err = RRDs::error;

	if($err) {
		print "Error updating $svr RRD: $err\n" ;
	}
}

#########################################################################
# Main Code Starts Here

autoflush STDOUT 1;

# Get configuration
readconf('servers','routers.cgi');

# Process each server
foreach ( @servers ) {
#	print "Server $_ : \n";

	create_rrd( $_ ) if ( ! -f "$config{'routers.cgi-dbpath'}/$_.rrd" );
	$pid = fork ;
	if(!defined $pid) {
		print "fork: $!\n";
	} else {
		if(! $pid ) {
			# fork off each test!
			fetch_data( $_ );
			update_rrd( $_ );
			exit 0;
		}
	}
}

exit 0;
