#!/usr/bin/perl -w
# vim:ts=4
##############################################################################
# rrd-archive-clean.pl v0.3
# S Shipway 2004.  Distributed under the GNU GPL
#
# This script will identify orphaned rrd archives, and archives for targets
# that have 'no archive' configured.  It will then delete them.
# It will not delete expired archives -- rrd-archive will take care fo that.
#
# Usage:
#    perl rrd-archive-clean.pl
#
# Will also read the routers.conf file, and look in the [archive] section,
# if it exists.  See the example for the options.
#
# Added options to your MRTG .cfg file:
#
# routers.cgi*Archive[targetname]: 
#   can take 'daily xxx' for some number xxx, 'monthly yyy' for some number yyy
#   to specify expiry of daily archives (in days) and monthly (in months).
#   Default is 31 days, 12 months.
#
# Steve Shipway, Jan 2004
#
# Options:
#  -F : do it for real
#  -n : show filenames that would/will be deleted
#  -b : do NOT also delete the base file (IE, archives only)
#
# 0.3: May 2012 - fix correct expiry of old archives
##############################################################################

use strict;
use Date::Calc;
################# CONFIGURABLE LINES START ###############
# default location of routers.conf file
my( $conffile ) = "/u01/etc/routers2.conf";
# default number of days after which to expire archived logs
my( $expiredaily ) = 31;
my( $expiremonthly ) = 12; # 1st of the month are Monthly
################# CONFIGURABLE LINES END #################

my($forreal) = 0;
my($printname) = 0;
my($basefiles) = 1;
my(@cfgfiles) = ();
my($pattern, $thisfile);
my($workdir, $rrd, $opt );
my($expd, $expm);
my(%targets,$t);
my( %config );
my( $NT ) = 0;
my( $pathsep ) = "/";
my( $confpath, $cfgfiles );
my( $debug ) = 0;
my(%paths) = ();
my(%valid) = ();
my($apath);
my($df)=0;
my($candidate);
my(@now);

###########################################################################
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
###########################################################################

sub processfile($) {
	my $candidate = $_[0];
		if(( $candidate =~ /[\\\/]([^\\\/]+)\.rrd\.d[\\\/]/ ) 
			or ( $candidate =~ /[\\\/]([^\\\/]+)\.rrd$/ )) {
			# found it
			$t = $1;
			if($basefiles and (!$valid{$t} or $valid{$t}<2)) {
				# zap it as we keep no archives for this target
				print " Removing archive\n" if($printname);
				print "!" if(!$printname);
				if($forreal) { unlink $candidate; }
				$df++;
			} elsif( $candidate =~ /[\\\/](\d\d\d\d)-(\d\d)-(\d\d)[\\\/\.]/ ) {
				# is it too old?
				my($y,$m,$d)=($1,$2,$3);
				if($d == 1) { # monthly check 
					my $mo = ($now[4]+1-$m+12*($y-1900-$now[5]));
					if( $mo > $expiremonthly ) {
						# delete!
						print " Removing - $mo months\n" if($printname);
						print "!" if(!$printname);
						if($forreal) { unlink $candidate; }
						$df++;
					}
				} else {
					my $do = Date::Calc::Delta_Days($y,$m,$d,$now[5]+1900,$now[4]+1,$now[3]);
					if( $do > $expiredaily ) {
						# delete!
						print " Removing - $do days\n" if($printname);
						print "!" if(!$printname);
						if($forreal) { unlink $candidate; }
						$df++;
					}
				}
			}
		} else {
			# we cant identify it, best to keep it then
			print "?" if(!$printname);
		}
}

############### MAIN CODE STARTS HERE #######

$|=1;

# get parameters
print "Reading configuration\n" if($debug);
readconf('routers.cgi','web','archive');

$confpath = $config{'routers.cgi-confpath'};
$confpath = $config{'archive-confpath'}
	if(defined $config{'archive-confpath'});
$cfgfiles = $config{'routers.cgi-cfgfiles'};
$cfgfiles = $config{'archive-cfgfiles'}
	if(defined $config{'archive-cfgfiles'});
if(! -d $confpath ) {
	print "Error: MRTG directory $confpath does not exist.\n";
	exit 1;
}
$expiredaily = $config{'archive-expiredaily'}
	if(defined $config{'archive-expiredaily'});
$expiremonthly = $config{'archive-expiremonthly'}
	if(defined $config{'archive-expiremonthly'});

# Now we have the defaults, and we know which files to process.
# We can optimise our processing of the .cfg files.

foreach $pattern ( split " ",$cfgfiles ) {
#	print "$confpath$pathsep$pattern\n" if($debug);
	push @cfgfiles, glob( $confpath.$pathsep.$pattern );
}

while ( @ARGV and $ARGV[0]=~/^-/ ) {
	if( @ARGV and $ARGV[0] eq '-F' ) {
		$forreal = 1;
		shift @ARGV;
		next;
	}
	if( @ARGV and $ARGV[0] eq '-n' ) {
		$printname = 1;
		shift @ARGV;
		next;
	}
	if( @ARGV and $ARGV[0] eq '-b' ) {
		$basefiles = 0;
		shift @ARGV;
		next;
	}
	print "Option '".$ARGV[0]."' not known.\n";
	exit(1);
}

@cfgfiles = @ARGV if(@ARGV); 

if(!$forreal) {
	print "NOTE: Running in test mode only: not deleting things for real.\nUse -F option to actually delete orphaned files.\n";
}
print "Default expiry: DAILY($expiredaily), MONTHLY($expiremonthly)\n";

print "Processing configuration files\n" ;
foreach $thisfile ( @cfgfiles ) {
	next if(!-f $thisfile);
	open CFG,"<$thisfile" or next;
	print ".";
	$workdir = $config{'routers.cgi-dbpath'}; # default
	%targets = ( '_' => { expd => $expiredaily, expm => $expiremonthly });
	while ( <CFG> ) {
		if( /^\s*Include\s*:\s*(\S+)/i ) { push @cfgfiles,$1; next; }
		if( /^\s*WorkDir\s*:\s*(\S+)/i ) {
			$workdir = $1; next;
		}
		if( /^\s*Directory\[(\S+)\]\s*:\s*(\S+)/i ) {
			$t = lc $1;
			$targets{$t} = {} if(!defined $targets{$t});
			$targets{$t}->{directory} = $2;
			next;
		}
		if( /^\s*Target\[(\S+)\]/i ) {
			$t = lc $1;
			$targets{$t} = {} if(!defined $targets{$t});
			$targets{$t}->{file} = "$t.rrd";
			next;
		}
		if( /^\s*routers\.cgi\*Archive\[(\S+)\]\s*:\s*(\S.+)/i ) {
			$t = lc $1;
			$opt = $2;
			($expd, $expm) = ($expiredaily, $expiremonthly);
			if( $opt =~ /no/i ) {
				($expd, $expm) = (0,0);
			} elsif( $opt =~ /daily/ or $opt =~ /monthly/) {
				if( $opt =~ /daily\s+(\d+)/i ) { $expd = $1; }
				if( $opt =~ /monthly\s+(\d+)/i ) { $expm = $1; }
			} elsif( $opt =~ /(\d+)/i ) { $expd = $1; }
			$targets{$t}->{expd} = $expd;
			$targets{$t}->{expm} = $expm;
			next;
		}
	}
	close CFG;
	# now process the archiving
	foreach $t ( keys %targets ) {
		next if(!defined $targets{$t}->{file}); # skip dummy ones
		foreach ( keys %{$targets{'_'}} ) {
			$targets{$t}->{$_} = $targets{'_'}->{$_}
				if(!defined $targets{$t}->{$_});
		}
		$rrd = $workdir;
		$rrd .= $pathsep.$targets{$t}->{directory} if(defined $targets{$t}->{directory});
		$apath = $rrd.$pathsep."archive";
		$paths{$apath} = 1 if(!defined $paths{$apath} and $targets{$t}->{expd});
		$rrd .= $pathsep.$targets{$t}->{file};
		$targets{$t}->{rrd} = $rrd;
		$valid{$t} = 1; # keep the root
		$valid{$t} = 2 if($targets{$t}->{expd}); # keep archives
	}

}
print "\n";

# Now, keys(%valid) holds a list of valid targetnames.
#      keys(%paths) holds a list of archive directories
if($basefiles) {
print "Checking the root .rrd files \n";
foreach ( glob($config{'routers.cgi-dbpath'}.$pathsep.'*.rrd') ) {
	# find the targetname
	if( /[\\\/]([^\\\/]+)\.rrd$/ ) {
		$t = $1;
		if(!$valid{$t}) {
#			print "\nRemoving $_\n";
			if($forreal) { unlink $_; }
			if($printname) { print "$_\n"; }
			else { print "!"; }
			$df++;
		}
	} else {
		print "?";
	}
}
print "\n";
}

print "Identifying archives to delete\n";
@now = localtime(time);
foreach $apath ( keys %paths ) {
	print ">" if(!$printname);
	print "Building list for $apath\nWait..." if($printname);
	if($config{'routers.cgi-archive-mode'}
            and $config{'routers.cgi-archive-mode'} =~ /hash/i ) {
		my $cdir;
		foreach $cdir ( glob( $apath.$pathsep."*".$pathsep."*.d") ) {
			print "\r                                                                            \rArchive $cdir " if($printname);
			foreach $candidate ( glob( $cdir.$pathsep.'*.rrd' ) ) {
				print "\r                                                                            \r$candidate " if($printname);
				processfile($candidate);
			}
		}
	} else {
		foreach $candidate ( glob( $apath.$pathsep.'*'.$pathsep.'*.rrd') ) {
			# find the targetname
			print "\r                                                                            \r$candidate " if($printname);
			processfile($candidate);
		}
	}
}
print "\n";

print "All finished ($df files ";
print "would have been " if(!$forreal);
print "deleted).\n" ;
exit(0);
