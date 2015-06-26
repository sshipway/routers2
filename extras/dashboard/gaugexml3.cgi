#!/usr/bin/perl
#vim:ts=4
#
# gaugexml3.cgi : Steve Shipway www.steveshipway.org
#
# Produce XML for slickboard/swfgauge, based on contents of MRTG .cfg file
#
# V2.1: fix refresh bug when target param given
#  2.2: parameterise the routers2 URL
#  2.3: fix if the current max value is actually zero
#       correct the legends and the aspercent usage
#       correctly implement the thresholds display
#  3.0: update for slickboard.swf instead of gauge.swf
#  3.1: support more gaugexml* directives, Upperlimit, etc
#  3.2: extra context menu etc, fix tooltips, fix links on registered
#  3.3: hidden legend in drawer (slickboard only)
#  3.4: Fix for Perl 5.10/RHEL6/etc (small gauges)
#  3.5: Fix for gaugexml.cgi * directive parsing
#  3.6: fix for upperlimit

# Call the CGI with parameters:
#    cols = number of columns, default 1
#    width = width, default 200
#    twitch = twitch amount, default 2
#    cfg = MRTG cfg file relative to cfgpath, required
#    target = MRTG targetname (default is all targets)


use strict;
use CGI;
use FileHandle;
use Text::ParseWords;

my($VERSION) = "v3.4";
my($REGISTERED) = ""; # Set this to your license key if you have one
########################################################################
# If my url matches this regexp, we're in public mode
my($PUBLICURL) = 'public';
# If in public mode, requested cfg must match this regexp
my($PUBLICCFG) = '^other-summary\/';
# This is the confpath from the routers2.conf
my($CFGDIR) = "/u01/mrtg/conf";
# This is the URL for routers2.cgi, if you have it
my($ROUTERSCGI) = "http://monitor.auckland.ac.nz/cgi-bin/routers2-public.cgi";
# Default workdir for RRD files if not set in cfg file
my($workdir) = "/u01/rrdtool";
# Use 1 for SLICKBOARD.SWF, 0 for GAUGE.SWF
my($MODE) = 1;
# Set to 1 to get popups with additional info (usually only for debugging)
my($INFO) = 0;
# Degrees for the needles to twicth
# Set to non-zero to have twitching by default (1 is about right)
my($TWITCH) = 1;
# How often to update in seconds; recommend 60 minimum, 300 maximum
my($DELAY) = 60;
# Default type (gauge/bars)
my($TYPE) = '';
########################################################################
# Not a good idea to change below here
# Columns of gauges if placing multiple ones
my($COLS,$WIDTH,$HEIGHT) = ( 1, 200, 250 );
my($FROMANGLE,$TOANGLE) = ( -140, 140 );
my($OBJECT) = 0;
my($XOFF,$YOFF) = (0,0);
my($q) = new CGI;
my($URL) = $q->url();
my(%interfaces);
my($debugmessage) = '';
my($interval) = 5;
my($pathsep) = '/';
my($links) = '';
my($DEBUG) = 0;
my($BACK) = 4;
my($TARGET) = '';
my($DEVICE) = '';
my($curdiv) = 1; # Current divisor for the gauge
my(@defcolours) = ( 
         "00ff00","0000ff","ff0000","00cccc","cccc00","cc00cc",
        "8800ff", "88ff00", "ff8800", "0088ff", "ff0088", "00ff88" );
 
$DEBUG = 1 if( $q->url() =~ /localhost/ );

#############################################################################
# Utility functions
sub roundoff($) { # this is rather ugly
	my($a) = $_[0];
	my($b) = $a;
	return $a if( $a =~/^\d5?0*$/ );
	$a = int(($a*1.1)+0.99);
	$b = substr($a,0,1); $b += 1 if ( $a !~ /^\d0*$/ );
	$b += 1 if( $b>1 and ($b % 5) ne 0 );
	$b = 5 if($b>1 and $b<5 and $a<10);
	$b .= '0' x (length($a)-1);
	print "Rounding off ".$_[0]." ==110%=> $a ==choose=> $b\n" if($DEBUG);
	return $b;
}
sub doformat($) { 
	my($sfx)="";
	return "" if($_[0] eq "U");
	if($_[0]=~ /([^\d]+)$/) { $sfx = $1; }
	return ((int(100*$_[0]/$curdiv)/100).$sfx); 
}
sub dokmgformat($$) {
	my($v,$u) = @_;
	my($s) = doformat($v);

	$s .= 'k' if($curdiv == 1000);
	$s .= 'M' if($curdiv == 1000000);
	$s .= 'G' if($curdiv == 1000000000);
	$s .= 'T' if($curdiv == 1000000000000);
	$s .= $u if($u);
	
	return $s;
}
sub getunits($$$) {
	my($m,$u,$f) = @_;
	
	$curdiv = "1";
	$u =~ s/&nbsp;//g; $u =~ s/\s*$//;

	if($m > 2000000000000 ) { $curdiv = 1000000000000; return "T$u" if($u and !$f);
return "x1e12" ; }
	if($m > 2000000000 ) { $curdiv = 1000000000; return "G$u" if($u and !$f);
return "x1e9" ; }
	if($m > 2000000 ) { $curdiv = 1000000; return "M$u" if($u and !$f);
return "x1,000,000" ; }
	if($m > 2000 ) { $curdiv = 1000; return "k$u" if($u and !$f);
return "x1,000" ; }
	$curdiv = 1; return $u if(!$f); return "";
}
sub inlist($@)
{
    my($pat) = shift @_;
    return 0 if(!defined $pat or !$pat or !@_);
    foreach (@_) { return 1 if( $_ and /$pat/i ); }
    return 0;
}
sub calcstep($) {
	my($m) = $_[0];
	my($a);
	$a = int($m/10);
	$a = 1 if($a < 1);

	return 0.1 if($m == 1);
	return 0.25 if($m < 3);
	return 0.5 if($m < 5);
	return $a if( $a =~ /^[125]/ ) ;
	$a =~ s/^./2/ if( $a =~ /^3/ ) ;
	$a =~ s/^./5/ if( $a =~ /^[467]/ ) ;
	$a =~ s/^./10/ if( $a =~ /^[89]/ ) ;
	
	return $a;
}

#############################################################################
# Read MRTG .cfg file.  Modified from function in routers2.cgi

sub readcfg($) {
	my($cfgfile,$makespecial) = @_;
	my($opts, $graph, $key, $k, $fd, $buf, $curif, @myifs, $arg, $argb, $rrd);
	my($ifcnt, @ifarr, $t, $desc, $url, $icon, $targ, $newfile, $targfile);
	my( $lasthostname, $lastcommunity ) = ("","");
	my($level, $insec, $noop, $logdir);

	my( $inpagetop, $inpagefoot ) = (0,0);

	return if(!$cfgfile);

	$debugmessage .= "$cfgfile ";

	$fd = new FileHandle ;

	if(! $fd->open( "<$cfgfile" )) {
		$interfaces{$cfgfile} = {
			shdesc=>"Error", desc=>"Cannot open file $cfgfile", inmenu=>0,
			rrd=>"", insummary=>0, inout=>0, incompact=>0, mode=>"ERROR",
			icon=>"alert-sm.gif" };
		return;
	}

	print "Processing $cfgfile\n" if($DEBUG);

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
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Target\[(.+?)\]\s*:\s*(.+)/i ) {
			$curif = $2; $arg = $3;
			push @myifs, $curif;
			# This ***MIGHT*** save people who put their .cfg files
			# out of sequence?
			if(!defined $interfaces{$curif}) {
			$interfaces{$curif} = { file=>$cfgfile, target=>$curif,
					insummary=>1, incompact=>1, inmenu=>1, isif=>0,
					interval=>$interval, nomax=>0, noabsmax=>0  };
			} else {
			$interfaces{$curif} = { file=>$cfgfile, target=>$curif,
					insummary=>1, incompact=>1, inmenu=>1, isif=>0,
					interval=>$interval, nomax=>0, noabsmax=>0,
					%{$interfaces{$curif}}  };
			}
			if(defined $interfaces{_}{directory}) {
				$interfaces{$curif}{rrd} = 
					$workdir.$pathsep.$interfaces{_}{directory}
					.$pathsep.(lc $curif).".rrd";
			} else {
				$interfaces{$curif}{rrd} = $workdir.$pathsep.(lc $curif).".rrd";
			}
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
#			print "Added interface $curif\n" if($DEBUG);
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\*)?(Title|Descr?|Description)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $3; $arg = $4;
			if(!defined $interfaces{$curif}) {
				if(defined $interfaces{"_$curif"}) {
					$curif = "_$curif";
				} else {
					$interfaces{$curif} = {note=>"Out of sequence"};
				}
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
		if( $buf =~ /^\s*routers2?\.cgi\*Short(Name|Descr?|Description)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{shdesc} = $arg if($arg);
			next;
		}
		if(( $buf =~ /^\s*(routers2?\.cgi|g[au][ua]gexml3?\.cgi|slickboard|swfgauge)\*Options\[(.+?)\]\s*:\s*(\S.*)/i )  
			or ( $buf =~ /^\s*g[au][ua]ge\.(swf|cgi)\*Options\[(.+?)\]\s*:\s*(\S.*)/i )) { 
			$curif = $2; $arg = $3;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{cgioptions}="" if(!$interfaces{$curif}{cgioptions});
			$interfaces{$curif}{cgioptions} .= " ".$arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\.cgi\*)?MaxBytes\[(.+?)\]\s*:\s*(\d+)/i ) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{maxbytes} = $3;
			next;
		}
		if($buf=~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\*|g[au][ua]gexml3?\.cgi|g[au][ua]ge\.swf\*|slickboard\*|swfgauge\*)?Unscaled\[(.+?)\]\s*:\s*([6dwmy]*)/i){ 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{unscaled} = $3;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\.cgi\*)?YLegend\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{ylegend} = $3;
			next;
		}
		if($buf=~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\.cgi\*)?ShortLegend\[(.+?)\]\s*:\s*(.*)/i){ 
			$curif = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{unit} = $3;
			$interfaces{$curif}{unit} =~ s/&nbsp;/ /g;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\.cgi\*)?(Legend[IO1234TA][IO]?)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $3; $key = lc $2; $arg = $4;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$arg =~ s/&nbsp;/ /;
			$interfaces{$curif}{$key} = $arg;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*Mode\[(.+?)\]\s*:\s*(\S+)/i ) {
			next if(!defined $interfaces{$1});
			$interfaces{$1}{mode} = $2;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*(Graph|Summary)\[(.+?)\]\s*:\s*(\S.*)/i ) {
			$curif = $2; $arg = $3; $argb = (lc $1);
			next if( $curif eq '_' ); # not allowed
			if(!defined $interfaces{$curif}) {
				if( $argb eq "summary") {
					$curif = "_$curif" ;
				} else {
					# Create a dummy target...
					$interfaces{$curif} = { file=>$cfgfile, target=>$curif,
					insummary=>0, incompact=>0, inmenu=>0, isif=>0,
					interval=>$interval, nomax=>0, noabsmax=>0  };
					if(defined $interfaces{_}{directory}) {
						$interfaces{$curif}{rrd} = 
							$workdir.$pathsep.$interfaces{_}{directory}
							.$pathsep.(lc $curif).".rrd";
					} else {
						$interfaces{$curif}{rrd} 
							= $workdir.$pathsep.(lc $curif).".rrd";
					}
				}
			}
			next if(!defined $interfaces{$curif});
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
				push @{$interfaces{"_$graph"}{targets}}, $curif
					if(!inlist("^$curif\$",@{$interfaces{"_$graph"}{targets}}));
				$interfaces{"_$graph"}{cgioptions} .= " $opts";
			} else {
				if( $argb eq "summary" ) {
					$interfaces{"_$graph"} = {
						shdesc=>$graph,  targets=>[$curif], 
						cgioptions=>$opts, mode=>"\177_USERSUMMARY",
						usergraph=>1, icon=>"summary-sm.gif", 
						inout=>0, incompact=>0, withtotal=>0, withaverage=>0,
						insummary=>0, inmenu=>1, desc=>"Summary $graph",
						issummary=>1
					};
				} else {
					$interfaces{"_$graph"} = {
						shdesc=>$graph,  targets=>[$curif], 
						cgioptions=>$opts, mode=>"\177_USER",
					usergraph=>1, icon=>"cog-sm.gif", inout=>0, incompact=>0,
					insummary=>0, inmenu=>1, desc=>"User defined graph $graph",
						withtotal=>0, withaverage=>0, issummary=>0
					};
					$interfaces{"_$graph"}{unit} = $interfaces{$curif}{unit}
						if($interfaces{$curif}{unit});
					$interfaces{"_$graph"}{rrd} = $interfaces{$curif}{rrd};
				}
#				$interfaces{"_$graph"}{withtotal} = 1 
#					if( defined $config{'routers.cgi-showtotal'}
#						and $config{'routers.cgi-showtotal'}=~/y/i);
				push @myifs, "_$graph";
			}
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*Ignore\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			if( $arg =~ /y/i ) {  
				$interfaces{$curif}{insummary} = 0;
				$interfaces{$curif}{inmenu} = 0;
				$interfaces{$curif}{inout} = 0;
				$interfaces{$curif}{isif} = 0;
			}
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*InSummary\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{insummary} = 1; }
			else { $interfaces{$curif}{insummary} = 0; }
			next;
		}
		if( $buf =~ /^\s*(g[au][ua]ge\.swf|g[au][ua]gexml3?\.cgi|swfgauge|slickboard)\*Hide\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{inmenu} = 0; }
			else { $interfaces{$curif}{inmenu} = 1; }
			next;
		}
		if( $buf =~ /^\s*(g[au][ua]ge\.swf|g[au][ua]gexml3?\.cgi|swfgauge|slickboard)\*Max(Bytes)?\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $3; $arg = $4;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{maxbytes} = $2;
			$interfaces{$curif}{unscaled} = "none";
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*InMenu\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{inmenu} = 1; }
			else { $interfaces{$curif}{inmenu} = 0; }
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*InOut\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{inout} = 1; }
			else { $interfaces{$curif}{inout} = 0; }
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*InCompact\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{incompact} = 2; }
			else { $interfaces{$curif}{incompact} = 0; }
			next;
		}
		if( $buf =~ /^\s*Directory\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			$arg =~ s/[\s\\\/]+$//; # trim trailing spaces and path separators!
			$interfaces{$curif}{rrd} = 
				$workdir.$pathsep.$arg.$pathsep.(lc $curif).".rrd";
			$interfaces{$curif}{directory} = $arg;
			next;
		}
		if( $buf =~ /^\s*Logdir\s*:\s*(\S+)/i ) { 
			$logdir = $1; $logdir =~ s/[\\\/]+$//; $workdir = $logdir; next; }
		if( $buf =~ /^\s*Workdir\s*:\s*(\S+)/i and !$logdir ) { 
			$workdir = $1; $workdir =~ s/[\\\/]+$//; next; }
		if( $buf =~ /^\s*Interval\s*:\s*(\d+)/i ) { $interval = $1; next; }
		if( $buf =~ /^\s*Include\s*:\s*(\S+)/i ) { 
			readcfg($1);
			next; 
		}
		if( $buf =~ /^\s*LibAdd\s*:\s*(\S+)/i ) { push @INC, $1; next; }
		if($buf=~ /^\s*(routers2?\.cgi\*)?MaxBytes(\d)\[(.+?)\]\s*:\s*(\d+)/i ){
			$curif = $3; $arg = $4;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{"maxbytes$2"} = $arg;
			$interfaces{$curif}{maxbytes} = $arg
				if(!$interfaces{$curif}{maxbytes});
			next;
		}
#		# the regexp from hell
#		if( $buf =~ /^\s*(routers2?\.cgi\*)?Colou?rs\[(.+?)\]\s*:\s*[^#]*(#[\da-f]{6})[\s,]+[^#]*(#[\da-f]{6})[\s,]+[^#]*(#[\da-f]{6})[\s,]+[^#]*(#[\da-f]{6})/i ) { 
#			$curif = $2; 
#			$curif = "_$curif" if(!defined $interfaces{$curif});
#			next if(!defined $interfaces{$curif});
#			$interfaces{$curif}{colours} = [ $3,$4,$5,$6 ];
#			next;
#		}
        if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\.cgi\*|swfgauge\*|gauge\.swf\*|slickboard\*)?Colou?rs\[(.+?)\]\s*:\s*(.*)/i ) {
            $curif = $2; $arg = $3;
            $curif = "_$curif" if(!defined $interfaces{$curif});
            next if(!defined $interfaces{$curif});
            $interfaces{$curif}{colours} = []; # null array
            while( $arg =~ s/^[\s,]*[^#]*(#[\da-fA-F]{6})[\s,]*// ) {
                push @{$interfaces{$curif}{colours}},$1;
            }
            $interfaces{$curif}{colours} = [ '#00ff00','#0000ff' ]
                if($#{$interfaces{$curif}{colours}}<0);
            next;
        }
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\.cgi\*|swfgauge\*|gauge\.swf\*|slickboard\*)?AbsMax\[(.+?)\]\s*:\s*(\d+)/i ) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{absmaxbytes} = $3;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Factor\[(.+?)\]\s*:\s*(-?[\d\.]+)/i ) { 
			$curif = $2; $arg = $3;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{factor} = $arg if($arg != 0);
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Supp?ress?\[(.+?)\]\s*:\s*(\S+)/i ) { 
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{suppress} = $arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi|g[au][ua]gexml3?\.cgi|swfgauge|slickboard|g[au][ua]ge\.swf)\*UpperLimit\[(.+?)\]\s*:\s*(\d+)/i ) { 
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{upperlimit} = $arg;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*LowerLimit\[(.+?)\]\s*:\s*(\d+)/i ) { 
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{lowerlimit} = $arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\.cgi\*|swfgauge\*|gauge\.swf\*|slickboard\*)?(Thresh(Max|Min)[IO])\[(.+?)\]\s*:\s*([\d%]+)/i ) { 
			$curif = $4; $arg = $5; 
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{(lc $2)} = $arg;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*FixUnits?\[(.+?)\]\s*:\s*(\d+)/i ) { 
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{exponent} = $arg;
			$interfaces{$curif}{fixunits} = 1; # Implied
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
#		print "Processing interface $curif options (isif=".$interfaces{$curif}{isif}."...\n" if($DEBUG);
		if(defined $interfaces{$curif}{options} ) {
		foreach $k ( split /[\s,]+/,$interfaces{$curif}{options} ) {
#			print "Option: $k\n" if($DEBUG);
			if( $k eq "unknaszero") { $interfaces{$curif}{unknaszero} = 1; }
			$interfaces{$curif}{noo} = 1 if( $k eq "noo");
			$interfaces{$curif}{noi} = 1 if( $k eq "noi");
			if( $k eq "bits") { 
				$interfaces{$curif}{bytes} = 0; 
				$interfaces{$curif}{bits} = 1; }
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
			if( $k eq "dorelpercent") {
				 $interfaces{$curif}{noo} = 1;
				 $interfaces{$curif}{dorelpercent} = 1;
				 $interfaces{$curif}{fixunits} = 1;
				 $interfaces{$curif}{percent} = 0;
				 $interfaces{$curif}{bytes} = 1;
				 $interfaces{$curif}{bits} = 0;
				 $interfaces{$curif}{total} = 0;
				 $interfaces{$curif}{percentile} = 0;
				 $interfaces{$curif}{perminute} = 0;
				 $interfaces{$curif}{perhour} = 0;
				 $interfaces{$curif}{withtotal} = 0;
				 $interfaces{$curif}{noabsmax} = 1;
				 $interfaces{$curif}{nomax} = 0;
				 $interfaces{$curif}{mblegend} = 'Equality';
				 $interfaces{$curif}{unit} = '%';
				 $interfaces{$curif}{totunit} = '';
				 $interfaces{$curif}{ylegend} = 'percentage';
				 $interfaces{$curif}{mode} = 'relpercent';
			}
			$interfaces{$curif}{integer} = 1 if( $k eq "integer");
		} } # if defined options
		if ( defined $interfaces{$curif}{cgioptions} ) {
		  foreach $k ( split /[\s,]+/,$interfaces{$curif}{cgioptions} ) {
			# print "Extended Option: $k\n" if($DEBUG);
			$interfaces{$curif}{available} = 1 if( $k eq "available");
			$interfaces{$curif}{available} = 0 if( $k eq "noavailable");
			$interfaces{$curif}{noo} = 1 if( $k eq "noo");
			$interfaces{$curif}{noi} = 1 if( $k eq "noi");
			$interfaces{$curif}{noo} = 0 if( $k eq "o");
			$interfaces{$curif}{noi} = 0 if( $k eq "i");
			$interfaces{$curif}{c2fi} = 1 if( $k eq "c2fi");
			$interfaces{$curif}{c2fo} = 1 if( $k eq "c2fo");
			if( $k eq "bytes") { $interfaces{$curif}{bytes} = 1; 
				$interfaces{$curif}{bits} = 0; next; }
			if( $k eq "bits") { $interfaces{$curif}{bits} = 1;
				$interfaces{$curif}{bytes} = 0; next;  }
			if( $k eq "unknaszero") { $interfaces{$curif}{unknaszero} = 1; }
			if( $k eq "perminute") {
				$interfaces{$curif}{perminute} = 1
					if(!defined $interfaces{$curif}{perhour}
						and !defined $interfaces{$curif}{perminute});
				next;
			}
			if( $k eq "perhour") {
				$interfaces{$curif}{perhour} = 1
					if(!defined $interfaces{$curif}{perhour}
						and !defined $interfaces{$curif}{perminute});
				next;
			}
			$interfaces{$curif}{isif} = 1 if($k eq "interface");
			if( $k eq "ignore") {
				$interfaces{$curif}{inmenu} = 0 ;
				$interfaces{$curif}{insummary} = 0 ;
				$interfaces{$curif}{inout} = 0 ;
				$interfaces{$curif}{incompact} = 0 ;
				next;
			}
			$interfaces{$curif}{unscaled} = "" if( $k eq "scaled");
			if( $k eq "nototal") {
				if($interfaces{$curif}{usergraph}) {
					$interfaces{$curif}{withtotal} = 0 ;
				} else {
					$interfaces{$curif}{total} = 0 ;
				}
				next;
			}
			$interfaces{$curif}{percentile} = 0 if( $k eq "nopercentile");
			if( $k eq "summary" ) {
				$interfaces{$curif}{summary} = 1;
				$interfaces{$curif}{compact} = 0;
				$interfaces{$curif}{withtotal} = 0;
				$interfaces{$curif}{withaverage} = 0;
				$interfaces{$curif}{insummary} = 0 ;
				$interfaces{$curif}{incompact} = 0 ;
				next;
			}
			if( $k eq "compact" ) {
				$interfaces{$curif}{summary} = 0;
				$interfaces{$curif}{compact} = 1;
				$interfaces{$curif}{withtotal} = 0;
				$interfaces{$curif}{withaverage} = 0;
				$interfaces{$curif}{insummary} = 0;
				$interfaces{$curif}{incompact} = 0;
				next;
			}
			if( $k eq "total") {
				if($interfaces{$curif}{usergraph}) {
					$interfaces{$curif}{withtotal} = 1 ;
				} else {
					$interfaces{$curif}{total} = 1 ;
				}
				next;
			}
			if( $k eq "aspercent") {
				 $interfaces{$curif}{aspercent} = 1;
				 $interfaces{$curif}{fixunits} = 1;
				 $interfaces{$curif}{percent} = 0;
				 $interfaces{$curif}{bytes} = 1;
				 $interfaces{$curif}{bits} = 0;
				 $interfaces{$curif}{total} = 0;
				 $interfaces{$curif}{percentile} = 0;
				 $interfaces{$curif}{perminute} = 0;
				 $interfaces{$curif}{perhour} = 0;
				 $interfaces{$curif}{withtotal} = 0;
				 $interfaces{$curif}{noabsmax} = 1;
				 $interfaces{$curif}{mblegend} = '';
				 $interfaces{$curif}{unit} = '%';
				 $interfaces{$curif}{totunit} = '';
				 $interfaces{$curif}{ylegend} = 'percentage';
				 $interfaces{$curif}{mode} = 'percent';
				next;
			}
			$interfaces{$curif}{withaverage} = 1 if( $k eq "average");
			$interfaces{$curif}{nolegend} = 1 if( $k eq "nolegend");
			$interfaces{$curif}{nodetails} = 1 if( $k eq "nodetails");
			$interfaces{$curif}{nomax} = 1 if( $k eq "nomax");
			$interfaces{$curif}{noabsmax} = 1 if( $k eq "noabsmax");
			$interfaces{$curif}{percent} = 0 if( $k eq "nopercent");
			$interfaces{$curif}{integer} = 1 if( $k eq "integer");
			$interfaces{$curif}{'reverse'} = 1 if( $k eq "reverse");
			$interfaces{$curif}{rigid} = 1 if( $k eq "rigid");
			if( $k =~ /^#[\da-fA-F]{6}$/ ) {
				$interfaces{$curif}{colours} = []
					if(!defined $interfaces{$curif}{colours});
				push @{$interfaces{$curif}{colours}}, $k;
				next;
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
		if( $interfaces{$curif}{isif} and !$interfaces{$curif}{mult} ) {
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
		$interfaces{$curif}{mult}=1 if(!$interfaces{$curif}{mult});
		$interfaces{$curif}{factor}=1 if(!$interfaces{$curif}{factor});
		# calculate RRD filename
		if(!$interfaces{$curif}{usergraph}) {
			$rrd = $workdir;
			$rrd .= $pathsep.$interfaces{$curif}{directory}
				if($interfaces{$curif}{directory});
			$rrd .= $pathsep.lc($interfaces{$curif}{target}).".rrd";
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
}

#############################################################################
# Create a single bar graph with the parameters given
sub dobars($$$$$$$$$$@) {
	my($title,$curif,$x,$y,$max,$thresh,$ylegend,$aspercent,$realmax,$unit,$fix,@arr) = @_;
	my($ysiz) = 0;
	my($val,$prev,$cur);
	my($width);
	my($ps);
	my($yleg2,$tmp);
	my($legend) = "";
	my($gx,$gy,$gwidth,$gheight);
	my($bwidth,$bgap,$bpos);
	my($ticks);

	print "<object>\n" if($MODE);
	if($aspercent) {
		$max = 100 if(!$max or $max>1000);
	} else {
		$max = $realmax if(!$max);
	}
	$width = $WIDTH/$COLS; # 200
	$ysiz = $width;
	$ps = int($width/20);
	$gx = $x+50; $gy = $y+20; # graph top lh corner
	$gwidth = $width - 65;    # graph width
	$gheight = $width - 10;   # graph height
	$ysiz = $width + 15; $ysiz += 35 if($MODE);
	$bgap = $gwidth / (6 + 5*$#arr ); # gap between bars
	$bwidth = 4 * $bgap; # bar width

	# title
	print "<object>" if($MODE);
	print "<text x='$x' y='$y' size='".($ps+2)."' width='$width' ".($MODE?"align_h":"align")."='center' color='000000'>$title</text>\n";
	if($MODE) {
		print "<tooltip fill_alpha='0.5' bold='false' >Device: $DEVICE\%0DTarget: $curif</tooltip>\n" if($INFO);
		print "</object>\n";
	}

	#link 
	if($ROUTERSCGI) {
		if($MODE) {
			$links .= "  <object><rect x='$gx' y='$gy' width='$gwidth' height='$gheight' fill_alpha='0' state='hit' />\n<action>"
			."<item type='link' url='$ROUTERSCGI?if=$curif&rtr=$DEVICE' target='mrtgwindow' target_shift='_blank' />\n"
			."</action>\n";
			$links .= "<tooltip fill_alpha='0.7' >Click for MRTG graph</tooltip>\n" if($REGISTERED);
			$links .= "</object>\n";
		} else {
			$links .= " <area x='$x' y='$y' width='$width' height='$width' url='$ROUTERSCGI?if=$curif&rtr=$DEVICE' />\n";
		}
	}
	if($MODE) { print $links; $links = "";}

	# axis
	if($aspercent) { $yleg2 = '%'; $curdiv = 1; } 
	else { $yleg2 = getunits($max,$unit,$fix);  }
	print "<line x1='$gx' y1='".($gy+$gheight)."' x2='".($gx+$gwidth)."' y2='"
		.($gy+$gheight)."' />\n";
	print "<line x1='$gx' y1='$gy' x2='$gx' y2='".($gy+$gheight)."' />\n";
	if($MODE) {
		$ticks = int($max / calcstep($max))+1;
		print "<linear_numbers x1='".($gx-5)."' y1='".($gy+$gheight)."' x2='".($gx-5)."' y2='$gy' number_start='0' number_end='".($max/$curdiv)."' count='$ticks' orientation='right' bold='false' size='$ps' decimals='".(($max/$curdiv)<5?1:0)."' />\n";
		print "<linear_ticks x1='$gx' y1='".($gy+$gheight)."' x2='$gx' y2='$gy' count='$ticks' thickness='1' length='5' />\n";
	}
	print "<text x='".($gx-30)."' y='$gy' width='$gheight' height='15' size='$ps' color='000000' ".($MODE?"align_h":"align")."='center' rotation='90'>$ylegend".($yleg2?" : $yleg2":"")."</text>\n";

	# threshold backgrounds
	if($thresh and $max) {
		my($fromy, $toy);
		if($aspercent) { $thresh = $thresh * 100.0 / $realmax; }
		$thresh = $max if($thresh>$max);
		$fromy = $gy+$gheight-($gheight*$thresh/$max);
		$toy   = $gy+$gheight-($gheight*($realmax>$max?$max:$realmax)/$max);
		print "<rect x='$gx' y='$toy' width='$gwidth' height='".($fromy-$toy)."' fill_color='ff0000' fill_alpha='0.20' />\n";
		print "<rect x='$gx' y='$fromy' width='$gwidth' height='".($gheight+$gy-$fromy)."' fill_color='00ff00' fill_alpha='0.20' />\n";
	} else {
		print "<rect x='$gx' y='$gy' width='$gwidth' height='$gheight' fill_color='ffffff' fill_alpha='0.10' />\n";
	}

	# bars
	$bpos = $gx + $bgap;
	foreach $val ( @arr ) {
		if( $val->{value} ne 'U' ) {
			print "<object>" if($MODE);
			$prev = $val->{value};
			$prev = $q->param($val->{target}.'-'.$val->{io}) 
				if(defined $q->param($val->{target}.'-'.$val->{io}));
			if($aspercent) { $prev = $prev/$realmax*100.0; }
			$cur = $val->{value};
			if($aspercent) { $cur = $cur/$realmax*100.0; }
		
			# first the bar
			print "<rect x='$bpos' y='$gy' width='$bwidth' height='$gheight' fill_color='".$val->{colour}."' line_color='".$val->{colour}."' />\n";
			print "<scale x='$bpos' y='".($gy+$gheight)."' start='".($prev/$max)."' end='".($cur/$max)."' direction='vertical' shake_span='".($TWITCH/360)."' shake_frequency='0.2' />\n";
			print "<tooltip fill_alpha='0.7' color='".$val->{colour}."' >Current: "
				.dokmgformat($aspercent?($val->{value}*100.0/$realmax):($val->{value}),(($yleg2=~/^x/)?$ylegend:$yleg2))
				."</tooltip>\n"
				if($MODE and ($val->{value} ne "U"));

			$bpos += $bwidth + $bgap;
			print "</object>" if($MODE);
		}

		# now the legend
		if( $val->{legend} ) {
			$ysiz += 2;
			$legend .= "<rect x='".($x+10)."' y='".($y+$ysiz)."' width='".($width-20)."' height='15' line_color='000000' fill_color='ffffff' />\n";
			$legend .= "<text size='$ps' x='".($x+12)."' y='".($y+$ysiz)."' width='".($width-24)."' color='".$val->{colour}."' ".($MODE?"align_h":"align")."='left' bold='false' >".$val->{legend}."</text>\n";
			$legend .= "<object><rect x='".($x+10)."' y='".($y+$ysiz)."' width='".($width-20)."' height='15' fill_alpha='0' /><tooltip fill_alpha='0.7' color='".$val->{colour}."' >Current: "
				.dokmgformat($aspercent?($val->{value}*100.0/$realmax):($val->{value}),(($yleg2=~/^x/)?$ylegend:$yleg2))
				."</tooltip></object>\n"
				if($MODE and ($val->{value} ne "U"));
			print $legend if(!$MODE);
			$ysiz += 11;
		}
	}


	# legend drawer
	if($MODE and $legend) { # put the legend into a drawer object
		print "<object><rect x='".($x+9)."' y='".($y+$width+30)."' width='".($width-18)."' height='".($ysiz-$width+15)."' corner_tl='5' corner_tr='5' fill_color='ffffff' line_thickness='1' />\n";
		print "<text x='".($x+10)."' y='".($y+$width+30)."' width='".($width-20)."' height='10' align_h='center' bold='true' size='10' >Legend</text>\n";
		print "$legend\n";
		print "<drawer type='up' depth='".($ysiz-$width-30)."' handle_front='15' handle_back='15' />";
		print "</object>\n";
		print "<rect x='$x' y='".($y+$width+50)."' width='$width' height='".($ysiz-$width+30)."' fill_color='cccccc' />\n";

		$ysiz = $width + 50;
	}

	print "</object>\n" if($MODE);

	return $ysiz;
}
#############################################################################
# Create a single gauge with the parameters given
sub dogauge($$$$$$$$$$@) {
	my($title,$curif,$x,$y,$max,$thresh,$ylegend,$aspercent,$realmax,$unit,$fix,@arr) = @_;
	my($ysiz) = 0;
	my($val,$prev,$cur);
	my($width,$cx,$cy,$rad);
	my($fangle,$angle,$tickstep,$lx,$ly,$tickv);
	my($ps);
	my($yleg2,$tmp);
	my($legend) = "";

	print "<object>\n" if($MODE);
	
	print "realmax=$realmax  max=$max\n" if($DEBUG);
	if($aspercent) {
		$max = 100 if(!$max or $max>1000);
	} else {
		$max = $realmax if(!$max);
	}

	$width = $WIDTH/$COLS; # 200
	$rad = int($width/2*0.9); # 90
	$cx = $x + $width/2; $cy = $y + $width/2 + 15;
	$ysiz = $width;
	$ps = int($width/20);
	
	# title
	print "<object>" if($MODE);
	print "<text x='$x' y='$y' size='".($ps+2)."' width='$width' ".($MODE?"align_h":"align")."='center' color='000000'>$title</text>\n";
	if($MODE) {
		print "<tooltip fill_alpha='0.5' bold='false' >Device: $DEVICE\%0DTarget: $curif</tooltip>\n" if($INFO);
		print "</object>\n";
	}
	$ysiz += 15; $ysiz += 35 if($MODE);

	# The main gauge
	print "<circle x='".($cx+5)."' y='".($cy+5)."' radius='$rad' fill_color='99bbff' line_color='404040' line_alpha='".($MODE?"0.":"")."30' line_thickness='15' />\n";
	print "<circle x='$cx' y='$cy' radius='$rad' fill_color='99bbff' line_color='eeeeee' line_thickness='15' />\n<circle x='".($cx+2)."' y='".($cy+2)."' radius='20' fill_color='303030'/>\n";

	# The threshold background
	if($thresh and $max) {
	my($gf, $gt, $rf, $rt ) = ( $FROMANGLE, $TOANGLE, $TOANGLE, $TOANGLE );
	if($aspercent) { $thresh = $thresh * 100.0 / $realmax; }
	if( $thresh > 0 ) {
		$thresh = $max if($thresh>$max);
		$rf = $gt = $thresh/$max*($TOANGLE-$FROMANGLE)+$FROMANGLE;
		$rt = $realmax/$max*($TOANGLE-$FROMANGLE)+$FROMANGLE if($realmax<$max);
	} elsif( $thresh < 0 ) {
		$thresh = -$max if((-$thresh)>$max);
		$rt = $gf = -$thresh/$max*($TOANGLE-$FROMANGLE)+$FROMANGLE;
		$rf = $FROMANGLE; $gt = $TOANGLE;
	}

	print "<circle x='$cx' y='$cy' radius='".($width/2*0.75)."' start='$gf' end='$gt' fill_color='00ff00' fill_alpha='".($MODE?"0.":"")."40' />\n" if($gt>$gf);

	print "<circle x='$cx' y='$cy' radius='".($width/2*0.75)."' start='$rf' end='$rt' fill_color='ff0000' fill_alpha='".($MODE?"0.":"")."30' />\n" if($rt>$rf);

	} # thresholds and max defined


	# the background and numbers : use max
	if($aspercent) {
		$yleg2 = '%'; $curdiv = 1;
	} else {
		$yleg2 = getunits($max,$unit,$fix); # also inits divisor
	}
	$tickv = 0;
	$tickstep = calcstep($max);
	while( $tickv <= $max ) {
		$angle = int( ($TOANGLE-$FROMANGLE)*$tickv/$max )+$FROMANGLE;
		$lx = $width * 0.48 * sin($angle/180*3.141);
		$ly = $width * 0.48 * cos($angle/180*3.141);
		print "<line x1='".($cx+$lx)."' y1='".($cy-$ly)."' x2='".($cx+$lx*0.9)."' y2='".($cy-$ly*0.9)."' thickness='1' color='000000' />";
		print "<text x='".($cx+$lx)."' y='".($cy-$ly)."' width='200' size='$ps' color='000000' align='left' rotation='$angle'>".doformat($tickv)."</text>\n";
		$tickv += $tickstep;
	}
	print "<text x='".($cx-$width/4)."' y='".($cy+$width/4)."' width='".($width/2)."' size='$ps' color='000000' ".($MODE?"align_h":"align")."='center' rotation='0'>$ylegend</text>\n";
	print "<text x='".($cx-$width/4)."' y='".($cy+$width/4+$ps+1)."' width='".($width/2)."' size='$ps' color='000000' ".($MODE?"align_h":"align")."='center' rotation='0'>$yleg2</text>\n";


	# the pointers in array
	foreach $val ( @arr ) {
		if( $val->{value} ne 'U' ) {
		print "<object>" if($MODE);
		$prev = $val->{value};
		$prev = $q->param($val->{target}.'-'.$val->{io}) 
			if(defined $q->param($val->{target}.'-'.$val->{io}));
		if($aspercent) { $prev = $prev/$realmax*100.0; }
		$cur = $val->{value};
		if($aspercent) { $cur = $cur/$realmax*100.0; }
		$fangle = int(($TOANGLE-$FROMANGLE)*$prev/$max)+$FROMANGLE;
		$fangle = $TOANGLE if($fangle > $TOANGLE);
		if( $cur > $max ) {
			$angle = $TOANGLE;
			print "<rotate x='$cx' y='$cy' start='$fangle' span='".($angle-$fangle)."' step='5' shake_span='0' shake_frequency='0.2' ".($MODE?"/":"").">\n";
		} else {
			$angle = int( ($TOANGLE-$FROMANGLE)*$cur/$max )+$FROMANGLE;
			print "<rotate x='$cx' y='$cy' start='$fangle' span='".($angle-$fangle)."' step='5' shake_span='$TWITCH' shake_frequency='0.2' ".($MODE?"/":"").">\n";
		}
		if($MODE) {
		print "<polygon fill_color='".$val->{colour}."' fill_alpha='1' line_alpha='0.3' line_color='".$val->{colour}."' caps='none' >
<point x='".($cx-3)."' y='$cy' />
<point x='".($cx+3)."' y='$cy' />
<point x='".($cx+1)."' y='".int($y + $width*0.15)."' />
<point x='".($cx-1)."' y='".int($y + $width*0.15)."' />
</polygon>\n";
		} else {
		print "<polygon fill_color='".$val->{colour}."' fill_alpha='100' line_alpha='30'>
<point x='".($cx-3)."' y='$cy' /><point x='".($cx+3)."' y='$cy' />
<point x='".($cx+1)."' y='".int($y + $width*0.15)."' />
<point x='".($cx-1)."' y='".int($y + $width*0.15)."' />
</polygon>\n";
		}
		print "<rect x='".($cx-3)."' y='$cy' width='7' height='30' fill_color='".$val->{colour}."' fill_alpha='".($MODE?"0.":"")."90' line_alpha='".($MODE?"0.":"")."50' />\n";
		print "</rotate>\n" if(!$MODE);
		print "</object>" if($MODE);
		}

		# now the legend
		if( $val->{legend} ) {
			$ysiz += 2;
			$legend .= "<rect x='".($x+10)."' y='".($y+$ysiz)."' width='".($width-20)."' height='15' line_color='000000' fill_color='ffffff' />\n";
			$legend .= "<text size='$ps' x='".($x+12)."' y='".($y+$ysiz)."' width='".($width-24)."' color='".$val->{colour}."' ".($MODE?"align_h":"align")."='left' bold='false' >".$val->{legend}."</text>\n";
			$legend .= "<object><rect x='".($x+10)."' y='".($y+$ysiz)."' width='".($width-20)."' height='15' fill_alpha='0' /><tooltip fill_alpha='0.7' color='".$val->{colour}."' >Current: "
				.dokmgformat($aspercent?($val->{value}*100.0/$realmax):($val->{value}),(($yleg2=~/^x/)?$ylegend:$yleg2))
				."</tooltip></object>\n"
				if($MODE and ($val->{value} ne "U"));
			print $legend if(!$MODE);
			$ysiz += 11;
		}
	}

	print "<circle x='$cx' y='$cy' radius='20' fill_color='000000'/>\n";

	#link 
	if($ROUTERSCGI) {
		if($MODE) {
			$links .= "  <object><circle x='$cx' y='$cy' radius='$rad' fill_alpha='0' state='hit' />\n<action>"
			."<item type='link' url='$ROUTERSCGI?if=$curif&rtr=$DEVICE' target='mrtgwindow' target_shift='_blank' />\n"
			."</action>\n";
			$links .= "<tooltip fill_alpha='0.7' >Click for MRTG graph</tooltip>\n" if($REGISTERED);
			$links .= "</object>\n";
		} else {
			$links .= " <area x='$x' y='$y' width='$width' height='$width' url='$ROUTERSCGI?if=$curif&rtr=$DEVICE' />\n";
		}
	}
	if($MODE) { print $links; $links = "";}

	# legend drawer
	if($MODE and $legend) { # put the legend into a drawer object
		print "<object><rect x='".($x+9)."' y='".($y+$width+30)."' width='".($width-18)."' height='".($ysiz-$width+15)."' corner_tl='5' corner_tr='5' fill_color='ffffff' line_thickness='1' />\n";
		print "<text x='".($x+10)."' y='".($y+$width+30)."' width='".($width-20)."' height='10' align_h='center' bold='true' size='10' >Legend</text>\n";
		print "$legend\n";
		print "<drawer type='up' depth='".($ysiz-$width-30)."' handle_front='15' handle_back='15' />";
		print "</object>\n";
		print "<rect x='$x' y='".($y+$width+50)."' width='$width' height='".($ysiz-$width+30)."' fill_color='cccccc' />\n";

		$ysiz = $width + 50;
	}

	print "</object>\n" if($MODE);

	return $ysiz;
}

sub outputxml() {	
	my($curif);
	my($c) = 0;
	my($h,$maxh,$rrd);
	my($x,$y) = (0,0);
	my(@values,$maxval,$ylegend, $v, $thresh,$legend,$opt,$val);
	my($subif,@subifs);
	my(@clr,$clr,$npts);
	my( $datastart, $datastep, $dsnames, $dsdata, @opts, $error );
	my(@targets) = ();
	my($explicit) = 0;
	my($aspercent) = 0;
	my($unit) = "";
	my($realmax) = 0;

	if($MODE) { 
		if(!$OBJECT) {
			print "<slickboard>\n";
			if($REGISTERED) {
				print "<license><string>$REGISTERED</string></license>\n";
				print "<context_menu>
<item label_a='Version' />
<item label_a='About gaugexml' />
<item label_a='About MRTG' />
<item label_a='About SlickBoard' />
<item type='separator' />
<item label_a='Full Screen' label_b='Normal view' type='toggle_screen' />
<item label_a='Print Gauge' />
</context_menu>\n";
				print "<action>
<item event='context_1' type='alert' text='gaugexml3.cgi $VERSION%0DMore information at:%0Dhttp://www.steveshipway.org/gaugexml'  />
<item event='context_2' type='link' url='http://www.steveshipway.org/gaugexml' target='_self' target_shift='_new' />
<item event='context_3' type='link' url='http://www.mrtg.org/' target='_self' target_shift='_new' />
<item event='context_4' type='link' url='http://www.maani.us/slickboard' target='_self' target_shift='_new' />
<item event='context_6' type='toggle_screen'  />
<item event='context_7' type='print'  />
</action>";
			} # registered
		}
		print "<object>\n"; 
        print "<rect x='$XOFF' y='$YOFF' width='".($WIDTH-1)."' height='".($HEIGHT-1)."' state='hit' fill_alpha='0.5' fill_color='cccccc' line_alpha='1' line_thickness='1' />\n" if($OBJECT);
	} else { print "<gauge>\n"; }
	$opt = "";
	if( $TARGET ) {
		@targets = ( $TARGET );
		$explicit = 1;
	} else {
		@targets = keys %interfaces;
	}
	foreach $curif ( @targets ) {
		if( !defined $interfaces{$curif} 
			and defined $interfaces{"_$curif"} )  {
			$curif = "_$curif";
		}
		next if(!$interfaces{$curif}{inmenu} and !$explicit);    # This isnt in menu
		next if( $interfaces{$curif}{issummary} ); # this isnt a graph
		last if($y>$HEIGHT);
		print "Interface $curif\n" if($DEBUG);

		$aspercent = 0; $unit = "";
		$aspercent = 1 if($interfaces{$curif}{aspercent});
		$unit = $interfaces{$curif}{unit} if($interfaces{$curif}{unit});
		$realmax = $interfaces{$curif}{maxbytes}*$interfaces{$curif}{mult};

		# work out the values
		if($interfaces{$curif}{usergraph}) {
			@subifs = @{$interfaces{$curif}{targets}};
			$interfaces{$curif}{ylegend} = $interfaces{$interfaces{$curif}{targets}[0]}{ylegend} if(!$interfaces{$curif}{ylegend});
		} else { @subifs = ( $curif ); }
		$ylegend = $interfaces{$curif}{ylegend};
		$ylegend = 'bps' if(!$ylegend);
		$interfaces{$curif}{colours} = [ @defcolours ]
			if(!defined $interfaces{$curif}{colours});

		# retrieve a set of values, plus colours.
		@values = (); # { value, colour, legend }
		@clr = ();
		print "Colours: ".(join ",",@{$interfaces{$curif}{colours}})."\n"
			if($DEBUG);
		foreach $subif ( @subifs ) {
			print "    subif $subif\n" if($DEBUG);
			$aspercent = 1 if($interfaces{$subif}{aspercent});
			$unit = $interfaces{$subif}{unit} 
				if($interfaces{$subif}{unit} and!$unit);
			$realmax = $interfaces{$subif}{maxbytes}*$interfaces{$subif}{mult}
				if($realmax<($interfaces{$subif}{maxbytes}*$interfaces{$subif}{mult}));
			print "    realmax=$realmax ifmax=".$interfaces{$subif}{maxbytes}."\n" if($DEBUG);
			$rrd = $interfaces{$subif}{rrd};
			@opts = ( $rrd, "AVERAGE", "-e", "now", "-s", "now-".(5*$BACK)."min", "-r",
				"5min" );
			( $datastart, $datastep, $dsnames, $dsdata ) = RRDs::fetch( @opts );
			$error = RRDs::error();
			if($error) {
				push @values, 
					{ value=>'U', colour=>'cccccc', legend=>"Err:$error",
					target=>$interfaces{$subif}{target}, io=>'' };
				next;
			}	
			$npts = $#$dsdata;
			if($DEBUG) {
				print "Retrieved $npts points of data.\n";
				print "subif mult=".$interfaces{$subif}{mult}."\n";
				print "subif fact=".$interfaces{$subif}{factor}."\n";
			}
			if(! $interfaces{$subif}{noi} and !$interfaces{$curif}{noi} ) {
				@clr = @{$interfaces{$curif}{colours}} if(!@clr); # reset
				$clr = shift @clr; $clr =~ s/#//g;
				print "This Colour=$clr\n" if($DEBUG);
				if($interfaces{$curif}{usergraph}) {
					$legend = $interfaces{$subif}{shdesc};
					if(! $interfaces{$subif}{noo} and !$interfaces{$curif}{noo}) {
						$legend = $interfaces{$subif}{shdesc};
						$legend = $interfaces{$subif}{desc} if(!$legend);
						$legend = $subif if(!$legend);
						$legend .= "(".($interfaces{$subif}{legend1}?$interfaces{$subif}{legend1}:"Inbound").")";
					} else {
						$legend = $interfaces{$subif}{desc};
						$legend = $interfaces{$subif}{shdesc} if(!$legend);
						$legend = $subif if(!$legend);
					}
				} elsif( $interfaces{$subif}{noo} or $interfaces{$curif}{noo}){
					$legend = "";
				} else {
					$legend = $interfaces{$subif}{legend1};
					$legend = "Inbound" if(!$legend);
				}
				$v = 'U';
				foreach ( 0..$npts ) {
					$v = $dsdata->[$_]->[0] if(defined $dsdata->[$_]
						and defined $dsdata->[$_]->[0]);
				}
				if($v ne 'U') {
					$v *= $interfaces{$subif}{mult} 
						if( $interfaces{$subif}{mult} );
					$v *= $interfaces{$subif}{factor} 
						if( $interfaces{$subif}{factor} );
				push @values, 
					{ value=>$v, colour=>$clr, legend=>$legend,
					target=>$interfaces{$subif}{target}, io=>'i' };
				} else {
				push @values, 
					{ value=>'U', colour=>'cccccc', legend=>$legend,
					target=>$interfaces{$subif}{target}, io=>'i' };
				}
				print "Inbound = $v\n" if($DEBUG);
			}
			if(! $interfaces{$subif}{noo} and !$interfaces{$curif}{noo} ) {
				@clr = @{$interfaces{$curif}{colours}} if(!@clr); # reset
				$clr = shift @clr; $clr =~ s/#//g;	
				if($interfaces{$curif}{usergraph}) {
					if(! $interfaces{$subif}{noi} and !$interfaces{$curif}{noi} ) {
						$legend = $interfaces{$subif}{shdesc};
						$legend = $interfaces{$subif}{desc} if(!$legend);
						$legend = $subif if(!$legend);
						$legend .= "(".($interfaces{$subif}{legend2}?$interfaces{$subif}{legend2}:"Outbound").")";
					} else {
						$legend = $interfaces{$subif}{desc};
						$legend = $interfaces{$subif}{shdesc} if(!$legend);
						$legend = $subif if(!$legend);
					}
				} elsif( $interfaces{$subif}{noi} or $interfaces{$curif}{noi}){
					$legend = "";
				} else {
					$legend = $interfaces{$subif}{legend2};
					$legend = "Outbound" if(!$legend);
				}
				$v = 'U';
				foreach ( 0..$npts ) {
					$v = $dsdata->[$_]->[1] if(defined $dsdata->[$_]
						and defined $dsdata->[$_]->[1]);
				}
				if($v ne 'U') {
					$v *= $interfaces{$subif}{mult} 
						if( $interfaces{$subif}{mult} );
					$v *= $interfaces{$subif}{factor} 
						if( $interfaces{$subif}{factor} );
					push @values, 
						{ value=>$v, colour=>$clr, legend=>$legend,
					target=>$interfaces{$subif}{target}, io=>'o' };
				} else {
					push @values, 
						{ value=>'U', colour=>'cccccc', legend=>$legend,
					target=>$interfaces{$subif}{target}, io=>'o' };
				}
				print "Outbound = $v\n" if($DEBUG);
			}
		}

		# work out max
		$maxval = 0;
		if($interfaces{$curif}{unscaled}=~/d/i 
			or $interfaces{$curif}{upperlimit}) {
			$maxval = $interfaces{$curif}{maxbytes} 
				if($interfaces{$curif}{maxbytes});
			$maxval = $interfaces{$curif}{absmax} 
				if($interfaces{$curif}{absmax});
			$maxval *= $interfaces{$curif}{mult}
				if($interfaces{$curif}{mult});
			$maxval *= $interfaces{$curif}{factor}
				if($interfaces{$curif}{factor});
			$maxval = $interfaces{$curif}{upperlimit} 
				if($interfaces{$curif}{upperlimit});
		}
		unless( $interfaces{$curif}{rigid} and $maxval ) {
			foreach ( @values ) {
				$maxval = $_->{value} 
					if($_->{value} ne 'U' and ($_->{value} > $maxval));
				print "".$_->{value}." so MAX=$maxval\n" if($DEBUG);
			}
		}
		$maxval = 100 if(!$maxval);
		$realmax = $maxval if(!$realmax);
		$maxval = $maxval/$realmax*100.0 if($aspercent and (!$interfaces{$curif}{rigid}));
		$maxval = roundoff($maxval) unless($interfaces{$curif}{rigid});
		$maxval = 1 if(!$maxval);
		
		# thresholds
		$thresh = 0;
		$thresh = $interfaces{$curif}{threshmaxi}
		if( !$thresh and defined $interfaces{$curif}{threshmaxi} );
		$thresh = $interfaces{$curif}{threshmaxo}
		if( !$thresh and defined $interfaces{$curif}{threshmaxo} );
		$thresh = -$interfaces{$curif}{threshmini}
		if( !$thresh and defined $interfaces{$curif}{threshmini} );
		$thresh = -$interfaces{$curif}{threshmino}
		if( !$thresh and defined $interfaces{$curif}{threshmino} );
		if( defined $thresh and $thresh =~ /^([\d\.]+)\%/) {
			$thresh = $1 * $realmax /100.0;
		}
	
		if($aspercent) {
			$maxval = roundoff($maxval*100.0/$realmax);
			$ylegend = "Usage";
		}
		# create a gauge
		if($TYPE and $TYPE eq 'bars') {
			$h = dobars($interfaces{$curif}{shdesc}?$interfaces{$curif}{shdesc}:$interfaces{$curif}{desc},
				$curif,
				$XOFF+$c*$WIDTH/$COLS+1,$YOFF+$y+1,
				$maxval, $thresh, $ylegend, $aspercent, $realmax, $unit,
				(defined $interfaces{$curif}{fixunit}?$interfaces{$curif}{fixunit}:$interfaces{$subifs[0]}{fixunit}),
				@values);
		} else {
			$h = dogauge($interfaces{$curif}{shdesc}?$interfaces{$curif}{shdesc}:$interfaces{$curif}{desc},
				$curif,
				$XOFF+$c*$WIDTH/$COLS+1,$YOFF+$y+1,
				$maxval, $thresh, $ylegend, $aspercent, $realmax, $unit,
				(defined $interfaces{$curif}{fixunit}?$interfaces{$curif}{fixunit}:$interfaces{$subifs[0]}{fixunit}),
				@values);
		}
		$maxh = $h if($h > $maxh );

		$c += 1; if($c >= $COLS) { $c = 0; $y += $maxh; $maxh = 0; }

		foreach $val ( @values ) {
			$opt .= "&".$val->{target}.'-'.$val->{io}."=".$val->{value} 
				if($val->{value} ne 'U');
		}
	}
	if(!$MODE) {
		print "<link>$links</link>\n";
	}
	print "<update url='$URL?cfg=$DEVICE"
		.($TARGET?"&target=$TARGET":"")
		."&cols=$COLS&width=$WIDTH&t=".time
        .($OBJECT?"&object=1&x=$XOFF&y=$YOFF":"")
		.($REGISTERED?"&license=$REGISTERED":"")
		.($TYPE?"&type=$TYPE":"")
		."$opt' delay='$DELAY' ".($MODE?"":"delay_type='1'")
		." retry='2' timeout='15' />\n";
	if($MODE) {
#        if($OBJECT) { # we're working in embedded mode, so enable drag/drop
#            print "<action><item type='drag' /></action>\n";
#            print "<mask target='mask$$' />\n";
#            print "<object id='mask$$' ><rect x='$XOFF' y='$YOFF' width='$WIDTH' height='$HEIGHT' /></object>\n";
#        }
		print "</object>";
		print "</slickboard>\n" if(!$OBJECT);
	} else {
		print "<gauge>\n";
	}
}
sub blankgauge {
	my($msg) = $_[0];
	$msg = "Error" if(!$msg);
	print $q->header(-expires=>"now",-type=>"text/xml",-pragma=>"nocache");
	if($MODE) {
		print "<slickboard>\n" if(!$OBJECT);
		print "<object><text x='0' y='0' word_wrap='1' width='$WIDTH' >$msg</text></object>\n";
		print "</slickboard>\n" if(!$OBJECT);
	} else {
		print "<gauge>\n<comment value='$msg' />\n</gauge>\n";
	}

}
# Test for approved cfg files.
sub cfgok($) {
	my($c) = $_[0];
	return 1 if($c =~ /$PUBLICCFG/);
	return 0;
}
#############################################################################
# MAIN

$REGISTERED=$q->param('license') if(defined $q->param('license'));
$TWITCH=$q->param('twitch') if(defined $q->param('twitch'));
$DEVICE=$q->param('cfg');
$TARGET=$q->param('target') if($q->param('target'));
$WIDTH=$q->param('width') if($q->param('width'));
$WIDTH=200 if($WIDTH<200);
$HEIGHT=$q->param('height') if($q->param('height'));
$HEIGHT=250 if($HEIGHT<250);
$COLS=int($WIDTH/200); 
$COLS=$q->param('cols') if($q->param('cols'));
$COLS=1 if($COLS<1);
$XOFF   = $q->param('x')    if( $q->param('x') );
$YOFF   = $q->param('y')    if( $q->param('y') );
$OBJECT = 1 if( $q->param('object') or $XOFF or $YOFF );
$URL    = $q->param('url')  if( $q->param('url') );
$TYPE   = $q->param('type') if( $q->param('type') );

if( ($q->url() =~ /$PUBLICURL/) and !cfgok($DEVICE)) { 
	blankgauge("Illegal request");
	exit(0); 
}
if( ! -f $CFGDIR.$pathsep.$DEVICE ) {
	blankgauge("File $CFGDIR$pathsep$DEVICE does not exist");
	exit(0);
}
readcfg($CFGDIR.$pathsep.$DEVICE);
print $q->header(-expires=>"now",-type=>"text/xml",-pragma=>"nocache");
require RRDs;
outputxml;
exit(0);
