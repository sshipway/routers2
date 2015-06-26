#!perl
# if you are in NT, you might want that to be #!perl.exe 
#
# Create the [targetnames] and [targettitles] sections for the .conf file
#
# usage: perl targetnames.pl routers.conf > newsections
#
# v0.3
#
# Uses the SNMP libraries that come with MRTG, instead of Net::SNMP,
# since NT doesnt have Net::SNMP in ActivePerl by default.
##########################################################################

use strict;
# Lets use the MRTG SNMP libraries instead
eval {
require SNMP_Session;
require BER;
require SNMP_util;
};
if($@) {
	print "## You need to have the SNMP_Session, BER and SNMP_util Perl libraries\n## in the current directory or in the Perl library path!\n";
	print "## ".$@."\n";
	exit 1;
}

$SNMP_Session::suppress_warnings = 2;

my( $conffile, %config,@cfgfiles, $pathsep );
my($SHDESC ) = "1.3.6.1.2.1.2.2.1.2";
my($DESC   ) = "1.3.6.1.2.1.31.1.1.1.18";
my($SYSDESC) = "1.3.6.1.2.1.1.1.0";
my($IFINDEX) = "1.3.6.1.2.1.4.20.1.2";

##########################################################################

#################################
# Read in confgiuration file

# readconf: pass it a list of section names
sub readconf(@)
{
	my ($inlist, $i, @secs, $sec);
	
	@secs = @_;
	%config = ();

	# set defaults
	%config = (
		'routers.cgi-confpath' => ".",
		'routers.cgi-cfgfiles' => "*.conf",
		'web-png' => 0
	);

	( open CFH, "<".$conffile ) || do {
		print "ERROR: cannot open configuration file $conffile\n";
		exit(1);
	};

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
		# note final \s* to strip all trailing spaces
		if ( $inlist ) { /(\S+)\s*=\s*(\S.*)\s*$/ and $config{"$sec-$1"}=$2; }
	}
	
	# get list of configuration files
	@cfgfiles = ();
	$pathsep = "/";
	$pathsep = "\\" if($config{'routers.cgi-NT'});
	
	foreach ( split " ", $config{'routers.cgi-cfgfiles'} ) {
		# this may push a 'undef' onto the list, if the glob doesnt match
		# anything.  We avoid this later...
		push @cfgfiles, glob($config{'routers.cgi-confpath'}.$pathsep.$_);
	}
}
##########################################################################
sub output_conf()
{
 print "\n###############################################################\n";
	print "# Put this into your $conffile file,\n";
	print "# to replace the existing targetnames and targettitles sections.\n";
	print "\n# Names gathered from existing .conf file override any found\n";
	print "# via SNMP search.\n";
	print "[targetnames]\n";
	foreach ( keys %config ) {
		/^targetnames-(.*)/ and do { print "$1 = ".$config{$_}."\n"; }
	}

	print "\n# Names gathered from existing .conf file override any found\n";
	print "# via SNMP search.\n";
	print "[targettitles]\n";
	foreach ( keys %config ) {
		/^targettitles-(.*)/ and do { print "$1 = ".$config{$_}."\n"; }
	}
	print "\n# END\n";

}

##########################################################################
# read a MRTG file, get the target and SNMP it.
sub process_file($)
{
	my($f) = @_;
	my($desc, $shdesc, $targ, $oid, $ifndx, $comm, $rtr);
	my($snmp,$snmperr,$resp);

	( open MRTG, $f ) || return;
	while ( <MRTG> ) {
		$rtr = "";
		# identify targets like  2:community@router
		if( /^\s*Target\[(\S+)\]:\s*(\d+):(\S+)@(\S+)/i ) {
			$targ = $1; $ifndx = $2; $comm = $3; $rtr = $4;
		}
		# identify targets like /a.b.c.d:community@rout
		elsif( /^\s*Target\[(\S+)\]:\s*\/(.+):(\S+)@(\S+)/i ) {
			$targ = $1; $comm = $3; $rtr = $4;
			($ifndx) = SNMP_util::snmpget("$comm\@$rtr","$IFINDEX.$2");
		}
		# default
		elsif( /^\s*Target\[(\S+)\]:\s*(.+)/i ) {
			print "# unable to parse target '$1'\n";
			next;
		}
		else {
			# we couldnt understand it
			next;
		}
		if( ! $rtr ) {
			print "# Unable to identify the router name in target '$targ'\n";
			next;
		}
		if( ! $comm) {
			print "# Unable to identify the SNMP community name in target '$targ'\n";
			next;
		}
		if( ! $ifndx ) {
			print "# Unable to identify the interface index number in target '$targ'\n";
			next;
		}

		# put it in if we found it
		($shdesc, $desc) = SNMP_util::snmpget("$comm\@$rtr",
			"$SHDESC.$ifndx", "$DESC.$ifndx" );
		$shdesc = "" if(!defined $shdesc);
		$desc = "" if(!defined $desc);
		if( !$shdesc and !$desc ) {
			print "# No SNMP descriptions available for '$targ'\n";
		} else {
		$config{"targetnames-$targ"} = $shdesc 
			if($shdesc and !defined $config{"targetnames-$targ"} );
		$config{"targettitles-$targ"} = $desc
			if($desc and !defined $config{"targettitles-$targ"} );
		}
	}
	close MRTG;
}

##########################################################################
# Main code starts here

$conffile = $ARGV[0];
if(!$conffile) {
	print "targetnames.pl ERROR:\n";
	print "Usage: perl targetnames.pl routers.conf > targetnames.conf\n";
	print "Please specify the name and location of your routers.conf file.\n";
	exit 1;
}

# get in the settings, and the ones already configured.
readconf('routers.cgi','targetnames','targettitles');

# now, we go through all of the MRTG .conf files, and read them
foreach ( @cfgfiles ) {
	process_file($_) if(defined $_);
}

# now print what we've found
output_conf;
exit 0;
