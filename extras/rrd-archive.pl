#!/usr/bin/perl 
# vim:ts=4
##############################################################################
# rrd-archive.pl v0.5
# S Shipway 2003,2004,2013.  Distributed under the GNU GPL
#
# This Perl script can be run on a nightly basis.
#
# This script will check the specified .cfg files, and will archive the
# corresponding .rrd files  as defined (default is to archive for one month).
# This is different from the graph 'Archive' function - this will archive
# the raww .rrd data, not the graph itself and is therefore far more
# flexible (although more costly in disk space).
#
# It will also delete expired archives - default is to keep for 1 month,
# except for the 1st of each month which is kept for a year, and the first 
# of Jan which is kept indefinitely.
#
# First change the conffile location defined below, and the perl location 
# definedin the first line.
#
# Run this script at just before midnight via cron or your favourite scheduler
# 55 23 * * * /usr/local/bin/rrd-archive.pl
#
# Usage:
#    perl rrd-archive.pl
#
# Will also read the routers.conf file, and look in the [archive] section,
# if it exists.  See the example for the options.
#
# Added options to your MRTG .cfg file:
#
# routers.cgi*Archive[targetname]: 
#   can take 'daily xxx' for some number xxx, 'monthly yyy' for some number yyy
#   to specify expiry of daily archives (in days) and monthly (in months).
#   Default is 30 days, 12 months.
#
# Steve Shipway, Oct 2003
##############################################################################

use strict;
################# CONFIGURABLE LINES START ###############
# default location of routers.conf file
my( $conffile ) = "/u01/etc/routers2.conf";
# default number of days after which to expire archived logs
my( $expiredaily ) = 31;
my( $expiremonthly ) = 12; # 1st of the month are Monthly
################# CONFIGURABLE LINES END #################

my($VERSION) = "0.5";
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

my( @now, $today );

#################################
# For RRD archives: make 2chr subdir name from filename
sub makehash($) {
    my($x);
# This is more balanced
    $x = unpack( '%8C*',$_[0] );
# This is easier to follow
#   $x = substr($_[0],0,2);
    return $x;
}

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
		$config{"routers.cgi-$_"} =~ s/[\/\\]\s*$//;
	}

}
###########################################################################
# Run the archive for the specified RRD
sub do_archive($$$) {
	my( $rrd, $expd, $expm ) = @_;
	my( $archdir, $rrdfile, $rrdpath );
	my( $newfile );
	my( $y, $m, $d, $afile, $age );

	print "--Target $rrd\n" if($debug);

	if(!$expd) { # If expiredaily is 0, then we dont archive at all.
		print "  No archiving required for this target.\n" if($debug);
		return;
	}

	# Identify and create the archive location. Should really use Basename
	if( $rrd =~ /^(.*)[\\\/]([^\\\/]+\.rrd)$/ ) {
		$rrdpath = $1; $rrdfile = $2;
	} else {
		$rrdpath =  $pathsep; $rrdfile = $rrd;
	}
	$archdir = $rrdpath.$pathsep."archive";
	if(!-d $archdir) { 
		if(!mkdir($archdir,0755)) {
			print "Unable to create directory $archdir\n";
			return;
		}
	}
	if($config{'routers.cgi-archive-mode'} and
        $config{'routers.cgi-archive-mode'}=~/hash/i ) {
		if(!-d $archdir.$pathsep.makehash($rrdfile)) { 
			if(!mkdir($archdir.$pathsep.makehash($rrdfile),0755)) {
				print "Unable to create directory $archdir/hash\n";
				return;
			} else {
				print "Created directory for hash\n";
			}
		}
		if(!-d $archdir.$pathsep.makehash($rrdfile).$pathsep.$rrdfile.".d") { 
			if(!mkdir($archdir.$pathsep.makehash($rrdfile).$pathsep.$rrdfile.".d",0755)) {
				print "Unable to create directory $archdir/hash/rrd\n";
				return;
			} else {
				print "Created directory for hash/rrd\n";
			}
		}
		$newfile = $archdir.$pathsep.makehash($rrdfile).$pathsep.$rrdfile.".d".$pathsep.$today.".rrd";
	} else {
		# do we need to create a new date directory?
		if(!-d $archdir.$pathsep.$today) { 
			if(!mkdir($archdir.$pathsep.$today,0755)) {
				print "Unable to create directory $archdir.$pathsep.$today\n";
				return;
			} else {
				print "Created directory for $today\n";
			}
		}
		$newfile = $archdir.$pathsep.$today.$pathsep.$rrdfile;
	}
	# Now we have an archive location.

	# Next, we want to archive the current .rrd file into this location.
	if( -f $newfile ) {
		print "Archive $newfile already exists!\n" if($debug);
		print "!" if(!$debug);
	} else {
		my($buf);
		print "." if(!$debug);
		if(open (CURRENT, "<$rrd") and open (NEW, ">$newfile")) {
		binmode CURRENT or die("Bad filehandle"); 
		binmode NEW or die("Bad filehandle");
		while( read CURRENT, $buf, 16384 ) { print NEW $buf; }
		close NEW;
		close CURRENT;
		print "  (A) Archived $rrdfile for $today\n" if($debug);
		} else {
			print "$rrd\n$newfile\nProblem opening files: $!\n";
		}
	}

	# Now we want to expire anything that is too old in this tree
	# This is probably not the most efficient way of achieving this
	foreach $afile (glob(
        ($config{'routers.cgi-archive-mode'} and
            $config{'routers.cgi-archive-mode'}=~/hash/i )?
		($archdir.$pathsep.makehash($rrdfile).$pathsep.$rrdfile.".d".$pathsep."*-*-*.rrd"):($archdir.$pathsep."*".$pathsep.$rrdfile)
		)) {
		$afile =~ /[\\\/](\d\d\d\d)-(\d\d)-(\d\d)(.rrd)?[\\\/]/;
		($y,$m,$d) = ($1,$2,$3);
		if(!$y) {
			# error parsing filename.  This should never happen, but does.
			print "ERROR: Cannot find yyyy-mm-dd in $afile\n";
			next;
		}
		$age = ($now[5]+1900)-$y; # years
		$age = ($age * 12) + ($now[4]+1) - $m; # months
		
		if( $d == 1 ) {
			# month aging
			if( $expm and ( $age >= $expm )) { 
				unlink($afile); 
				print "  (M) Deleted $afile\n" if($debug);
			} # zap it
		} else {
			# day aging
			$age = ($age * 30) + $now[3] - $d; # days (approx)
			# we might zap things a day early in feb though
			if( $age >= $expd ) { 
				unlink($afile); 
				print "  (D) Deleted $afile\n" if($debug);
			} # zap it
		}
	}

	# Remove any empty directories
	# We have to do this per-target since targets may have differnt
	# retention times for their archives, and may have different
	# workdirs.  Really we should make a list of unique workdirs
	# and process them after.

	foreach $afile ( glob($archdir.$pathsep."*") ) {
		rmdir $afile; # this will fail unless afile is empty
	}
}

###########################################################################


############### MAIN CODE STARTS HERE #######

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
$expiredaily = $config{'archive-keepdaily'}
	if(defined $config{'archive-keepdaily'});
$expiremonthly = $config{'archive-expiremonthly'}
	if(defined $config{'archive-expiremonthly'});
$expiremonthly = $config{'archive-keepmonthly'}
	if(defined $config{'archive-keepmonthly'});

# What day do we log as?
if( $config{'archive-asyesterday'} =~ /[y1]/i ) {
	@now = localtime(time-(24*3600));
} else {
	@now = localtime(time);
}
$today = sprintf("%04d-%02d-%02d",$now[5]+1900,$now[4]+1,$now[3]);

# Now we have the defaults, and we know which files to process.
# We can optimise our processing of the .cfg files.

foreach $pattern ( split " ",$cfgfiles ) {
#	print "$confpath$pathsep$pattern\n" if($debug);
	push @cfgfiles, glob( $confpath.$pathsep.$pattern );
}

if( @ARGV ) { @cfgfiles = @ARGV; }

foreach $thisfile ( @cfgfiles ) {
	next if(!-f $thisfile);
	open CFG,"<$thisfile" or next;
	print "Processing $thisfile\n" ;
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
		$rrd .= $pathsep.$targets{$t}->{file};
		$targets{$t}->{rrd} = $rrd;
		do_archive ( $rrd, $targets{$t}->{expd}, $targets{$t}->{expm});
	}
	print "\n" if(!$debug);

}

print "All finished.\n" ;
exit(0);
