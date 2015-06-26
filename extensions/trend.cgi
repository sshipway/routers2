#!/usr/bin/perl 
##!/usr/bin/speedy 
# vim:ts=4
# trend.cgi
#    Generate a trending graph, based on yearly data, for the specified
#    mrtg target.  A module to be called from routers.cgi Extension interface
# 
#  Copyright S Shipway 2003
#  version 0.1: first working attempt, released with routers.cgi v2.13
#  version 0.2: fix bugs (routers.cgi v2.13a)
#  version 0.3: Directory[] directive was broken
#  version 0.4: some reporting issues
#  version 0.5: error checking, more comments etc
#  version 0.6: not much
#  version 0.7: more configuration in routers2.conf, better error messages
#  version 1.0: Removed external rrdtool exe call and XML stage.  Now all
#               processing of the temporary rrd is done internally. Also,
#               appears to be Windows compatible.
#  version 1.1: added different base options
#  version 1.2: added decolon function for RRD v1.2.x compatibility
#  version 1.3: added stylesheet support
#  version 1.4: added MAX/AVG option
#  version 1.5: more RRD1.2.x support
#  version 2.0: more RRD version compatibility stuff
#          2.1: better libadd support
#
##########################################################################
# To install this script:
#   Change the #! line at the beginning to give correct Perl location
#   Set correct Temporary working directory in Constants 
#      $TMPPATH 
#   Copy trend.cgi into web server cgi-bin, correct permissions
#   Define an Extension in the .cfg file for a particular target
#      routers.cgi*Extension[targetname]: "Trending analysis" /cgi-bin/trend.cgi graph-sm.gif
#   Try out different decay factors
#
#  You can put 'trendurl = /cgi-bin/trend.cgi' into your routers2.conf
#  to automatically add trending analysis to all targets (undocumented)
#
##########################################################################

use strict;
use CGI;
use FileHandle;
use Text::ParseWords;
use File::Basename;

# Constants
#########################################################################
###################### CHANGE THESE TO MAKE IT WORK ####################
#########################################################################
# This is the temporary working directory.  Must have write permissions.
my( $TMPPATH ) = "/tmp"; # eg: "C:\\temp" for windows
#########################################################################
##################### END OF SECTION YOU HAVE TO CHANGE #################
#########################################################################
my( $DEFPREDICT ) = 50;
my( $VERSION ) = "2.1";
# decay factor can be between 1.0 and 0.  0=history unimportant, 1.0=all
# data equally important.
my( @decays ) = ( 1.0, 0.99, 0.95, 0.9, 0.8, 0.66, 0.5 );

###GLOBAL#START########################################################
# Global Variables (change to our() for speedycgi and perl 5.8)
# To log errors and progress, set debug=1 and set LOG
my( $debug ) = 0; # override in routers2.conf 'debug = 1'
my( $LOG   ) = "$TMPPATH/trend.log"; # this must be writeable! override with
                                     # routers2.conf 'logfile = ...'
my( $DECAY   ) = 0.95;
my( $PREDICT ) = $DEFPREDICT;
my( $BASE    ) = 0; # 0=current, 1=average
my( $device, $community, $targetwindow, $target, $file, $backurl )
	= ( "","public","graph","","","");
my( $conffile ) = "/u01/etc/routers2.conf"; # overridden by passed parameters
my( $routersurl ) = '';
my( $q ) = new CGI;
my( %headeropts ) = ();
my( %config ) = ();
my( $authuser ) = '';
my( $pathsep ) = '/';
my( %target ) = ();
my( $tempfile ) = '/tmp/trend.foo';
my( $ds, $rrddata , $starttime, $endtime, $interval) = ('','','','','');
my( $trendstart, $trenddelta ); # array references
my( $dwmy ) = 'm';
my( %interfaces );
my( $workdir ) = '';
my( $monthlylabel ) = '%W';
my( $dailylabel ) = '%H';
my( @params ) = ();
my( $graphsuffix ) = 'png';
my( $lastupdate ) = 0;
my( $gstyle ) = 'l2';
my( $ksym, $k, $M, $G ) = ( 'K', 1024,1024000, 1024000000);
my( @info ) = ();
my( $cfile );
my( $fgcolour, $bgcolour, $linkcolour ) = ( "#000000", "#ffffff", "#000080" );
my( $consolidation, $conspfx ) = ("AVERAGE","Avg");
#my( $consolidation, $conspfx ) = ("MAX","Max");
my( $myurl ) = $q->url();
###GLOBAL#END##########################################################


#################################
# For RRD v1.2 compatibility: remove colons for COMMENT directive if
# we are in v1.2 or later, else leave them there
sub decolon($) {
    my($s) = $_[0];
    return $s if($RRDs::VERSION < 1.002 );
    $s =~ s/:/\\:/g;
    return $s;
}
 
#######################################################################
sub errlog($)
{
	return if(!$debug);
	open LOG, ">>$LOG" or return;
	LOG->autoflush(1);
	print LOG "".localtime(time).": ".(join " ",@_)."\n";
	close LOG;
}
#######################################################################
sub inlist($@)
{
	my($pat) = shift @_;
	return 0 if(!defined $pat or !$pat or !@_);
	foreach (@_) { return 1 if( $_ and /$pat/i ); }
	return 0;
}

######################
# calculate short date string from given time index

sub shortdate($)
{
	my( $dformat ) = "%c"; # windows perl doesnt have %R
	my( $datestr, $fmttime ) = ("",0);
	return "DATE ERROR 1" if(!$_[0]);
	$fmttime = $_[0];
	$fmttime = time if(!$fmttime);	
	my( $sec, $min, $hour, $mday, $mon, $year ) = localtime($fmttime);
	# try to get local formatting
	$dformat = $config{'web-shortdateformat'}
		if(defined $config{'web-shortdateformat'});
	$dformat =~ s/&nbsp;/ /g;
	eval { require POSIX; };
	if($@) {
		$datestr = $mday."/".($mon+1)."/".($year-100);
	} else {
		$datestr = POSIX::strftime($dformat,
			0,$min,$hour,$mday,$mon,$year);
	}
	return "DATE ERROR 2" if(!$datestr);
	return $datestr;
}

#################################
# For string trims.  Remove leading and trailing blanks
sub trim($)
{
	my($x)=$_[0];
	$x=~s/\s*$//;
	$x=~s/^\s*//;
	$x;
}
#############################################################################
# reformat to look nice
# params -- number, fix flag, integer flag
sub doformat($$$)
{
	my( $sufx ) = "";
	my( $val, $fix, $intf ) = @_;

	return "???" if(!defined $val or $val !~ /\d/ );
	return $val if( $val == 0 );

	if(!$fix) {
		if( $val >= $G ) {
			$val /= $G; $sufx = "G";
		} elsif( $val >= $M  ) {
			$val /= $M; $sufx = "M";
		} elsif( $val >= $k ) {
			$val /= $k; $sufx = $ksym;
		}
	} 
	
	return sprintf "%.0f %s",$val,$sufx 
		if( $intf or ( int($val*100) == (100*int($val)) ) );
	return sprintf "%.2f %s",$val,$sufx;
}
# Round the number to a set no of decimal places
sub dp($$) {
	my($num,$dcp) =@_;
	my($rv);
	return '0' if(!$num);
	$rv = sprintf '%.'.$dcp.'f',$num;
	$rv =~ s/\.0+$//; # remove trailing .0
	return $rv;
}

#######################################################################
# Read in configuration file

# readconf: pass it a list of section names
sub readconf(@)
{
	my ($inlist, $i, @secs, $sec, $usersec);
	@secs = @_;
	%config = ();
	$usersec = "\177";
	$usersec = "user-".(lc $authuser) if( $authuser );

	# set defaults
	%config = (
		'routers.cgi-confpath' => ".",
		'routers.cgi-cfgfiles' => "*.conf *.cfg",
		'web-png' => 0
	);

	( open CFH, "<".$conffile ) || do {
		print $q->header({-expires=>"now"});	
		start_html_ss({ -title => "Error", -bgcolor => "#ffd0d0",
			-class=>'error'  });	
		print $q->h1("Error").$q->p("Cannot read config file $conffile.");
		print $q->end_html();
		exit(0);
	};

	$inlist=0;
	$sec = "";
	while( <CFH> ) {
		/^\s*#/ && next;
		/\[(.*)\]/ && do { 
			$sec = lc $1;
			$inlist=0;	
			foreach $i ( @secs ) {
				if ( (lc $i) eq $sec ) { $inlist=1; last; }
			}
			# override for additional sections
			# put it here so people cant break things easily
			next if($inlist);
			if( ( $sec eq $usersec ) or ( $sec eq 'routers2.cgi' ) ) {
				$sec = 'routers.cgi'; $inlist = 1;
			}
			next;
		};
		# note final \s* to strip all trailing spaces (which works because
		# the *? operator is non-greedy!)  This should also take care of
		# stripping trailing CR if file created in DOS mode (yeuchk).
		if ( $inlist ) { /(\S+)\s*=\s*(\S.*?)\s*$/ and $config{"$sec-$1"}=$2; }
	}
	close CFH;
	
	# Activate NT compatibility options.
	# $^O is the OS name, NT usually produces 'MSWin32'.  By checking for 'Win'
	# we should be able to cover most possibilities.
	if ( (defined $config{'web-NT'} and $config{'web-NT'}=~/[1y]/i) 
		or $^O =~ /Win/ or $^O =~ /DOS/i  ) {
		$pathsep = "\\";
	}

	# backwards compatibility for old v1.x users
	$config{'routers.cgi-iconurl'} = $config{'routers.cgi-iconpath'}
		if( !defined $config{'routers.cgi-iconurl'} 
			and defined $config{'routers.cgi-iconpath'} );

	# some path corrections: remove trailing path separators on f/s paths
	foreach ( qw/dbpath confpath graphpath graphurl/ ) {
		$config{"routers.cgi-$_"} =~ s/[\/\\]$//;
	}
	# and add a trailing path separator on URL paths...
	$config{'routers.cgi-iconurl'} = "/rrdicons/" 
		if(!defined $config{'routers.cgi-iconurl'} );
	$config{'routers.cgi-iconurl'} .= "/" 
		if( $config{'routers.cgi-iconurl'} !~ /\/$/ );

	# allow [routers.cgi] section to override [web] section for some
	# parameters
	$config{'web-backurl'} = $config{'routers.cgi-backurl'}
		if(defined $config{'routers.cgi-backurl'});

	# For broken web servers (eg thttpd)
	$myurl = $config{'routers.cgi-trendurl'} 
		if(defined $config{'routers.cgi-trendurl'} );
	$myurl = $config{'trend.cgi-myurl'} 
		if(defined $config{'trend.cgi-myurl'} );
}
#######################################################################
# stylesheet start_html
sub start_html_ss
{
    my($opts,$bgopt) = @_;
    my($ssheet) = "";

    $opts->{-encoding} = $config{'web-charset'} if($config{'web-charset'});

#    if(!defined $opts->{'-link'}) {
#        $opts->{'-link'}=$linkcolour;
#        $opts->{'-vlink'}=$linkcolour;
#        $opts->{'-alink'}=$linkcolour;
#    }
#    $opts->{'-text'}=$deffgcolour if(!defined $opts->{'-text'});
#    $opts->{'-bgcolor'}=$defbgcolour if(!defined $opts->{'-bgcolor'});

    # If we have overridden things, then put it into the sheet here.
    # overriding style sheet using mrtg .cfg file options
    if( $bgopt and $opts->{-class}) {
        $ssheet .= "body.".$opts->{'-class'}." { background: $bgopt }\n";
    }
    # overriding style sheet using routers2.conf options
    # default pages
    if( $config{"routers.cgi-bgcolour"} or $config{"routers.cgi-fgcolour"} ) {
        $ssheet .= "body { ";
        $ssheet .= " color: ".$config{"routers.cgi-fgcolour"}."; "
            if($config{"routers.cgi-fgcolour"});
        $ssheet .= " background: ".$config{"routers.cgi-bgcolour"}
            if($config{"routers.cgi-bgcolour"});
        $ssheet .= "}\n";
    }
    # links
    $ssheet .=  "A:link { color: ".$config{'routers.cgi-linkcolour'}. " }\n "
        ."A:visited { color: ".$config{'routers.cgi-linkcolour'}. " }\n "
        ."A:hover { color: ".$config{'routers.cgi-linkcolour'}. " } \n"
        if($config{'routers.cgi-linkcolour'});

    if($config{'routers.cgi-stylesheet'}) {
        $opts->{'-style'} = { -src=>$config{'routers.cgi-stylesheet'}, -code=>$ssheet };
    }
    print $q->start_html($opts)."\n";
}

#######################################################################
# possible MODEs: interface, cpu, memory, generic (more to come) 
sub identify($) {
	my( $key, %identify, $k, @d, $mode );
	my($unit,$totunit,$okfile);
	my($timel, $times);

	$k = $_[0];

	# description defaults
	if(defined $config{"targetnames-$k"}) {
		$interfaces{$k}{shdesc} = $config{"targetnames-$k"};
	}
	if(defined $config{"targettitles-$k"}) {
		$interfaces{$k}{desc} = $config{"targettitles-$k"};
	}
	if(!defined $interfaces{$k}{shdesc}) {
		if(!defined $config{'targetnames-ifdefault'}
			or $config{'targetnames-ifdefault'} !~ /target/ ) {
			if(defined $interfaces{$k}{ipaddress}) {
				$interfaces{$k}{shdesc} = $interfaces{$k}{ipaddress};
			} elsif(defined $interfaces{$k}{ifdesc}) {
				$interfaces{$k}{shdesc} = $interfaces{$k}{ifdesc};
			} elsif(defined $interfaces{$k}{ifno}) {
				$interfaces{$k}{shdesc} = "#".$interfaces{$k}{ifno};
			} else {
#				$interfaces{$k}{desc} =~ /^(\S+)/;
#				$interfaces{$k}{shdesc} = $1;
				$interfaces{$k}{shdesc} = $interfaces{$k}{desc};
			}
		}
		$interfaces{$k}{shdesc} = $k if(!defined $interfaces{$k}{shdesc});
	}

	# try and identify the interface
	@d = ( $k, $interfaces{$k}{desc}, $interfaces{$k}{shdesc} );
	$mode = "";
	$mode = $interfaces{$k}{mode} if(defined $interfaces{$k}{mode});
	%identify = ();
	if(! $mode) {
		if( inlist( "cpu", @d ) and ($interfaces{$k}{maxbytes}==100) )
			{ $mode = "cpu"; }
		elsif( defined $interfaces{$k}{ifno} or defined $interfaces{$k}{ifdesc} 
			or $interfaces{$k}{isif} or  defined $interfaces{$k}{ipaddress} ) 
			{ $mode = "interface"; $interfaces{$k}{isif} = 1; }
		elsif( inlist( "interface", @d ) or inlist("serial",@d)
			or inlist( "ATM", @d )  or inlist( "[^x]port", @d ))
			{ $mode = "interface"; }
		elsif( inlist( "mem", @d ) ) { $mode = "memory"; }
		else { $mode = "generic"; }
		$interfaces{$k}{mode} = $mode;
	}

	# set appropriate defaults for thismode
	if(!defined $interfaces{$k}{mult}) { 
		if($mode eq "interface" and 
			(!defined $config{'routers.cgi-bytes'} 
			or $config{'routers.cgi-bytes'} !~ /y/ )
		) { $interfaces{$k}{mult} = 8; }
		else { $interfaces{$k}{mult} = 1; }
	}
	
	# defaults for everything...
	$timel = "second"; $times = "s"; $unit = ""; $totunit = "";
	if($mode eq "interface") { $totunit = "bytes"; }
	if($interfaces{$k}{mult} > 3599 ) {
		$timel = "hour"; $times = "hr";
		if($interfaces{$k}{mult} > 3600) { $totunit = "bits"; }
	} elsif($interfaces{$k}{mult} >59 ) {
		$timel = "minute"; $times = "min";
		if($interfaces{$k}{mult} > 60) { $totunit = "bits"; }
	} elsif($interfaces{$k}{mult} > 1) { $totunit = "bits"; }
	$unit = "$totunit/$times";
	$unit = "bps" if($unit eq "bits/s");
	$identify{ylegend} = "per $timel";
	$identify{background} = $bgcolour;
	$identify{legendi} = "In: ";
	$identify{legendo} = "Out:";
	$identify{legend1} = "Incoming" ;
	$identify{legend2} = "Outgoing";
	$identify{legend3} = "Peak inbound";
	$identify{legend4} = "Peak outbound";
	$identify{total} = 1;
	$identify{percentile} = 1;
	$identify{percent} = 1;
	$identify{unit} = $unit;
	$identify{totunit} = $totunit;
	$identify{unscaled} = "";

	if($mode eq "interface") {
		$identify{ylegend} = "traffic in $unit";
		$identify{legendi} = "In: ";
		$identify{legendo} = "Out:";
		$identify{legend1} = "Incoming traffic";
		$identify{legend2} = "Outgoing traffic";
		$identify{legend3} = "Peak inbound traffic";
		$identify{legend4} = "Peak outbound traffic";
		$identify{icon} = "interface-sm.gif";
#		$identify{background} = "#ffffff";
		$identify{unscaled} = "6dwmy";
		$identify{total} = 1;
	} elsif( $mode eq "cpu" ) {
		$identify{ylegend} = "Percentage use";
		$identify{legendi} = "CPU";
		$identify{unit} = "%";
		$identify{fixunits} = 1;
		$identify{totunit} = "";
		$identify{legend1} = "CPU usage";
		$identify{legend3} = "Peak CPU usage";
		$identify{legend2} = "";
		$identify{legend4} = "";
		$identify{icon} = "cpu-sm.gif";
#		$identify{background} = "#ffffd0";
		$identify{unscaled} = "6dwmy";
		$identify{percent} = 0;
		$identify{total} = 0;
	} elsif( $mode eq "memory" ) {
		$identify{ylegend} = "Bytes used";
		$identify{legendi} = "MEM";
		$identify{legendo} = "MEM";
		$identify{legend1} = "Memory usage";
		$identify{legend3} = "Peak memory usage";
		$identify{legend2} = "Sec. memory usage";
		$identify{legend4} = "Peak sec memory usage";
		$identify{icon} = "cpu-sm.gif";
#		$identify{background} = "#d0d0ff";
		$identify{total} = 0;
		$identify{unit} = "bytes"; 
		$identify{unit} = "bits" if($interfaces{$k}{bits}); 
		$identify{totunit} = "";
	} elsif( $mode eq "ping" ) {
		$identify{totunit} = "";
		$identify{unit} = "ms";
		$identify{fixunit} = 1;
		$identify{ylegend} = "milliseconds";
		$identify{legendi} = "High:";
		$identify{legendo} = "Low:";
		$identify{legend1} = "Round trip time range";
		$identify{legend2} = "Round trip time range";
		$identify{legend3} = "High peak 5min RTT";
		$identify{legend4} = "Low peak 5min RTT";
		$identify{icon} = "clock-sm.gif";
#		$identify{background} = "#ffffdd";
		$identify{total} = 0;
		$identify{percent} = 0;
		$identify{percentile} = 0;
		$identify{unscaled} = "";
	}

	# unscaled default option
	if( defined $config{'routers.cgi-unscaled'} ) {
		if( $config{'routers.cgi-unscaled'} =~ /y/i ) {
			$identify{unscaled} = "6dwmy" ;
		} else {
			$identify{unscaled} = "" ;
		}
	}

	# set icon
	$identify{icon} = guess_icon( 0, $k, $interfaces{$k}{desc}, $interfaces{$k}{shdesc} ) if(!defined $identify{icon});

	# different default for totunit
	# if we have a custom 'unit' but no custom 'totunit', then try to be
	# a bit more clever.
	if( defined $interfaces{$k}{unit} ) {
		my( $u ) = $interfaces{$k}{unit};
		if( $u =~ /^(.*)\// ) {
			$identify{totunit} = $1;
		} elsif( $u =~ /^(.*)ps$/ ) {
			$identify{totunit} = $1;
		} else {
			$identify{totunit} = $u;
		}
	}

	# set the defaults
	foreach $key ( keys %identify ) {
		$interfaces{$k}{$key} = $identify{$key} 
			if(!defined $interfaces{$k}{$key} );
	}

	$interfaces{$k}{mult} = 1 if(!defined $interfaces{$k}{mult});
	$interfaces{$k}{maxbytes} = 0 if(!defined $interfaces{$k}{maxbytes});
	$interfaces{$k}{max} = $interfaces{$k}{maxbytes} * $interfaces{$k}{mult};
	$interfaces{$k}{max1} = $interfaces{$k}{maxbytes1} * $interfaces{$k}{mult}
		if(defined $interfaces{$k}{maxbytes1});
	$interfaces{$k}{max2} = $interfaces{$k}{maxbytes2} * $interfaces{$k}{mult}
		if(defined $interfaces{$k}{maxbytes2});
	$interfaces{$k}{max} = $interfaces{$k}{max1} if(defined $interfaces{$k}{max1} and $interfaces{$k}{max1} > $interfaces{$k}{max} );
	$interfaces{$k}{max} = $interfaces{$k}{max2} if(defined $interfaces{$k}{max2} and $interfaces{$k}{max2} > $interfaces{$k}{max} );
	$interfaces{$k}{absmax} 
		= $interfaces{$k}{absmaxbytes} * $interfaces{$k}{mult}
		if(defined $interfaces{$k}{absmaxbytes});
	if(defined $interfaces{$k}{factor} ) {
		$interfaces{$k}{max} *= $interfaces{$k}{factor};
		$interfaces{$k}{absmax} *= $interfaces{$k}{factor}	
			if(defined $interfaces{$k}{absmax});
		$interfaces{$k}{max1} *= $interfaces{$k}{factor}	
			if(defined $interfaces{$k}{max1});
		$interfaces{$k}{max2} *= $interfaces{$k}{factor}	
			if(defined $interfaces{$k}{max2});
	}
	$interfaces{$k}{noo} = 1 if(!$interfaces{$k}{legend2});
	$interfaces{$k}{noi} = 1 if(!$interfaces{$k}{legend1});

	# catch the stupid people
	if($interfaces{$k}{noo} and $interfaces{$k}{noi}) {
		$interfaces{$k}{inmenu} = 0;
		$interfaces{$k}{insummary} = 0;
		$interfaces{$k}{inout} = 0;
	}

}
# guess an appropriate icon.  1st param is 1 for devices menu, 0 for targets
# other parameters are a list of attributes to check
sub guess_icon($@)
{
	my($m) = shift @_;

	if($m) {
		# these tests for devices menu only
		return "cisco-sm.gif" if( inlist "cisco",@_ );
		return "3com-sm.gif" if( inlist "3com",@_ );
		return "intel-sm.gif" if( inlist "intel",@_ );
		return "router-sm.gif" if( inlist "router",@_ );
		return "switch-sm.gif" if( inlist "switch",@_ );
		return "firewall-sm.gif" if( inlist "firewall",@_ );
		return "ibm-sm.gif" if( inlist "ibm",@_ );
		return "linux-sm.gif" if( inlist "linux",@_ );
		return "freebsd-sm.gif" if( inlist "bsd",@_ );
		return "novell-sm.gif" if( inlist "novell",@_ );
# these commented out as patterns are too short to be reliable
#		return "mac-sm.gif" if( inlist "mac|apple",@_ );
#		return "sun-sm.gif" if( inlist "sun",@_ );
#		return "hp-sm.gif" if( inlist "hp",@_ );
		return "win-sm.gif" if( inlist "windows",@_ );
	}
	return "mail-sm.gif"    if( inlist 'mail|messages',@_ );
	return "web-sm.gif"     if( inlist 'internet',@_  or inlist 'proxy',@_ );
	return "phone-sm.gif"   if( inlist 'phone',@_ );
	return "modem-sm.gif"   if( inlist 'modem',@_ );
	return "disk-sm.gif"    if( inlist 'nfs\w',@_ or inlist 'dsk',@_ );
	return "globe-sm.gif"   if( inlist 'dns\w',@_ );
	return "people-sm.gif"  if( inlist 'user[s ]',@_ );
	return "server-sm.gif"  if( inlist 'server|host',@_ );
	return "web-sm.gif"     if( inlist 'web',@_ );
	return "traffic-sm.gif" if( inlist 'traffic',@_ );
	return "chip-sm.gif"    if( inlist 'memory|cpu',@_ );
	return "interface-sm.gif" if(!$m and  inlist 'interface|serial',@_ );
	return "disk-sm.gif"    if( inlist 'dis[kc]|filesystem',@_ );
	return "clock-sm.gif"   if( inlist 'time|rtt|ping',@_ );
	return "temp-sm.gif"    if( inlist 'temp|climate|environment|heat',@_ );
	return "menu-sm.gif"    if( inlist '\wlog',@_ );
	return "interface-sm.gif" if(!$m and  inlist 'BRI|eth|tok|ATM|hme',@_ );
	return "load-sm.gif"    if( inlist 'load|weight',@_ );
	return "web-sm.gif"     if( inlist 'www',@_ );
	
	if($m) {
		# last chance with these less reliable ones
		return "mac-sm.gif" if( inlist "mac|apple",@_ );
		return "sun-sm.gif" if( inlist "sun",@_ );
		return "hp-sm.gif"  if( inlist "hp",@_ );
		return "win-sm.gif" if( inlist "win|pdc|bdc",@_ );
	}

	if($m) {
		return $config{'targeticons-filedefault'} 
			if(defined $config{'targeticons-filedefault'});
		return "menu-sm.gif";
	} else {
		return $config{'targeticons-ifdefault'} 
			if(defined $config{'targeticons-ifdefault'});
		return "target-sm.gif";
	}
}

#######################################################################
# read in a specified cfg file (default to current router file)

# interfaces hash: key= targetname
#            data: hash:
#            keys: lots.

sub read_cfg_file
{
	my($cfgfile) = $_[0];
	my($opts, $graph, $key, $k, $fd, $buf, $curif, @myifs, $arg,$rrd);
	my($ifcnt, @ifarr, $t, $desc, $url, $icon, $targ, $newfile, $targfile);
	my( $lasthostname, $lastcommunity ) = ("","");

	my( $inpagetop, $inpagefoot ) = (0,0);

	return if(!$cfgfile);

	$fd = new FileHandle ;

	if(! $fd->open( "<$cfgfile" )) {
		return;
	}

	$key = ""; $curif = ""; @myifs = ();
	while ( $buf = <$fd> ) {
		next if( $buf =~ /^\s*#/ );
		next if( $buf =~ /^\s*$/ ); # bit more efficient
		if( $inpagefoot ) {
			if( $curif and $buf =~ /^\s+\S/ ) {
				$interfaces{$curif}{pagefoot} .= $buf;
				next;
			}
			$inpagefoot = 0;
		}
		if( $inpagetop ) {
			if( $curif and $buf =~ /^\s+\S/ ) {
				$interfaces{$curif}{pagetop} .= $buf;
				next;
			}
			$inpagetop = 0;
		}
		if( $buf =~ /^\s*Target\[(.+?)\]\s*:\s*(.+)/i ) {
			$curif = $1; $arg = $2;
			next if(defined $interfaces{$curif});
			push @myifs, $curif;
			$interfaces{$curif} = { file=>$cfgfile, target=>$curif,
					insummary=>1, incompact=>1, inmenu=>1, isif=>0,
					interval=>$interval, nomax=>0, noabsmax=>0  };
			$interfaces{$curif}{rrd} = $workdir.$pathsep.(lc $curif).".rrd";
			if( $arg =~ /^-?(\d+):([^\@:\s]+)\@([\w\-\.]+)/ ) {
				# interface number
				$interfaces{$curif}{isif} = 1;
				$interfaces{$curif}{ifno} = $1;
				$interfaces{$curif}{community} = $2;
				$interfaces{$curif}{hostname} = $3;
				$interfaces{$curif}{mode} = "interface";
			} elsif( $arg =~ /^-?\/(\d+\.\d+\.\d+\.\d+):([^\@:\s]+)\@([\w\-\.]+)/ ) {
				# IP address
				$interfaces{$curif}{isif} = 1;
				$interfaces{$curif}{ipaddress} = $1;
				$interfaces{$curif}{community} = $2;
				$interfaces{$curif}{hostname} = $3;
				$interfaces{$curif}{mode} = "interface";
			} elsif( $arg =~ /^-?[\\#!](\S.*?):([^\@:\s]+)\@([\w\-\.]+)/ ) {
				$interfaces{$curif}{isif} = 1;
				$interfaces{$curif}{ifdesc} = $1;
				$interfaces{$curif}{community} = $2;
				$interfaces{$curif}{hostname} = $3;
				$interfaces{$curif}{mode} = "interface";
				$interfaces{$curif}{ifdesc} =~ s/\\(.)/$1/g ;
			} elsif( $arg =~ /&\w*[\d\.]+:(\S+)\@([\w\-\.]+)/ ) {
				# explicit OIDs
				$interfaces{$curif}{community} = $1;
				$interfaces{$curif}{hostname} = $2;
			} elsif( $arg =~ /mrtg.ping.probe/ ) {
				# special for the mrtg-ping-probe.pl
				$interfaces{$curif}{mode} = "ping";
				$interfaces{$curif}{graphstyle} = "range";
				$interfaces{$curif}{incompact} = 1;
				$interfaces{$curif}{ifdesc} = "Response time" ;
			} elsif( $arg =~ /`/ ) {
				# external program
				$interfaces{$curif}{insummary} = 1;
				$interfaces{$curif}{incompact} = 1;
			} else { # a target of some sort we dont yet know
				$interfaces{$curif}{insummary} = 0;
				$interfaces{$curif}{incompact} = 0;
			}
			$interfaces{$curif}{inout} = $interfaces{$curif}{isif};
			foreach $k ( qw/isif inout incompact insummary inmenu/ ) {
				$interfaces{$curif}{$k} = $interfaces{'_'}{$k}
					if(defined $interfaces{'_'}{$k});
			}
			$lasthostname = $interfaces{$curif}{hostname}
				if(defined $interfaces{$curif}{hostname});
			$lastcommunity= $interfaces{$curif}{community}
				if(defined $interfaces{$curif}{community});
			next;
		}
		if( $buf =~ /^\s*(routers\.cgi\*)?(Title|Descr?)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $3; $arg = $4;
			if(!defined $interfaces{$curif}) {
				$curif = "_$curif";
				next if(!defined $interfaces{$curif});
			}
			$interfaces{$curif}{desc} = $arg;
			next;
		}
		if( $buf =~ /^\s*Options\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $1;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{options} = "" if(!$interfaces{$curif}{options});
			$interfaces{$curif}{options} .= ' '.$2;
			next;
		}
		if( $buf =~ /^\s*(routers\.cgi\*)?PageTop\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2;  $arg = $3;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{pagetop} = $arg;
			$inpagetop = 1;
			next;
		}
		if( $buf =~ /^\s*(routers\.cgi\*)?PageFoot\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2;  $arg = $3;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{pagefoot} = $arg;
			$inpagefoot = 1;
			next;
		}
		if( $buf =~ /^\s*SetEnv\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			foreach $k ( quotewords('\s+',0,$arg) ) {
				if( $k =~ /MRTG_INT_IP=\s*(\d+\.\d+\.\d+\.\d+)/ ) {
					$interfaces{$curif}{ipaddress}=$1
					if(!defined $interfaces{$curif}{ipaddress});
					next;
				}
				if( $k =~ /MRTG_INT_DESCR?=\s*(\S.*)/ ) {
					$interfaces{$curif}{shdesc}=$1
					if(!defined $interfaces{$curif}{shdesc});
					next;
				}
			}
			next;
		}
		if( $buf =~ /^\s*routers\.cgi\*Short(Name|Descr?)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2; $arg = $3;
			$curif = "_".$curif if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{shdesc} = $arg if($arg);
			next;
		}
		if( $buf =~ /^\s*routers\.cgi\*Options\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			next if(!defined $interfaces{$1});
			$interfaces{$1}{cgioptions}="" if(!$interfaces{$1}{cgioptions});
			$interfaces{$1}{cgioptions} .= " ".$2;
			next;
		}
		if( $buf =~ /^\s*(routers\.cgi\*)?MaxBytes\[(.+?)\]\s*:\s*(\d+)/i ) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{maxbytes} = $3;
			next;
		}
		if($buf=~ /^\s*(routers\.cgi\*)?Unscaled\[(.+?)\]\s*:\s*([6dwmy]*)/i){ 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{unscaled} = $3;
			next;
		}
		if($buf=~ /^\s*(routers\.cgi\*)?WithPeaks?\[(.+?)\]\s*:\s*([dwmy]*)/i) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{withpeak} = $3;
			next;
		}
		if( $buf =~ /^\s*(routers\.cgi\*)?YLegend\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{ylegend} = $3;
			next;
		}
		if($buf=~ /^\s*(routers\.cgi\*)?ShortLegend\[(.+?)\]\s*:\s*(.*)/i){ 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{unit} = $3;
			$interfaces{$2}{unit} =~ s/&nbsp;/ /g;
			next;
		}
		if($buf=~ /^\s*routers\.cgi\*TotalLegend\[(.+?)\]\s*:\s*(.*)/i){ 
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			$arg =~ s/&nbsp;/ /g;
			$interfaces{$curif}{totunit} = $arg;
			next;
		}
		if( $buf =~ /^\s*(routers\.cgi\*)?(Legend[IO1234TA][IO]?)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $3; $key = lc $2; $arg = $4;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$arg =~ s/&nbsp;/ /;
			$interfaces{$curif}{$key} = $arg;
			next;
		}
		if( $buf =~ /^\s*routers\.cgi\*Mode\[(.+?)\]\s*:\s*(\S+)/i ) {
			next if(!defined $interfaces{$1});
			$interfaces{$1}{mode} = $2;
			next;
		}
		if( $buf =~ /^\s*routers\.cgi\*Graph\[(.+?)\]\s*:\s*(\S.*)/i ) {
			$curif = $1; $arg = $2;
			if( $arg =~ /^"/ ) {
				$arg =~ /^"([^"]+)"\s*:?(.*)/;
				$opts = $2; $graph = $1;
			} else {
				$arg =~ /^(\S+)\s*:?(.*)/;
				$opts = $2; $graph = $1;
			}
				next if(!$graph);
			$interfaces{$curif}{usergraphs} = [] 
				if(!defined $interfaces{$curif}{usergraphs});
			push @{$interfaces{$curif}{usergraphs}}, $graph;
			if( defined $interfaces{"_$graph"} ) {
				push @{$interfaces{"_$graph"}{targets}}, $curif;
				$interfaces{"_$graph"}{cgioptions} .= " $opts";
			} else {
				$interfaces{"_$graph"} = {
					shdesc=>$graph,  targets=>[$curif], 
					cgioptions=>$opts, mode=>"\177_USER",
					usergraph=>1, icon=>"cog-sm.gif", inout=>0, incompact=>0,
					insummary=>0, inmenu=>1, desc=>"User defined graph $graph",
					withtotal=>0, withaverage=>0
				};
				$interfaces{"_$graph"}{withtotal} = 1 
					if( defined $config{'routers.cgi-showtotal'}
						and $config{'routers.cgi-showtotal'}=~/y/i);
				push @myifs, "_$graph";
			}
			next;
		}
		if( $buf =~ /^\s*routers.cgi\*Icon\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			if(!defined $interfaces{$curif}) {
				$curif = "_$curif";
				next if(!defined $interfaces{$curif});
			}
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{icon} = $arg;
			next;
		}
		if( $buf =~ /^\s*routers.cgi\*Ignore\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			if( $arg =~ /y/i ) {  
				$interfaces{$curif}{insummary} = 0;
				$interfaces{$curif}{inmenu} = 0;
				$interfaces{$curif}{inout} = 0;
				$interfaces{$curif}{isif} = 0;
			}
			next;
		}
		if( $buf =~ /^\s*routers.cgi\*InSummary\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{insummary} = 1; }
			else { $interfaces{$curif}{insummary} = 0; }
			next;
		}
		if( $buf =~ /^\s*routers.cgi\*InMenu\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{inmenu} = 1; }
			else { $interfaces{$curif}{inmenu} = 0; }
			next;
		}
		if( $buf =~ /^\s*routers.cgi\*InOut\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{inout} = 1; }
			else { $interfaces{$curif}{inout} = 0; }
			next;
		}
		if( $buf =~ /^\s*routers.cgi\*InCompact\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{incompact} = 2; }
			else { $interfaces{$curif}{incompact} = 0; }
			next;
		}
		if( $buf =~ /^\s*Background\[(.+?)\]\s*:\s*(#[a-f\d]+)/i ) { 
			next if(!defined $interfaces{$1});
			$interfaces{$1}{background} = $2;
			next;
		}
		if( $buf =~ /^\s*Timezone\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			next if(!defined $interfaces{$1});
			$interfaces{$1}{timezone} = $2;
			next;
		}
		if( $buf =~ /^\s*Directory\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			$arg =~ s/[\s\\\/]+$//; # trim trailing spaces and path separators!
			$interfaces{$curif}{directory} = $arg;
			$interfaces{$curif}{rrd} = 
				$workdir.$pathsep.$arg.$pathsep.(lc $curif).".rrd";
			next;
		}
		if( $buf =~ /^\s*Workdir\s*:\s*(\S+)/i ) { 
			$workdir = $1; $workdir =~ s/[\\\/]+$//; next; }
		if( $buf =~ /^\s*Interval\s*:\s*(\d+)/i ) { $interval = $1; next; }
		if( $buf =~ /^\s*Include\s*:\s*(\S+)/i ) { 
			$newfile = $1;
			$newfile = (dirname $cfgfile).$pathsep.$newfile
				if( $newfile !~ /^([a-zA-Z]:)?[\/\\]/ );
			read_cfg_file($newfile); 
			next; 
		}
		if( $buf =~ /^\s*LibAdd\s*:\s*(\S+)/i ) { unshift @INC, $1; next; }
		if($buf=~ /^\s*(routers\.cgi\*)?MaxBytes(\d)\[(\S+)\]\s*:\s*(\d+)/i ){
			$curif = $3; $arg = $4;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{"maxbytes$2"} = $arg;
			$interfaces{$curif}{maxbytes} = $arg
				if(!$interfaces{$curif}{maxbytes});
			next;
		}
		# the regexp from hell
		if( $buf =~ /^\s*(routers\.cgi\*)?Colou?rs\[(.+?)\]\s*:\s*[^#]*(#[\da-f]{6})[\s,]+[^#]*(#[\da-f]{6})[\s,]+[^#]*(#[\da-f]{6})[\s,]+[^#]*(#[\da-f]{6})/i ) { 
			$curif = $2; 
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{colours} = [ $3,$4,$5,$6 ];
			next;
		}
		if( $buf =~ /^\s*routers\.cgi\*MBLegend\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $1; 
			$curif = "_$curif" if(!defined $interfaces{$curif});
			$interfaces{$curif}{mblegend} = $2;
			next;
		}
		if( $buf =~ /^\s*routers\.cgi\*AMLegend\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $1; 
			$curif = "_$curif" if(!defined $interfaces{$curif});
			$interfaces{$curif}{amlegend} = $2;
			next;
		}
		if( $buf =~ /^\s*(routers\.cgi\*)?AbsMax\[(.+?)\]\s*:\s*(\d+)/i ) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{absmaxbytes} = $3;
			next;
		}
		if( $buf =~ /^\s*WeekFormat(\[.+?\])?\s*:\s*%?([UVW])/i ) {
			# yes I know this is ugly, it is being retrofitted
			$monthlylabel = "%".$2;
			next;
		}
		if( $buf =~ /^\s*routers\.cgi\*GraphStyle\[(.+?)\]\s*:\s*(\S+)/i ) { 
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{graphstyle} = $arg;
			next;
		}
		if( $buf =~ /^\s*(routers\.cgi\*)?Factor\[(.+?)\]\s*:\s*([\d\.]+)/i ) { 
			$curif = $2; $arg = $3;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{factor} = $arg if($arg > 0);
			next;
		}
		if( $buf =~ /^\s*(routers\.cgi\*)?Supp?ress?\[(.+?)\]\s*:\s*(\S+)/i ) { 
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{suppress} = $arg;
			next;
		}
	}
	$fd->close;

	# now take the current file defaults
	foreach $key ( keys %{$interfaces{'_'}} ) {
		foreach $curif ( @myifs ) {
			$interfaces{$curif}{$key} = $interfaces{'_'}{$key}
				if(!defined $interfaces{$curif}{$key});
		}
	}
	foreach $key ( keys %{$interfaces{'^'}} ) {
		foreach $curif ( @myifs ) {
			$interfaces{$curif}{$key} = $interfaces{'^'}{$key}.' '.$interfaces{$curif}{$key};
		}
	}
	foreach $key ( keys %{$interfaces{'$'}} ) {
		foreach $curif ( @myifs ) { 
			$interfaces{$curif}{$key} .= ' '.$interfaces{'$'}{$key};
		}
	}

	# now process the options
	foreach $curif ( @myifs ) {
		next if(!$curif);
		if(defined $interfaces{$curif}{options} ) {
		foreach $k ( split /[\s,]+/,$interfaces{$curif}{options} ) {
			$interfaces{$curif}{noo} = 1 if( $k eq "noo");
			$interfaces{$curif}{noi} = 1 if( $k eq "noi");
			if( $k eq "bits") { $interfaces{$curif}{bits} = 1; }
			if( $k eq "perminute") {
				$interfaces{$curif}{perminute} = 1
					if(!defined $interfaces{$curif}{perhour}
						and !defined $interfaces{$curif}{perminute});
			}
			if( $k eq "perhour") {
				$interfaces{$curif}{perhour} = 1
					if(!defined $interfaces{$curif}{perhour}
						and !defined $interfaces{$curif}{perminute});
			}
			if( $k eq "nopercent") {
				$interfaces{$curif}{percent} = 0 ;
				# default incompact to NO if target has nopercent set
				$interfaces{$curif}{incompact} = 0 
					if($interfaces{$curif}{incompact} == 1);
			}
			$interfaces{$curif}{integer} = 1 if( $k eq "integer");
		} }
		if ( defined $interfaces{$curif}{cgioptions} ) {
		  foreach $k ( split /[\s,]+/,$interfaces{$curif}{cgioptions} ) {
			$interfaces{$curif}{available} = 1 if( $k eq "available");
			$interfaces{$curif}{available} = 0 if( $k eq "noavailable");
			$interfaces{$curif}{noo} = 1 if( $k eq "noo");
			$interfaces{$curif}{noi} = 1 if( $k eq "noi");
#			$interfaces{$curif}{mult} = 8 if( $k eq "bits");
#			$interfaces{$curif}{mult} = 1 if( $k eq "bytes");
			$interfaces{$curif}{noi} = 1 if( $k eq "noi");
			if( $k eq "bytes") { $interfaces{$curif}{bytes} = 1; 
				$interfaces{$curif}{bits} = 0; }
			if( $k eq "bits") { $interfaces{$curif}{bits} = 1;
				$interfaces{$curif}{bytes} = 0;  }
			if( $k eq "perminute") {
				$interfaces{$curif}{perminute} = 1
					if(!defined $interfaces{$curif}{perhour}
						and !defined $interfaces{$curif}{perminute});
			}
			if( $k eq "perhour") {
				$interfaces{$curif}{perhour} = 1
					if(!defined $interfaces{$curif}{perhour}
						and !defined $interfaces{$curif}{perminute});
			}
			$interfaces{$curif}{isif} = 1 if($k eq "interface");
			if( $k eq "ignore") {
				$interfaces{$curif}{inmenu} = 0 ;
				$interfaces{$curif}{insummary} = 0 ;
				$interfaces{$curif}{inout} = 0 ;
				$interfaces{$curif}{incompact} = 0 ;
			}
			$interfaces{$curif}{unscaled} = "" if( $k eq "scaled");
			$interfaces{$curif}{total} = 0 if( $k eq "nototal");
			$interfaces{$curif}{percentile} = 0 if( $k eq "nopercentile");
			if( $k eq "summary" ) {
				$interfaces{$curif}{summary} = 1;
				$interfaces{$curif}{compact} = 0;
				$interfaces{$curif}{withtotal} = 0;
				$interfaces{$curif}{withaverage} = 0;
				$interfaces{$curif}{insummary} = 0 ;
				$interfaces{$curif}{incompact} = 0 ;
			}
			if( $k eq "compact" ) {
				$interfaces{$curif}{summary} = 0;
				$interfaces{$curif}{compact} = 1;
				$interfaces{$curif}{withtotal} = 0;
				$interfaces{$curif}{withaverage} = 0;
				$interfaces{$curif}{insummary} = 0 ;
				$interfaces{$curif}{incompact} = 0 ;
			}
			if( $k eq "total") {
				 $interfaces{$curif}{withtotal} = 1 ;
				 $interfaces{$curif}{total} = 1 ;
			}
			$interfaces{$curif}{withaverage} = 1 if( $k eq "average");
			$interfaces{$curif}{nolegend} = 1 if( $k eq "nolegend");
			$interfaces{$curif}{nodetails} = 1 if( $k eq "nodetails");
			$interfaces{$curif}{nomax} = 1 if( $k eq "nomax");
			$interfaces{$curif}{noabsmax} = 1 if( $k eq "noabsmax");
			$interfaces{$curif}{percent} = 0 if( $k eq "nopercent");
			$interfaces{$curif}{integer} = 1 if( $k eq "integer");
			if( $k =~ /^#[\da-fA-F]{6}$/ ) {
				$interfaces{$curif}{colours} = []
					if(!defined $interfaces{$curif}{colours});
				push @{$interfaces{$curif}{colours}}, $k;
			}
			$interfaces{$curif}{fixunits} = 1 
				if( $k =~ /^fixunits?/i or $k =~ /^nounits?/i );
		  }
		}
		# fix the mult
		if($interfaces{$curif}{bytes}) {
			$interfaces{$curif}{mult} = 1;
		} elsif($interfaces{$curif}{bits} ) {
			$interfaces{$curif}{mult} = 8;
		}
		if($interfaces{$curif}{perminute}) {
			$interfaces{$curif}{mult}=1 if(!$interfaces{$curif}{mult});
			$interfaces{$curif}{mult} *= 60;
		} elsif($interfaces{$curif}{perhour}) {
			$interfaces{$curif}{mult}=1 if(!$interfaces{$curif}{mult});
			$interfaces{$curif}{mult} *= 3600;
		}
		# sanity check
		if( $interfaces{$curif}{incompact} and !$interfaces{$curif}{maxbytes}){
			$interfaces{$curif}{incompact} = 0;
		}
		# RRD file name
		if(! $interfaces{$curif}{usergraph} ) {
			$rrd = $workdir;
			$rrd .= $pathsep.$interfaces{$curif}{directory}
				if($interfaces{$curif}{directory});
			$rrd .= $pathsep.(lc $curif).".rrd";
			$interfaces{$curif}{rrd} = $rrd;
		}
	}

	# now read the corresponding .ok file, if it exists
	$cfgfile =~ s/\.conf$/.ok/;
	$cfgfile =~ s/\.cfg$/.ok/;
	if( open OK, "<$cfgfile" )  {
		my( %ifdesc ) = ();
		my( %ifip ) = ();
		while( <OK> ) {
			if( /\tDescr\t(.+)\t(\d+)/ ) {
				$ifdesc{$2} = $1; $ifdesc{$1} = $2;
			} 
			if( /\tIp\t(.+)\t(\d+)/ ) {
				$ifip{$2} = $1; $ifip{$1} = $2;
			} 
		}
		close OK;

		foreach $curif ( @myifs ) {
		if(!defined $interfaces{$curif}{ifno}) {
			$interfaces{$curif}{ifno} = $ifdesc{$interfaces{$curif}{ifdesc}}
			if(defined $interfaces{$curif}{ifdesc}
				and defined $ifdesc{$interfaces{$curif}{ifdesc}});
			$interfaces{$curif}{ifno} = $ifip{$interfaces{$curif}{ipaddress}}
			if(defined $interfaces{$curif}{ipaddress}
				and defined $ifip{$interfaces{$curif}{ipaddress}});
		}
		if(defined $interfaces{$curif}{ifno}) {
			$key = $interfaces{$curif}{ifno};
			$interfaces{$curif}{ifdesc} = $ifdesc{$key}
			if(defined $ifdesc{$key} and !defined $interfaces{$curif}{ifdesc});
			$interfaces{$curif}{ipaddress} = $ifip{$key}
			if(defined $ifip{$key} and !defined $interfaces{$curif}{ipaddress});
		}
		}
	} # ok file exists

	# now set up userdefined graphs for Incoming and Outgoing, if it is
	# necessary.
	$ifcnt = 0; @ifarr = (); $curif="";
	foreach ( @myifs ) { 
		$curif = $_ if(!$curif and $interfaces{$_}{community}
				and $interfaces{$_}{hostname} );
		if($interfaces{$_}{inout}) {
			$ifcnt++;
			push @ifarr, $_;
		}
	}
	if($ifcnt) {
		$t = "";
		if( defined $interfaces{'_incoming'} ) {
			push @{$interfaces{'_incoming'}{targets}},@ifarr
				if( $interfaces{'_incoming'}{mode} =~ /_AUTO/ );
		} else {
			$interfaces{'_incoming'} = {
			usergraph=>1, insummary=>0, inmenu=>1, inout=>0, incompact=>0,
			shdesc=>"Incoming",  targets=>[@ifarr], noo=>1, mult=>8,
			icon=>"incoming-sm.gif", mode=>"\177_AUTO",
			desc=>$t."Incoming traffic",
			withtotal=>0, withaverage=>0
			};
			if(defined $config{'routers.cgi-showtotal'} 
				and $config{'routers.cgi-showtotal'}=~ /y/i ) {
				$interfaces{'_incoming'}{withtotal} = 1;
			}
		}
		if( defined $interfaces{'_outgoing'}  ) {
			push @{$interfaces{'_outgoing'}{targets}},@ifarr
				if( $interfaces{'_outgoing'}{mode} =~ /_AUTO/ );
		} else {
			$interfaces{'_outgoing'} = {
			usergraph=>1, insummary=>0, inmenu=>1, inout=>0, incompact=>0,
			shdesc=>"Outgoing",  targets=>[@ifarr], noi=>1, mult=>8,
			icon=>"outgoing-sm.gif", mode=>"\177_AUTO",
			desc=>$t."Outgoing traffic",
			withtotal=>0, withaverage=>0
			};
			if(defined $config{'routers.cgi-showtotal'} 
				and $config{'routers.cgi-showtotal'}=~ /[1y]/i ) {
				$interfaces{'_outgoing'}{withtotal} = 1;
			}
		}
	}
}

sub read_cfg($)
{
	my($cfgfile) = $_[0];
	my($l,$key,$k);
	
	return if (!$cfgfile);

	%interfaces = ( '_'=>{x=>0}, '^'=>{x=>0}, '$'=>{x=>0} );
	$interval = 5;
	$workdir = $config{'routers.cgi-dbpath'};

	read_cfg_file($cfgfile); # recursive

	# zap defaults
	delete $interfaces{'_'};
	delete $interfaces{'$'};
	delete $interfaces{'^'};
	delete $interfaces{''} if(defined $interfaces{''});

	# first pass for interfaces
	foreach $key ( keys %interfaces ) { 
		next if($interfaces{$key}{usergraph});
		identify $key; 
	}
	# second pass for user graphs
	foreach $key ( keys %interfaces ) {
		next if(!$interfaces{$key}{usergraph});
		$k = $key; $k=~ s/^_//; # chop off initial _ prefix
		$interfaces{$key}{shdesc} = $config{"targetnames-$k"}
		if(defined $config{"targetnames-$k"});
		$interfaces{$key}{desc} = $config{"targettitles-$k"}
		if(defined $config{"targettitles-$k"});
		$interfaces{$key}{icon} = $config{"targeticons-$k"}
		if(defined $config{"targeticons-$k"});
		foreach $k ( keys %{$interfaces{$interfaces{$key}{targets}->[0]}} ) {
			$interfaces{$key}{$k} 
				= $interfaces{$interfaces{$key}{targets}->[0]}{$k}
				if(!defined $interfaces{$key}{$k});
		}
	}
}

#######################################################################
# Generate the page
sub mypage()
{
	my( $imgurl );
	my( $ahead );
	my( $javascript ) = "function RefreshMenu()
	{
	var mwin; var uopts;
	if( parent.menu ) {
	mwin = parent.menu;
	uopts = 'T';
	if( parent.menub ) { mwin = parent.menub; uopts = 't'; }
	mwin.location = '".$routersurl."?if=__none&rtr="
		.$q->escape($file)."&page=menu&xmtype=options&uopts='+uopts;
	}
	}";

	$imgurl = $myurl."?fi=".$q->escape($file)
		."&ta=".$q->escape($target)
		."&dwmy=$dwmy" 
		."&dk=$DECAY" 
		."&pr=$PREDICT" 
		."&ba=$BASE"
		."&t=$targetwindow&conf=".$q->escape($conffile)
		."&img=1";

	start_html_ss({-title=>"Trend Analysis",
		-script=>$javascript, -onLoad=>"RefreshMenu()",
		-text=>$fgcolour, -bgcolor=>$bgcolour, -class=>'trend',
		-link=>$linkcolour, -alink=>$linkcolour, -vlink=>$linkcolour
	});

	print $q->h1("Trend Analysis");

	print $q->img({ alt=>'Trend graph', src=>$imgurl }).$q->br."\n";
#	print $q->a({href=>$imgurl},$imgurl).$q->br;

	print "<DIV class=icons>";
	print $q->hr."\n<TABLE border=0 cellpadding=0 width=100% align=center><TR>";
	print "<TD valign=top>See alternative predictions:\n<UL>";
	foreach ( qw/daily weekly monthly yearly/ ) {
		if(substr($_,0,1) eq $dwmy) {
			print $q->li("Trending $_ predictions")."\n";
		} else {
		print $q->li($q->a({href=>(
				$myurl."?dwmy=".(substr($_,0,1))
				."&fi=".$q->escape($file)
				."&ta=".$q->escape($target)
				."&b=".$q->escape($backurl)
				."&t=".$q->escape($targetwindow)
				."&url=".$q->escape($routersurl)
				."&conf=".$q->escape($conffile)
				."&pr=$PREDICT" 
				."&dk=$DECAY"
				."&ba=$BASE"
			)},
			"Trending $_ predictions" )
		)."\n";
		}
	}
	print "</UL></TD>\n";
	print "<TD valign=top>See different historical weightings:\n<UL>";
	foreach ( @decays ) {
		if($_ eq $DECAY ) {
			print $q->li("Decay factor $_" )."\n";
		} else {
		print $q->li($q->a({href=>(
				$myurl."?dk=$_"
				."&fi=".$q->escape($file)
				."&ta=".$q->escape($target)
				."&b=".$q->escape($backurl)
				."&t=".$q->escape($targetwindow)
				."&url=".$q->escape($routersurl)
				."&conf=".$q->escape($conffile)
				."&pr=$PREDICT" 
				."&dwmy=$dwmy"
				."&ba=$BASE"
			)},
			"Decay factor $_" )
		)."\n";
		}
	}
	print "</UL></TD>\n";
	print "<TD valign=top>Different future distances:\n<UL>";
	foreach ( 50,100,150,200 ) {
		if( $dwmy eq "d" ) { $ahead = int(5 * $_ / 60)." hours"; }
		elsif( $dwmy eq "w" ) { $ahead = int( $_ / 48 )." days"; }
		elsif( $dwmy eq "m" ) { $ahead = int( $_ / 12 )." days"; }
		else { $ahead =  $_." days"; }
		if($_ eq $PREDICT ) {
			print $q->li("Look ahead $ahead")."\n";
		} else {
		print $q->li($q->a({href=>(
				$myurl."?pr=$_"
				."&fi=".$q->escape($file)
				."&ta=".$q->escape($target)
				."&b=".$q->escape($backurl)
				."&t=".$q->escape($targetwindow)
				."&url=".$q->escape($routersurl)
				."&conf=".$q->escape($conffile)
				."&dk=$DECAY"
				."&dwmy=$dwmy"
				."&ba=$BASE"
			)},
			"Look ahead $ahead" )
		)."\n";
		}
	}
	print "</UL></TD>\n";
	print "</TR></TABLE>\n";
	print "Base predicted trend on ";
	print $q->a({href=>(
				$myurl."?pr=$PREDICT"
				."&fi=".$q->escape($file)
				."&ta=".$q->escape($target)
				."&b=".$q->escape($backurl)
				."&t=".$q->escape($targetwindow)
				."&url=".$q->escape($routersurl)
				."&conf=".$q->escape($conffile)
				."&dk=$DECAY"
				."&dwmy=$dwmy"
				."&ba=0"
		)},"current value");
	print " or on ";
	print $q->a({href=>(
				$myurl."?pr=$PREDICT"
				."&fi=".$q->escape($file)
				."&ta=".$q->escape($target)
				."&b=".$q->escape($backurl)
				."&t=".$q->escape($targetwindow)
				."&url=".$q->escape($routersurl)
				."&conf=".$q->escape($conffile)
				."&dk=$DECAY"
				."&dwmy=$dwmy"
				."&ba=1"
		)},"weighted average value");
	print $q->hr."\n";
	print "Trend Decay: $DECAY".$q->br."\n";
	print "(smaller numbers mean pay less attention to historical data)<br>\n";
	print "See error log ".$q->a({href=>"$myurl?log=1",target=>"_new"},
		"here")."<BR>\n" if($debug);
	print "</DIV><DIV class=footer>";
	print $q->hr.$q->small("S Shipway: RRD trending analysis v$VERSION")."\n";
	print "</DIV>";

	print $q->end_html();
}
#######################################################################
sub create_rrd($) {
	my( $rrdfile ) = @_;
	my( $dblint, $curtime, $curvala, $curvalb, $i );
	my( $rv, $line, $t, $v, $e, $entry);
	my( $hita, $hitb ) = (0,0);
	my(@args) = ();

	# Create the empty RRD file with initial params

	unlink $rrdfile if(-f $rrdfile);
	@args = ( $rrdfile,'-b',$starttime-1,'-s',$interval );
	foreach ( @$ds, 't0', 't1' ) {
		push @args, "DS:$_:GAUGE:".($interval*2).":U:U";
	}
	push @args, "RRA:AVERAGE:0.5:1:800";
	push @args, "RRA:MAX:0.5:1:800";
	RRDs::create(@args);
	$e = RRDs::error();
	if( $e ) { errlog("RRDCreate ".(join " ",@args).": $e"); return; }

	# Output existing data ($rrddata,$starttine,$endtime,$interval)
	$t = $starttime;
	foreach $line ( @$rrddata ) {
		$entry = "$t";
		foreach $v ( @$line ) {
			if(defined $v) { $entry .= ":$v"; }
			else { $entry .= ":U"; }
		}
		$entry .= ":U:U";
		RRDs::update($rrdfile,$entry);
#		errlog($entry);
		$t += $interval;
	}

	# output predicted data (@$trendstart, @$trenddelta)
	$i = 0; ( $curvala, $curvalb ) = @$trendstart;
	while ( $i < $PREDICT ) {
		$entry = "$t:U:U:$curvala:$curvalb";
		RRDs::update($rrdfile,$entry);
		$t += $interval;
		$curvala += $$trenddelta[0]; $curvalb += $$trenddelta[1];
		if($curvala < 0 and !$hita and !$interfaces{$target   }{noi}) {
			$curvala = 0; $hita = 1; $$trenddelta[0]=0;
			push @info, "Zero for ".$interfaces{$target}{legendi}
				." ".localtime($t)."\\l";
		}
		if($curvala > $interfaces{$target   }{maxbytes} and !$hita
			and !$interfaces{$target   }{noi}) {
			$curvala = $interfaces{$target   }{maxbytes}; $hita = 1; 
			$$trenddelta[0]=0;
			push @info, "Max for ".$interfaces{$target   }{legendi}
				." ".localtime($t)."\\l";
		}
		if($curvalb < 0 and !$hitb and !$interfaces{$target   }{noo}) {
			$curvalb = 0; $hitb = 1; $$trenddelta[1]=0;
			push @info, "Zero for ".$interfaces{$target   }{legendo}
				." ".localtime($t)."\\l";
		}
		if($curvalb > $interfaces{$target   }{maxbytes} and !$hitb
			and !$interfaces{$target   }{noo}) {
			$curvalb = $interfaces{$target   }{maxbytes}; $hitb = 1; 
			$$trenddelta[1]=0;
			push @info, "Max for ".$interfaces{$target   }{legendo}
				." ".localtime($t)."\\l";
		}
		$i++;
	}
}
#######################################################################
# calculate wieghted SD for line $idx at given delta
# weighted sd = square root of weighted average of squares of difference
sub wsd($$) {
	my( $idx,  $delta ) = @_;
	my( $c, $tot, $w, $row, $v ) = (0,0,0,0,0);
	my( $fx );

	$fx  = $trendstart->[$idx];
	$w = 1;
	foreach $row ( 0 .. $#$rrddata ) {
		$v = $rrddata->[$#$rrddata - $row]->[$idx];
		if($v) { $tot += ($v-$fx)*($v-$fx) * $w; $c += $w;  }
		$w *= $DECAY; # Next value is less significant
		$fx -= $delta;
	}
	if($c) {
		$tot = sqrt($tot / $c); 
	} elsif( $tot ) {
		$tot = sqrt($tot); # should not be possible for tot>0 and c=0
	}

	return $tot;
}
#######################################################################
# This function will retrieve the RRD data, calculate the value and
# slope of the trend line, then call the outputxml function and rrdtool
# to create XML and the RRDTool database.
sub do_trending {
	my( $timeframe ) = "1d";
	my( $answer, $status, $e );
	my( $n, $idx, $c, $tot, $w, $row, $v, $deltadelta );
	my( $sd, $delta, $sda, $sdb, $lim );

	errlog("Starting trending function");
	@info = (); # extra lines to add to graph
	push @info, 'Trending analysis decay factor: '.doformat($DECAY,1,0).'\l';
 
	# set intervals (in seconds): 5min, 30min, 2hr, 1day
	foreach ( $dwmy ) {
		if( /w/ ) { $timeframe = "200h"; $interval = 1800; last; }
		if( /m/ ) { $timeframe = "800h"; $interval = 7200; last; }
		if( /y/ ) { $timeframe = "400d"; $interval = 3600*24; last; }
		$timeframe = "2000m"; $interval = 300;
	}

	# Read in the RRD file
	$endtime = RRDs::last($interfaces{$target}{rrd});
	$e = RRDs::error();
	errlog("RRDLast: ".$interfaces{$target}{rrd}.": $e") if ($e);
	return if($e);
	( $starttime, $interval, $ds, $rrddata ) 
		= RRDs::fetch($interfaces{$target}{rrd},$consolidation,"-r",$interval,	
			"-s",($endtime-(400*$interval)),"-e",$endtime);
	$e = RRDs::error();
	errlog("RRDFetch: ".$interfaces{$target}{rrd}.": $e") if ($e);
	return if($e);
	errlog(join(",",@$ds).": ".$#$rrddata." rows every $interval from "
		.localtime($starttime));

	# Calculate trends
	# this results in (a) last update time, (b) avg value then, 
	# (c) change in value per interval
	$trendstart = [ 0,0 ];
	$trenddelta = [ 0,0 ];
	foreach $idx ( 0, 1 ) {
		if( $BASE ) {
			# calculate weighted average (start point for line)
			$w = 1;   # weight of current sample
			$tot = 0; # total of values
			$c = 0;   # total weight
			$n = 0;   # count of samples processed
			foreach $row ( 0 .. $#$rrddata ) {
				$v = $rrddata->[$#$rrddata - $row]->[$idx];
				if($v) { $tot += $v * $w; $c += $w; $n++; }
				$w *= $DECAY; # Next value is less significant
			}
			$trendstart->[$idx] = $tot / $c if($c);
			errlog("Weighted average for $idx is: ".$trendstart->[$idx]." = $tot / $c, $n valid samples");
		} else {
			# use last value
			foreach $row ( 0 .. $#$rrddata ) {
				$v = $rrddata->[$#$rrddata - $row]->[$idx];
				last if(defined $v);
			}
			$v = 0 if(!defined $v);
			$trendstart->[$idx] = $v;
		}

		# now calculate best angle of line.
		# vary delta as weighted standard deviation decreases, until
		# we dont get a gain by going up or down.
		$delta = $trenddelta->[$idx];
		$deltadelta = $trendstart->[$idx]/100.0;
		$lim = $deltadelta/32768.0;
		$sd = wsd($idx,$delta);
		$n = 0;
		while(($n < 100)and ($deltadelta>$lim)) { # put a cap on iterations
			$n++;
			errlog("Delta=$delta, Deviation=$sd : deltadelta=$deltadelta, limit $lim");
			$sda = wsd($idx,$delta+$deltadelta);
			$sdb = wsd($idx,$delta-$deltadelta);
			errlog("up->$sda, down->$sdb");
			if($sd<$sda and $sd<$sdb) { # we are in a trough
				$deltadelta /= 2;
			} elsif( $sda < $sdb ) {
				$delta+=$deltadelta;
				$sd = $sda;
			} else {
				$delta-=$deltadelta;
				# chage direction
				$deltadelta = -($deltadelta/2);
				$sd = $sdb;
			}
		}
		$trenddelta->[$idx] = $delta;
		errlog("Delta set to $delta");
	}

	# create $tempfile.rrd 
	$lastupdate = $endtime + $PREDICT * $interval;
	create_rrd("$tempfile.rrd");
}
#######################################################################

sub rtr_params(@)
{
	my($ds0,$ds1,$ds2,$mds0,$mds1, $mds2,$t0,$t1)=("","","","","","","","");
	my($lin, $lout, $mlin, $mlout, $lextra);
	my($dwmy,$interface,$defrrd) = @_;
	my($ssin, $ssout, $sin, $sout, $ssext, $sext);
	my($l);
	my($workday) = 0;
	my($legendi,$legendo, $legendx);
	my(@clr, $escunit);
	my($max1, $max2);
	my($havepeaks) = 0;

	# are we peak lines on this graph?
	#if(!defined $config{'routers.cgi-withpeak'} 
	#	or $config{'routers.cgi-withpeak'} =~ /y/i ) {
	#	if( $dwmy =~ /[wmy]/ or ( $dwmy =~ /d/ and $usesixhour )) {
	#		$havepeaks = 1;
	#	}
	#}

	# are we going to work out the 'working day' averages as well?
	#if( defined $config{'routers.cgi-daystart'} 
	#	and defined $config{'routers.cgi-dayend'}
	#	and $config{'routers.cgi-daystart'}<$config{'routers.cgi-dayend'}
	#	and $dwmy !~ /y/ ){
	#	$workday = 1;
	#	$timezone = 0;
	#	# Calculate timezone.  We only need to do this if we're making a graph,
	#	# and we have a 'working day' defined.
	#	if( defined $config{'web-timezone'} ) {
	#		# If its been defined explicitly, then use that.
	#		$timezone = $config{'web-timezone'};
	#	} else {
	#		# Do we have Time::Zone?
	#		eval { require Time::Zone; };
	#		if ( $@ ) {
	#			my( @gm, @loc, $hourdif );
	#			eval { @gm = gmtime; @loc = localtime; };
	#			if( $@ ) {
	#				# Can't work out local timezone, so assume GMT
	#				$timezone = 0; 
	#			} else {
	#				$hourdif = $loc[2] - $gm[2];
	#				$hourdif += 24 if($loc[3]>$gm[3] or $loc[4]>$gm[4] );
	#				$hourdif -= 24 if($loc[3]<$gm[3] or $loc[4]<$gm[4] );
	#				$timezone = $hourdif;
	#			}
	#		} else {
	#			# Use the Time::Zone package since we have it
	#			$timezone = Time::Zone::tz_local_offset() / 3600; 
	#			# it's in seconds so /3600
	#		}
	#	}
	#}

	# escaped unit string
	$escunit = $interfaces{$interface}{unit};
	$escunit =~ s/%/%%/g;
	$escunit =~ s/:/\\:/g;
	$escunit =~ s/&nbsp;/ /g;

	# identify colours
	if( defined $interfaces{$interface}{colours} ) {
		@clr = @{$interfaces{$interface}{colours}};
	}
	if(! @clr ) {
		if( $gstyle =~ /b/ ) {
			@clr =  ("#888888", "#000000", "#cccccc","#444444", "#222222");
		} else {
			@clr = ("#00cc00", "#0000ff","#006600", "#ff00ff", "#ff0000" );
		}
	}

	#$defrrd = $interfaces{$interface}{rrd};
	$defrrd =~ s/:/\\:/g;

	$sin="In: "; $sout="Out:";
	$ssin = $ssout = "";
	$sin = $interfaces{$interface}{legendi}
		if( defined $interfaces{$interface}{legendi} );
	$sout= $interfaces{$interface}{legendo}
		if( defined $interfaces{$interface}{legendo} );
	$l = length $sin; $l = length $sout if($l < length $sout);
	$sin = substr($sin.'                ',0,$l);
	$sout= substr($sout.'                ',0,$l);
	$sin =~ s/:/\\:/g; $sout =~ s/:/\\:/g;
	$sin =~ s/%/%%/g; $sout =~ s/%/%%/g;
	if( $interfaces{$interface}{integer} ) {
		$ssin = "%5.0lf"; $ssout = "%5.0lf"; 
	} elsif( $interfaces{$interface}{fixunits} ) {
		$ssin = "%7.2lf "; $ssout = "%7.2lf "; 
	} else {
		$ssin = "%6.2lf %s"; $ssout = "%6.2lf %s"; 
	}
	if( defined $config{'routers.cgi-legendunits'}
		and $config{'routers.cgi-legendunits'} =~ /y/i ) {
		$ssin .= $escunit; $ssout .= $escunit;
	}
	$sin .= $ssin; $sout .= $ssout;
	
	{
		$lin = ":Inbound"; $lout = ":Outbound";
		$mlin = ":Peak Inbound"; $mlout = ":Peak Outbound";
		$lin = ":".$interfaces{$interface}{legend1}
			if( defined $interfaces{$interface}{legend1} );
		$lout = ":".$interfaces{$interface}{legend2}
			if( defined $interfaces{$interface}{legend2} );
		$mlin = ":".$interfaces{$interface}{legend3}
			if( defined $interfaces{$interface}{legend3} );
		$mlout = ":".$interfaces{$interface}{legend4}
			if( defined $interfaces{$interface}{legend4} );
		if($interfaces{$interface}{noo} or $havepeaks
			or ( defined $interfaces{$interface}{graphstyle} 
				and $interfaces{$interface}{graphstyle} =~ /range/i )) {
				$lin .= "\\l";  
		}
	}
	$lout .= "\\l" if($lout); 
	$lin = substr( $lin."                                ",0,30 ) 
		if($lin and !$interfaces{$interface}{noo}
			and $lin !~ /\\l$/ );
	$mlout = substr( $mlout."                                ",0,30 ) 
		if ($mlout);
	$mlin = substr( $mlin."                                ",0,30 ) 
		if ($mlin);

	if( $interfaces{$interface}{nolegend} ) { $lin = $lout = ""; }

	($ds0, $ds1, $t0, $t1) = ("ds0", "ds1", "t0", "t1");
	push @params,
		"DEF:in=".$defrrd.":$ds0:$consolidation", 
		"DEF:out=".$defrrd.":$ds1:$consolidation",
		"DEF:tin=".$defrrd.":$t0:$consolidation", 
		"DEF:tout=".$defrrd.":$t1:$consolidation"
		;
	($ds0, $ds1, $t0, $t1) = ("in", "out", "tin", "tout");
### do this if we are using BITS
	if( $interfaces{$interface}{mult} ne 1 ) {
		push @params, "CDEF:fin=$ds0,".$interfaces{$interface}{mult}.",*", 
			"CDEF:fout=$ds1,".$interfaces{$interface}{mult}.",*";
		push @params, "CDEF:ftin=$t0,".$interfaces{$interface}{mult}.",*", 
			"CDEF:ftout=$t1,".$interfaces{$interface}{mult}.",*";
		($ds0, $ds1, $t0, $t1) = ("fin", "fout", "ftin", "ftout");
	}
###
	if( defined $interfaces{$interface}{factor} ) {
		push @params, "CDEF:ffin=$ds0,".$interfaces{$interface}{factor}.",*", 
			"CDEF:ffout=$ds1,".$interfaces{$interface}{factor}.",*";
		push @params, "CDEF:fftin=$t0,".$interfaces{$interface}{factor}.",*", 
			"CDEF:fftout=$t1,".$interfaces{$interface}{factor}.",*";
		($ds0, $ds1, $t0, $t1) = ("ffin", "ffout", "fftin", "fftout");
	}
# And the percentages
	$max1 = $max2 = $interfaces{$interface}{max};
	$max1 = $interfaces{$interface}{max1} 
		if(defined $interfaces{$interface}{max1});
	$max2 = $interfaces{$interface}{max2} 
		if(defined $interfaces{$interface}{max2});
	if( $max1  ) {
		push @params,
			"CDEF:pcin=$ds0,100,*,".$max1.",/";
	#		"CDEF:mpcin=$mds0,100,*,".$max1.",/";
	}
	if( $max2  ) {
		push @params,
			"CDEF:pcout=$ds1,100,*,".$max2.",/";
	#		"CDEF:mpcout=$mds1,100,*,".$max2.",/";
	}


	if( $interfaces{$interface}{available} ) {
		# availability percentage
		push @params, "CDEF:apc=in,UN,out,UN,+,2,EQ,0,100,IF";
		# Now, the average of apc is the percentage availability!
	}

#	now for the actual lines : put the peaklines for d only if we have a 6 hr
#	dont forget to use more friendly colours if this is black and white mode
		push @params, "AREA:$ds0".$clr[0].$lin
			if(!$interfaces{$interface}{noi});
		push @params, "AREA:$t0#80ff80"
			if(!$interfaces{$interface}{noi});
		if(!$interfaces{$interface}{noo}) {
			if( defined $interfaces{$interface}{graphstyle} ) {
				if( $interfaces{$interface}{graphstyle} =~ /stack/i ) {
					push @params, "STACK:$ds1".$clr[1].$lout;
				} elsif( $interfaces{$interface}{graphstyle} =~ /range/i ) {
					push @params, "AREA:$ds1#ffffff"; # erase lower part
					# if workingday active, put HIGHLIGHTED lower in
					if( $workday and $gstyle !~ /b/) {
						push @params, "CDEF:lwday=wdin,UN,0,$ds1,IF",
							"AREA:lwday#ffffcc";
					}
					push @params, "LINE1:$ds1".$clr[0]; # replace last pixel
				} else {
					# we do it here so it isnt overwritten by the incoming area
					push @params, "LINE1:$ds1".$clr[1].$lout;
					push @params, "LINE1:$t1#8080ff";
				}
			} else {
				# we do it here so it isnt overwritten by the incoming area
				push @params, "LINE1:$ds1".$clr[1].$lout;
				push @params, "LINE1:$t1#8080ff";
			}
		}

# data unavailable
	push @params,
		"CDEF:down=in,UN,out,UN,tin,UN,tout,UN,+,+,+,4,EQ,INF,0,IF","AREA:down#d0d0d0";
# the max line
	if( $interfaces{$interface}{max} 
		and ! ( defined $config{'routers.cgi-maxima'}
			and  $config{'routers.cgi-maxima'} =~ /n/i )
		and !$interfaces{$interface}{nomax}
	) {
		my( $lmax ) = "";
		my( $lamax ) = "";
#		if( $dwmy !~ /s/ ) {
			if( defined $interfaces{$interface}{mblegend} ) {
				$lmax = $interfaces{$interface}{mblegend};
				$lmax =~ s/:/\\:/g; $lmax = ':'.$lmax;
			} elsif( $interfaces{$interface}{isif} ) {
				$lmax =":100% Bandwidth";
			} else { $lmax =":Maximum"; } 
			if( $max1 and $max2 and ($max1 != $max2) ) {
			$lmax .= " (".doformat($max1,$interfaces{$interface}{fixunits},0) 
				.$interfaces{$interface}{unit}.","
				.doformat($max2,$interfaces{$interface}{fixunits},0) 
				.$interfaces{$interface}{unit}.")\\l";
			} else {
			$lmax .= " (".doformat($interfaces{$interface}{max},
					$interfaces{$interface}{fixunits},0) 
				.$interfaces{$interface}{unit}.")\\l";
			}
			if( defined $interfaces{$interface}{absmax} ) {
				if( defined $interfaces{$interface}{amlegend} ) {
					$lamax = ":".$interfaces{$interface}{amlegend};
				} else { $lamax =":Hard Maximum"; } 
				$lamax .= " (".doformat($interfaces{$interface}{absmax},
					$interfaces{$interface}{fixunits},1) 
					.$interfaces{$interface}{unit}.")\\l";
			}
#		}
		if( $max1 and $max2 and ($max1 != $max2)) {
			if( $gstyle =~ /b/ ) {
				push @params, "HRULE:".$max1."#cccccc$lmax";
				push @params, "HRULE:".$max2."#cccccc";
			} else {
				push @params, "HRULE:".$max1."#ff0000$lmax";
				push @params, "HRULE:".$max2."#ff0000";
			}
		} else {
			if( $gstyle =~ /b/ ) {
			push @params, "HRULE:".$interfaces{$interface}{max}."#cccccc$lmax";
			} else {
			push @params, "HRULE:".$interfaces{$interface}{max}."#ff0000$lmax";
			}
		}
		if( defined $interfaces{$interface}{absmax}
			and !$interfaces{$interface}{noabsmax} ) {
			if( $gstyle =~ /b/ ) {
				push @params, "HRULE:".$interfaces{$interface}{absmax}
					."#aaaaaa$lamax";
			} else {
				push @params, "HRULE:".$interfaces{$interface}{absmax}
					."#ff0080$lamax";
			}
		}
	}
#	now for the labels at the bottom
		if( $max1 ) {
			if(!$interfaces{$interface}{noi}) {
#				push @params, "GPRINT:$mds0:MAX:Max $sin\\g" ;
#				push @params ,"GPRINT:mpcin:MAX: (%2.0lf%%)\\g"
#					if($interfaces{$interface}{percent});
				push @params,"GPRINT:$ds0:$consolidation:  $conspfx $sin\\g" ;
				push @params ,"GPRINT:pcin:$consolidation: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params,"GPRINT:$ds0:LAST:  Cur $sin\\g" ;
				push @params ,"GPRINT:pcin:LAST: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params, "COMMENT:\\l" ;
			}
			if(!$interfaces{$interface}{noo}) {
#				push @params, "GPRINT:$mds1:MAX:Max $sout\\g" ;
#				push @params ,"GPRINT:mpcout:MAX: (%2.0lf%%)\\g"
#					if($interfaces{$interface}{percent});
				push @params,"GPRINT:$ds1:$consolidation:  $conspfx $sout\\g" ;
				push @params ,"GPRINT:pcout:$consolidation: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params,"GPRINT:$ds1:LAST:  Cur $sout\\g" ;
				push @params ,"GPRINT:pcout:LAST: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params, "COMMENT:\\l" ;
			}
			if( defined $config{'routers.cgi-maxima'}
				and $config{'routers.cgi-maxima'} =~ /n/i
				and !$interfaces{$interface}{nomax} ) {
				my( $comment );
				if(defined $interfaces{$interface}{mblegend}) {
					$comment = $interfaces{$interface}{mblegend};
					$comment = "COMMENT:".decolon($comment);
				} elsif($interfaces{$interface}{isif}) {
					$comment = "COMMENT:100% Bandwidth";
				} else {
					$comment = "COMMENT:Maximum value";
				}
				$comment .= decolon(" ".doformat($interfaces{$interface}{max},
						$interfaces{$interface}{fixunits},0)
					.$escunit."\\l");
				push @params, $comment;
 		 	}
		} else {
			push @params,
#				"GPRINT:$mds0:MAX:Max $sin\\g",
				"GPRINT:$ds0:$consolidation:  $conspfx $sin\\g",
				"GPRINT:$ds0:LAST:  Cur $sin\\l" 
					if(!$interfaces{$interface}{noi});
			push @params,
#				"GPRINT:$mds1:MAX:Max $sout\\g",
				"GPRINT:$ds1:$consolidation:  $conspfx $sout\\g",
				"GPRINT:$ds1:LAST:  Cur $sout\\l"
					if(!$interfaces{$interface}{noo});
		}
		if( $interfaces{$interface}{available} ) {
			push @params, "GPRINT:apc:AVERAGE:Data availability\\: %.2lf%%\\l";
		}
	foreach (@info) {
		push @params, "COMMENT:".decolon($_);
	}
}

########################################################################
# Actually create the necessary graph

sub make_graph(@)
{
	my ($e, $thisurl, $s, $autoscale);
	my ($tstr, $gheight, $width, $gwidth, $gtitle);
	my( $maxwidth ) = 30;
	my( $endtime );
	my($thisgraph,$thisrrd) = @_;
	my($interface) = $target;
	my( $rrdoutput, $rrdxsize, $rrdysize );


# Shall we scale it, etc
	$autoscale = 1;
	$s = $dwmy; $s =~ s/s//;
	if( $interfaces{$interface}{unscaled} ) {
		$autoscale = 0 if ($interfaces{$interface}{unscaled} =~ /$s/i);
	}

	$tstr = "6-hour" if( $dwmy =~ /6/ ) ;
	$tstr = "Daily" if( $dwmy =~ /d/ ) ;
	$tstr = "Weekly" if( $dwmy =~ /w/ ) ;
	$tstr = "Monthly" if( $dwmy =~ /m/ ) ;
	$tstr = "Yearly" if( $dwmy =~ /y/ ) ;

	$gtitle = $interfaces{$interface}{desc};
	if( ($dwmy.$gstyle)=~/s/ ) {
		if($gstyle=~/x/) { $maxwidth = 50; }
		elsif($gstyle=~/l/) { $maxwidth = 40; }
		else { $maxwidth = 30; }
	}
	if(!$gtitle or ((length($gtitle)>$maxwidth)and(($dwmy.$gstyle) =~ /s/))) {
		$gtitle = "";
#		$gtitle .= $routers{$router}{shdesc}.": " 
#				if( defined $routers{$router}{shdesc});
		$gtitle .= $interfaces{$interface}{shdesc};
	}
	$gtitle .= ": Trend Analysis";
	$gtitle = $q->unescape($gtitle);
	$gtitle =~ s/&nbsp;/ /g; $gtitle =~ s/&amp;/&/g;

	@params = ();

	if ( $gstyle =~ /^s/ ) { $width = 200; $gwidth = 200; } #short
	elsif ( $gstyle =~ /^t/ ) { $width = 200; $gwidth = 400; } #stretch
	elsif ( $gstyle =~ /^l/ ) { $width = 400; $gwidth = 530; } #long
	elsif ( $gstyle =~ /^x/ ) { $width = 400; $gwidth = 800; } #xlong
	else { $width = 400; $gwidth = 400; } # default (normal)
	if ( $gstyle =~ /2/ ) { $gheight = 200; }
	else { $gheight = 100; }

	push @params, $thisgraph;
	if( $graphsuffix eq "png" ) {
		push @params, '--imgformat',uc $graphsuffix;
	}
	push @params,"--base", $k;
	push @params, qw/--lazy -l 0 --interlaced/;
	push @params,"--units-exponent",0
		if($interfaces{$interface}{fixunits}
			and $RRDs::VERSION >= 1.00030 );
	# only force the minimum upper-bound of graph if we have a max,
	# and we dont have maxima=n, and we dont have unscaled=n
	if( ! $autoscale ) {
		if( $interfaces{$interface}{max} and ( 
			!defined $config{'routers.cgi-maxima'}
			or $config{'routers.cgi-maxima'} !~ /n/i
		) ) {
			push @params, "-u", $interfaces{$interface}{max} ;
		} else {
			push @params, "-u", 1;
		}
	} else {
		push @params, "-u", 1;
	}
# could have added a "-r" there to enforce the upper limit rigidly
#	push @params, "-v", $config{$statistic}{-v};
	push @params, "-w", $gwidth, "-h", $gheight;
		push @params, "-e", $lastupdate;
		$endtime = $lastupdate;
	push @params, "-s", "end".(-1 * $width)."m"  if ( $dwmy =~ /6/ );
	push @params, "-s", "end".(-5 * $width)."m"  if ( $dwmy =~ /d/ );
	push @params, "-s", "end".(-25 * $width)."m" if ( $dwmy =~ /w/ );
	push @params, "-s", "end".(-2 * $width)."h"  if ( $dwmy =~ /m/ );
	push @params, "-s", "end".(-1 * $width)."d"   if ( $dwmy =~ /y/ );
	push @params,"--x-grid","MINUTE:15:HOUR:1:HOUR:1:0:$dailylabel"  
		if ( $dwmy =~ /6/ );
	push @params,"--x-grid","HOUR:1:HOUR:24:HOUR:2:0:$dailylabel"  
		if ( $dwmy =~ /d/ );
	push @params,"--x-grid","HOUR:6:DAY:1:DAY:1:86400:%a" 
		if ( $dwmy =~ /w/ );
	push @params,"--x-grid","DAY:1:WEEK:1:WEEK:1:604800:Week"
			." ".$monthlylabel  
		if ( $dwmy =~ /m/ and $RRDs::VERSION >= 1.00029  );
	push @params,"--title", $gtitle;

	if ( defined $interfaces{$interface}{ylegend} ) {
		push @params, "--vertical-label", $interfaces{$interface}{ylegend};
	} else {
		push @params, "--vertical-label", $interfaces{$interface}{unit};
	}

		rtr_params($dwmy,$interface,$thisrrd);

	if ( defined $config{'routers.cgi-withdate'}
		and $config{'routers.cgi-withdate'}=~/y/ ) {
		push @params, "COMMENT:".decolon(shortdate($endtime))."\\r";
	}
	
	( $rrdoutput, $rrdxsize, $rrdysize ) = RRDs::graph(@params);
	$e = RRDs::error();
	if($e) {
		print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
		errlog("RRDGraph: $e");
	} else {
		# output the graphic directly from disk
		open GRAPH, "<$thisgraph";
		binmode GRAPH;
		binmode STDOUT;
		print $q->header({ '-type'=>"image/$graphsuffix", '-expires'=>"now",
			'-Content-Disposition'=>"filename=\"image.$graphsuffix\"" });
		while( <GRAPH> ) { print; }
		close GRAPH;
	}
	return;	
}

#######################################################################
# create and output the GIF/PNG
sub makeimage {
	my( $tmpimage, $buf );

	# Create the graphic header
	$headeropts{'-expires'} = "+6min";
	if( defined $config{'web-png'} and $config{'web-png'}=~/[1yY]/ ) {
		$headeropts{'-type'} = 'image/png';
		$tmpimage = $tempfile.".png";
		$graphsuffix = 'png';
	} else {
		$headeropts{'-type'} = 'image/gif';
		$tmpimage = $tempfile.".gif";
		$graphsuffix = 'gif';
	}

	# call graphing on $tempfile.rrd to create $tmpimage
	make_graph($tmpimage,"$tempfile.rrd");

	# remove the temporary files
	unlink $tmpimage;
	unlink $tempfile.".rrd";
}

sub errorpage {
	if(!$q->param('img')) {
		print $q->header({%headeropts});
		start_html_ss({-title=>"Error",-class=>'error'});
		print $q->h1("Error in configuration")."\n";
		print $q->p($_[0]);
		print $q->hr.$q->small("S Shipway: RRD trending analysis v$VERSION")."\n";
		print "<!-- \nThis script should not be called from the command line!\n-->\n";
		print $q->end_html;
	} else {
		print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
	}
}
#######################################################################

# read in the conf file
$conffile = $q->param('conf') if(defined $q->param('conf'));
readconf('routers.cgi','web','trend.cgi');
$LOG = $config{'trend.cgi-logfile'} if( defined $config{'trend.cgi-logfile'} );
$debug = $config{'trend.cgi-debug'} if( defined $config{'trend.cgi-debug'} );
$DECAY = $config{'trend.cgi-decay'} if( defined $config{'trend.cgi-decay'} );
$TMPPATH = $config{'trend.cgi-workdir'} 
	if( defined $config{'trend.cgi-workdir'} 
	and -d $config{'trend.cgi-workdir'} );

# For debugging only
if( $q->param('log') ) {
	print $q->header(\%headeropts);
	start_html_ss({-class=>'error'});
	if( -r $LOG ) {
		print "\n<PRE>\n";
		open RLOG, "<$LOG";
		while ( <RLOG> ) { print; }
		close RLOG;
		print "</PRE>\n";
	} else {
		print $q->h1("Error").$q->p("No log file is available.")."\n";
	}
	print $q->end_html."\n";
	exit 0;
}
# Process parameters
$file   = $q->param('fi') if(defined $q->param('fi'));
$target = $q->param('ta') if(defined $q->param('ta'));
$backurl = $q->param('b') if(defined $q->param('b'));
$targetwindow = $q->param('t') if(defined $q->param('t'));
$dwmy = $q->param('dwmy') if(defined $q->param('dwmy'));
$DECAY = $q->param('dk') if(defined $q->param('dk'));
$PREDICT = $q->param('pr') if(defined $q->param('pr'));
$BASE = $q->param('ba') if(defined $q->param('ba'));
$routersurl = $q->param('url') if(defined $q->param('url'));

# HTTP headers
%headeropts = ( -expires=>"now" );
$headeropts{target} = $targetwindow if($targetwindow);

# caching daemon
if( $ENV{RRDCACHED_ADDRESS} ) {
	errlog("Warning: RRDCACHED_ADDRESS=".$ENV{RRDCACHED_ADDRESS});
	delete $ENV{RRDCACHED_ADDRESS};
}

# Test a few things
$cfile = $config{'routers.cgi-confpath'}.$pathsep.$file;
if( ! -r $cfile ) {
	errorpage("Unable to read configuration file $cfile : please check that this file exists, and is readable by the web process.  Check defaults in the trend.cgi script itself.");
	exit 0;
}
if( ! -w $TMPPATH ) {
	errorpage("Unable to write to temporary directory $TMPPATH :  Please check the definition in the routers2.conf, and the default specified in the trend.cgi script itself.");
	exit 0;
}
if( $debug and -f $LOG and ! -w $LOG ) {
	errorpage("Cannot write to log file $LOG : Either give a correct log file location (in the routers2.conf or the trend.cgi script) or disable debug logging (in the routers2.conf).");
	exit 0;
}
if( ! $target ) {
	errorpage("No Target defined: You cannot (yet) use trend.cgi as a device-level Extension, it must be defined as a Target-level one.");
	exit 0;
}

# Set colour defaults
foreach ( 'routers.cgi', 'trend.cgi' ) {
	$fgcolour = $config{"$_-fgcolor"} if(defined $config{"$_-fgcolor"});
	$fgcolour = $config{"$_-fgcolour"} if(defined $config{"$_-fgcolour"});
	$bgcolour = $config{"$_-bgcolor"} if(defined $config{"$_-bgcolor"});
	$bgcolour = $config{"$_-bgcolour"} if(defined $config{"$_-bgcolour"});
	$linkcolour = $config{"$_-linkcolor"} if(defined $config{"$_-linkcolor"});
	$linkcolour = $config{"$_-linkcolour"} if(defined $config{"$_-linkcolour"});
}

# read in the MRTG cfg file
read_cfg($cfile);

if(!defined $interfaces{$target} ) {
	errorpage( "Unable to find target '$target' in file $cfile" );
	exit 0;
}

unshift @INC, ( split /[\s,]+/,$config{"web-libadd"} )
	if( defined $config{"web-libadd"} );

eval { require RRDs; };
if($@) {
	errorpage("Unable to load RRDs perl module: Have you installed it correctly?<P>$@");
	exit 0;
}

# Background colours
$bgcolour = $interfaces{$target}{background}
	if(defined $interfaces{$target}{background});


# First, make the HTML page, calling self for the graphic
if(! $q->param('img') ) {
	print $q->header(\%headeropts);
	mypage;
	exit 0;
}
	
# Now we read in the rrd file, and do the trending
$tempfile = $TMPPATH.$pathsep."trend.".time;
do_trending($target{rrd},"$tempfile.rrd");

if ( -f "$tempfile.rrd" ) {
	# Make the page
	makeimage();
} else {
	print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
	errlog("Didn't make the working rrd file");
}

# End
errlog("Complete");
exit(0);
