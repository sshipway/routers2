#!/usr/bin/perl
#vim:ts=4
#
# graphxml3.cgi : Steve Shipway www.steveshipway.org
#
# Produce XML for slickboard/swfgauge, based on contents of MRTG .cfg file
#
# v1.0 : Link in graph image from Routers2
#  1.1 : improve legend
#  1.2 : more legend errors

use strict;
use CGI;
use FileHandle;
use Text::ParseWords;

my($VERSION) = "v1.2";
my($REGISTERED) = ""; # Set this to blank or your license key
########################################################################
# If my url matches this regexp, we're in public mode
my($PUBLICURL) = 'public';
# If in public mode, requested cfg must match this regexp
my($PUBLICCFG) = '^other-summary\/';
# This is the URL for routers2.cgi, if you have it
my($ROUTERSCGI) = "https://monitor.auckland.ac.nz/cgi-bin/routers2-open.cgi";
# The location of CFG files
my($CFGDIR) = '/u01/mrtg/conf';
# Use 1 for SLICKBOARD.SWF, 0 for GAUGE.SWF
my($MODE) = 1;
# Default workdir for RRD files if not set in cfg file
my($workdir) = "/u01/rrdtool";
########################################################################
# Not a good idea to change below here
my($DEBUG) = 0;
my($q) = new CGI;
my($URL) = $q->url();
my($debugmessage) = '';
my($pathsep) = "/";
my($interval) = 5;
my($workdir) = '';
my($curdiv);
my($links) = "";
my($TARGET) = "";
my($DEVICE) = "";
my($WIDTH) = 600; # actually 575x223
my($HEIGHT) = 250;
my($OBJECT) = 0;  # generates embeddable XML if 1
my($XOFF,$YOFF) = (0,0); # offset for generated objects
my(%interfaces) = ();
my(@defcolours) = (
         "0000ff","00ff00","ff0000","00cccc","cccc00","cc00cc",
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
		if(( $buf =~ /^\s*(routers2?\.cgi|g[au][ua]gexml3?|slickboard|swfgauge)\*Options\[(.+?)\]\s*:\s*(\S.*)/i )  
			or ( $buf =~ /^\s*g[au][ua]ge\.(swf|cgi)\*Options\[(.+?)\]\s*:\s*(\S.*)/i )) { 
			$curif = $2; $arg = $3;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{cgioptions}="" if(!$interfaces{$curif}{cgioptions});
			$interfaces{$curif}{cgioptions} .= " ".$arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\*)?MaxBytes\[(.+?)\]\s*:\s*(\d+)/i ) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{maxbytes} = $3;
			next;
		}
		if($buf=~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\*|g[au][ua]gexml3?\.cgi|g[au][ua]ge\.swf\*|slickboard|swfgauge)?Unscaled\[(.+?)\]\s*:\s*([6dwmy]*)/i){ 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{unscaled} = $3;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\*)?YLegend\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{ylegend} = $3;
			next;
		}
		if($buf=~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\*)?ShortLegend\[(.+?)\]\s*:\s*(.*)/i){ 
			$curif = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{unit} = $3;
			$interfaces{$curif}{unit} =~ s/&nbsp;/ /g;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\*)?(Legend[IO1234TA][IO]?)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
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
		if( $buf =~ /^\s*(g[au][ua]ge\.swf|g[au][ua]gexml3?|swfgauge|slickboard)\*Hide\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{inmenu} = 0; }
			else { $interfaces{$curif}{inmenu} = 1; }
			next;
		}
		if( $buf =~ /^\s*(g[au][ua]ge\.swf|g[au][ua]gexml3?|swfgauge|slickboard)\*Max(Bytes)?\[(.+?)\]\s*:\s*(\S+)/i ) {
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
        if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?|swfgauge|gauge\.swf|slickboard)?Colou?rs\[(.+?)\]\s*:\s*(.*)/i ) {
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
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\*|swfgauge\*|gauge\.swf\*|slickboard\*)?AbsMax\[(.+?)\]\s*:\s*(\d+)/i ) { 
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
		if( $buf =~ /^\s*(routers2?\.cgi|g[au][ua]gexml3?|swfgauge|slickboard|g[au][ua]ge\.swf)\*UpperLimit\[(.+?)\]\s*:\s*(\d+)/i ) { 
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
		if( $buf =~ /^\s*(routers2?\.cgi\*|g[au][ua]gexml3?\*|swfgauge\*|gauge\.swf\*|slickboard\*)?(Thresh(Max|Min)[IO])\[(.+?)\]\s*:\s*([\d%]+)/i ) { 
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

#############################################################################

sub slidexml($) {
	my($dwmy) = $_[0];
	my($refresh) = 300;

	print "<object>";
	print "<image url='$ROUTERSCGI?rtr=$DEVICE&if=$TARGET&page=image&xgtype=".$dwmy."s&xgstyle=x3D' fill='center' x='0' y='15' width='$WIDTH' height='".($HEIGHT-15)."' state='hit' />\n";
	print "<slide duration='10' /><transition_in type='fade' /><transition_out type='fade' />\n" if(!$OBJECT);

	print "<action>";
	print "<item type='link' url='$ROUTERSCGI?if=$TARGET&rtr=$DEVICE&xgtype=$dwmy' target='mrtgwindow' target_shift='_blank' />\n";
	print "</action>\n";	
	print "<tooltip fill_alpha='0.7' >Click for MRTG</tooltip>\n";

	$refresh = 300 if($dwmy eq 'd');
	$refresh = 1800 if($dwmy eq 'w');
	$refresh = 7200 if($dwmy eq 'm');

	print "<update url='$URL?cfg=$DEVICE&target=$TARGET"
		.($OBJECT?"&object=1&x=$XOFF&y=$YOFF":"")
		.($REGISTERED?"&license=$REGISTERED":"")
		."&width=$WIDTH&dwmy=$dwmy&t=".time
		."' delay='$refresh' ".($MODE?"":"delay_type='1'")
		." retry='2' timeout='15' />\n" if($refresh);
	print "</object>";
}

sub outputxml() {	
	my($x,$c);
	my($curif);
	my(@subifs);
	my($legend) = '';
	my($legendxml) = '';
	my($clr,@clr);
	my($ypos);

	if($MODE) { 
		if(!$OBJECT) {
			print "<slickboard>\n";
			if($REGISTERED) {
				print "<license><string>$REGISTERED</string></license>\n";
				print "<context_menu>
<item label_a='Version' />
<item label_a='About graphxml' />
<item label_a='About MRTG' />
<item label_a='About SlickBoard' />
<item type='separator' />
<item label_a='Full Screen' label_b='Normal view' type='toggle_screen' />
<item label_a='Print Gauge' />
</context_menu>\n";
				print "<action>
<item event='context_1' type='alert' text='gaugexml3.cgi $VERSION%0DMore information at:%0Dhttp://www.steveshipway.org/graphxml'  />
<item event='context_2' type='link' url='http://www.steveshipway.org/graphxml' target='_self' target_shift='_new' />
<item event='context_3' type='link' url='http://www.mrtg.org/' target='_self' target_shift='_new' />
<item event='context_4' type='link' url='http://www.maani.us/slickboard' target='_self' target_shift='_new' />
<item event='context_6' type='toggle_screen'  />
<item event='context_7' type='print'  />
</action>";
			}
		} else {
			print "<object>\n";
		}
#		print "<object>\n"; # slideshow doesnt work within object
        print "<rect x='$XOFF' y='$YOFF' width='".($WIDTH-1)."' height='".($HEIGHT-1)."' state='hit' fill_alpha='0.5' fill_color='cccccc' line_alpha='1' line_thickness='1' />\n" if($OBJECT);

	} else { print "<gauge>\n"; }

	# Graphs
	foreach ( qw/d w m y/ ) { 
		next if($interfaces{$TARGET}{suppress}
			and $interfaces{$TARGET}{suppress}=~/$_/);
		slidexml($_); 
		last if($OBJECT); # we only have one in this case
	}

	print "<text x='$x' y='0' width='$WIDTH' height='15' size='12' align_h='center' >".$interfaces{$TARGET}{desc}."</text>\n";

	# Controller drawers
	if(!$OBJECT) {
	$x=10; $c=1;
	foreach ( qw/daily weekly monthly yearly/ ) {
		next if($interfaces{$TARGET}{suppress} and /^([dwmy])/
			and $interfaces{$TARGET}{suppress}=~/$1/);
		print "<object>";
		print "<rect x='$x' y='-20' width='50' height='25' fill_color='FF6600' corner_bl='5' corner_br='5' state='hit' /> \n";
		print "<text x='$x' y='-20' width='50' height='20' size='10' alpha='.6' align_h='center' shadow='low' >$_</text>\n";
		print "<drawer type='down' depth='20' handle_back='5' handle_front='15' />\n";
		print "<action>";
		print "<item event='click' type='slideshow_jump' slide='$c' instant='false'  />\n";
#		print "<item event='click' type='slideshow_pause' />";
		print "</action>\n";	
		print "</object>\n";
		$x += 55; $c += 1;
	}
	print "<object id='play' >";
	print "<rect x='$x' y='-20' width='50' height='25' fill_color='FF0066' corner_bl='5' corner_br='5' state='hit' /> \n";
	print "<text x='$x' y='-20' width='50' height='20' size='10' alpha='.6' align_h='center' shadow='low' state='checked' >Cycle</text>\n";
	print "<text x='$x' y='-20' width='50' height='20' size='10' alpha='.6' align_h='center' shadow='low' state='unchecked' >Pause</text>\n";
	print "<drawer type='down' depth='20' handle_back='5' handle_front='15' />\n";
	print "<action>";
	print "<item event='click' type='slideshow_toggle' />";
	print "</action>\n";	
	print "</object>\n"; #play button
	} # not embedded

	# now the legend drawer
	$curif = $TARGET;
    if( !defined $interfaces{$curif}
        and defined $interfaces{"_$curif"} )  {
        $curif = "_$curif";
    }
	if($interfaces{$curif}{usergraph}) {
        @subifs = @{$interfaces{$curif}{targets}};
        $interfaces{$curif}{ylegend} = $interfaces{$interfaces{$curif}{targets}[0]}{ylegend} if(!$interfaces{$curif}{ylegend});
    } else { @subifs = ( $curif ); }
    $interfaces{$curif}{colours} = [ @defcolours ]
        if(!defined $interfaces{$curif}{colours});
	$ypos = 25;
	foreach my $subif ( @subifs ) {
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
					$legend = "Inbound traffic" if(!$legend);
				}
				if($legend) {
					$legendxml .= "<circle x='".($WIDTH+10)."' y='".($ypos+10)."' radius='5' fill_color='$clr' line_thickness='1' />";
					$legendxml .= "<text x='".($WIDTH+15)."' y='$ypos' width='".($WIDTH/2-20)."' height='10' align_h='left' bold='false' word_wrap='false' >$legend</text>\n";
					$ypos += 15;
				}
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
					$legend = "Outbound traffic $TARGET $curif $subif -" if(!$legend);
				}
				if($legend) {
					$legendxml .= "<circle x='".($WIDTH+10)."' y='".($ypos+10)."' radius='5' fill_color='$clr' line_thickness='1' />";
					$legendxml .= "<text x='".($WIDTH+15)."' y='$ypos' width='".($WIDTH/2-20)."' height='10' align_h='left' bold='false' word_wrap='false' >$legend</text>\n";
					$ypos += 12;
				}
			}
	}

	print "<object>";
	print "<rect x='".($WIDTH-15)."' y='20' width='".($WIDTH/2 + 20)."' height='".($HEIGHT-40)."' fill_color='FFFFFF' line_thickness='1' corner_tl='5' corner_bl='5' /> \n";
	print "<text x='".($WIDTH-15)."' y='".($HEIGHT-20)."' height='15' width='".($HEIGHT-40)."' size='10' alpha='.6' align_h='center' shadow='low' rotation='-90' >Legend</text>\n";
	print $legendxml;
	print "<drawer type='left' depth='".($WIDTH/2)."' handle_back='15' handle_front='20' />\n";
	print "</object>\n";
	print "<rect x='$WIDTH' y='20' width='".($WIDTH/2 + 20)."' height='".($HEIGHT-40)."' fill_color='cccccc' line_thickness='0' /> \n";
	
	if($MODE) {
#		print "<update url='$URL?cfg=$DEVICE&target=$TARGET"
#			.($OBJECT?"&object=1&x=$XOFF&y=$YOFF":"")
#			.($REGISTERED?"&license=$REGISTERED":"")
#			."&width=$WIDTH&dwmy=$dwmy&t=".time
#			."' delay='300' ".($MODE?"":"delay_type='1'")
#			." retry='2' timeout='15' />\n";
		print "</object>\n" if($OBJECT);
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
sub justobject($) {
	slidexml($_[0]);
}
#############################################################################
# MAIN

$REGISTERED=$q->param('license') if($q->param('license'));
$DEVICE=$q->param('cfg');
$TARGET=$q->param('target')   if($q->param('target'));
$WIDTH=$q->param('width')     if($q->param('width'));
$URL    = $q->param('url')    if($q->param('url'));
$OBJECT = $q->param('object') if($q->param('object'));

if( ($q->url() =~ /$PUBLICURL/) and !cfgok($DEVICE)) { 
	blankgauge("Illegal request");
	exit(0); 
}
if( ! -f $CFGDIR.$pathsep.$DEVICE ) {
	blankgauge("File $CFGDIR$pathsep$DEVICE does not exist");
	exit(0);
}
readcfg( $CFGDIR.$pathsep.$DEVICE );
delete $interfaces{'$'};
delete $interfaces{'_'};
delete $interfaces{'^'};
$TARGET = (sort keys %interfaces)[0] if(!$TARGET);
print $q->header(-expires=>"now",-type=>"text/xml",-pragma=>"nocache");
if($q->param('dwmy')) { # for refresh of graph object
	justobject($q->param('dwmy'));
} else {
	outputxml;
}
exit(0);
