#!/usr/bin/perl
#
# This Perl script can be run on a nightly basis.
# It checks the Graphs directory, and deletes and graph that is past its
# useful age.  It can optionally also expire any archived graphs.
#
# Before using, remember to change the first line and the configurable lines.
#
# Usage:
#    perl graphprune.pl
#
# Will also read the routers.conf file, and look in the [graphprune] section,
# if it exists, and will take the archmaxage parameter (defined below) or
# an override for the graphdir parameter.
#
# Steve Shipway, May 2002

################# CONFIGURABLE LINES START ###############
# location of routers.conf file
my( $conffile ) = "/usr/local/etc/routers2.conf";
# number of days after which to expire archived graphs
# Use 0 to mean 'do not expire'.
my( $archmaxage ) = 90;
################# CONFIGURABLE LINES END #################

my( %config );
my( $NT ) = 0;
my( $pathsep ) = "/";
my( $c, $f, $graphdir, $age );
my( $debug ) = 0;

# readconf: pass it a list of section names
sub readconf(@)
{
	my ($inlist, $i, @secs, $sec);
	
	@secs = @_;
	%config = ();

	# set defaults
	%config = ( 'routers.cgi-confpath' => ".",);

	( open CFH, "<".$conffile ) || do {
		print "Error: unable to open file $conffile\n";
		exit(0);
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
		# note final \s* to strip all trailing spaces (which doesnt work 
		# because the * operator is greedy!)
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

}


############### MAIN CODE STARTS HERE #######

# get parameters
readconf('routers.cgi','web','graphprune');

$graphdir = $config{'routers.cgi-graphpath'};
$graphdir = $config{'graphprune-graphpath'}
	if(defined $config{'graphprune-graphpath'});
$archmaxage = $config{'graphprune-archmaxage'}
	if(defined $config{'graphprune-archmaxage'});
if(! -d $graphdir ) {
	print "Error: Graph directory $graphdir does not exist.\n";
	exit 1;
}
if( ! -w $graphdir ) {
	print "Error: You do not have permission to delete old graphs.\n";
	exit 1;
}

# check all saved graphs for zappability
$c = 0;
foreach $f (glob($graphdir.$pathsep."*.gif"), 
	glob($graphdir.$pathsep."*.png")) {
	next if(!defined $f or ! -f $f );
	$age = (time - (stat $f)[9])/3600; # hours since modify
	if( $f =~ /-ys?-/ ) {
		if($age > 23 ) { 
			unlink $f; # delete yearly graphs older than one day
			$c += 1;
		} elsif($debug) { print "$f is OK ($age hrs)\n"; }
	} else {
		if($age >= 1) { # delete all 6/d/w/m files an hour old.
			unlink $f;
			$c += 1;
		} elsif($debug) { print "$f is OK ($age hrs)\n"; }
	}
}
print "Info: Cleaned up $c file(s) in graphs directory.\n";

exit (0) if(! $archmaxage );

# Now clean up the archive.
sub cleandir($)
{
	my ( $age, $f );
	my ( $d ) = shift @_;
	print "Checking dir $d\n" if($debug);
	foreach $f ( glob( $d.$pathsep.'*' ) ) {
		if( -d $f ) { &cleandir($f); next; }
		next if( $f !~ /\.(gif|png)$/ );
		$age = (time - (stat $f)[9])/(3600*24); # days since modify
		if( $age >= $archmaxage ) {
			unlink $f;
			$c += 1;
		} elsif($debug) { print "$f is OK ($age days)\n"; }
	}
}

$c = 0;
cleandir( $graphdir );
print "Info: Cleaned up $c old archive graph(s)\n";
exit(0);
