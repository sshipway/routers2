#!/usr/bin/perl 
# DONT FORGET TO CHANGE THE ABOVE PATH TO MATCH YOUR PERL LOCATION! 
#vim:ts=4
##############################################################################
# To use Speedycgi, you need to change the first line to this:
##!/usr/bin/speedy -- -M20 -t3600 -gnone -r500
# and then set the CACHE global variable (below) to 1.
# To use mod_perl, you should be able to put the script directly into the
# mod_perl directory and it will work.  This is not very thoroughly tested 
# though. You also need to set the CACHE global below to 1.
##############################################################################
# routers.cgi : Version v2.24
# Create router monitoring pages 
#
# This code is covered by the Gnu GPL.  See the README file, or the Gnu
# web site for more details.
#
# Includes code derived from overlib (C) Eric Bosrup
#
# Developed and tested with RRDTool v1.4.4, Perl 5.8, under Linux (RHEL5)
# Also partially tested with ActivePerl 5.6 with Apache under NT 
# Note - 95th percentile calcs DO NOT WORK under RRDTool v1.0.24 or earlier
# Windows users should avoid RRDTool v1.0.33 - v1.0.39 due to a bug.
#
##############################################################################
# DONT FORGET TO CHANGE THE LOCATION OF THE CONFIG FILE DEFINED BELOW!
##############################################################################
use strict;
use CGI;              # for CGI
use File::Basename;   # for identifying filenames under different OSs
use Text::ParseWords; # for parsing MRTG .conf file
use FileHandle;       # to have multiple conf files in recursion
use Getopt::Std;      # For limited command line operation
use POSIX qw(tzset strftime); # For timezone support
#use Data::Dumper;     # For persistent caching
use Time::Local 'timelocal_nocheck'; # For time conversions
##CONFIG#START################################################################
# You MUST set this to the location of the configuration file!
my ($conffile) = '/u01/etc/routers2.conf';
##############################################################################
# Are we running in speedycgi or mod_perl mode?  Can we cache configs?
# If you set this to 1 when you dont have speedycgi or mod_perl, it will
# slightly slow things down, but will not break anything.
# This can also be set in the routers2.conf with the cache=yes option
my ($CACHE) = 0;
##############################################################################
# You should set this to something random and secret, if you are using
# the script's internal authentication via cookies.  It's called this because
# it is embedded into a cookie...
my ($CHOCOLATE_CHIP) = 'fhglfwyt85jncwufjoinhffuku86yhgs';
##CONFIG#END##################################################################
my ($VERSION) = 'v2.24beta1';
my ($APPURL ) = 'http://www.steveshipway.org/software/';
my ($FURL   ) = 'http://www.steveshipway.org/forum/';
my ($MLURL  ) = 'http://www.steveshipway.org/mailman/listinfo/support_steveshipway.org';
my ($WLURL  ) = 'http://www.steveshipway.org/software/wishlist.html';
my ($BURL   ) = 'http://www.steveshipway.org/book/';
my ($APPMAIL) = 'mailto:steve@steveshipway.org';
##GLOBAL#START################################################################
# Global variables : uses 'use vars' for speeycgi and mod_perl
use vars qw($opt_A $opt_D $opt_T $opt_r $opt_i $opt_s $opt_t $opt_I $opt_a $opt_U $opt_C $opt_G);
use vars qw($meurl $meurlfull);
use vars qw($mtype $gtype $defgopts  $defgtype  $defrouter  $defif  $cookie);
($mtype,$gtype,$defgopts, $defgtype, $defrouter, $defif, $cookie) =
	('','','','','','','');
use vars qw(@cookies);
@cookies=();
use vars qw($gopts  $baropts  $defbaropts  $uopts);
($gopts, $baropts, $defbaropts, $uopts) = ('','','','');
use vars qw(%routers %routerscache); %routers = (); # loaded from cache
use vars qw(%cachedays); 
use vars qw($readinrouters); $readinrouters = 0;
use vars qw(%interfaces %ifstore); 
use vars qw(%lang $language); $language = '';
use vars qw(%gtypes  @gorder);
use vars qw(%gstyles  @sorder  %gstylenames);
use vars qw($gstyle  $defgstyle  $archdate);
($gstyle, $defgstyle, $archdate) = ('','','');
use vars qw(%headeropts); %headeropts = ();
use vars qw(@cfgfiles); @cfgfiles = ();
use vars qw($lastupdate  $workdir  $interval);
($lastupdate, $workdir, $interval) = ('','','');
use vars qw($basetime); $basetime = 0;
use vars qw($pagetype); $pagetype = '';
use vars qw($donecfg); $donecfg = 0;
use vars qw(%config); 
use vars qw($bn); $bn = '';
use vars qw($graphsuffix); $graphsuffix = "gif";
use vars qw($NT); $NT = 0;             # gets set to 1 if using NT 
use vars qw($pathsep); $pathsep = "/";      # gets set to "\\" if you have NT
use vars qw($dailylabel); $dailylabel = "%k";  # set to "%H" if you have ActivePerl
use vars qw($monthlylabel);
$monthlylabel = "%V";# use "%W" for alternate week numbering method
                         # gets set to %W if you have ActivePerl
use vars qw($usesixhour); $usesixhour = 0;
use vars qw($twinmenu); $twinmenu = 0;
use vars qw($rrdoutput); $rrdoutput = "";
use vars qw($rrdxsize  $rrdysize);
($rrdxsize, $rrdysize) = (0,0);
use vars qw($router  $interface);
($router, $interface) = ('','');
use vars qw($uselastupdate $archivetime); $uselastupdate = 0;
use vars qw($ksym $k $M $G $T);
($ksym,$k,$M,$G,$T) = ("K",1024,1024000,1024000000,1024000000000); # mixed 
use vars qw($grouping); $grouping = 0;       # Do we group when sorting routers?
use vars qw($group); $group = "";
use vars qw($csvmime); 
$csvmime = "text/comma-separated"; # MIME type for CSV downloads
use vars qw($windowtitle); $windowtitle = "Systems Monitor"; # Widow title
use vars qw($toptitle); $toptitle = "";                  # Title at top of page
use vars qw($timezone); $timezone = 0;
use vars qw($bits  $factor);
($bits, $factor) = ("!bits",8);
use vars qw($defbgcolour); $defbgcolour = "#ffffff";  # default colours
use vars qw($deffgcolour); $deffgcolour = "#000000";
use vars qw($menubgcolour); $menubgcolour = "#d0d0d0";
use vars qw($menufgcolour); $menufgcolour = "#000000";
use vars qw($authbgcolour); $authbgcolour = "#ffffff";
use vars qw($authfgcolour); $authfgcolour = "#000000";
use vars qw($linkcolour); $linkcolour = "#2020ff";
use vars qw($extra); $extra = "";
use vars qw($archiveme); $archiveme = 0;
use vars qw($archive); $archive = "";
use vars qw($myname); $myname = 'routers2.cgi';
use vars qw($debugmessage); $debugmessage = "Instance: $$\n";
use vars qw($authuser); $authuser  = "";
use vars qw($crypthack); $crypthack = 0; # compatibility for broken crypt 
use vars qw(@params); @params = ();
use vars qw($traffic); $traffic = "";
use vars qw($seclevel); $seclevel = 0;
use vars qw($comma); $comma = ','; # for CSV
use vars qw(@pathinfo); @pathinfo = ();
use vars qw($stime); $stime = (times)[0];
use vars qw($linewidth); $linewidth = 1;
use vars qw($charset); $charset = '';
use vars qw($rrdcached); $rrdcached = '';
use vars qw(@rrdcached); @rrdcached = ();
use vars qw($PERCENT); $PERCENT = 95;

##GLOBAL#END############################################################
# You MAY configure the descriptions in the lines below if you require
# or, remove some entries from the @sorder Styles list.
########################################################################
sub initlabels {
	%gtypes = ( 
		"d"=>"Daily",            "w"=>"Weekly", 
		"m"=>"Monthly",          "y"=>"Yearly", 
		"dwmy"=>"All Graphs",    "6dwmy"=>"All Graphs",
		"6dwmys"=>"Compact",     "dwmys"=>"Compact", 
		"6"=>"6 hour",           "6-"=>"Six hours ago",
		"m-"=>"Last Month",      "w-"=>"Last week", 
		"d-"=>"Yesterday",       "y-"=>"Last Year",    
		"dw"=>"Short term",      "my"=>"Long term",
		"6s"=>"Compact 6 hour",   
		"ds"=>"Compact daily",   "ws"=>"Compact weekly",
		"ms"=>"Compact monthly", "ys"=>"Compact yearly",
		"dm"=>"Day+Month",       "wm"=>"Week+Month", 
		"dy"=>"Day+Year",
		"x1"=>"X1", "x2"=>"X2", "x3"=>"X3", "x4"=>"X4"
	 );
	@gorder = qw/d w m y dwmy dwmys/; 
	# you might prefer to have the order reversed
	# NOTE: first word of these is the key used in routers.conf for default
	# base style: s t n l x y = widths; s t = half data width
	# suffix: D = double data width, 2 3 = height multiplier
    #         p = no javascript (pda), b = monochrome (b&w)
	# so for example, tD is the same as n
	%gstyles = ( 
		s=>"Short (PDA)", n=>"Normal (640x480)", t=>"Stretch", l=>"Long", 
		n2=>"Tall", l2=>"Big (800x600)", x3=>"Huge (1024x768)", x=>"ExtraLong",
		sbp=>"Palm III/V", nbp=>"Psion 3/3x/5", np=>"WinCE-1", sp=>"WinCE-2",
		l2p=>"Web TV", x2=>"Very Big (1024x768)" ,
		y3=>"Vast (widescreen)", x3D=>"Huge extended", l2D=>"Big extended",
		x3H=>"Huge stretch", l2H=>"Big stretch",
		x3T=>"Huge triple",
	);
	if(defined $config{'routers.cgi-sorder'} ) {
		@sorder = ();
		foreach ( split " ", $config{'routers.cgi-sorder'} ) {
			push @sorder, $_ if(defined $gstyles{$_});
		}
	} else {
		# you might want to remove some of these
		@sorder = qw/s t n n2 l l2 l2D x x3 x3D sbp nbp np l2p/; 
	}
}

##CODE#START############################################################
# Nothing else to configure after this line
########################################################################

# initialize CGI
use vars qw($q);
$q = new CGI; # At this point, parameters are parsed

$meurl = $q->url(-absolute=>1); # /cgi-bin/routers2.cgi
$meurlfull = $q->url(-full=>1); # http://server/cgi-bin/routers2.cgi
$meurlfull = "" if($meurlfull !~ /\/\/.*\//); # avoid IIS bug, maybe
$router = $interface = "";

#################################
# For RRD v1.2 compatibility: remove colons for COMMENT directive if
# we are in v1.2 or later, else leave them there
sub decolon($) {
	my($s) = $_[0];
	return $s if($RRDs::VERSION < 1.2 );
	$s =~ s/:/\\:/g;
	return $s;
}

#################################
# For RRD archives: make 2chr subdir name from filename
sub makehash($) {
	my($x);
# This is more balanced
	$x = unpack( '%8C*',$_[0] );
# This is easier to follow
#	$x = substr($_[0],0,2);
	return $x;
}

#################################
# For expanding variables
sub expandvars($) {
	my($s) = $_[0];
	my($luh);
	my($rv,$tmp);
	my($comm) = '';
	my($dev) = '';
	my($snmp,$snmperr,$resp) = ('','','');

	# Process %INCLUDE(....)% symbols
	while( $s =~ /\%INCLUDE\(\s*(\S+)\s*\)\%/ ) {
		my($f) = $1;
		my($d) = "";
		if( open INC,"<$f" ) {	
			while ( <INC> ) { $d .= $_; }
			close INC;
		} else {
			$d = "Error: File $f: $!";
		}
		$s =~ s/\%INCLUDE\(\s*$f\s*\)\%/$d/g;
	}

	# Process all standard symbols and their variants
	$s =~ s/\%ROUTERS2?\%/$meurlfull/g;
	$s =~ s/\%CFG(FILE)?\%/$routers{$router}{file}/g;
	$s =~ s/\%INTERVAL\%/$routers{$router}{interval}/g;
	$s =~ s/\%(ROUTER|DEVICE)\%/$router/g;
	$s =~ s/\%(TARGET|INTERFACE)\%/$interface/g;
	$s =~ s/\%STYLE\%/$gstyle/g;
	$s =~ s/\%TYPE\%/$gtype/g;
	$s =~ s/\%STYLENAME\%/$gstyles{$gstyle}/g;
	$s =~ s/\%TYPENAME\%/$gtypes{$gtype}/g;
	$s =~ s/\%L(U|ASTUPDATE)\%/$lastupdate/g;
	if($lastupdate) { $luh = longdate($lastupdate); } 
	else { $luh = "Unknown"; }
	$s =~ s/\%L(U|ASTUPDATE)H\%/$luh/g;
	$s =~ s/\%ARCHDATE\%/$archdate/g;
	$s =~ s/\%USER(NAME)?\%/$authuser/g;
	$tmp = optionstring({page=>"image"});
	$s =~ s/\%GRAPHURL\%/$meurlfull?$tmp/g;
	$tmp = 300;
	if( $gtype =~ /y/ ) { $tmp = 24 * 3600; }
	elsif( $gtype =~ /m/ ) { $tmp = 7200; }
	elsif( $gtype =~ /w/ ) { $tmp = 1800; }
	$s =~ s/\%AVGINT\%/$tmp/g;
	

	$rv = $routers{$router}{'cfgmaker-system'}; $rv="" if(!defined $rv);
	$s =~ s/\%CMSYSTEM\%/$rv/g;
	$rv = $routers{$router}{'cfgmaker-description'}; $rv="" if(!defined $rv);
	$s =~ s/\%CMDESC(RIPTION)?\%/$rv/g;
	$rv = $routers{$router}{'cfgmaker-contact'}; $rv="" if(!defined $rv);
	$s =~ s/\%CMCONTACT\%/$rv/g;
	$rv = $routers{$router}{'cfgmaker-location'}; $rv="" if(!defined $rv);
	$s =~ s/\%CMLOCATION\%/$rv/g;

	if( defined $interfaces{$interface} ) {
		$rv = $interfaces{$interface}{maxbytes}; $rv = "" if(!defined $rv);
		$s =~ s/\%(MAXBYTES|BANDWIDTH)\%/$rv/g;
		$rv = $interfaces{$interface}{ipaddress}; $rv = "" if(!defined $rv);
		$s =~ s/\%IP(ADDR(ESS)?)?\%/$rv/g;
		$rv = $interfaces{$interface}{community}; 
		$rv = $routers{$router}{community} if(! $rv);
		$rv = "" if(!defined $rv);
		$s =~ s/\%COMMUNITY\%/$rv/g;
		$rv = $interfaces{$interface}{hostname}; 
		$rv = $routers{$router}{hostname} if(! $rv);
		$rv = "" if(!defined $rv);
		$s =~ s/\%HOST(NAME)?\%/$rv/g;
		$rv = $interfaces{$interface}{rrd}; $rv = "" if(!defined $rv);
		$s =~ s/\%RRD(FILE)?\%/$rv/g;
		$rv = $interfaces{$interface}{ifno}; $rv = "" if(!defined $rv);
		$s =~ s/\%(IFNO|INTNUM)?\%/$rv/g;

		$rv = $interfaces{$interface}{'cfgmaker-description'}; 
		$rv = "" if(!defined $rv);
		$s =~ s/\%CMIDESC(RIPTION)?\%/$rv/g;

		if( defined $interfaces{$interface}{symbols} ) {
			foreach my $sym ( keys %{$interfaces{$interface}{symbols}} ) {
				my $v = $interfaces{$interface}{symbols}{$sym};
				$s =~ s/\%$sym\%/$v/g;
			}
		}
	} else {
		$rv = $routers{$router}{community}; $rv = "" if(!defined $rv);
		$s =~ s/\%COMMUNITY\%/$rv/g;
		$rv = $routers{$router}{hostname}; $rv = "" if(!defined $rv);
		$s =~ s/\%HOST(NAME)?\%/$rv/g;
	}
	if( defined $routers{$router}{symbols} ) {
		foreach my $sym ( keys %{$routers{$router}{symbols}} ) {
			my $v = $routers{$router}{symbols}{$sym};
			$s =~ s/\%$sym\%/$v/g;
		}
	}

	# Process %ENV(...)% symbols
	while( $s =~ /\%ENV\(\s*(\S+)\s*\)\%/ ) {
		my($a) = $1;
		my($b) = $ENV{$a};
		$s =~ s/\%ENV\($a\)\%/$b/g;
	}

	# Process %OID(....)% symbols
	while( $s =~ /\%OID\(\s*(\S+)\s*\)\%/ ) {
		my($a) = $1;
		my($b) = '[Not yet supported]';
		my($vb);
		$comm = $routers{$router}{community} if($routers{$router}{community});
		$dev  = $routers{$router}{hostname} if($routers{$router}{hostname});
		if($interface and $interfaces{$interface} ) {
			$comm = $interfaces{$interface}{community} 
				if($interfaces{$interface}{community});
			$dev  = $interfaces{$interface}{hostname} 
				if($interfaces{$interface}{hostname});
			$dev  = $interfaces{$interface}{ipaddress} 
				if($interfaces{$interface}{ipaddress});
		}
		if(! $comm) {
			$b = "[No community: Cannot request OID]";
		} elsif(! $dev) {
			$b = "[No hostname/IP known: Cannot request OID]";
		} else {
			# look up the OID via SNMP
			eval { require Net::SNMP; };
			if($@) {
				$b = "[Net::SNMP not available]";
			} else {
				if(!$snmp) {
					($snmp, $snmperr) = Net::SNMP->session(
						-hostname=>$dev, -community=>$comm, -timeout=>4 );
				}
				if($snmperr) { $b = "[SNMP Error: $snmperr]"; }
				else {
					$resp = $snmp->get_request( $a );
					if( defined $resp ) {
						$vb = $snmp->var_bind_types( $a );
						$b = "";
						foreach ( keys %$resp ) { 
							if($vb->{$_} eq *TIMETICKS ) {
								$b .= ticks_to_time($resp->{$_}); 
							} else { $b .= $resp->{$_}; }
						}
					} else { $b = "[SNMP Error:".$snmp->error()."]"; }
				}
			}
		}
		$s =~ s/\%OID\($a\)\%/$b/;
	}
	$snmp->close() if($snmp);

	# Process %EXEC(...)% symbol
	if(defined $config{'web-allow-execs'} 
		and $config{'web-allow-execs'}=~/[y1]/) {
		while( $s =~ /\%EXEC\(([^\)]+)\)\%/ ) {
			my($a) = $1;
			my($b) = `$a`; # DANGER WILL ROBINSON!
			$s =~ s/\%EXEC\($a\)\%/$b/;
		}
	}
	return $s;
}

#################################
# For sorting

sub rev { $b cmp $a; }
sub numerically { 
	return ($a cmp $b) if( $a !~ /\d/ or $b !~ /\d/ );
	$a <=> $b; 
} 
sub bytraffic {
	return -1 if(!$a or !$b or !$traffic);
#	return -1 if(!defined $interfaces{$a}{$traffic}
#		or !defined $interfaces{$b}{$traffic});
	$interfaces{$b}{$traffic} <=> $interfaces{$a}{$traffic};
}
sub byiflongdesc {
	my ( $da, $db ) = ( "#$a","#$b" );
	# is this an invalid interface?
	return 0 if(!defined $interfaces{$a} or !defined $interfaces{$b});
	return 1  if(!$interfaces{$a}{inmenu} and $interfaces{$b}{inmenu});
	return -1 if(!$interfaces{$b}{inmenu} and $interfaces{$a}{inmenu});
	if( defined $config{'targetnames-ifsort'} ) {
		if( $config{'targetnames-ifsort'} eq 'icon' ) {
			return $interfaces{$a}{icon} cmp $interfaces{$b}{icon}
				if($interfaces{$a}{icon} ne $interfaces{$b}{icon});
		} elsif( $config{'targetnames-ifsort'} eq 'mode' ) {
			return $interfaces{$a}{mode} cmp $interfaces{$b}{mode}
				if($interfaces{$a}{mode} ne $interfaces{$b}{mode});
		}
	} else {
		return $interfaces{$a}{mode} cmp $interfaces{$b}{mode}
			if($interfaces{$a}{mode} ne $interfaces{$b}{mode});
	}
	# we always sort by description in the end
	$da = $interfaces{$a}{shdesc} if( defined $interfaces{$a}{shdesc} );
	$db = $interfaces{$b}{shdesc} if( defined $interfaces{$b}{shdesc} );
	$da = $interfaces{$a}{desc} if( defined $interfaces{$a}{desc} );
	$db = $interfaces{$b}{desc} if( defined $interfaces{$b}{desc} );
	(lc $da) cmp (lc $db);
}
sub byifdesc {
	my ( $da, $db ) = ( "#$a","#$b" );
	# is this an invalid interface?
	return 0 if(!defined $interfaces{$a} or !defined $interfaces{$b});
	return 1  if(!$interfaces{$a}{inmenu} and $interfaces{$b}{inmenu});
	return -1 if(!$interfaces{$b}{inmenu} and $interfaces{$a}{inmenu});

	if( defined $config{'targetnames-ifsort'} ) {
		if( $config{'targetnames-ifsort'} eq 'icon' ) {
			return $interfaces{$a}{icon} cmp $interfaces{$b}{icon}
				if($interfaces{$a}{icon} ne $interfaces{$b}{icon});
		} elsif( $config{'targetnames-ifsort'} eq 'mode' ) {
			return $interfaces{$a}{mode} cmp $interfaces{$b}{mode}
				if($interfaces{$a}{mode} ne $interfaces{$b}{mode});
		}
	} else {
		return $interfaces{$a}{mode} cmp $interfaces{$b}{mode}
			if($interfaces{$a}{mode} ne $interfaces{$b}{mode});
	}
	# we always sort by description in the end
	$da = $interfaces{$a}{shdesc} if( defined $interfaces{$a}{shdesc} );
	$db = $interfaces{$b}{shdesc} if( defined $interfaces{$b}{shdesc} );
	(lc $da) cmp (lc $db);
}
sub bydesc { 
	my ( $da, $db ) = ($routers{$a}{desc}, $routers{$b}{desc});
	$da = $a if ( ! $da );
	$db = $b if ( ! $db );
	(lc $da) cmp (lc $db); 
}
# Sorting function for devices menu
sub byshdesc { 
	my ( $da, $db ) = ($routers{$a}{shdesc}, $routers{$b}{shdesc});
	if( $grouping ) {
		my ( $ga ) = $routers{$a}{group};
		my ( $gb ) = $routers{$b}{group};
		$ga=$config{"targetnames-$ga"} if(defined $config{"targetnames-$ga"});
		$gb=$config{"targetnames-$gb"} if(defined $config{"targetnames-$gb"});
		# Sort by group name first
		my ( $c  ) = $ga cmp $gb;
		if($c) { return $c; }
	}
	# Sort by description of device
	$da = $a if ( ! $da );
	$db = $b if ( ! $db );
	(lc $da) cmp (lc $db); 
}
# For sorting component targets in a userdefined
# sort option can be MAX, AVG, LAST
sub byoption {
	return($interfaces{$b}{sorttmp} <=> $interfaces{$a}{sorttmp});
}
sub byoptionrev {
	return($interfaces{$a}{sorttmp} <=> $interfaces{$b}{sorttmp});
}
sub sorttargets($$$) {
	my($interface,$dwmy,$option) = @_;
	my($from,$rrd,$e);
	my($resolution,$interval,$seconds);
	my($curif);
	my(@sorted) = ();

	return if(!$interfaces{$interface}{targets});

	if( $option =~ /desc|name|title/i ) {
		@sorted = 
			sort { (lc $interfaces{$a}{shdesc}) cmp (lc $interfaces{$b}{shdesc}); }
				@{$interfaces{$interface}{targets}};
		return @sorted;
	}

	$resolution = 60; $interval = "6h"; $seconds = 6*3600;
	if ( $dwmy=~/d/ ){$resolution=300; $interval="24h"; $seconds=86400; }
	elsif($dwmy=~/w/){$resolution=1800; $interval="7d"; $seconds=7*86400; }
	elsif($dwmy=~/m/){$resolution=7200; $interval="1month"; $seconds=30*86400;}
	elsif($dwmy=~/y/){$resolution=86400; $interval="1y"; $seconds=365*86400;}

	$curif = $interfaces{$interface}{targets}[0];
	$rrd = $interfaces{$curif}{rrd};
	if($basetime) {
		$from = $basetime;
	} elsif( $dwmy =~ /-/ ) {
		$from = "now-$interval";
	} elsif($uselastupdate > 1 and $archivetime) {
		$from = $archivetime;
	} elsif($uselastupdate) {
		$from = RRDs::last($rrd,@rrdcached);
		$e = RRDs::error();
		if($e) {
			$from = "now";
			$interfaces{$curif}{errors}.= $q->br.$q->small(langmsg(8999,"Error").": $e")."\n";
		}
	} else {
		$from = "now-5min";
	}

	foreach $curif ( @{$interfaces{$interface}{targets}} ) {
		$interfaces{$curif}{sorttmp} = 0;
		$rrd = $interfaces{$curif}{rrd};
		if( $option =~ /max/i ) {
			my ( $start, $step, $names, $values ) = 
				RRDs::fetch($rrd,"MAX","-s","$from-$interval",
					"-e",$from,"-r",$seconds,@rrdcached);
			$e = RRDs::error();
			if($e) { 
				$interfaces{$curif}{errors} .= $q->br.$q->small(langmsg(8999,"Error").": $e");
			} else {
				my ($maxin, $maxout) = get_max($values);
				$interfaces{$curif}{sorttmp}=(($maxin>$maxout)?$maxin:$maxout);
			}
		} elsif( $option =~ /last/i ) {
		} else { # avg
			my ( $start, $step, $names, $values ) = 
				RRDs::fetch($rrd,"AVERAGE","-s","$from-$interval",
					"-e",$from,"-r",$seconds,@rrdcached);
			$e = RRDs::error();
			if($e) { 
				$interfaces{$curif}{errors} .= $q->br.$q->small(langmsg(8999,"Error").": $e");
			} else {
				my ($avgin, $avgout) = get_avg($values);
				$interfaces{$curif}{sorttmp}=(($avgin>$avgout)?$avgin:$avgout);
			}
		}
	}

	if($option=~/rev/) {
		@sorted = sort byoptionrev @{$interfaces{$interface}{targets}};
	} else {
		@sorted = sort byoption @{$interfaces{$interface}{targets}};
	}
	return @sorted;
}
#####################
# Timezone calculations
# Calculate timezone.  We don't need to do this again if its already been 
# done in a previous iteration.  Now, we need this if we're making a graph
# with working day intervals, or if we're on a graph/summary page with a 
# time popup - but we may as well do it every time.
sub calctimezone() {
	my( @gm, @loc, $hourdif );
$timezone = 0;
if( defined $config{'web-timezone'} ) {
	# If its been defined explicitly, then use that.
	$timezone = $config{'web-timezone'};
} else {
	# Do we have Time::Zone?
	eval { require Time::Zone; };
	if ( $@ ) {
		eval { @gm = gmtime; @loc = localtime; };
		if( $@ ) {
			# Can't work out local timezone, so assume GMT
			$timezone = 0; 
		} else {
			$hourdif = $loc[2] - $gm[2];
			$hourdif += 24 if($loc[3]>$gm[3] or $loc[4]>$gm[4] );
			$hourdif -= 24 if($loc[3]<$gm[3] or $loc[4]<$gm[4] );
			$timezone = $hourdif;
		}
	} else {
		# Use the Time::Zone package since we have it
		$timezone = Time::Zone::tz_local_offset() / 3600; 
		# it's in seconds so /3600
	}
}
}

######################
# For grouping multilevel.  Work out which groups we need to display.
# (activegroup, thisgroup, lastgroup)
# returns [ [groupname,depth,active], ... ]
sub getgroups($$$) {
	my(@rv) = ();
	my($ag,$tg,$lg) = @_;
	my(@ag,@tg,@lg);
	my($gs) = ':';
	my($i) = 0;
	my($actv) = 1;

	$gs = $config{'routers.cgi-groupsep'} 
		if(defined $config{'routers.cgi-groupsep'});
	$gs =~ s/\//\\\//g;

	@ag = split /$gs/,$ag;
	@tg = split /$gs/,$tg;
	@lg = split /$gs/,$lg;

	while( $i <= $#tg ) {
		$actv = 0 if( $tg[$i] ne $ag[$i] );

		if( $tg[$i] ne $lg[$i] ) {
			$tg[$i] =~ s/^\s*//; # trim leading spaces
			push @rv, [ $tg[$i], $i, $actv ];
		}
		last if(!$actv);
		$i += 1;
	}

#	push @rv, [ $tg, 0, 0 ];
	return @rv;
}

######################
# Replacement for glob: find archives
# return list of dates
# This time, we also cache the list of archive dates, if we can
sub findarch($$)
{
	my(@files) = ();
	my($path,$file) = @_;

	if ($config{'routers.cgi-archive-mode'} and
		$config{'routers.cgi-archive-mode'}=~/hash/i ) {
		foreach ( glob( $path.$pathsep.makehash($file).$pathsep.$file.".d".$pathsep."*-*-*.rrd" ) ) { 
			push @files, $1 if( /(\d\d\d\d-\d\d-\d\d).rrd/ );
		}
	} else {
		opendir DIR, $path or return @files;
		foreach ( readdir DIR ) { 
			push @files, $_ if( -f $path.$pathsep.$_ .$pathsep.$file );
		}
		closedir DIR;
	}
	return @files;
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
	$dformat = $config{'web-dateonlyformat'}
		if(defined $config{'web-dateonlyformat'});
	$dformat = $config{'web-shortdateformat'}
		if(defined $config{'web-shortdateformat'});
	$dformat =~ s/&nbsp;/ /g;
	$datestr = POSIX::strftime($dformat,
		0,$min,$hour,$mday,$mon,$year);
	return "DATE ERROR 2" if(!$datestr);
	return $datestr;
}
sub longdate($) {
	# try to get local formatting
	my( $dformat ) = "%c";
	my( $datestr, $fmttime ) = ("",$_[0]);
	my( $sec, $min, $hour, $mday, $mon, $year ) = localtime($fmttime);
	$dformat = $config{'web-shortdateformat'}
		if(defined $config{'web-shortdateformat'});
	$dformat = $config{'web-longdateformat'}
		if(defined $config{'web-longdateformat'});
	$datestr = POSIX::strftime($dformat,0,$min,$hour,$mday,$mon,$year);
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

#################################
# build up option string
sub optionstring(%)
{
	my(%o,$options);
	%o = %{$_[0]};

	$o{page}="graph" if(!defined $o{page});
	$o{xgtype}="$gtype" if($gtype and !defined $o{xgtype});
	$o{xmtype}="$mtype" if($mtype and !defined $o{xmtype});
	$o{xgstyle}="$gstyle" if($gstyle and !defined $o{xgstyle});
	$o{xgopts}="$gopts" if($gopts and !defined $o{xgopts});
	$o{bars}="$baropts" if($baropts and !defined $o{bars});
	$o{rtr}="$router" if($router and !defined $o{rtr});
	$o{if}="$interface" if($interface and !defined $o{if});
	$o{extra}="$extra" if($extra and !defined $o{extra});
	$o{uopts}="$uopts" if($uopts and !defined $o{uopts});
	$o{arch}="$archdate" if($archdate and !defined $o{arch});
# This shouldnt be propagated, really.
#	$o{nomenu}=1 if($q->param('nomenu') and !defined $o{nomenu});

	$options = "";
	foreach ( keys %o ) {
		if( $o{$_} ) {
			$options .= "&" if ($options);
			$options .= "$_=".$q->escape($o{$_});
		}
	}
	return $options;
}

#################################
# Generate the javascript for the page header
sub make_javascript(%)
{
	my($js) = "";
	my(%opa,%opb);
	my($ua,$ub);

	return("function LoadMenu() { }") if($q->param('nomenu') or $gstyle=~/p/);

	%opa = ( page=>"menu" );
	foreach ( keys %{$_[0]} ) { $opa{$_}=$_[0]->{$_}; }

	$js = "	
	// these local versions are not optimised but avoid cross-site scripting
	// problems when running in distributed mode
	// Test for parent.menu in case someone is running graph frame standalone
	function setlocationa(url) {
		if(parent.makebookmark) { parent.setlocationa(url); }
	}
	function setlocationb(url) {
		if(parent.makebookmark) { parent.setlocationb(url); }
	}
";
	if( $twinmenu ) {
		%opb = %opa;
		$opa{xmtype} = "routers"; $opa{'if'} = "";
		$opb{page} = "menub"; $opb{xmtype} = "options";
		$ua = "$meurlfull?".optionstring(\%opa)."#top";
		$ub = "$meurlfull?".optionstring(\%opb)."#top"; 
		$js .= "function LoadMenu() { setlocationb(\"$ub\"); setlocationa(\"$ua\");	}\n";
	} else { # not twinmenu mode
		$opa{xmtype}="routers" 
		if($router eq "none" or (defined $opa{rtr} and $opa{rtr} eq "none"));
		$opa{'if'}='' if($opa{xmtype}eq'routers');
		$ua = "$meurlfull?".optionstring(\%opa)."#top"; 
		$js .= "function LoadMenu() { setlocationa(\"$ua\"); } \n";
	}

	return $js;
}
# Makes the javascript for a popup time window on graphs.
# This goes into a hidden div called dpopup at the top of the page.
# This incorporates bits of code copied from the overlib javascript library
# which is (C) Eric Bosrup
sub graphpopupscript() {
	my($js,$xpad,$ypad);
	my($stretch) = 1;

    if(( defined $config{'routers.cgi-javascript'} 
    	and $config{'routers.cgi-javascript'} =~ /[n0]/i ) 
		or $gstyle =~ /p/ ) {
        $js = " function clearpopup() { }
            function timepopup() { }
            function mousemove() { } ";
    } else {
		eval { require RRDs; }; # just in case
		return "" if($@);
		if( $RRDs::VERSION >= 1.4 ) { $xpad = 66; $ypad = 33; }
		elsif( $RRDs::VERSION >= 1.2 ) { $xpad = 69; $ypad = 33; }
		else { $xpad = 75; $ypad = 30; }
		$stretch *= 2 if ($gstyle=~/D/);
		$stretch /= 2 if ($gstyle=~/H/);
		$stretch /= 2 if ($gstyle=~/^t/); # for stretch style, t==nH

	$js = "// Function for RRDs version ".$RRDs::VERSION."\n";
	$js .= "
// This javascript code derived in part from Overlib by Eric Bosrup
var tzoffset = 0;
";
	if(defined $config{'routers.cgi-actuals'}
		and $config{'routers.cgi-actuals'}=~/[y1]/i
		and (!defined $config{'routers.cgi-javascript'}
		or $config{'routers.cgi-javascript'}=~/[y1]/i)) {
		# larger offset if we're using actuals
		$js .= "
var ooffsety = -40; // above the cursor, to the right
var ooffsetx = 10;  // offset of popup from cursor position
";
	} else {
		$js .= "
var ooffsety = -25; // above the cursor, to the right
var ooffsetx = 5;  // offset of popup from cursor position
";
	}
	$js .= "
var owidth = 100;  // width of the popup
var pop=null;
var gx, gy, gw;
var img=null;
var interval = 0;
var endtime = 0;
var ns4=(document.layers)? true:false;
var ns6=(document.getElementById)? true:false;
var ie4=(document.all)? true:false;
var ie5=false;
var ie6=false;
var dow=new Array(\"Sun\",\"Mon\",\"Tue\",\"Wed\",\"Thu\",\"Fri\",\"Sat\",\"Sun\");
var actual=new Array(5); // to hold 6/d/w/m/y arrays of 400 items
var xactual=new Array(5); // to hold 6/d/w/m/y  flags
xactual[0]=0; xactual[1]=0; xactual[2]=0; xactual[3]=0; xactual[4]=0; xactual[5]=0;
if(ie4){
	if((navigator.userAgent.indexOf('MSIE 5')> 0)
	||(navigator.userAgent.indexOf('MSIE 6')> 0)
	||(navigator.userAgent.indexOf('MSIE 7')> 0)
	){ ie5=true; }
	if((navigator.userAgent.indexOf('MSIE 6')> 0)
	||(navigator.userAgent.indexOf('MSIE 7')> 0)
	){ ie6=true; }
	if(ns6){ ns6=false; }
}

function getextra(t) {
	var idx;
	var group;
	var rv = \"\";
	if(interval<1)return rv;
	if(interval == 1800) { // weeks have only 333 not 400 dp in graph image
	idx = 400-Math.floor((endtime-t)/(1500*$stretch)); // array index
	} else {
	idx = 400-Math.floor((endtime-t)/(interval*$stretch)); // array index
	}
	group = 0; // 6 hourly
	if ( interval > 61  ) { group = 1; } // daily
	if ( interval > 301 ) { group = 2; } // weekly
	if ( interval > 1801 ) { group = 3; } // monthly
	if ( interval > 7201 ) { group = 4; } // yealy
	// now, see if we have stored any data for this interval
	if( xactual[group]>0 && (\"\"+actual[group][idx])!=\"undefined\" ) { rv = \"<BR>\"+actual[group][idx]; }
	return rv;
}
function clearpopup() {
  if(pop != null ) {
    if(ns4)pop.visibility=\"hide\";
    else if(ie4)pop.visibility=\"hidden\";
    else if(ns6)pop.style.visibility=\"hidden\";
  } else { self.status = \"Error - no popup div defined.\"; }
  endtime = 0;
}
function settext(s) {
  if( pop != null ) {
    if(ns4){
      pop.document.write(s);
      pop.document.close();
      pop.visibility=\"show\";
    }else if(ie4){
      self.document.all['dpopup'].innerHTML=s;
      pop.visibility=\"visible\";
    }else if(ns6){
      range=self.document.createRange();
      range.setStartBefore(pop);
      domfrag=range.createContextualFragment(s);
      while(pop.hasChildNodes()){ pop.removeChild(pop.lastChild); }
      pop.appendChild(domfrag);
      pop.style.visibility=\"visible\";
    } // else { self.status = \"Error - cannot determine brower\"; }
  } else { self.status = \"Error - no popup div available\"; }
}
function repositionTo(obj,xL,yL){
  if((ns4)||(ie4)){ obj.left=xL; obj.top=yL; }
  else if(ns6){
    obj.style.left=xL + \"px\";
    obj.style.top=yL+ \"px\";
  }
}
function fix(n) { var d = n; if(d<10) d=\"0\"+d; return d; }
function findPosX(obj)
{
	var curleft = 0;
	if (obj.offsetParent) {
		while (obj.offsetParent) {
			curleft += obj.offsetLeft;
			if( obj.scrollLeft ) curtop -= obj.scrollLeft; 
			obj = obj.offsetParent;
		}
	}
	else {
		if (obj.x) curleft += obj.x;
		if( obj.scrollLeft ) curtop -= obj.scrollLeft; 
	}
	return curleft;
}

// Here we have a problem - IE gives offset relative to window, Netscape
// gives relative to frame.  So a scrolled window doesnt work in IE.
function findPosY(obj)
{
	var curtop = 0;
	if (obj.offsetParent) {
		while (obj.offsetParent) { 
			curtop += obj.offsetTop;
			if( obj.scrollTop ) curtop -= obj.scrollTop; 
			 obj = obj.offsetParent; 
		}
	}
	else {
		if (obj.y) curtop += obj.y;
		if( obj.scrollTop ) curtop -= obj.scrollTop; 
	}
	return curtop;
}

function mousemove(e) {
  var msg, ox, oy, t, extra;
  var placeX, placeY, winoffset, ohpos, ovpos, iwidth, iheight, scrollheight;
  var scrolloffset, oaboveheight, d;

  if( ! endtime ) return;
	if(!e) { e=window.event; }
	if( typeof(e.pageX)=='number' ) { 
       ox = e.pageX; oy=e.pageY; 
		winoffset = self.pageXOffset; 
		scrolloffset = self.pageYOffset;
    } else if( typeof(e.clientX)=='number' ) {
		if( document.documentElement) {
			winoffset = document.documentElement.scrollLeft;
			scrolloffset = document.documentElement.scrollTop;
			ox = e.clientX + winoffset;
			oy = e.clientY + scrolloffset;
		} else {
			winoffset = document.body.scrollLeft;
			scrolloffset= document.body.scrollTop;
			ox = e.clientX + winoffset;
			oy = e.clientY + scrolloffset;
		}
	} else if(ie5) {
		winoffset = self.document.body.scrollLeft;
		scrolloffset = self.document.body.scrollTop; 
		ox=e.x+winoffset;
		oy=e.y+scrolloffset; 
	} else { 
		ox = e.x; oy =e.y; 
		winoffset = 0;  // guess
		scrolloffset = 0;
	}

// ox,oy is where the mouse is.  placeX,placeY is where the popup is going

// now determine the frame size (inner width and height)
  if(ie4){ iwidth=self.document.body.clientWidth; 
    iheight=self.document.body.clientHeight; } 
  else if(ns4){ iwidth=self.innerWidth; iheight=self.innerHeight; } 
  else if(ns6){ iwidth=self.outerWidth; iheight=self.outerHeight; }
// iwidth is the actual page width. owidth is the bit outside.
// winoffset is how much we've scrolled horizontally
// X position for popup
  placeX = ox+ooffsetx;
  if(placeX > (iwidth-owidth+winoffset)){
    placeX = iwidth-owidth+winoffset ;
    if(placeX < 0) placeX = 0; // should be impossible
  }
// y position for popup
  if((oy - scrolloffset)> iheight){ ovpos=35; }else{ ovpos=36; }
  if(ovpos==35){
    if(oaboveheight==0){
      var divref=(ie4)? self.document.all['dpopup'] : pop;
      oaboveheight=(ns4)? divref.clip.height : divref.offsetHeight;
    }
    placeY=oy -(oaboveheight + ooffsety);
    if(placeY < scrolloffset)placeY=scrolloffset; // why doesnt this work?
  }else{ placeY=oy + ooffsety; }
// relative to image 
  ox -= findPosX(img); oy -= findPosY(img);
// calculate time at cursor
  if(( ox >= $xpad ) && ( ox <= (gx+$xpad)) && ( oy >= $ypad ) && ( oy <= (gy+$ypad) )) {
    if( interval == 1800 ) { // special for weekly
      t = endtime - 1500 * ($xpad+gx-ox)*gw/gx; // may only be approximate?
    } else {
      t = endtime - interval * ($xpad+gx-ox)*gw/gx; // may only be approximate?
    }
  } else { t = 0; }
  if( t ) {
	// the problem is we want to display this in the timezone of the TARGET.
	// t is the UTC time, and the Javascript Date object will give everything
	// relative to the workstation timezone.  So, we add the tz offset of
	// the Target, and subtract the tz offset of the workstation.
	// note that the passed tzoffset and that returned by getTimezoneOffset
	// seem to be different signs.
    d = new Date(t*1000);
    d.setTime((t+tzoffset+(d.getTimezoneOffset()*60))*1000);
    if( interval > 72000 ) { // dayofweek day/month (yearly graph)
";
	# I tawt I taw a Mewwican!
	if( defined $config{"web-shortdateformat"} 
		and $config{"web-shortdateformat"}=~ /\/\%d|\%D/ ) {
		# I did! I did taw a Mewwican!
	    $js .= " msg = dow[d.getDay()]+\" \"+(d.getMonth()+1)+\"/\"+d.getDate();\n";
	} else {
		$js .= " msg = dow[d.getDay()]+\" \"+d.getDate()+\"/\"+(d.getMonth()+1);\n";
	}
	$js .= "
    } else if( interval > 4000 ) { // dayofweek day hour:00 (monthly graph)
      msg = dow[d.getDay()]+\" \"+d.getDate()+\" \"+fix(d.getHours())+\":00\";
    } else if( interval > 1000 ) { // dayofweek day time (weekly graph)
      msg = dow[d.getDay()]+\" \"+d.getDate()+\" \"+fix(d.getHours())+\":\"+fix(d.getMinutes());
    } else { // time (daily graph)
      msg = fix(d.getHours())+\":\"+fix(d.getMinutes());
    }
// for debugging the amazingly difficult timezone calculations
//	msg = msg + \" \" + d.getDay() + \"<BR>\" + endtime + \":\" + t + \"<BR>\" + tzoffset + \":\" + (d.getTimezoneOffset()*60);
	extra = getextra(t);
    settext(\"<STRONG>\"+msg+\"</STRONG>\"+extra);
	repositionTo(pop, placeX, placeY);
  } else {
    if(ns4)pop.visibility=\"hide\";
    else if(ie4)pop.visibility=\"hidden\";
    else if(ns6)pop.style.visibility=\"hidden\";
  }
}

function timepopup(o,n,px,py,i,t,dx,tzo) {
  divname = n; img = o; gx = px; gy = py; interval = i; endtime = t; gw = dx;
  tzoffset = tzo;
  if(ns4) { pop=self.document.dpopup; }
  else if(ie4) { if(self.dpopup) { pop=self.dpopup.style;} else { endtime=0;}}
  else if(ns6) { pop=self.document.getElementById(\"dpopup\"); }
  else { endtime = 0; }
}";
	}
	return $js;
}

#################################
# For persistent caching.  This requires the settings in the routers2.conf
# to specify caching, and specify a caching file.
# Return 0 if worked, 1 if it didnt.
# When loading the cache, set $^T to the modify date of the cache file.
sub write_cache()
{
	my($f);
	return 0 if(!defined $config{'routers.cgi-cachepath'});
	$debugmessage .= "Saving cache file...\n";
	eval { require  Data::Dumper; }; return 1 if($@);
	$f = $config{'routers.cgi-cachepath'}."/routers2.cache";
	open C,">$f" or return 1;
	print C Data::Dumper->Dump([\%routerscache],
		[qw(savrc)]);
#	print C Data::Dumper->Dump([\%routerscache,\%cachedays,\%ifstore],
#		[qw(savrc savcd savis)]);
	close C;
	$debugmessage .= "...done.\n";
	return 0;
}
sub load_cache()
{
	my(@s,$f,$d);
	my($savis,$savrc,$savcd);
	return 0 if(!defined $config{'routers.cgi-cachepath'});
	$debugmessage .= "Checking Cache file\n";
	return 0 if($readinrouters);
	$debugmessage .= "Attempting to load Cache file\n";
	eval { require Data::Dumper; }; 
	if($@) { $debugmessage .= "Unable to load: $@\n"; return 1; }
	$f = $config{'routers.cgi-cachepath'}."/routers2.cache";
	open C,"<$f" or do { 
		$debugmessage .= "Failed to open cache file: $!\n";
		return 1; };
	$d = ""; while( <C> ) { $d .= $_; };
	@s = stat C; $^T = $s[9]; # in case the file is too old
	close C;
	$debugmessage .= "Trying to eval cache file contents\n";
	eval $d;
#	if($@) { %routerscache = (); %cachedays = (); %ifstore = (); return 1; }
#	%routerscache = %$savrc; %cachedays = %$savcd; %ifstore = %$savis;
	if($@ or !$savrc) { %routerscache = ();  
		$debugmessage .= "Failed to eval: $@\n";
		return 1; }
	%routerscache = %$savrc; 
	$debugmessage .= "Cache file loaded OK\n";
	return 0;
}
#################################
# Create a bar graph, as requested by the CGI parameters.
# This should be given two CGI parameters: IN and OUT.  Use GD libraries if
# available to make a simple bar with green bar and blue line. IN and OUT are
# supposed to be percentages.
sub do_bar()
{
	my( $gd, $black, $white, $green, $blue, $grey );
	my( $w, $h ) = (400,10);
	my($x1,$x2);

	eval { require GD; };
	if($@) {
		# GD libraries not available.  So, redirect to error message graphic.
		print $q->redirect($config{'routers.cgi-iconurl'}."error.gif");
		return;
	}

	if( defined $q->param('L') ) 
		{ $w = $q->param('L') if($q->param('L') >100); }

	# We have GD.  So, make up a simple bar graphic and print it - after
	# giving the correct HTML headers of course.
	$gd = new GD::Image($w,$h);
	$black = $gd->colorAllocate(0,0,0);
	$white = $gd->colorAllocate(255,255,255);
	$green = $gd->colorAllocate(0,255,0);
	$blue  = $gd->colorAllocate(0,0,255);
	$grey  = $gd->colorAllocate(192,192,192);

	if( $q->param('IN') < 0 and $q->param('OUT') < 0) {
		# unknown data
		$gd->fill(1,1,$grey); # background
	} else {
		$gd->fill(1,1,$white); # background
		$x1 = $w * $q->param('IN') /100.0 ; 
		$x2 = $w * $q->param('OUT') /100.0 ; 
		$gd->rectangle(0,0,$x1-1,(($x2>=0)?($h/2):$h)-1,$green) if($x1>1);
		$gd->fill(1,1,$green) if($x1 > 2);
		$gd->rectangle(0,(($x1>=0)?($h/2):0),$x2-1,$h-1,$blue) if($x2>1);
		$gd->fill(1,$h-2,$blue) if($x2 > 2);
	}
	$gd->rectangle(0,0,$w-1,$h-1,$black); # box around it

	if(!$gd->can('gif') or( $gd->can('png') 
		and defined $config{'web-png'} and $config{'web-png'}=~/[1y]/i )) {
		print $q->header({ -type=>"image/png", -expires=>"+6min" });
		binmode STDOUT;
		print $gd->png();
	} else {
		print $q->header({ -type=>"image/gif", -expires=>"+6min" });
		binmode STDOUT;
		print $gd->gif();
	}
}
# Thanks to Ciaran Anscomb for this idea
# Dont forget to add \n to help firefox and older browsers with line
# length limitations!
sub do_bar_html($$$$$) {
	my($barlen,$i,$o,$withi,$witho)=@_;
	my($bh)=4;

	if( $config{'routers.cgi-stylesheet'} ) {
		$bh=8 if(!$witho or !$withi);
		print "<TD style='margin-left: 0.5em;'><SMALL>";
		print "<div style='border: 1px solid black; margin: 0; padding: 0; width: ".($barlen-2)."px; height: 8px; background-color: white;'>\n";
		print "<div style='width: $i\%; height: ${bh}px; background-color: #00ff00;'></div>\n" if($withi);
		print "<div style='width: $o\%; height: ${bh}px; background-color: #0000ff;'></div>\n" if($witho);
		print "</div></SMALL></TD>\n";
	} else {
		print "<TD align=left><SMALL>";
		print $q->img({border=>0,height=>10,width=>$barlen,src=>"$meurlfull?page=bar&L=$barlen&IN=$i&OUT=$o"});
 		print "</SMALL></TD>\n";
	}

}

#################################
# Read in language file
sub readlang($) {
	my($l) = $_[0];
	my($f,$sec);

	return "Cached" if( defined $lang{$l} ); # already read it
	if(defined $config{'web-langdir'}) {
		$f = $config{'web-langdir'} ;
	} else {
		$f = dirname($conffile);
	}
	$f .= $pathsep."lang_$l.conf";
	return "Language file not present" if(! -r $f); # no language file defined
	
	open LFH,"<$f" or return;
	$lang{$l} = { file=>$f };
	$sec = "";
	while( <LFH> ) {
		/^\s*#/ && next;
		/\[(.*)\]/ && do { $sec = lc $1; };
		chomp;
		/^\s*(\S+)\s*=\s*(\S.*?)\s*$/ and $lang{$l}{"$sec-$1"}=$2; 
	}
	close LFH;
	return 0;
}
sub langmsg($$) {
	my($code,$default) = @_;
	return $default if(!$language);                # no language defined
	return $default if(!defined $lang{$language}); # language not loaded
	return $lang{$language}{"messages-$code"} 
		if($lang{$language}{"messages-$code"});
	return $default;
}
sub langinfo {
	return "None" if(!$language);
	return "Language $language not loaded" if(!defined $lang{$language});
	return $lang{$language}{"global-description"}
		." Ver ".$lang{$language}{"global-version"}.", "
		.$lang{$language}{"global-author"};
}
sub langhtml($$) {
	my($m);
	$m = langmsg($_[0],$_[1]);
	$m =~ s/ /&nbsp;/g; $m =~ s/</&lt;/g; $m =~ s/>/&gt;/g;
	return $m;
}
sub initlang {
	my($l) = $_[0];
	my($rv);

	initlabels();
	if($l) {
		$language = $l;	
	} else {
		$language = '';
		$language = $config{'routers.cgi-language'}
			if(defined $config{'routers.cgi-language'});
		$language = $q->cookie('lang') if(!defined $l and $q->cookie('lang'));
	}
	return if(!$language);
	$rv = readlang($language);
	$debugmessage .= "Lang=[$rv] ";
	return if(!defined $lang{$language});
	# load the per-language defaults
	foreach ( qw/windowtitle iconurl charset weeknumber hournumber/ ) {
		$config{"routers.cgi-$_"} = $lang{$language}{"global-$_"}
			if(defined $lang{$language}{"global-$_"});
	}
	foreach ( qw/shortdateformat longdateformat dateonlyformat/ ) {
		$config{"web-$_"} = $lang{$language}{"global-$_"}
			if(defined $lang{$language}{"global-$_"});
	}
	$config{'routers.cgi-iconurl'} .= "/" 
		if( $config{'routers.cgi-iconurl'} !~ /\/$/ );
	foreach ( keys %gtypes ) {
		$gtypes{$_} = $lang{$language}{"types-$_"} 
			if( defined $lang{$language}{"types-$_"} );
	}
	foreach ( keys %gstyles ) {
		$gstyles{$_} = $lang{$language}{"styles-$_"} 
			if( defined $lang{$language}{"styles-$_"} );
	}
}

#################################
# Special start_html
#
# Attributes are defined at 4 levels.
# 1. style on element.  Only used for the popup div to override everything.
# 2. style in page header.  Used for user colour defaults in routers2.conf
# 3. stylesheet. Used for most stuff, unless...
# 4. element attributes. Only used if no stylesheet definitions
sub start_html_ss
{
	my($opts,$bgopt) = @_;
	my($ssheet) = "";
	my($bodies) = "body.summary, body.generic, body.compact, body.info, body.interface, body.cpu, body.memory";

	$opts->{-encoding} = $charset if($charset);

	$opts->{-head} = [] if(!$opts->{-head});
	push @{$opts->{-head}}, $q->meta({-http_equiv => 'Content-Type', 
		-content => "text/html; charset=$charset"}) if($charset);
	push @{$opts->{-head}}, $q->meta({-http_equiv=>'Refresh',-content=>$headeropts{-Refresh}}) if($headeropts{-Refresh});
	$opts->{-meta} = {charset=>$charset} if($charset);

	if(!defined $opts->{'-link'}) {
		$opts->{'-link'}=$linkcolour;
		$opts->{'-vlink'}=$linkcolour;
		$opts->{'-alink'}=$linkcolour;
	}
	$opts->{'-text'}=$deffgcolour if(!defined $opts->{'-text'});
	$opts->{'-bgcolor'}=$defbgcolour if(!defined $opts->{'-bgcolor'});
	$opts->{'-title'}=$windowtitle if(!defined $opts->{'-title'});

	# If we have overridden things, then put it into the sheet here.
	# overriding style sheet using mrtg .cfg file options
	if( $bgopt and $opts->{-class}) {
		$ssheet .= "body.".$opts->{'-class'}." { background: $bgopt }\n";
		$bodies = "body.compact, body.info";
	}
	# overriding style sheet using routers2.conf options
	# default pages
	if( $config{"routers.cgi-bgcolour"} or $config{"routers.cgi-fgcolour"} ) {
		$ssheet .= "body, $bodies { ";
		$ssheet .= " color: ".$config{"routers.cgi-fgcolour"}."; "
			if($config{"routers.cgi-fgcolour"});
		$ssheet .= " background: ".$config{"routers.cgi-bgcolour"}
			if($config{"routers.cgi-bgcolour"});
		$ssheet .= "}\n";
	}
	# Auth pages
	if( $config{"routers.cgi-authbgcolour"} or $config{"routers.cgi-authfgcolour"} ) {
		$ssheet .= "body.auth { ";
		$ssheet .= " color: ".$config{"routers.cgi-authfgcolour"}."; "
			if($config{"routers.cgi-authfgcolour"});
		$ssheet .= " background: ".$config{"routers.cgi-authbgcolour"}
			if($config{"routers.cgi-authbgcolour"});
		$ssheet .= "}\n";
	}
	# Menus
	if( $config{"routers.cgi-menubgcolour"} or $config{"routers.cgi-menufgcolour"} ) {
		$ssheet .= "body.sidemenu, body.header { ";
		$ssheet .= " color: ".$config{"routers.cgi-menufgcolour"}."; "
			if($config{"routers.cgi-menufgcolour"});
		$ssheet .= " background: ".$config{"routers.cgi-menubgcolour"}
			if($config{"routers.cgi-menubgcolour"});
		$ssheet .= "}\n";
	}
	# links
	$ssheet .=  "A:link { color: ".$config{'routers.cgi-linkcolour'}. " }\n "
		."A:visited { color: ".$config{'routers.cgi-linkcolour'}. " }\n "
		."A:hover { color: ".$config{'routers.cgi-linkcolour'}. " } \n"
		if($config{'routers.cgi-linkcolour'});

	$opts->{'-style'} = [ { -code=>$ssheet } ];
	if ( ! defined $opts->{'-script'} ) {
		$opts->{'-script'} = [ ];
	} elsif(! ref $opts->{'-script'} ) {
		$opts->{'-script'} = [ $opts->{'-script'} ];
	}
 	if($config{'routers.cgi-stylesheet'}) {
		push @{$opts->{'-style'}}, { -src=>$config{'routers.cgi-stylesheet'} };
	}
	if( $config{'routers.cgi-extendedtime'} and $config{'routers.cgi-extendedtime'}=~/f/i ) {
		push @{$opts->{'-style'}}, { -src=>'/JSCal2/css/jscal2.css' };
#		push @{$opts->{'-style'}}, { -src=>'/JSCal2/css/border-radius.css' };
		push @{$opts->{'-style'}}, { -src=>'/JSCal2/css/reduce-spacing-more.css' };
#		push @{$opts->{'-style'}}, { -src=>'/JSCal2/css/gold/gold.css' };
		push @{$opts->{'-script'}}, 
			{ -type=>'text/javascript', -src=>'/JSCal2/js/jscal2.js' };
		push @{$opts->{'-script'}}, 
			{ -type=>'text/javascript', -src=>'/JSCal2/js/lang/en.js' };
		if( $language =~ /^(..)/ and ($1 ne 'en')) {
			push @{$opts->{'-script'}}, 
				{ -type=>'text/javascript', -src=>"/JSCal2/js/lang/${1}.js" };
		}
	}

	print $q->start_html($opts)."\n";
	print "<div id=\"dpopup\" style=\"position:absolute; visibility:hidden; z-index:1000;\" class=popup></div>\n";
}
#################################
# Read in configuration file

# readconf: pass it a list of section names
# This should really be cached, keyed on $extra$myname$authuser
sub readconf(@)
{
	my ($inlist, $i, @secs, $sec, $usersec);
	
	@secs = @_;
	%config = ();

	$usersec = "\177";
	if( $authuser ) {
		$usersec = "user-".(lc $authuser) ;
	} else {
		$usersec = "user-none";
	}

	# set defaults
	%config = (
		'routers.cgi-confpath' => ".",
		'routers.cgi-cfgfiles' => "*.conf *.cfg",
		'web-png' => 0
	);

	( open CFH, "<".$conffile ) || do {
		print $q->header({-expires=>"now"});	
		start_html_ss({ -title => langmsg(8999,"Error"), 
			-bgcolor => "#ffd0d0", -class => 'error'  });	
		print $q->h1(langmsg(8999,"Error"))
			.$q->p(langmsg(3002,"Cannot read config file")." $conffile.");
		print $q->end_html();
		exit(0);
	};

	$inlist=0;
	$sec = "";
	while( <CFH> ) {
		/^\s*#/ && next;
		/^\s*\[(.*)\]/ && do { 
			$sec = lc $1;
			$inlist=0;	
			foreach $i ( @secs ) {
				if ( (lc $i) eq $sec ) { $inlist=1; last; }
			}
			# override for additional sections
			# put it here so people cant break things easily
			if( !$inlist and 
				( $sec eq "extra-$extra" or $sec eq $myname 
				or $sec eq $usersec ) ) {
				$sec = 'routers.cgi'; $inlist = 1;
			}
			next;
		};
		# note final \s* to strip all trailing spaces (which works because
		# the *? operator is non-greedy!)  This should also take care of
		# stripping trailing CR if file created in DOS mode (yeuchk).
		if ( $inlist ) { 
			/^\s*(\S+)\s*=\s*(\S.*?)\s*$/ and $config{"$sec-$1"}=$2; 
		}
	}
	close CFH;
	
	# legacy support for old dbdrive directive
	if(defined $config{'routers.cgi-dbdrive'} 
		and $config{'routers.cgi-dbdrive'}) {
		$pathsep = "\\"; # and use the DOS path separator
		if( $config{'routers.cgi-dbpath'} !~ /^\w:/ ) {
			# backwards compatibility to add DB drive on, if not there already
			$config{'routers.cgi-dbpath'} = $config{'routers.cgi-dbdrive'}
				.":".$config{'routers.cgi-dbpath'};
		}
	}

	# Activate NT compatibility options.
	# $^O is the OS name, NT usually produces 'MSWin32'.  By checking for 'Win'
	# we should be able to cover most possibilities.
	if ( (defined $config{'web-NT'} and $config{'web-NT'}=~/[1y]/i) 
		or $^O =~ /Win/ or $^O =~ /DOS/i  ) {
		$dailylabel = "%H";   # Activeperl cant support %k option to strftime
		$monthlylabel = "%W"; # Activeperl cant support %V option either....
		$pathsep = "\\";
		$NT = 1;
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
	$config{'routers.cgi-smalliconurl'} = $config{'routers.cgi-iconurl'} 
		if( !defined  $config{'routers.cgi-smalliconurl'});
	$config{'routers.cgi-iconurl'} = $config{'routers.cgi-alticonurl'} 
		if( defined  $config{'routers.cgi-alticonurl'});
	$config{'routers.cgi-iconurl'} .= "/" 
		if( $config{'routers.cgi-iconurl'} !~ /\/$/ );
	$config{'routers.cgi-smalliconurl'} .= "/" 
		if( defined $config{'routers.cgi-smalliconurl'} 
			and $config{'routers.cgi-smalliconurl'} !~ /\/$/ );

	# get list of configuration files
	@cfgfiles = ();
	if( $config{'routers.cgi-cfgfiles'} ne 'none' ) {
	foreach ( split " ", $config{'routers.cgi-cfgfiles'} ) {
		# this may push a 'undef' onto the list, if the glob doesnt match
		# anything.  We avoid this later...
		push @cfgfiles, glob($config{'routers.cgi-confpath'}.$pathsep.$_);
	}
	}

	# fix defaultinterface, if not specified correctly
	if( defined $config{'routers.cgi-defaulttarget'} 
		and ! defined $config{'routers.cgi-defaultinterface'}  ) {
		$config{'routers.cgi-defaultinterface'} =
			$config{'routers.cgi-defaulttarget'} ;
	}
	if( defined $config{'routers.cgi-defaultinterface'} 
		and $config{'routers.cgi-defaultinterface'} !~ /^_/
	) {
		$config{'routers.cgi-defaultinterface'} =
			"__".$config{'routers.cgi-defaultinterface'};
		$config{'routers.cgi-defaultinterface'} = "_outgoing"
			if( $config{'routers.cgi-defaultinterface'} eq "__outgoing" );
		$config{'routers.cgi-defaultinterface'} = "_incoming"
			if( $config{'routers.cgi-defaultinterface'} eq "__incoming" );
		$config{'routers.cgi-defaultinterface'} = "_summary_"
			if( $config{'routers.cgi-defaultinterface'} eq "__summary" );
	}

	# escaping
	if( $NT ) {
		$config{'routers.cgi-defaultrouter'} =~ s/\\/\//g
			if( defined $config{'routers.cgi-defaultrouter'} );
	}

	# allow [routers.cgi] section to override [web] section for some
	# parameters
	$config{'web-backurl'} = $config{'routers.cgi-backurl'}
		if(defined $config{'routers.cgi-backurl'});

	# We see if we have specified cache mode, or are in mod_perl, or 
	# are using speedycgi or fastcgi.
	$CACHE = 1 if ( ( defined $config{'routers.cgi-cache'} 
		  and $config{'routers.cgi-cache'} =~ /[y1]/i )
		or (!defined $config{'routers.cgi-cache'} and (
		  $ENV{MOD_PERL} or $ENV{FCGI_PROCESS_ID}
		or (eval {require CGI::SpeedyCGI} && CGI::SpeedyCGI->i_am_speedy) 
        )));

	unshift @INC, (split /[\s,]+/,$config{'web-libadd'}) 
		if(defined $config{'web-libadd'});
}

##########################
sub do_footer()
{
	print "<DIV class=footer>";
	if($uopts !~ /s/) {
		print $q->hr."\n<TABLE width=100% border=0 cellpadding=0 class=footer><TR class=footer>\n";
		print "<TD align=left valign=top class=footer id=ftleft width=125px>"
			.$q->a( { href=>$APPURL, target=>"_new", class=>'footer' } ,
			$q->img({ src=>"${config{'routers.cgi-smalliconurl'}}routers2.gif", 
				alt=>"Routers2.cgi web page", border=>0, width=>120, height=>40, class=>'footer' })).$q->br
			.$q->center($q->small($q->a({href=>$WLURL,target=>"_new",class=>'footer',style=>'@media print { display:none; }'},"Say Thanks!")))
			."</TD><TD valign=top align=left class=footer id=ftmiddle>";
		print $q->small({class=>'footer'},"routers.cgi Version $VERSION : &copy; "
			.$q->a({href=>$APPMAIL, class=>'footer'},"Steve Shipway")
			." 2000-2014 : ".$q->a({ href=>$APPURL, target=>"_top", class=>'footer' },$APPURL)
		)."\n";
		if($language) {
			print $q->br()."<SMALL class=footer>Language pack [$language]";
			print ": ".$lang{$language}{'global-description'}
				if($lang{$language}{'global-description'});
			print " Version ".$lang{$language}{'global-version'}
				if($lang{$language}{'global-version'});
			print " by ".$lang{$language}{'global-author'}
				if($lang{$language}{'global-author'});
			print "</SMALL>\n";
		}
		if(!defined $config{'web-paranoia'} or $config{'web-paranoia'}!~/[1y]/i){
		if( -r "/proc/loadavg" ) {
			open LA,"</proc/loadavg";
			my($lal) = <LA> ;
			$lal =~ /^(\S+)\s+(\S+)\s+(\S+)/ ;
			print $q->br()."<SMALL class=footer><I class=footer>Current system load average: $1 $2 $3</I></SMALL>\n";
			close LA;
		}
		print $q->br()."<SMALL class=footer>Page took ".(int(((times)[0]-$stime)*100)/100)."s to generate</SMALL>";
		}
		print "</TD><TD align=right valign=top class=footer id=ftright width=125px>"
			.$q->a( { href=>"http://www.rrdtool.org/", target=>"_new", class=>'footer' } ,
			$q->img({ src=>"${config{'routers.cgi-smalliconurl'}}rrdtool.gif", 
				alt=>"RRDTool", border=>0, class=>'footer' })
		).$q->br
			.$q->center($q->small($q->a({href=>"http://people.ee.ethz.ch/~oetiker/wish/",target=>"_new",class=>'footer',style=>'@media print { display:none; }'},"Say Thanks!")))
		."</TD><TR></TABLE>\n";
	} # uopts
	if(!defined $config{'web-paranoia'} or $config{'web-paranoia'}!~/[1y]/i){
		print "<!-- R:[$router]\n     I:[$interface]\n     A:[$archive]\n     U:[$authuser] -->\n";
		print "<!--\n$debugmessage-->\n" if($debugmessage);
		print "<!-- Refresh: ".$headeropts{-Refresh}." -->\n";
		print "<!-- Expires: ".$headeropts{-expires}." -->\n";
		print "<!-- Language: ".langinfo()." -->\n";
		print "<!-- CF: ".($interfaces{$interface}{cf}?$interfaces{$interface}{cf}:"Not defined")." -->\n";
		print "<!-- Archive requested -->\n" if($archiveme);
#		print "<!-- rrdtool version ".$RRDs::VERSION." -->\n";
		print "<!-- rrdcached=$rrdcached -->\n" if($rrdcached);
#		print "<!-- \@INC\n".(join "\n",@INC)."\n-->\n";
		print "<!-- Processing took ".((times)[0]-$stime)."s -->\n";
	}
	print "</DIV>";
	print $q->end_html();
}
sub do_simple_footer() {
	print "<DIV class=footer>";
	print $q->hr({class=>'footer'})."\n";
	if(!defined $config{'web-paranoia'} 
		or $config{'web-paranoia'}=~/[n0]/i) {
		print $q->small({class=>'footer'},"routers.cgi Version $VERSION : &copy; "
			.$q->a({href=>$APPMAIL,class=>'footer'},"Steve Shipway")
			." 2000-2014 : ".$q->a({ href=>$APPURL, target=>"_top",class=>'footer' },$APPURL)
		)."\n" ;
		print "<!-- U:[$authuser] -->\n";
		print "<!-- $debugmessage\n-->\n" if($debugmessage);
	}
	print "</DIV>";
	print $q->end_html();
}
###########################################################################
# for security - create login page, verify username/password/cookie
# routers.conf:
#
# verify_id -- reads cookies and params, returns verified username
sub verify_id {
	my($uname,$cookie,$checksum, $token);

	$uname = $q->remote_user(); # set by web server
	return $uname if($uname);

	# now taste cookie 
	$cookie = $q->cookie('auth');
	return '' if(!$cookie);                         # no cookie!
	return '' if($cookie !~ /^\s*([^:]+):(.*)$/);   # this isnt my cookie...
	($uname, $checksum) = ($1,$2);
	$token = $uname.$q->remote_host();
	$token .= $CHOCOLATE_CHIP;       # secret information
#   Can't do this because we havent read in the config file yet
#	$token .= $config{'web-auth-key'} if(defined $config{'web-auth-key'});
	$token = unpack('%32C*',$token); # checksum
	if( $config{'web-auth-debug'} ) {
		$debugmessage .= "\ncookie[given[$uname:$checksum],test[$token]]\n";
	}
	return $uname if( $token eq $checksum ); # yummy cookie
	
	# bleah, nasty taste
	return '';
}
# call appropriate verification routine
sub user_verify($$) {
	my($rv) = 0; # default: refuse
	my($u,$p) = @_;

	# get the auth configuration info
	readconf( 'web' ); 

	if( defined( $config{'web-ldaps-server'} ) ) {
		$rv = ldap_verify($u,$p,1);
		return $rv if($rv);
	}
	if( !$rv and defined( $config{'web-ldap-server'} ) ) {
		$rv = ldap_verify($u,$p,0);
		return $rv if($rv);
	}
	if( !$rv and defined( $config{'web-mysql-server'} ) ) {
		$rv = mysql_verify($u,$p);
		return $rv if($rv);
	}
	if( defined( $config{'web-password-file'} ) ) {
		$rv = file_verify($config{'web-password-file'},$u,$p,0);
		return $rv if($rv);
	}
	if( defined( $config{'web-htpasswd-file'} ) ) {
		$rv = file_verify($config{'web-htpasswd-file'},$u,$p,1);
		return $rv if($rv);
	}
	if( defined( $config{'web-md5-password-file'} ) ) {
		$rv = file_verify($config{'web-md5-password-file'},$u,$p,2);
		return $rv if($rv);
	}
	if( defined( $config{'web-unix-password-file'} ) ) {
		$rv = file_verify($config{'web-unix-password-file'},$u,$p,3);
		return $rv if($rv);
	}

	return 0;
}
# verify against a password file:   username:password
sub file_verify($$$$) {
	my($pwfile,$u,$p,$encmode) = @_;
	my($fp,$salt,$cp);

	$debugmessage .= " file_verify($pwfile,$u,$p,$encmode)\n"
		if( $config{'web-auth-debug'} );

	open PW, "<$pwfile" or return 0;
	while( <PW> ) {
		if( /([^\s:]+):([^:]+)/ ) {
			if($1 eq $u) {
				$fp = $2;
				chomp $fp;
				close PW; # we are returning whatever
				if($encmode == 0) { # unencrypted. eek!
					return 1 if($p eq $fp); 
				} elsif ($encmode == 1) { # htpasswd (unix crypt)
					if($crypthack) {
					 require Crypt::UnixCrypt;
					 $Crypt::UnixCrypt::OVERRIDE_BUILTIN = 1;
					}
					$salt = substr($fp,0,2);
					$cp = crypt($p,$salt); 
					return 1 if($fp eq $cp); 
				} elsif ($encmode == 2) { # md5 digest
					require Digest::MD5;
					return 1 if($fp eq Digest::MD5::md5($p));
				} elsif ($encmode == 3) { # unix crypt
					if($crypthack) {
					 require Crypt::UnixCrypt;
					 $Crypt::UnixCrypt::OVERRIDE_BUILTIN = 1;
					}
					$salt = substr($fp,0,2);
					$cp = crypt($p,$salt); 
					return 1 if($fp eq $cp); 
				} # add new ones here...
				if( $config{'web-auth-debug'} ) {
					$debugmessage .= "Mismatch password [$u][$p]:[$fp]!=[$cp]\n";
				}
				return 0;
			} elsif( $config{'web-auth-debug'} ) {
				$debugmessage .= "Mismatch user [$1][$u]\n";
			}
		} elsif( $config{'web-auth-debug'} ) {
			$debugmessage .= "Bad format line $_";
		}
	}
	close PW;

	return 0; # not found
}
# LDAP verify a username
sub ldap_verify($$$) {
	my($u, $p, $sec) = @_;
	my($dn,$context,$msg);
	my($ldap);
	my($attr,@attrlist);

	if($sec) {
		# load the LDAPS module
		eval { require IO::Socket::SSL; require Net::LDAPS; };
		if($@) { return 0; } # no Net::LDAPS installed
	} else {
		# load the LDAP module
		eval { require Net::LDAP; };
		if($@) { return 0; } # no Net::LDAP installed
	}

	# Connect to LDAP and verify username and password
	if($sec) {
		$ldap = new Net::LDAPS($config{'web-ldaps-server'});
	} else {
		$ldap = new Net::LDAP($config{'web-ldap-server'});
	}
	if(!$ldap) { return 0; }
	@attrlist = ( 'uid','cn' );
	@attrlist = split( " ", $config{'web-ldap-attr'} )
		if( $config{'web-ldap-attr'} );
	
	foreach $context ( split ":", $config{'web-ldap-context'}  ) {
		foreach $attr ( @attrlist ) {
			$dn = "$attr=$u,".$context;
			$msg = $ldap->bind($dn, password=>$p) ;
			if(!$msg->is_error) {
				$ldap->unbind();
				return 1;
			}
		}
	}

	return 0; # not found
}
# Use mysql to verify a username
sub mysql_verify($$) { 
	my($u, $p) = @_; 
	my($dsn,$dbh,$sthini);
	my($db,$rv,@row);
	my($bu,$bp);

	eval { require DBI; require DBD::mysql; };
	if($@) { $debugmessage.="MySQL Error: $@\n"; return 0; } 

	$debugmessage .= "Starting MySQL authentication for user $u\n";

	$db = $config{'web-mysql-database'};
	return 0 if(!$db);
	$bu = $config{'web-mysql-user'};
	$bp = $config{'web-mysql-password'};

	$dsn = "DBI:mysql:database=$db;host=".$config{'web-mysql-server'}; 
	$dbh = DBI->connect($dsn, ($bu?$bu:$u), ($bu?$bp:$p));
	if(!$dbh) { # bind failed
		$debugmessage .= "Failed to bind to MySQL database as "
			.($bu?$bu:$u)."\n";
		return 0;
	}
	if(!$bu) { # just doing a bind check
		$dbh->disconnect(); # important for mod_perl etc
		return 1; # all OK
	}
	if( ! $config{'web-mysql-table'} ) {	
		$debugmessage .= "ERROR: No mysql-table name was set in the routers2.conf, although mysql-user and mysql-password were.!\n";
		return 0;
	}
	$sthini = $dbh->prepare("SELECT PASSWORD(?) `tpass`,`pass` FROM `"
		.$config{'web-mysql-table'}."` WHERE `user`=?");
	if(!$sthini) { 
		$debugmessage .= "Failed to prepare MySQL statement\n";
		$dbh->disconnect; return 0; }
	$rv = $sthini->execute($p,$u);
	if(!$rv) { 
		$debugmessage .= "Failed to execute MySQL statement\n";
		$dbh->disconnect; return 0; }
	@row = $sthini->fetchrow_array;
	$sthini->finish; $dbh->disconnect;
	if (!$row[0]) {
		$debugmessage .= "User $u was not found in table\n";
		return 0;
	}
	if ($row[0] eq $row[1]) { return 1; }
	return 0; 
}

# generate_cookie -- returns a cookie with current usrname, expiry
sub generate_cookie {
	my($cookie);
	my($exp) = "+10min"; # note this stops wk/mon/yrly autoupdate from working
	my($token);

	return "" if(!$authuser);

	$exp = $config{'web-auth-expire'} if(defined $config{'web-auth-expire'});
	$exp = "+10min" if(!$exp); # some checking for format

	$token = $authuser.$q->remote_host; # should really have time here also
	$token .= $CHOCOLATE_CHIP;          # secret information
#	$token .= $config{'web-auth-key'} if(defined $config{'web-auth-key'});
	$token = $authuser.':'.unpack('%32C*',$token); # checksum

	$cookie = $q->cookie( -name=>'auth', -value=>$token, 
		-path=>$q->url(-absolute=>1), -expires=>$exp ) ;

	return $cookie;
}
# login_page -- output HTML login form that submits to top level
sub login_page {
	# this is sent if auth = y and page = top (or blank),
	# or if page = login
	print $q->header({ -target=>'_top', -expires=>"now" })."\n";
	start_html_ss({ -title =>langmsg(1000,"Login Required"),
	-onload => "document.login.username.focus();",
	-expires => "now", -bgcolor=>$authbgcolour, -text=>$authfgcolour,
	-class => 'auth' });
	print $q->h1(langmsg(1000,"Authentication required"))."\n";

	print "<FORM NAME=login METHOD=POST ACTION=$meurl TARGET=_top>\n";

	print $q->p(langmsg(1001,"Please log in with your appropriate username and password in order to get access to the system."))."\n";
	
	print "<TABLE BORDER=0 ALIGN=CENTER>\n";
	print $q->Tr($q->td($q->b(langmsg(1002,"Username")))
		.$q->td($q->textfield({name=>'username'}) ))."\n";
	print $q->Tr($q->td($q->b(langmsg(1003,"Password")))
		.$q->td($q->password_field({name=>'password'}) ))."\n";
	print $q->Tr($q->td("")
		.$q->td($q->submit({name=>'login',value=>'Login'}) ))."\n";
	print "</TABLE></FORM>\n";
	do_simple_footer;
	#print $q->end_html;
}
# force_login -- output HTML that sends top level to login page
sub force_login {
	my($javascript);
	my($err) = shift;
	# Javascript that sets window.location to login URL
	# This is created if auth = y and page != login and !authuser

	$javascript = "function redir() { ";
	$javascript .= "alert('$err'); " if($err);
	$javascript .= " window.location = '$meurlfull?page=login'; }";

	$javascript = "function redir() {} " if($config{'web-auth-debug'});

	print $q->header({ -target=>'_top', -expires=>"now" })."\n";
	start_html_ss({ -title =>langmsg(1000,"Login Required"),
	-expires => "now",  -script => $javascript , -onload => "redir()",
	-class => 'auth'});
	print $q->h1({class=>'auth'},langmsg(1000,"Authentication required"))."\n";
	print "Please ".$q->a({href=>"$meurlfull?page=login",class=>'auth'},"login")
		." before continuing.\n";
	print "<!-- $err -->\n";
	do_simple_footer;
	#print $q->end_html;
}
# logout -- set auth cookie to blank, expire now, and redirect to top
sub logout_page {
	my($cookie,$javascript);
	# Javascript that sets window.location to login URL

	$javascript = "function redir() { window.location = '$meurlfull?page=main'; }";
	$cookie = $q->cookie( -name=>'auth', -value=>'', 
		-path=>$q->url(-absolute=>1), -expires=>"now" ) ;

	print $q->header({ -target=>'_top', -expires=>"now",
		-cookie=>[$cookie] })."\n";
	start_html_ss({ -title =>langmsg(1004,"Logout complete"),
	-expires => "now",  -script => $javascript , -onload => "redir()",
		-bgcolor=>$authbgcolour, -text=>$authfgcolour, -class => 'auth' });
	print $q->h1({class=>'auth'},langmsg(1004,"Logged out of system"))."\n";
	print "Please ".$q->a({href=>"$meurlfull?page=main",class=>'auth'},"go back to the front page")
		." to continue.\n";
	do_simple_footer;
	#print $q->end_html;
}

#################################
# Read in files

###########################################################################
# identify the type of file/interface and set up defaults
sub inlist($@)
{
	my($pat) = shift @_;
	return 0 if(!defined $pat or !$pat or !@_);
	foreach (@_) { return 1 if( $_ and /$pat/i ); }
	return 0;
}
sub routerdefaults($)
{
	my( $key, $k, %identify );
	
	$k = $_[0];
	%identify = ();
	$identify{icon} = guess_icon(1,$k, $routers{$k}{shdesc}, $routers{$k}{hostname} );

	foreach $key ( keys %identify ) {
		$routers{$k}{$key} = $identify{$key} if(!$routers{$k}{$key} );
	}
}
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
		if(defined $config{'targetnames-ifdefault'}
			and $config{'targetnames-ifdefault'} =~ /cfgmaker/i ) {
			if( $interfaces{$k}{pagetop} =~ /Port Name\s*:[^<]*<\/TD>\s*<TD[^>]*>\s*([^<>\s][^<>]+)</i ) {
				$interfaces{$k}{shdesc} = "$1" if($1);
			} elsif( $interfaces{$k}{pagetop} =~ /Description\s*:[^<]*<\/TD>\s*<TD[^>]*>\s*([^\s<>][^<>]+)</i ) {
				$interfaces{$k}{shdesc} = "$1" if($1);
				$interfaces{$k}{'cfgmaker-description'} = $1;
			} elsif( $interfaces{$k}{pagetop} =~ /(ifName|Interface)\s*:[^<]*<\/TD>\s*<TD[^>]*>\s*([^\s<>][^<>]+)</i ) {
				$interfaces{$k}{shdesc} = "$2" if($2);
			} elsif( $interfaces{$k}{pagetop} =~ /Traffic Analysis for (\S+)/i ) {
				$interfaces{$k}{shdesc} = "$1" if($1);
			};
			if(!$interfaces{$k}{shdesc} and defined $interfaces{$k}{ifdesc}) {
				$interfaces{$k}{shdesc} = $interfaces{$k}{ifdesc};
			};
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
		elsif(( inlist( "interface", @d ) or inlist("serial",@d)
			or inlist( "ATM", @d )  or inlist( "[^mxpe]port\s", @d ))
				and  !defined $interfaces{$k}{unit} 
				and  !defined $interfaces{$k}{legendi} )
			{ $mode = "interface"; }
		elsif( inlist( "mem", @d ) ) { $mode = "memory"; }
#		elsif( inlist( "percent", @d )) { $mode = "percent"; }
		else { $mode = "generic"; }
		$interfaces{$k}{mode} = $mode;
	}

	# defaults for everything...
	# set appropriate defaults for thismode
	$times = "s"; $unit = ""; $totunit = "";
	if(!defined $interfaces{$k}{mult}) { 
		if($mode eq "interface" and 
			(!defined $config{'routers.cgi-bytes'} 
			       or $config{'routers.cgi-bytes'} !~ /y/ )
			and !$interfaces{$k}{bytes}
		) { $interfaces{$k}{mult} = 8; $unit = "bits"; }
		else { $interfaces{$k}{mult} = 1; }
	}
	if(!$unit and $interfaces{$k}{bytes}) { $unit = "bytes"; }
	if(!$unit and $interfaces{$k}{bits}) { $unit = "bits"; }
	if(!$unit and ($mode eq "interface")) { $unit = "bits"; }
	$timel = langmsg(2400,"second"); 
	if($interfaces{$k}{mult} > 3599 ) {
		$timel = langmsg(2402,"hour"); $times = "hr";
		if($interfaces{$k}{mult} > 3600) { $unit = "bits"; }
	} elsif($interfaces{$k}{mult} >59 ) {
		$timel = langmsg(2401,"minute"); $times = "min";
		if($interfaces{$k}{mult} > 60) { $unit = "bits"; }
	} elsif($interfaces{$k}{mult} > 1) { $unit = "bits"; }
	$totunit = "bytes" if($unit);
	$identify{ylegend} = "$unit per $timel";
	$unit = "$unit/$times";
	$unit = "bps" if($unit eq "bits/s");
	$unit = "Bps" if($unit eq "bytes/s");
	$identify{background} = $defbgcolour;
	$identify{legendi} = langmsg(6403,"In: ");
	$identify{legendo} = langmsg(6404,"Out:");
	$identify{legend1} = langmsg(6405,"Incoming") ;
	$identify{legend2} = langmsg(6406,"Outgoing");
	$identify{legend3} = langmsg(6407,"Peak inbound");
	$identify{legend4} = langmsg(6408,"Peak outbound");
	if( defined $config{'routers.cgi-percentile'}
		and $config{'routers.cgi-percentile'} =~ /y/i ) {
		$identify{percentile} = 1;
		$identify{total} = 1;
	} else {
		$identify{percentile} = 0;
		$identify{total} = 0;
	}
	$identify{factor} = 1;
	$identify{percent} = 1;
	$identify{unit} = $unit;
	$identify{totunit} = $totunit;
	$identify{unscaled} = "";

	if($mode eq "interface") {
		$identify{ylegend} = "traffic in $unit";
		$identify{legendi} = langmsg(6403,"In: ");
		$identify{legendo} = langmsg(6404,"Out:");
		$identify{legend1} = langmsg(6405,"Incoming traffic") ;
		$identify{legend2} = langmsg(6406,"Outgoing traffic");
		$identify{legend3} = langmsg(6407,"Peak inbound traffic");
		$identify{legend4} = langmsg(6408,"Peak outbound traffic");
		$identify{icon} = "interface-sm.gif";
		$identify{background} = $defbgcolour; #"#ffffff";
		$identify{unscaled} = "6dwmy";
#		$identify{total} = 1;
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
		$identify{background} = $defbgcolour; #"#ffffd0";
		$identify{unscaled} = "6dwmy";
		$identify{percent} = 0;
		$identify{total} = 0;
		$identify{mult} = 1;
	} elsif( $mode eq "memory" ) {
		$identify{ylegend} = "Bytes used";
		$identify{legendi} = "MEM";
		$identify{legendo} = "MEM";
		$identify{legend1} = "Memory usage";
		$identify{legend3} = "Peak memory usage";
		$identify{legend2} = "Sec. memory usage";
		$identify{legend4} = "Peak sec memory usage";
		$identify{icon} = "cpu-sm.gif";
		$identify{background} = $defbgcolour; #"#d0d0ff";
		$identify{total} = 0;
		$identify{unit} = "bytes"; 
		$identify{unit} = "bits" if($interfaces{$k}{bits}); 
		$identify{totunit} = "";
	} elsif( $mode eq "ping" ) {
		$identify{totunit} = "";
		$identify{unit} = "ms";
		$identify{fixunits} = 1;
		$identify{ylegend} = "milliseconds";
		$identify{legendi} = "High:";
		$identify{legendo} = "Low:";
		$identify{legend1} = "Round trip time range";
		$identify{legend2} = "Round trip time range";
		$identify{legend3} = "High peak 5min RTT";
		$identify{legend4} = "Low peak 5min RTT";
		$identify{icon} = "clock-sm.gif";
		$identify{background} = $defbgcolour; #"#ffffdd";
		$identify{total} = 0;
		$identify{percent} = 0;
		$identify{percentile} = 0;
		$identify{unscaled} = "";
	} elsif( $mode eq "percent"  ) {
		$identify{totunit} = "";
		$identify{unit} = "%";
		$identify{fixunits} = 1;
		$identify{ylegend} = langmsg(2409,"percentage");
		$identify{total} = 0;
		$identify{percent} = 0;
		$identify{percentile} = 0;
	} elsif( $mode eq "relpercent" ) {
		$identify{totunit} = "";
		$identify{unit} = "%";
		$identify{fixunits} = 1;
		$identify{ylegend} = langmsg(2409,"percentage");
		$identify{total} = 0;
		$identify{percent} = 0;
		$identify{percentile} = 0;
		$identify{legendi} = langmsg(2410,"ratio:");
		$identify{legend1} = langmsg(2411,"Inbound as % of outbound");
		$identify{legend3} = langmsg(2412,"Peak Inbound as % of peak outbound");
		if( defined $interfaces{$k}{ifno} or defined $interfaces{$k}{ifdesc} 
			or $interfaces{$k}{isif} or  defined $interfaces{$k}{ipaddress} ) {
			$identify{icon} = "interface-sm.gif";
		}
	}

	# unscaled default option
	if( defined $config{'routers.cgi-unscaled'} ) {
		if( $config{'routers.cgi-unscaled'} =~ /[1y]/i ) {
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

	$interfaces{$k}{unit2} = $interfaces{$k}{unit}
		if(!defined $interfaces{$k}{unit2});
	$interfaces{$k}{totunit2} = $interfaces{$k}{totunit}
		if(!defined $interfaces{$k}{totunit2});

	$interfaces{$k}{mult} = 1 if(!defined $interfaces{$k}{mult});
	$interfaces{$k}{maxbytes} = 0 if(!defined $interfaces{$k}{maxbytes});
	$interfaces{$k}{max} = $interfaces{$k}{maxbytes} * $interfaces{$k}{mult};
	$interfaces{$k}{max1} = $interfaces{$k}{maxbytes1} * $interfaces{$k}{mult}
		if(defined $interfaces{$k}{maxbytes1});
	$interfaces{$k}{max2} = $interfaces{$k}{maxbytes2} * $interfaces{$k}{mult}
		if(defined $interfaces{$k}{maxbytes2});
	# Multiply thresholds by appropriate amount
	foreach ( qw/threshmini threshmaxi threshmino threshmaxo upperlimit lowerlimit/ ) {
		$interfaces{$k}{$_} *= $interfaces{$k}{mult} 
			if(defined $interfaces{$k}{$_});
	}
	$interfaces{$k}{max} = $interfaces{$k}{max1} if(defined $interfaces{$k}{max1} and $interfaces{$k}{max1} > $interfaces{$k}{max} );
	$interfaces{$k}{max} = $interfaces{$k}{max2} if(defined $interfaces{$k}{max2} and $interfaces{$k}{max2} > $interfaces{$k}{max} );
	$interfaces{$k}{absmax} 
		= $interfaces{$k}{absmaxbytes} * $interfaces{$k}{mult}
		if(defined $interfaces{$k}{absmaxbytes});
	if($interfaces{$k}{factor} and $interfaces{$k}{factor}!=1 ) {
		foreach ( 'max','absmax','max1','max2' ) { 
			$interfaces{$k}{$_} *= $interfaces{$k}{factor}	
				if(defined $interfaces{$k}{$_});
		}
		foreach my $mm ( 'max','min' ) { foreach my $io ( 'i','o' ) {
			$interfaces{$k}{"thresh$mm$io"} *= $interfaces{$k}{factor}	
				if(defined $interfaces{$k}{"thresh$mm$io"});
		}}
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
		return "juniper-sm.gif" if( inlist "juniper",@_ );
		return "3com-sm.gif" if( inlist "3com",@_ );
		return "intel-sm.gif" if( inlist "intel",@_ );
		return "router-sm.gif" if( inlist "router",@_ );
		return "switch-sm.gif" if( inlist "switch",@_ );
		return "firewall-sm.gif" if( inlist "firewall",@_ );
		return "ibm-sm.gif" if( inlist "ibm",@_ );
		return "linux-sm.gif" if( inlist "linux",@_ );
		return "freebsd-sm.gif" if( inlist "bsd",@_ );
		return "novell-sm.gif" if( inlist "novell",@_ );
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

# Parse an extension parameters
sub parse_ext($) {
	my ( $desc, $url, $icon, $targ, $level, $insec, $noop ) = 
		("","","cog-sm.gif","graph",0,0,0 );
	my( @tok ) = quotewords('\s+',0,$_[0]);
#	$desc = shift @tok;
#	$url = shift @tok;
	foreach (@tok) {
		if( /^(https?:|ftp|ssh:|telnet:)?\// and !$url ) { $url = $_; next; }
		if( /\.(gif|png|jpg)$/ ) { $icon = $_; next; }
		if(!$desc) { $desc = $_ ; next; }
		if( /^\d+$/ ) { $level = $_; next; }
		if( /^insec(ure)?$/ ) { $insec = 1; next; }
		if( /^noopt(ion)?s?$/ ) { $noop = 1; next; }
		if(!$url) { $url = $_ ; next; } # must be a strange URL
		$targ = $_; # Must be a target frame name
	}
	$desc = "Extension" if(!$desc);
	$url  = "/" if(!$url);
	return ($desc, $url, $icon, $targ, $level, $insec, $noop);
}
sub parse_link($) {
	my ( $desc, $targfile, $icon, $targ, $level ) = 
		("Link",$router,"link-general-sm.gif","_summary",0 );
	my( @tok ) = quotewords('\s+',0,$_[0]);
	$desc = shift @tok;
	$targfile = shift @tok;
	foreach (@tok) {
		if( /^\d+$/ ) { $level = $_; next; }
		if( /\.(gif|png|jpg)$/ ) { $icon = $_; next; }
		$targ = $_; # Must be a target frame name
	}
	return ($desc, $targfile, $icon, $targ, $level);
}

# read in all routers files.

# routers hash: key= filename (within confpath)
#         data: hash: 
#               keys: filename (full), shdesc, desc, inmenu, hasinout
#                     group, icon

sub read_routers()
{
	my( $matchstr, $curfile, $curpat, $key, $bn, $group, $f );
	my( $arg, $desc, $url, $icon, $targ, $insec, $level, $noop, $targfile );
	my( $rckey );
	my( $optimise ) = 0;

	if($CACHE and (-M $config{'routers.cgi-confpath'} >= 0)) {
	# cache key: people may have different cfg file sets!
		$rckey = $config{'routers.cgi-confpath'}
			.'/'.$config{'routers.cgi-cfgfiles'};
	
		if(defined $routerscache{$rckey}) {
			%routers = %{$routerscache{$rckey}};
			if($router and defined $routers{$router} and
				# file has disappeared!
				! -f $routers{$router}{file} ) {
				$debugmessage .= "refresh(routers)";
				%routers = ();
				%routerscache = ();
			} elsif((-M $routers{$router}{file}) < 0 ) {
				# config files have changed!
				$^T = time; # set 'script init time' to first read of cfg files
				%ifstore = ();      # clean out all cached info
				%routerscache = (); # clean out all cached info
				$debugmessage .= "refresh(routers)\n";
				$readinrouters = 0;
				%cachedays = ();
			} else {
				$debugmessage .= "fromcache(routers)\n";
				$readinrouters = 1;
				return;
			}
		} else {
			load_cache();
			if(defined $routerscache{$rckey} 
				and -f $routerscache{$rckey}{$router}{file}) {
				%routers = %{$routerscache{$rckey}};
				$debugmessage .= "fromdiskcache(routers)\n";
				$readinrouters = 1;
				return;
			} else {
				$debugmessage .= "Disk cache out of date.  Re-reading.\n";
			}
		}
	}
	
	$optimise = 1 if( defined $config{'routers.cgi-optimise'} 
		and $config{'routers.cgi-optimise'} =~ /[y1]/i );

	%routers = ();
	if(-M $config{'routers.cgi-confpath'} < 0) {
		# config files have changed!
		$^T = time; # set 'script init time' to first read of cfg files
		%ifstore = ();      # clean out all cached info
		%routerscache = (); # clean out all cached info
			%cachedays = ();
		$debugmessage .= "refresh(routers)\n";
		$readinrouters = 0;
	}

FILE: for $curfile ( @cfgfiles ) {
			next if(! -f $curfile or ! -r $curfile);
			$key = $curfile;
			$matchstr = $config{'routers.cgi-confpath'}.$pathsep;
			$matchstr =~ s/\\/\\\\/g;
			$key =~ s/^$matchstr//;
			$f = $bn = basename($curfile,'');
			$f =~ s/\.c(fg|onf)$//;
			$group = dirname($curfile);
			# set the defaults
			$routers{$key} = { 
				file=>$curfile, inmenu=>1, group=>$group, icon=>"",
				interval=>5, hastarget=>0
			};

			# read the file for any overrides
			open CFG,"<$curfile" || do {
#				$routers{$key}{inmenu}=0;
				$routers{$key}{desc}="Error opening file";
				$routers{$key}{icon}="alert-sm.gif";
				next;
			};
LINE:		while( <CFG> ) {
				/^#\s+System:\s+(.*)/ and do {
					$desc = $1;
					$routers{$key}{'cfgmaker-system'} = $desc;
					$routers{$key}{desc} = $desc
					if( $desc and defined $config{'targetnames-routerdefault'}
					and $config{'targetnames-routerdefault'} =~ /cfgmaker/i );
					next;
				};
				/^#\s+(Description|Contact|Location):\s+(.*)/ and do {
					($arg,$desc)=($1,$2);
					$routers{$key}{('cfgmaker-'.(lc $arg))} = $desc;
					next;
				};
				/^\s*#/ && next; # Optimise!
				if( /^\s*(routers2?\.cgi\*)?Target\[\S+\]\s*:.*:([^\s@]+)@([^:\s]+)/i ) {
					$routers{$key}{community}=$2 if(!$routers{$key}{community});
					$routers{$key}{hostname}=$3 if(!$routers{$key}{hostname});
					$routers{$key}{hastarget}=1;
					next;
				}
				if( /^\s*(routers2?\.cgi\*)?Target\[\S+\]/i ) {
					$routers{$key}{hastarget}=1;
					next;
				}
				if( /^\s*(routers2?\.cgi\*)?Include\s*:/i ) {
					$routers{$key}{hastarget}=1; # make the assumption
					next;
				}
				if( /^\s*Title\[\S+\]\s*:\s*(.*)/i ) {
					$routers{$key}{firsttitle}=$1;
					$routers{$key}{hastarget}=1;
					last if($optimise);
					next;
				}
				if( /^\s*WorkDir\s*:\s*(.*)/i ) {
					$routers{$key}{workdir}=$1;
					next;
				}
				if( /^\s*Interval\s*:\s*([\d\.]+):?(\d*)/i ) {
					$routers{$key}{interval}=$1;
					$routers{$key}{interval} += $2/60 if($2);
					next;
				}
				next unless( /^\s*routers2?\.cgi\*/i ); # Optimise!
				if( /^\s*routers2?\.cgi\*Options\s*:\s*(.*)/i ) {
					$routers{$key}{inmenu} = 0 if($1 =~ /ignore/i );
					next;
				}
				if( /^\s*routers2?\.cgi\*(Descr?|Name|Description)\s*:\s*(.*)/i ) {
					$routers{$key}{desc} = $2;
					next;
				}
				if( /^\s*routers2?\.cgi\*Short(Descr?|Name|Description)\s*:\s*(.*)/i ) {
					$routers{$key}{shdesc} = $2;
					next;
				}
				if( /^\s*routers2?\.cgi\*Icon\s*:\s*(.*)/i ) {
					$routers{$key}{icon}=$1;
					next;
				}
				if( /^\s*routers2?\.cgi\*Ignore\s*:\s*(\S+)/i ) {
					$arg = $1;
					if($arg =~ /y/i) {
						delete $routers{$key};
						close CFG;
						next FILE;
					}
					next;
				}
				if( /^\s*routers2?\.cgi\*InMenu\s*:\s*(\S+)/i ) {
					$arg = $1;
					$routers{$key}{inmenu}=0 if($arg =~ /n/i);
					next;
				}
				if( /^\s*routers2?\.cgi\*RoutingTable\s*:\s*(\S+)/i ) {
					$arg = $1;
					$routers{$key}{routingtable}="n" if($arg =~ /[0n]/i);
					$routers{$key}{routingtable}="y" if($arg =~ /[1y]/i);
					next;
				}
				if( /^\s*routers2?\.cgi\*ClearExtensions?\s*:\s*(\S.*)/i ) {
					$arg = $1;
					$routers{$key}{extensions} = [] if($arg =~ /[y1]/i);
					next;
				}
				if( /^\s*routers2?\.cgi\*Extensions?\s*:\s*(\S.*)/i ) {
					$arg = $1;
					( $desc, $url, $icon, $targ, $level, $insec, $noop ) = 
						parse_ext($arg);
					
					next if(!$url or !$desc);
					$routers{$key}{extensions} = [] 
						if(!defined $routers{$key}{extensions});
					my( $lasthostname,$lastcommunity ) = ( '','' );
					$lasthostname = $routers{$key}{hostname}
						if( defined $routers{$key}{hostname} );
					$lastcommunity= $routers{$key}{community}
						if( defined $routers{$key}{community} );
					push @{$routers{$key}{extensions}}, 
						{desc=>$desc, url=>$url, icon=>$icon, target=>$targ,
				hostname=>$lasthostname, community=>$lastcommunity,
						insecure=>$insec, level=>$level, noopts=>$noop };
					next;
				}
				if( /^\s*routers2?\.cgi\*Link\s*:\s*(\S.*)/i ) {
					$arg = $1;
					( $desc, $targfile, $icon, $targ, $level ) 
						= parse_link($arg);
					next if(!$targfile or !$desc);
					$icon = "link-general-sm.gif" if(!$icon);
					$url = $meurlfull."?rtr=".$q->escape($targfile)
						."&if=".$q->escape($targ)."&page=graph&xmtype=options";
					$routers{$key}{extensions} = [] 
						if(!defined $routers{$key}{extensions});
					push @{$routers{$key}{extensions}}, 
						{ desc=>$desc, url=>$url, icon=>$icon, target=>"graph",
							level=>$level, insecure=>0, noopts=>2 };
					next;
				}
				if( /^\s*routers2?\.cgi\*Redirect\s*:\s*(\S+)/i ) {
					$arg = $1;
					$routers{$key}{redirect} = $arg;
					$routers{$key}{inmenu} = 1;
					$routers{$key}{hastarget} = 1;
					next;
				}
				if( /^\s*routers2?\.cgi\*NoCache\s*:\s*(\S+)/i ) {
					$arg = $1;
					if($arg=~/[y1]/i) { $routers{$key}{nocache} = 1; } 
					else { $routers{$key}{nocache} = 0; }
					next;
				}
				if( /^\s*routers2?\.cgi\*Summary\s*:\s*(.*)/i ) {
					$arg = $1;
					$routers{$key}{summaryoptions} = $arg;
					if($arg=~/active/i) { $routers{$key}{activesummary} = 1; } 
#					if($arg=~/2/) { $routers{$key}{activesummary} = 1; } 
					next;
				}
				if( /^\s*routers2?\.cgi\*InOut\s*:\s*(\S+)/i ) {
					$arg = $1;
					if($arg=~/[a2]/i) { $routers{$key}{activeinout} = 1; } 
					$routers{$key}{inoutoptions} = $1;
					next;
				}
				if( /^\s*routers2?\.cgi\*(Set)?Symbol\s*:\s*(\S+)\s+(.*)/i ) {
					($arg,$desc)=($2,$3);
					$desc =~ s/^['"]//; $desc =~ s/['"]$//; # allow quotes
					$routers{$key}{symbols}{$arg}=$desc;
					next;
				}
				if( /^\s*routers2?\.cgi\*(Snmp)?Community\s*:\s*(\S+)/i ) {
					$routers{$key}{community} = $2;
					next;
				}
				if( /^\s*(routers2?\.cgi\*)?RRDCached\s*:\s*(\S+)/i ) {
					$routers{$key}{rrdcached} = $2;
					next;
				}
			}
			close CFG;

			# desc default
			if(!$routers{$key}{shdesc}) {
				if($config{'targetnames-routerdefault'} =~ /hostname/ ) {
					if(defined $routers{$key}{hostname} ) {
						$routers{$key}{shdesc} = $routers{$key}{hostname};
					} else {
						$routers{$key}{shdesc} = $f;
					}
				} elsif($config{'targetnames-routerdefault'} =~ /ai/
					and defined $routers{$key}{firsttitle} ) {
					$routers{$key}{firsttitle} =~ /([^\s:\(]+)/;
					$routers{$key}{shdesc} = $1;
					$routers{$key}{desc} = $routers{$key}{firsttitle};
				} else {
					$routers{$key}{shdesc} = $f;
#					$routers{$key}{desc} = $curfile if(!$routers{$key}{desc});
				}
			}
			$routers{$key}{desc} = $routers{$key}{shdesc}
				if(!$routers{$key}{desc});

			# check routers.conf for any overrides
			if(defined $config{"targetnames-$bn"}) {
				$routers{$key}{shdesc} = $config{"targetnames-$bn"};
				$routers{$key}{desc} = $config{"targetnames-$bn"}; 
			}
			$routers{$key}{desc} = $config{"targettitles-$bn"}
				if(defined $config{"targettitles-$bn"});
			$routers{$key}{icon} = $config{"targeticons-$bn"}
				if(defined $config{"targeticons-$bn"});

			routerdefaults $key;
#		} # files
#	} # patterns
	} # files

	foreach $key ( keys %routers ) {
		$routers{$key}{inmenu} = 0 if(!$routers{$key}{hastarget});
	}

	if( $config{'routers.cgi-servers'} =~ /[yY1]/ ) {
		foreach ( keys %config ) {
			if( /^servers-(\S+)/i ) {
				$routers{"#SERVER#$1"} = { 
					file=>"", inmenu=>1, group=>"SERVERS", 
					icon=>"server-sm.gif", server=>$1, interval=>5, 
					hastarget=>1, inmenu=>1, desc=>$config{$_},
					shdesc=>$config{$_}
				};
				$routers{"#SERVER#$1"}{icon} = $config{"targeticons-$1"}
					if(defined $config{"targeticons-$1"});
			}
		}
	}

	# we need to copy the hash, not a hashref, since %routers will be
	# re-used in future invocations
	if($CACHE) {
		$routerscache{$rckey} = { %routers };
		$debugmessage .= "cached[routers] \n";
		write_cache;
	} else {
		$debugmessage .= "NOCACHE[routers] \n";
	}
	$readinrouters = 1 ; # for people without caching
}

###########################################################################

# set pseudointerfaces for a server target
sub set_svr_ifs()
{
	my( $server );

	%interfaces = ();
	$server = $router;
	$server =~ s/^#SERVER#//;

	$interfaces{"CPU"} = { file=>"",  icon=>"chip-sm.gif",
		rrd=>($config{'routers.cgi-dbpath'}.$pathsep."$server.rrd"), 
		shdesc=>"CPU Usage", mult=>1, unit=>"%", fixunits=>1,
		legendi=>"User:", legendo=>"System:", ylegend=>"Percentage",
		legendx=>"Wait:", 
		legend1=>"User processes", legend2=>"System Processes",
		legend3=>"Max User Processes", legend4=>"Max System processes",
		legend5=>"System Wait", legend6=>"Max system wait",
		desc=>"CPU Usage on $server", mode=>"SERVER", hostname=>$server,
		insummary=>1, incompact=>0, inmenu=>1, isif=>0, inout=>0,
		interval=>5, nomax=>1, noabsmax=>1, maxbytes=>100, max=>100,
		available=>1  };
	$interfaces{"Users"} = { file=>"",   mult=>1,icon=>"people-sm.gif",
		rrd=>($config{'routers.cgi-dbpath'}.$pathsep."$server.rrd"), 
		shdesc=>"Users", noo=>1, integer=>1, percent=>0, fixunits=>1,
		ylegend=>"User count",
		legendi=>"Users:", legend1=>"User count", legend3=>"Max user count",
		desc=>"User count on $server", mode=>"SERVER", hostname=>$server,
		insummary=>1, incompact=>0, inmenu=>1, isif=>0, inout=>0,
		interval=>5, nomax=>1, noabsmax=>1, maxbytes=>10000,
		available=>1  };
	$interfaces{"Page"} = { file=>"",   mult=>1, icon=>"disk-sm.gif",
		rrd=>($config{'routers.cgi-dbpath'}.$pathsep."$server.rrd"), 
		shdesc=>"Paging", noo=>1, unit=>"pps", fixunits=>1,
		legendi=>"Activity:", legend1=>"Paging activity", 
		legend3=>"Max paging activity", percent=>0, ylegend=>"Pages per second",
		desc=>"Paging activity on $server", mode=>"SERVER", hostname=>$server,
		insummary=>1, incompact=>0, inmenu=>1, isif=>0, inout=>0,
		interval=>5, nomax=>1, noabsmax=>1, maxbytes=>10000,
		available=>1  };
}

###########################################################################
# read in a specified cfg file (default to current router file)

# interfaces hash: key= targetname
#            data: hash:
#            keys: lots.

sub read_cfg_file($$)
{
	my($cfgfile,$makespecial) = @_;
	my($opts, $graph, $key, $k, $fd, $buf, $curif, @myifs, $arg, $argb, $rrd);
	my($argc);
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

	$key = ""; $curif = ""; @myifs = ();
	while ( $buf = <$fd> ) {
		next if( $buf =~ /^\s*#/ );
		next if( $buf =~ /^\s*$/ ); # bit more efficient
		# solve problem of DOS cfg file under UNIX causing Pango layout issues
		$buf =~ s/\s+$//; 
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
				$interfaces{$curif}{ifdesc} = langmsg(2413,"Response time") ;
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
		if( $buf =~ /^\s*(routers2?\.cgi\*)?(Title|Descr?|Description)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
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
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{options} = "" if(!$interfaces{$curif}{options});
			$interfaces{$curif}{options} .= ' '.$2;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?PageTop\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2;  $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{pagetop} = $arg;
			$inpagetop = 1;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?PageFoot\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2;  $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{pagefoot} = $arg;
			$inpagefoot = 1;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?SetEnv\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2; $arg = $3;
			next if(!defined $interfaces{$curif});
			foreach $k ( quotewords('\s+',0,$arg) ) {
				if( $k =~ /MRTG_INT_IP=\s*["]?\s*(\d+\.\d+\.\d+\.\d+)/ ) {
					$interfaces{$curif}{ipaddress}=$1
					if(!defined $interfaces{$curif}{ipaddress});
					next;
				}
				if( $k =~ /MRTG_INT_DESCR?=\s*["]?\s*(\S[^"]*)/ ) {
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
		if( $buf =~ /^\s*routers2?\.cgi\*Options\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{cgioptions}="" 
				if(!$interfaces{$curif}{cgioptions});
			$interfaces{$curif}{cgioptions} .= " ".$arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?MaxBytes\[(.+?)\]\s*:\s*(\d+[\.,]?\d*)/i ) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{maxbytes} = $3;
			next;
		}
		if($buf=~ /^\s*(routers2?\.cgi\*)?Unscaled\[(.+?)\]\s*:\s*([6dwmyn]*)/i){ 
			$curif = $2; $arg = $3;
			next if(!defined $interfaces{$curif});
			$arg = "" if($arg =~ /n/i); # for 'none' or 'n' option
			$interfaces{$curif}{unscaled} = $arg;
			next;
		}
		if($buf=~ /^\s*(routers2?\.cgi\*)?WithPeaks?\[(.+?)\]\s*:\s*([dwmyn]*)/i) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{withpeak} = $3;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?(YLegend2?)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $3; $arg = $4; $key = lc $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{$key} = $arg;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*ScaleShift\[(.+?)\]\s*:\s*(\S+)/i ) { 
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{scaleshift} = $arg;
			if($arg=~/(-?\d+\.?\d*)(:(-?\d+\.?\d*))?/) {
				$interfaces{$curif}{scale} = ($1?$1:1);
				$interfaces{$curif}{shift} = ($3?$3:0);
			}
			next;
		}
		if($buf=~ /^\s*(routers2?\.cgi\*)?ShortLegend(2?)\[(.+?)\]\s*:\s*(.*)/i){ 
			next if(!defined $interfaces{$3});
			$interfaces{$3}{"unit$2"} = $4;
			$interfaces{$3}{"unit$2"} =~ s/&nbsp;/ /g;
			next;
		}
		if($buf =~ /^\s*routers2?\.cgi\*TotalLegend(2?)\[(.+?)\]\s*:\s*(.*)/i){ 
			$curif = $2; $arg = $3; $key = "totunit$1";
			next if(!defined $interfaces{$curif});
			$arg =~ s/&nbsp;/ /g;
			$interfaces{$curif}{$key} = $arg;
			next;
		}
		# We now allow any number of digits for future expansion
		if( $buf =~ /^\s*(routers2?\.cgi\*)?(Legend[IOTA\d]\d*[IOTA]?)\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $3; $key = lc $2; $arg = $4;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$arg =~ s/&nbsp;/ /;
			# for backwards compatibility. 1T used to be TI, etc
			# IT and OT are the new total versions of I and O for userdefineds
			$key = "legendti" if($key eq "legend1t");
			$key = "legendto" if($key eq "legend2t");
			$key = "legendai" if($key eq "legend1a");
			$key = "legendao" if($key eq "legend2a");
			$interfaces{$curif}{$key} = $arg;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*Mode\[(.+?)\]\s*:\s*(\S+)/i ) {
			next if(!defined $interfaces{$1});
			$interfaces{$1}{mode} = $2;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*RoutingTable\s*:\s*(\S.*)/i ) {
			$arg = $1;
			$routers{$router}{routingtable} = "y" if($arg =~ /y/i);
			$routers{$router}{routingtable} = "n" if($arg =~ /n/i);
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*ClearExtensions?\s*:\s*(\S.*)/i
			) {
#			and !$readinrouters) {
			$arg = $1;
			$routers{$router}{extensions} = [] if($arg =~ /[y1]/i);
			next;
		}
		if( # !$readinrouters and
			$buf =~ /^\s*routers2?\.cgi\*Extensions?\s*:\s*(\S.*)/i ) {
			$arg = $1;
			( $desc, $url, $icon, $targ, $level, $insec, $noop ) 
				= parse_ext($arg);
			next if(!$url or !$desc);
			$routers{$router}{extensions} = [] 
				if(!defined $routers{$router}{extensions});
			push @{$routers{$router}{extensions}}, 
				{desc=>$desc, url=>$url, icon=>$icon, target=>$targ,
				hostname=>$lasthostname, community=>$lastcommunity,
				insecure=>$insec, level=>$level, noopts=>$noop };
					next;
			next;
		}
		if( # !$readinrouters and 	
			$buf =~ /^\s*routers2?\.cgi\*Link\s*:\s*(\S.*)/i ) {
			$arg = $1;
			( $desc, $targfile, $icon, $targ, $level ) 
				= parse_link($arg);
			next if(!$targfile or !$desc);
			$icon = "link-general-sm.gif" if(!$icon);
			$url = $meurlfull."?rtr=".$q->escape($targfile)
				."&if=".$q->escape($targ)."&page=graph&xmtype=options";
			$routers{$router}{extensions} = [] 
				if(!defined $routers{$router}{extensions});
			push @{$routers{$router}{extensions}}, 
				{ desc=>$desc, url=>$url, icon=>$icon, target=>"graph",
					level=>$level, insecure=>0, noopts=>2 };
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*Extensions?\[(.+?)\]\s*:\s*(\S.*)/i ) {
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			( $desc, $url, $icon, $targ, $level, $insec, $noop ) 
				= parse_ext($arg);
			$interfaces{$curif}{extensions} = [] 
				if(!defined $interfaces{$curif}{extensions});
			push @{$interfaces{$curif}{extensions}}, 
				{ desc=>$desc, url=>$url, icon=>$icon, target=>$targ,
				hostname=>$interfaces{$curif}{hostname},
				community=>$interfaces{$curif}{community},
				level=>$level, insecure=>$insec, noopts=>$noop };
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*Link\[(.+?)\]\s*:\s*(\S.*)/i ) {
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
#			( $desc, $targfile, $targ, $icon ) = quotewords('\s+',0,$arg);
			( $desc, $targfile, $icon, $targ, $level ) 
				= parse_link($arg);
			next if(!$targfile or !$desc);
#			if( $targ =~ /\.(gif|png)$/ and !$icon ) {
#				$icon = $targ; $targ = "";
#			}
			$icon = "link-general-sm.gif" if(!$icon);
			$url = $meurlfull."?rtr=".$q->escape($targfile)
				."&if=".$q->escape($targ)."&page=graph&xmtype=options";
			$interfaces{$curif}{extensions} = [] 
				if(!defined $interfaces{$curif}{extensions});
			push @{$interfaces{$curif}{extensions}}, 
				{ desc=>$desc, url=>$url, icon=>$icon, target=>"graph",
					level=>$level, insecure=>0, noopts=>2 };
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
			if( defined $interfaces{"_$graph"} ) {
				push @{$interfaces{"_$graph"}{targets}}, $curif
					if(!inlist("^$curif\$",@{$interfaces{"_$graph"}{targets}}));
				$interfaces{"_$graph"}{cgioptions} .= " $opts";
				$interfaces{"_$graph"}{usergraph} = 1;
			} else {
				$interfaces{$curif}{usergraphs} = [] 
					if(!defined $interfaces{$curif}{usergraphs});
				push @{$interfaces{$curif}{usergraphs}}, $graph;
				# here we set up various defaults.  Anything not set here
				# and not set by the user will be inherited from target 1
				if( $argb eq "summary" ) { # summary page
					$interfaces{"_$graph"} = {
						shdesc=>$graph,  targets=>[$curif], 
						cgioptions=>$opts, mode=>"\177_USERSUMMARY",
						usergraph=>1, icon=>"summary-sm.gif", 
						inout=>0, incompact=>0, withtotal=>0, withaverage=>0,
						insummary=>0, inmenu=>1, desc=>"Summary $graph",
						issummary=>1, pagetop=>"", pagefoot=>""
					};
				} else { # userdefined graph
					$interfaces{"_$graph"} = {
						shdesc=>$graph,  targets=>[$curif], 
						cgioptions=>$opts, mode=>"\177_USER",
					usergraph=>1, icon=>"cog-sm.gif", inout=>0, incompact=>0,
					insummary=>0, inmenu=>1, desc=>"User defined graph $graph",
						withtotal=>0, withaverage=>0, issummary=>0, 
						pagetop=>"", pagefoot=>"", factor=>1
					};
					$interfaces{"_$graph"}{rrd} = $interfaces{$curif}{rrd};
				}
				$interfaces{"_$graph"}{withtotal} = 1 
					if( defined $config{'routers.cgi-showtotal'}
						and $config{'routers.cgi-showtotal'}=~/y/i);
				push @myifs, "_$graph";
			}
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*Icon\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{icon} = $arg;
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
			elsif( $arg =~ /[2a]/i ) {  $interfaces{$curif}{insummary} = 2; }
			else { $interfaces{$curif}{insummary} = 0; }
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*InMenu\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{inmenu} = 1; }
			elsif( $arg =~ /[2a]/i ) {  $interfaces{$curif}{inmenu} = 2; }
			else { $interfaces{$curif}{inmenu} = 0; }
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*InOut\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{inout} = 1; }
			elsif( $arg =~ /[2a]/i ) {  $interfaces{$curif}{inout} = 2; }
			else { $interfaces{$curif}{inout} = 0; }
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*InCompact\[(.+?)\]\s*:\s*(\S+)/i ) {
			$curif = $1; $arg = $2;
			next if(!defined $interfaces{$curif});
			if( $arg =~ /[1y]/i ) {  $interfaces{$curif}{incompact} = 1; }
			elsif( $arg =~ /[2a]/i ) {  $interfaces{$curif}{incompact} = 2; }
			else { $interfaces{$curif}{incompact} = 0; }
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Background\[(.+?)\]\s*:\s*(#[a-fA-F\d]+)/i ) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{background} = $3;
			$interfaces{$2}{xbackground} = $3; # if using stylesheets
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Timezone\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{timezone} = $3;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Directory\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $2; $arg = $3;
			next if(!defined $interfaces{$curif});
			$arg =~ s/[\s\\\/]+$//; # trim trailing spaces and path separators!
			$interfaces{$curif}{rrd} = 
				$workdir.$pathsep.$arg.$pathsep.(lc $curif).".rrd";
			$interfaces{$curif}{directory} = $arg;
			next;
		}
		if( $buf =~ /^\s*Logdir\s*:\s*(\S+)/i ) { 
			$logdir = $1; $logdir =~ s/[\\\/]+$//; $workdir = $logdir; next; }
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Workdir\s*:\s*(\S+)/i and !$logdir ) { 
			$workdir = $2; $workdir =~ s/[\\\/]+$//; next; }
		if( $buf =~ /^\s*Interval\s*:\s*([\d\.]+):?(\d*)/i ) { 
			$interval = $1; $interval += $2/60 if($2); next; }
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Include\s*:\s*(\S+)/i ) { 
			$newfile = $2;
			$newfile = (dirname $cfgfile).$pathsep.$newfile
				if( $newfile !~ /^([a-zA-Z]:)?[\/\\]/ );
			foreach my $d ( glob( $newfile ) ) {
				read_cfg_file($d,0); 
			}
			next; 
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?LibAdd\s*:\s*(\S+)/i ) {
			$interfaces{$curif}{libadd} = $2;
			unshift @INC, $1; next; }
		if($buf=~ /^\s*(routers2?\.cgi\*)?MaxBytes(\d)\[(.+?)\]\s*:\s*(\d+)/i ){
			$curif = $3; $arg = $4;
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{"maxbytes$2"} = $arg;
			$interfaces{$curif}{maxbytes} = $arg
				if(!$interfaces{$curif}{maxbytes});
			next;
		}
		# the regexp from hell - preserved for posterity
#		if( $buf =~ /^\s*(routers2?\.cgi\*)?Colou?rs\[(.+?)\]\s*:\s*[^#]*(#[\da-f]{6})[\s,]+[^#]*(#[\da-f]{6})[\s,]+[^#]*(#[\da-f]{6})[\s,]+[^#]*(#[\da-f]{6})/i ) { 
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Colou?rs\[(.+?)\]\s*:\s*(.*)/i ) { 
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{colours} = []; # null array
			while( $arg =~ s/^[\s,]*[^#]*(#[\da-fA-F]{6})[\s,]*//i ) {
				push @{$interfaces{$curif}{colours}},$1;
			}
			$interfaces{$curif}{colours} = [ '#00ff00','#0000ff','#800080','#008000' ]
				if($#{$interfaces{$curif}{colours}}<0); 
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*MBLegend\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $1; 
			$curif = "_$curif" if(!defined $interfaces{$curif});
			$interfaces{$curif}{mblegend} = $2;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*AMLegend\[(.+?)\]\s*:\s*(\S.*)/i ) { 
			$curif = $1; 
			$curif = "_$curif" if(!defined $interfaces{$curif});
			$interfaces{$curif}{amlegend} = $2;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?AbsMax\[(.+?)\]\s*:\s*(\d+[\.,]?\d*)/i ) { 
			next if(!defined $interfaces{$2});
			$interfaces{$2}{absmaxbytes} = $3;
			next;
		}
		if( $buf =~ /^\s*WeekFormat(\[.+?\])?\s*:\s*%?([UVW])/i ) {
			# yes I know this is ugly, it is being retrofitted
			$monthlylabel = "%".$2;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*GraphStyle\[(.+?)\]\s*:\s*(\S+)/i ) { 
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{graphstyle} = $arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Factor\[(.+?)\]\s*:\s*(-?[\d\.,]+)/i ) { 
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
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
		if( $buf =~ /^\s*(routers2?\.cgi\*)?UpperLimit\[(.+?)\]\s*:\s*(\d+[\.,]?\d*)/i ) { 
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{upperlimit} = $arg;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*IfNo\[(.+?)\]\s*:\s*(\d+)/i ) { 
			$curif = $1; $arg = $2;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{ifno} = $arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?LowerLimit\[(.+?)\]\s*:\s*(\d+[\.,]?\d*)/i ) { 
			$curif = $2; $arg = $3;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{lowerlimit} = $arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?(Thresh(Max|Min)[IO])\[(.+?)\]\s*:\s*(\d+[\.,]?\d*)(%?)/i ) { 
			$curif = $4; $arg = $5; $argb = $6;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			if( $argb ) { # Its a percentage! Set here for later usage
				$interfaces{$curif}{(lc $2)."pc"} = 1;
			}
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
		if( $buf =~ /^\s*routers2?\.cgi\*HRule\[(.+?)\]\s*:\s*(-?\d+[\.,]?\d*)\s*"?([^"]*)"?\s*(#([0-9a-f]{6}))?/i ) { 
			$curif = $1; $arg = $2; $argb = $3; $argc = $5;
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{hrule} = [] 
				if(!defined($interfaces{$curif}{hrule}));	
			push @{$interfaces{$curif}{hrule}}, {
				value=>$arg, desc=>$argb, colour=>$argc
			};
			next;
		}
		# Experimental: routers.cgi*Line[target]: rpn expression
		if( $buf =~ /^\s*routers2?\.cgi\*Line\[(.+?)\]\s*:\s*(\S.*)$/i ) { 
			$curif = $1; $arg = $2; 
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			next if(!$interfaces{$curif}{usergraph});
			$interfaces{$curif}{lines} = [] 
				if(!defined($interfaces{$curif}{lines}));	
			push @{$interfaces{$curif}{lines}}, {
				legend1=>"", legendi=>"", legendo=>"", units=>"",
				rpn=>[split /[\s,]/,$arg]
			};
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*(Set)?Symbol\[(.+?)\]\s*:\s*(\S+)\s+(.*)$/i ) {
			($curif,$arg,$desc)=($2,$3,$4);
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$desc =~ s/^"//; $desc =~ s/"$//; # allow surrounding quotes
			$interfaces{$curif}{symbols}{$arg}=$desc;
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*Comment\[(.+?)\]\s*:\s*(.*)$/i ) {
			($curif,$arg)=($1,$2);
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			if(defined $interfaces{$curif}{comment}) {
				push @{$interfaces{$curif}{comment}},$arg;
			} else {
				$interfaces{$curif}{comment}=[$arg];
			}
			next;
		}
		if( $buf =~ /^\s*routers2?\.cgi\*SortBy\[(.+?)\]\s*:\s*(\S*)/i ) {
			($curif,$arg)=($1,$2);
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{sortby}=$arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Kilo\[(.+?)\]\s*:\s*(1024|1000)/i ) {
			($curif,$arg)=($2,$3);
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{kilo}=$arg;
			next;
		}
		if( $buf =~ /^\s*(routers2?\.cgi\*)?Kmg\[(.+?)\]\s*:\s*(\S+)/i ) {
			($curif,$arg)=($2,$3);
			$curif = "_$curif" if(!defined $interfaces{$curif});
			next if(!defined $interfaces{$curif});
			$interfaces{$curif}{kmg}=[ split /,/,$arg ];
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
	# now check for threshold percentages
	# we do this now because people may set maxbytes after setting thresh*,
	# or may set thresholds as percentages in the default target.
	foreach $curif ( @myifs ) {
		next if(!$curif);
		foreach ( qw/maxi maxo mini mino/ ) {
			if( $interfaces{$curif}{"thresh${_}pc"} 
				and $interfaces{$curif}{maxbytes} ) {
				$interfaces{$curif}{"thresh${_}"} =
					$interfaces{$curif}{maxbytes} 
					*( $interfaces{$curif}{"thresh${_}"} /100.0 );
			} #if
		}#foreach
	}#foreach

	# now process the options
	foreach $curif ( @myifs ) {
		next if(!$curif);
		if(defined $interfaces{$curif}{options} ) {
		foreach $k ( split /[\s,]+/,$interfaces{$curif}{options} ) {
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
					if(($interfaces{$curif}{incompact} == 1)
					and($interfaces{$curif}{max} ne 100));
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
			$interfaces{$curif}{logscale} = 1 if( $k eq "logscale");
		} } # if defined options
		if ( defined $interfaces{$curif}{cgioptions} ) {
		  foreach $k ( split /[\s,]+/,$interfaces{$curif}{cgioptions} ) {
			if( $k eq "default") {
				$routers{$router}{defif} = $curif;
				$interfaces{$curif}{default} = 1 ;
				next;
			}
			$interfaces{$curif}{logscale} = 1 if( $k eq "logscale");
			$interfaces{$curif}{withfoot} = 1 if( $k eq "withpagefoot");
			$interfaces{$curif}{withtop} = 1 if( $k eq "withpagetop");
			$interfaces{$curif}{active} = 1 if( $k eq "active");
			$interfaces{$curif}{active} = 1 if( $k eq "activeonly");
			$interfaces{$curif}{cf} = 'MAX' if( $k eq "maximum");
			$interfaces{$curif}{cf} = 'MAX' if( $k eq "maxvalue");
			$interfaces{$curif}{cf} = 'MIN' if( $k eq "minimum");
#			$interfaces{$curif}{cf} = 'LAST' if( $k eq "last");
			$interfaces{$curif}{available} = 1 if( $k eq "available");
			$interfaces{$curif}{available} = 0 if( $k eq "noavailable");
			$interfaces{$curif}{noo} = 1 if( $k eq "noo");
			$interfaces{$curif}{noi} = 1 if( $k eq "noi");
			$interfaces{$curif}{noo} = 0 if( $k eq "o");
			$interfaces{$curif}{noi} = 0 if( $k eq "i");
			$interfaces{$curif}{c2fi} = 1 if( $k eq "c2fi");
			$interfaces{$curif}{c2fo} = 1 if( $k eq "c2fo");
#			$interfaces{$curif}{mult} = 8 if( $k eq "bits");
#			$interfaces{$curif}{mult} = 1 if( $k eq "bytes");
			if( $k eq "bytes") { $interfaces{$curif}{bytes} = 1; 
				$interfaces{$curif}{bits} = 0; next; }
			if( $k eq "bits") { $interfaces{$curif}{bits} = 1;
				$interfaces{$curif}{bytes} = 0; next;  }
			if( $k eq "unknaszero") { $interfaces{$curif}{unknaszero} = 1; }
			if( $k eq "unknasprev") { $interfaces{$curif}{unknasprev} = 1; }
			if( $k eq "overridelegend") { $interfaces{$curif}{overridelegend} = 1; }
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
			$interfaces{$curif}{percentile} = 1 if( $k eq "percentile");
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
			$interfaces{$curif}{nodetails} = 1 if( $k eq "nodetail");
			$interfaces{$curif}{nodesc} = 1 if( $k eq "nodesc");
			$interfaces{$curif}{nogroup} = 1 
				if( $k eq "nogroup" or $k eq "nogroups");
			$interfaces{$curif}{nogroup} = 0 if( $k eq "group" );
			$interfaces{$curif}{nolines} = 1 if( $k eq "nolines");
			if( $k eq "nomax") {
				$interfaces{$curif}{nomax} = 1;
				$interfaces{$curif}{percent} = 0; 
				# percent doesnt make sense if you dont have a maximum 
				$interfaces{$curif}{incompact} = 0 
					if($interfaces{$curif}{incompact} == 1);
			}
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
			$interfaces{$curif}{altscale} = 1 if( $k eq "altscale");
			$interfaces{$curif}{altscale} = 0 if( $k eq "noaltscale");
			$interfaces{$curif}{nothresholds} = 1 if( $k eq "nothresholds");
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
		if( $interfaces{$curif}{incompact} and 
			(!$interfaces{$curif}{maxbytes} or $interfaces{$curif}{nomax})){
			$interfaces{$curif}{incompact} = 0;
		}
		if( $interfaces{$curif}{cf} and $interfaces{$curif}{cf} eq 'MAX'){
			# cant have WithPeak if you have cf=MAX set
			$interfaces{$curif}{withpeak} = "n";
		}
		
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
	$cfgfile =~ s/\.(conf|cfg)$/.ok/;
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

	# Creation of special interfaces moved to read_cfg
}

sub read_cfg()
{
	my($cfgfile) = $_[0];
	my($l,$key,$k);
	my($ifcnt,$curif,@ifarr);
	
	$cfgfile = $routers{$router}{file} 
		if(!$cfgfile and $router and defined $routers{$router});
	$cfgfile = $config{'routers.cgi-confpath'}.$pathsep.$router 
		if(!$cfgfile and $router);
	return if (!$cfgfile);

	# now, have we done $cfgfile before?
	if( $CACHE and defined $ifstore{$cfgfile}
		and !$routers{$router}{nocache} and (-M $cfgfile >= 0 )) {
		# yes!
		%interfaces = %{$ifstore{$cfgfile}};
		$routers{$router}{extensions} = [@{$ifstore{"R:$cfgfile"}}]
			if(defined $ifstore{"R:$cfgfile"});
		$debugmessage .= "fromcache($cfgfile)\n";
		return;
	}
	if( -M $cfgfile < 0 ) {
		undef $ifstore{$cfgfile};
		undef $ifstore{"R:$cfgfile"};
		$debugmessage .= "refresh($cfgfile)\n";
	}

	$debugmessage .= "Reading: ";

	%interfaces = ( '_'=>{x=>0}, '^'=>{x=>0}, '$'=>{x=>0} );
	$interval = 5;
	$workdir = $config{'routers.cgi-dbpath'};

	# Clear extension list ready to re-load it
	$routers{$router}{extensions} = [] if(defined $routers{$router});
	# recursively read the .cfg file and any includes
	read_cfg_file($cfgfile,1);

	# zap defaults
	delete $interfaces{'_'};
	delete $interfaces{'$'};
	delete $interfaces{'^'};
	delete $interfaces{''} if(defined $interfaces{''});

	# now set up userdefined graphs for Incoming and Outgoing, if it is
	# necessary.
	$ifcnt = 0; @ifarr = (); $curif="";
	foreach ( keys %interfaces ) { 
		$curif = $_ if(!$curif and $interfaces{$_}{community}
				and $interfaces{$_}{hostname} );
		if($interfaces{$_}{inout}) {
			$ifcnt++;
			push @ifarr, $_;
		}
	}
	$debugmessage .= "ifcnt=$ifcnt\n";
	if($ifcnt) {
		my($t);
		$t = "";
		$t = $routers{$router}{shdesc}.": " 
			if($router and defined $routers{$router}
				and defined $routers{$router}{shdesc});
		if( defined $interfaces{'_incoming'} ) {
			push @{$interfaces{'_incoming'}{targets}},@ifarr
				if( $interfaces{'_incoming'}{mode} =~ /_AUTO/ );
		} else {
			$interfaces{'_incoming'} = {
			usergraph=>1, insummary=>0, inmenu=>1, inout=>0, incompact=>0,
			shdesc=>langmsg(2405,"Incoming"),  targets=>[@ifarr], noo=>1, mult=>8,
			icon=>"incoming-sm.gif", mode=>"\177_AUTO",
			desc=>$t.langmsg(2414,"Incoming traffic"),
			withtotal=>0, withaverage=>0, issummary=>0,
			graphstyle=>'lines'
			};
			$interfaces{'_incoming'}{active} = 1
				if($routers{$router}{activeinout});
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
			shdesc=>langmsg(2406,"Outgoing"),  targets=>[@ifarr], noi=>1, mult=>8,
			icon=>"outgoing-sm.gif", mode=>"\177_AUTO",
			desc=>$t.langmsg(2415,"Outgoing traffic"),
			withtotal=>0, withaverage=>0, issummary=>0,
			graphstyle=>'lines'
			};
			$interfaces{'_outgoing'}{active} = 1
				if($routers{$router}{activeinout});
			if(defined $config{'routers.cgi-showtotal'} 
				and $config{'routers.cgi-showtotal'}=~ /[1y]/i ) {
				$interfaces{'_outgoing'}{withtotal} = 1;
			}
		}
	}

	# Now set up default userdefined summary, if anything is insummary
	@ifarr = (); 
	foreach ( keys %interfaces )  {
		push @ifarr, $_ if($interfaces{$_}{insummary}); 
		# first pass for interfaces
		identify $_ if(!$interfaces{$_}{usergraph});
	}
	if(@ifarr) {
		if( defined $interfaces{'_summary_'} ) {
			push @{$interfaces{'_summary_'}{targets}},@ifarr
				if( $interfaces{'_summary_'}{mode} =~ /_AUTOSUMMARY/ );
		} else {
			$interfaces{'_summary_'} = {
				usergraph=>1, insummary=>0, inmenu=>1, inout=>0, incompact=>0,
				shdesc=>langmsg(2416,"Summary"),  
				targets=>[@ifarr], noo=>1, mult=>8,
				icon=>"summary-sm.gif", mode=>"\177_AUTOSUMMARY",
				withtotal=>0, withaverage=>0, issummary=>1
			};
			$interfaces{'_summary_'}{active} = 1
				if($routers{$router}{activesummary});
			$interfaces{'_summary_'}{active} = 1
				if($routers{$router}{summaryoptions} and $routers{$router}{summaryoptions} =~ /active/);
			$interfaces{'_summary_'}{nodetails} = 1
				if($routers{$router}{summaryoptions} and $routers{$router}{summaryoptions} =~ /nodetail/);
		}
	}

	# Can we call out to the routingtable.cgi program?
	if( defined $config{'routers.cgi-routingtableurl'} and $curif 
		and ( !defined $routers{$router}{routingtable}
			or $routers{$router}{routingtable} =~ /[1y]/i )) {
		$routers{$router}{extensions} = []
			if( !defined $routers{$router}{extensions} );
		push @{$routers{$router}{extensions}}, { 
			url=>$config{'routers.cgi-routingtableurl'},
			desc=>langmsg(2417,"Routing Table"), icon=>"router-sm.gif",
			community=>$interfaces{$curif}{community},
			hostname=>$interfaces{$curif}{hostname},
			level=>0, insecure=>1
		};
	}

	# second pass for user graphs
	foreach $key ( keys %interfaces ) {
		if($interfaces{$key}{usergraph}) {
			$k = $key; $k=~ s/^_//; # chop off initial _ prefix
			$interfaces{$key}{shdesc} = $config{"targetnames-$k"}
			if(defined $config{"targetnames-$k"});
			$interfaces{$key}{desc} = $config{"targettitles-$k"}
			if(defined $config{"targettitles-$k"});
			$interfaces{$key}{icon} = $config{"targeticons-$k"}
			if(defined $config{"targeticons-$k"});
			# Inherit most options from first target
			foreach $k (keys %{$interfaces{$interfaces{$key}{targets}->[0]}}) {
				$interfaces{$key}{$k} 
					= $interfaces{$interfaces{$key}{targets}->[0]}{$k}
					if(!defined $interfaces{$key}{$k}
						and ($k ne 'extensions')
						and ($k ne 'pagetop') and ($k ne 'pagefoot')
					);
			}
		} else {
			# Can we call out to the trend.cgi program? (undocumented)
			if( defined $config{'routers.cgi-trendurl'} 
				and !$interfaces{$key}{usergraph} ) {
				$interfaces{$key}{extensions} = [] 
					if(!defined $interfaces{$key}{extensions});
				push @{$interfaces{$key}{extensions}}, {
					url=>$config{'routers.cgi-trendurl'},
					desc=>langmsg(2418,"Trend Analysis"), icon=>"graph-sm.gif",
					target=>"graph", level=>0, insecure=>0
				};
			}
		}
	}

	# at this point, %interfaces is set up.
	if($CACHE) {
		# cache it
		$ifstore{$cfgfile} = { %interfaces };
		$debugmessage .= "cached[$cfgfile] ";
		if(defined $routers{$router}{extensions}) {
			$ifstore{"R:$cfgfile"} = [ @{$routers{$router}{extensions}} ];
			$debugmessage .= "cached[$cfgfile:X] ";
		}
		$debugmessage .= "\n";
		if( $archdate ) { # clean up mess before caching
			foreach my $tmpif ( keys %interfaces ) {
				$ifstore{$cfgfile}{$tmpif}{rrd} 
					= $ifstore{$cfgfile}{$tmpif}{origrrd} 
					if($ifstore{$cfgfile}{$tmpif}{origrrd});
			}
		}
#		write_cache;
	} else {
		$debugmessage .= "NOCACHE\n";
	}
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
		if( abs($val) >= $T ) {
			$val /= $T; $sufx = 'T';
		} elsif( abs($val) >= $G ) {
			$val /= $G; $sufx = 'G';
		} elsif( abs($val) >= $M  ) {
			$val /= $M; $sufx = 'M';
		} elsif( abs($val) >= $k ) {
			$val /= $k; $sufx = $ksym;
		} elsif( abs($val) < 0.001 ) {
			$val *= 1000000; $sufx = 'u';
		} elsif( abs($val) < 1 ) {
			$val *= 1000; $sufx = 'm';
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

#################################
# Calculate nth percentile (bits), and total bandwidth (bits), for current rrd
# and for specified interval (d,w,m,y)
# Returns ( desc, [inpercentile,intotal,emsg], [outpercentile,outtotal,emsg] )

sub calc_percentile($$$)
{
	my( $thisif, $pcinterval, $percentile ) = @_; # interface, dwmy, 95
	my( @rv, $e, @opts );
	my( $rrd, $ds );
	my( $resolution, $startpoint, $desc ); # fetch input values
	my( $datastart, $datastep, $dsnames, $dsdata ); # fetch return values
	my( $pc, $row, $totalbits, @pcarray, $idx, $pcidx );

	return ("",["-","-","No interface"],["-","-",""]) 
		if(!$thisif); # just in case

	$rrd = $interfaces{$thisif}{rrd};
	if($rrdcached and $rrdcached!~/^unix:/) {
		my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
		$rrd =~ s/^$pth\/*//;
	}
	foreach ( $pcinterval ) {
		/y/ and do { $resolution = 3600; $startpoint = "-1y"; 
			$desc = langmsg(2420,"rolling last year"); last; };
		/m/ and do { $resolution = 1800; $startpoint = "-1month"; 
			$desc = langmsg(2421,"rolling last month"); last; };
		/w/ and do { $resolution = 300; $startpoint = "-7d"; 
			$desc = langmsg(2422,"last 7 days"); last; };
		/6/ and do { $resolution = 60*$interfaces{$thisif}{interval}; 
			$desc = langmsg(2423,"last 6 hours");
			$startpoint = "-6h"; last; };
		$resolution = 60*$interfaces{$thisif}{interval}; # interval
		$startpoint = "-24h"; # 1 day
		$desc = langmsg(2424,"last 24 hours");
	}
	$desc =~ s/last/previous/ if($pcinterval =~ /-/);
	$resolution = 300 if(!$resolution);
	push @rv, $desc;
	
	# fetch the data
	eval { require RRDs; };
	if( $@ ) {
		return ("", ["-","-","No RRDs.pm"],["-","-",""]) ;
	}
	if($basetime) {
		@opts = ( $rrd,"AVERAGE","-e",$basetime,"-s","end$startpoint" );
	} elsif( $pcinterval =~ /-/ ) {
		@opts = ( $rrd,"AVERAGE","-e","now$startpoint","-s","end$startpoint" );
	} elsif( $uselastupdate > 1 and $archivetime) {
		@opts = ( $rrd,"AVERAGE","-e",$archivetime,"-s","end$startpoint" );
	} elsif( $uselastupdate ) {
		@opts = ( $rrd,"AVERAGE","-e",$lastupdate,"-s","end$startpoint" );
	} else {
		@opts = ( $rrd,"AVERAGE","-s",$startpoint );
	}
	( $datastart, $datastep, $dsnames, $dsdata ) = RRDs::fetch( @opts, @rrdcached );
	$e = RRDs::error();
	if ( $e ) {
		@rv = ("",["?","?",$e], ["?","?","fetch ".(join " ",@opts)]);
		return @rv;
	}

	# now we do two calculations: the total traffic ( $datastep*sum(value) )
	# for both in and out, and the percentile (95% into sorted array )
	foreach $idx ( 0..1 ) {
		$totalbits = 0; @pcarray = ();
		foreach $row ( @$dsdata ) {
			# ???? Is this correctly skipping UNKN values?
			#      This needs to be checked, we should avoid UNKN in %ile
			next if(!defined $row->[$idx]);
			if( $row->[$idx] =~ /\d/ ) {
#			$totalbits += $row->[$idx]*$interfaces{$thisif}{mult}*$datastep;
# We no longer multiply by {mult} since we DO NOT want to multiple for 
# permin/perhour totals (datastep takes care of that) and we want bits to
# be totalled in bytes.
			$totalbits += $row->[$idx]*$datastep;
			push @pcarray, ( $row->[$idx] * $interfaces{$thisif}{mult} );
			}
		}	
		@pcarray = sort numerically @pcarray if($#pcarray>0);
		$pcidx = int($#pcarray * $percentile / 100);
# Now, at this point, if $thisif is a RANGE, we should do percentile and
# 100-percentile , ie, the opposite for the 'from'.
		if( $idx and $interfaces{$thisif} and $interfaces{$thisif}{graphstyle} 
			and $interfaces{$thisif}{graphstyle} eq "range" ) {
			$pcidx = int($#pcarray * (100-$percentile) / 100);
		}
		$pc = $pcarray[$pcidx];
		# multiply by the factor : we did the mult previously
		$pc *= $interfaces{$thisif}{factor} if($interfaces{$thisif}{factor}); 
		$totalbits *= $interfaces{$thisif}{factor} 
			if($interfaces{$thisif}{factor}); 
		# the c2f options are BEFORE display
		if(($interfaces{$thisif}{c2fi} and !$idx)
			or ($interfaces{$thisif}{c2fo} and $idx)) {
			$pc = $pc * 1.8 + 32;
			$totalbits = $totalbits * 1.8 + 32; # yes its stupid but consistent
		}
		push @rv, [ $pc.' ', $totalbits, '' ];
	}

	return @rv;
}

#################################
# Top menu

sub do_head()
{
my($iconsuffix) = "";
my($loginbuttons) = "";
my($colwid) = 115;
my($logo);

$iconsuffix = "-bw" if( $gstyle =~ /b/ );

start_html_ss({ -bgcolor => $menubgcolour, -text => $menufgcolour,
	-class => 'header' });
print "<DIV class=header>";
if( $config{'web-auth-required'} =~ /^[yo]/i ) {
	if( $authuser ) {
		$loginbuttons = $q->td({ -align=>"LEFT", -width=>110, -valign=>"TOP",
			class=>'header', id=>'htlogin' }, 
			$q->a({href=>"$meurlfull?page=logout", target=>'_top', class=>'header'},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}logout$iconsuffix.gif",
			alt=>langmsg(5000,"Logout"), border=>"0", width=>100, height=>20, class=>'header'}))
			."<div class=login>"
			.$q->br.langmsg(1002,"User").":&nbsp;<div class=username>$authuser</div></div>");
	} else {
		$loginbuttons = $q->td({ -align=>"LEFT", -width=>110, -valign=>"TOP", class=>'header', id=>'htlogin' }, 
			$q->a({href=>"$meurlfull?page=login", target=>'_top', class=>'header'},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}login$iconsuffix.gif",
			alt=>langmsg(5001,"Login"), border=>"0", width=>100, height=>20, class=>'header'}))
			);
	}
} elsif( $config{'web-auth-required'} =~ /^s/i ) {
	if( $authuser ) {
		$loginbuttons = $q->td({ -align=>"LEFT", -width=>110, -valign=>"TOP",
			class=>'header', id=>'htlogin' }, 
			"<div class=login>"
			.langmsg(1002,"User").":&nbsp;<div class=username>$authuser</div>"
			."</div>"
		);
	} else {
		$loginbuttons = $q->td({ -align=>"LEFT", -width=>110, -valign=>"TOP", class=>'header', id=>'htlogin' }, 
			$q->a({href=>($config{'web-shib-login'}?$config{'web-shib-login'}:'/secure'), target=>'_top', class=>'header'},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}login$iconsuffix.gif",
			alt=>langmsg(5001,"Login"), border=>"0", width=>100, height=>20, class=>'header'}))
			);
	}
}

# Page top logo, may be overridden
if($config{'routers.cgi-logourl'}) {
	$logo = $q->img({ src=>$config{'routers.cgi-logourl'}, border=>0, class=>'header'});
} else {
	$logo = $q->a( { href=>$APPURL, target=>"_new", class=>'header' } ,
		$q->img({ src=>($config{'routers.cgi-smalliconurl'}."routers2.gif"),
			alt=>"Routers2.cgi", border=>0, width=>120, height=>40, class=>'header' }));
}

print "\n".$q->table( { -border=>"0", -width=>"100%", cellspacing=>0, cellpadding=>1, class=>'header' },
  $q->Tr( { -valign=>"TOP", -width=>"100%", class=>'header' }, "\n".
    $q->td({ -align=>"LEFT", -width=>$colwid, -valign=>"TOP", class=>'header', id=>'htleft' }, 
	($config{'web-backurl'}?( "<DIV nowrap><nobr>".
      $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
	border=>0, width=>15, height=>15, class=>'header'})."&nbsp;".
      $q->a({ href=>$config{'web-backurl'}, target=>"_top", class=>'header'}, 
      $q->img({ src=>"${config{'routers.cgi-iconurl'}}mainmenu$iconsuffix.gif", alt=>langmsg(5002,"Main Menu"), border=>0,
		width=>100, height=>20, class=>'header' }))."</nobr></DIV>"."\n"
	):"")."<DIV nowrap><nobr>"
      .$q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
	border=>0, width=>15, height=>15, class=>'header'})."&nbsp;"
	.$q->a({href=>"javascript:parent.graph.location.reload(true)", class=>'header'},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}refresh$iconsuffix.gif",alt=>langmsg(5003,"Refresh"), border=>"0",
		width=>100, height=>20, class=>'header'}))."</nobr></div>"
    )."\n"
	.$loginbuttons
    .$q->td({ -align=>"CENTER", -valign=>"TOP", class=>'header', id=>'htmiddle' }, $toptitle)."\n"
    .$q->td({ -align=>"RIGHT", -width=>1, -valign=>"TOP", class=>'header', id=>'htright' }, $logo)."\n"
  )
),"\n";
print "</DIV>";
# Finish off the page
print $q->end_html();
}

###########################
# Side menu

# $mtype specified 'routers' (list routers) or 'options' (list options)


sub do_menu()
{
my ($iflabel);
my ($target) = "graph";
my ($rtrdesc,$gs,$adesc);
my ($iconsuffix) = "";
my ($groupdesc, $lastgroup, $thisgroup);
#my ($hassummary) = 0;
my ($hascompact) = 0;
my ($explore) = "y";
my (@archive) = ();
my ($archivepat);
my ($timeframe);
my ($lurl); # link URL
my ($menulevel) = 0;
my ($multilevel) = 0;
my ($gs) = ':';
my ($pfx);

# explore will contain either y, n, or i
$explore = $config{'routers.cgi-allowexplore'}
	if( defined $config{'routers.cgi-allowexplore'} );
$mtype = "options" if( $explore !~ /y/i );

$iconsuffix = "-bw" if( $gstyle =~ /b/ );
$target = "_top" if( $gstyle =~ /p/ );

# Start it off
start_html_ss({ -bgcolor => $menubgcolour, -text => $menufgcolour, 
	nowrap => "yes", -class => 'sidemenu' });

print "<DIV NOWRAP class=sidemenu>\n";

# top link for other stuff
#if( $mtype eq "options" or !$router or $router eq "none"
#	or $router eq "__none" or $interface eq "__none" ) {
#	print $q->a({name=>"top"},"");
#}
print "<FONT size=".$config{'routers.cgi-menufontsize'}.">\n"
	if( defined $config{'routers.cgi-menufontsize'} );

# Main stuff and links
if ( $mtype eq "options" ) {
	# check for inout graphs
	foreach ( keys %interfaces ) {
#		if( $interfaces{$_}{insummary} ) { $hassummary = 1; }
		if( $interfaces{$_}{incompact} ) { $hascompact = 1; }
	}
	# check for archive
	if( defined $config{'routers.cgi-archive'} 
		and $config{'routers.cgi-archive'} !~ /^n/i ) {
		$archivepat = $router; $archivepat =~ s/[\?#\\\/]//g;
		$archivepat = $config{'routers.cgi-graphpath'}.$pathsep
			.$archivepat.$pathsep.$interface.$pathsep."*.*";
		# do this in an eval because some Perl implementations treat a null 
		# glob as an error (why??)
		eval { @archive = glob($archivepat); };
	}

	# now show it all
	if( !$twinmenu ) {
	print "<nobr>"
    	.$q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
			border=>0, width=>15, height=>15, class=>'sidemenu'})."&nbsp;"
		.$q->a({ href=>"$meurlfull?".optionstring(
		{ page=>"menu",xmtype=>"routers" }),class=>'sidemenu', target=>"_self",
		onMouseOver=>"if(devices){devices.src='${config{'routers.cgi-iconurl'}}devices-dn-w.gif'; window.status='Show list of routers';}", 
		onmouseout=>"if(devices){devices.src='${config{'routers.cgi-iconurl'}}devices-dn$iconsuffix.gif'; window.status='';}" },
		$q->img({ src=>"${config{'routers.cgi-iconurl'}}devices-dn$iconsuffix.gif", 
		alt=>langmsg(5004,"Devices"), border=>0 , name=>"devices",
		class => 'sidemenu',
		width=>100, height=>20}))."</nobr>\n".$q->br."\n"
		if( $explore =~ /y/i );
	}
	# list options
	if( $explore !~ /n/i and $router ne "none") {
		print "<nobr>";
      	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
			border=>0, width=>15, height=>15,class=>'sidemenu'})."&nbsp;"
	  .$q->img({ src=>"${config{'routers.cgi-iconurl'}}targets$iconsuffix.gif",
			alt=>langmsg(5005,"Targets"),width=>100, height=>20,class=>'sidemenu' })
		."</nobr>".$q->br."\n";
	foreach ( sort byifdesc keys( %interfaces ) ) {
		next if(!$_); # avoid the '#' interface...
		next if(!$interfaces{$_}{inmenu}); # if not in menu...
		$iflabel = $interfaces{$_}{shdesc} if(defined $interfaces{$_}{shdesc});
		$iflabel = "#$_" unless ( $iflabel );
		$iflabel =~ s/ /\&nbsp;/g; # get rid of spaces...
		print "<NOBR>";
		if( $_ eq $interface ) {
			my(@k) = (keys %interfaces);
			print $q->a({name=>"top"},"") if($#k>25); }
		if( $interfaces{$_}{icon} ) {
			print $q->img({ 
				src=>($config{'routers.cgi-smalliconurl'}.$interfaces{$_}{icon}),
				width=>15, height=>15, alt=>$interfaces{$_}{desc},class=>'sidemenu' }),"&nbsp;";
		} elsif( $interfaces{$_}{isif} ) {
			print $q->img({
				src=>($config{'routers.cgi-smalliconurl'}."interface-sm.gif"),
				width=>15, height=>15, alt=>$interfaces{$_}{desc},class=>'sidemenu' }),"&nbsp;";
		} else {
			print $q->img({
				src=>($config{'routers.cgi-smalliconurl'}."target-sm.gif"),
				width=>15, height=>15, alt=>$interfaces{$_}{desc},class=>'sidemenu' }),"&nbsp;";
		}
		if ( $interface eq $_ ) {
			print $q->b($iflabel);
		} else {
			if( $gstyle =~ /p/ ) {
				print $q->a({ href=>"$meurlfull?".optionstring(
	{ page=>"main", if=>"$_" }), target=>"_top",class=>'sidemenu' }, $iflabel );
			} else {
				print $q->a({ href=>"$meurlfull?".optionstring(
	{ if=>"$_" }), target=>"graph",class=>'sidemenu' }, $iflabel );
			}
		}	
		print "</NOBR>".$q->br."\n";
	
	} #  special targets - summary, compact, info, userdefined
	if( $router ne "none" and $router ne "__none" ) {
		if($hascompact) {
		if( $config{'routers.cgi-stylesheet'}
			or ! defined $config{'routers.cgi-compact'}
			or $config{'routers.cgi-compact'} !~ /n/i ) {
		print "<NOBR>";
		print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}compact-sm.gif",
			width=>15, height=>15,class=>'sidemenu'  }),"&nbsp;";
		if( $interface eq "__compact" ) {
			print $q->b(langhtml(2000,"Compact summary"));
		} else {
			if( $gstyle =~ /p/ ) {
			print $q->a({ href=>"$meurlfull?".optionstring( 
	{ page=>"main", if=>"__compact" }), target=>"_top",class=>'sidemenu' },
	langhtml(2000,"Compact summary"));	
			} else {
			print $q->a({ href=>"$meurlfull?".optionstring(
	{ if=>"__compact" }), target=>"graph",class=>'sidemenu' },
	langhtml(2000,"Compact summary"));	
			}
		}
		print "</NOBR>".$q->br."\n";
		} # compact option
		} # hascompact
		if( $router !~ /^#/ ) {
		print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}menu-sm.gif",
			width=>15, height=>15,class=>'sidemenu'  }),"&nbsp;";
		if( $interface eq "__info" ) {
			print $q->b(langhtml(2001,"Information")),$q->br,"\n";
		} else {
			if( $gstyle =~ /p/ ) {
			print $q->a({ href=>"$meurlfull?".optionstring(
	{ page=>"main",if=>"__info"}), target=>"_top",class=>'sidemenu'},
	langhtml(2001,"Information")),$q->br,"\n";	
			} else {
			print $q->a({ href=>"$meurlfull?".optionstring(
	{ if=>"__info" }), target=>"graph",class=>'sidemenu' },
	langhtml(2001,"Information")),$q->br,"\n";	
			}
		}
		} # not system special #SERVER# 
	# any userdefined's for this router?
	if ( defined $routers{$router}{extensions} ) {
		my( $u, $ext, $targ );
		foreach $ext ( @{$routers{$router}{extensions}} ) {
			if($seclevel<$ext->{level}) {
#				print $ext->{desc}." (".$ext->{level}.")".$q->br."\n";
				next;
			}
			$targ = "graph";
			$targ = $ext->{target} if( defined $ext->{target} );
			$u = $ext->{url};
			if(!$ext->{noopts}) {
			$u .= "?x=1" if( $u !~ /\?/ );
			$u .= "&fi=".$q->escape($router)
				."&url=".$q->escape($q->url());
			$u .= "&t=".$q->escape($targ); 
			$u .= "&L=".$seclevel; 
			$u .= "&r=".$q->escape($ext->{hostname})
			."&h=".$q->escape($ext->{hostname}) if(defined $ext->{hostname});
			$u .= "&c=".$q->escape($ext->{community})
				if(defined $ext->{community} and $ext->{insecure});
			$u .= "&b=".$q->escape("javascript:history.back();history.back()")
				."&conf=".$q->escape($conffile);
			$u .= "&ad=$archdate&arch=$archdate" if($archdate);
			} elsif( $ext->{noopts} == 2 ) { # special for Link[]
				$u .= "&L=$seclevel&xgtype=$gtype&xgstyle=$gstyle";  
				$u .= "&ad=$archdate&arch=$archdate" if($archdate);
			}
			print "<NOBR>".$q->img({ src=>(${config{'routers.cgi-smalliconurl'}}
				.$ext->{icon}), width=>15, height=>15,class=>'sidemenu'  }),"&nbsp;";
			print $q->a({ href=>$u, target=>$targ,class=>'sidemenu' },
				expandvars($ext->{desc}) )."</NOBR>".$q->br."\n";
		}
	} # extensions defined
	} # not 'none' router
	print $q->br;
	} # explore

	print "\n<DIV class=sidemenuoptions>";
	if( !$archive and $interface ne "__none" and $interface ne "__info" ) {
		print "<nobr>";
      	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
	border=>0, width=>15, height=>15,class=>'sidemenu'})."&nbsp;";
	print $q->img({ src=>"${config{'routers.cgi-iconurl'}}graphs$iconsuffix.gif", alt=>langmsg(5006,"Graphs"),
		width=>100, height=>20,class=>'sidemenu' })."</nobr>". $q->br."\n";
	# Here, if the option is enabled, use the calendar tool
	if( $config{'routers.cgi-extendedtime'} and $config{'routers.cgi-extendedtime'}=~/f/i ) {
		my($mindate) = "";
		my($rrdinfo);
		my($e);
		my($rranum) = 0;
		my($gwindow) = 400;
		my($basedate) = "";
		my($rrdfilename);
		my($datestr,$dformat) = ('Live Data','%Y-%m-%d');
		my($mday,$mon,$year);
		if(defined $interfaces{$interface}{origrrd}) {
			$rrdfilename = $interfaces{$interface}{origrrd};
		} else {
			$rrdfilename = $interfaces{$interface}{rrd};
		}
		# convert this into a param that can be used by Javascript Date()
		if( $q->param('arch') ) {
			if( $q->param('arch') =~ /(\d\d\d\d)-(\d\d)-(\d\d)/ ) {
				$basedate = "$1,".($2-1).",$3";
				($mday,$mon,$year)=($3,$2-1,$1-1900);
				$dformat = $config{'web-dateonlyformat'}
					if(defined $config{'web-dateonlyformat'});
				$dformat =~ s/&nbsp;/ /g;
				$datestr = POSIX::strftime($dformat,0,0,0,$mday,$mon,$year);
			} else {
				$datestr = $q->param('arch');
			}
		}
		if( $gtype =~ /w/ ) {
			$gwindow = 333; # weekly graphs are shorter time window
			$rranum = 1;
		} elsif( $gtype =~ /m/ ) {
			$rranum = 2;
		} elsif( $gtype =~ /y/ ) {
			$rranum = 3;
		}
		if($rrdcached and $rrdcached!~/^unix:/) {
			my($pth) = $config{'routers.cgi-dbpath'};
			$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
			$rrdfilename =~ s/^$pth\/*//;
		}
		eval { require RRDs; };
		if($@) {
			$e = $@;
		} else {
			$rrdinfo  = RRDs::info($rrdfilename,@rrdcached);
			$e = RRDs::error();
		}
		if($e) {
			print "<!-- RRD error: $e -->\n";
			print "<!-- RRD file: $rrdfilename -->\n";
			print "<!-- RRDcached option: $rrdcached -->\n";
			print "<!-- RRDcached setting: ".(join(" ",@rrdcached))." -->\n";
		} else {
			print "<!-- RRD rra=$rranum rows=".$rrdinfo->{"rra[${rranum}].rows"}." -->\n";
		}
		if(defined $rrdinfo and !$e and $rrdinfo->{"rra[${rranum}].rows"} ) {	
			$mindate = 1000 * (time() - ($rrdinfo->{step} * $rrdinfo->{"rra[${rranum}].pdp_per_row"} * ($rrdinfo->{"rra[${rranum}].rows"}-$gwindow)));
		}
		print "<TABLE><TR><TD>";
		print "<FORM name=dateform method=GET action=$meurlfull target=graph class=sidemenu>";
		print "<span id=\"calendar-trigger\">".$q->img({ src=>"${config{'routers.cgi-smalliconurl'}}calendar-sm.gif",
			width=>15, height=>15, class=>'sidemenuform', id=>'dateanchor'  }),"&nbsp;"; # spacer
		print "<button id=\"calendar-trigger-button\">$datestr</button></span><br>\n";
		print $q->hidden(-id=>"calendar-field", -name=>"arch", -override=>1, -default=>($q->param('arch')));
		print $q->hidden(-name=>'rtr', -default=>"$router", -override=>1);
		print $q->hidden(-name=>'if', -default=>"$interface", -override=>1);
		print $q->hidden(-name=>'page', -default=>'graph', -override=>1);
		print $q->hidden(-name=>'xpage', -default=>'graph', -override=>1); # grr
		print $q->hidden(-name=>'xgtype', -default=>"$gtype", -override=>1);
		print $q->hidden(-name=>'xgstyle', -default=>"$gstyle", -override=>1);
		print $q->hidden(-name=>'xgopts', -default=>"$gopts", -override=>1);
		print $q->hidden(-name=>'bars', -default=>"$baropts", -override=>1);
		print $q->hidden(-name=>'extra', -default=>"$extra", -override=>1);
		print $q->hidden(-name=>'uopts', -default=>"$uopts", -override=>1);
		print "</FORM>";
		print "</TD></TR></TABLE>\n";
		print "<SCRIPT>\n
// JSCal2 Calendar control from http://www.dynarch.com/projects/calendar/
function getDateInfo(date, wantsClassName) {
	var idate = Calendar.dateToInt(date);
	if (String(idate).indexOf(\"0821\") == 4) {
		return { klass: \"birthday\", tooltip: \"Steve's Birthday!\" };
	}
};
var cal = Calendar.setup({
	inputField : \"calendar-field\",
	trigger    : \"calendar-trigger\",
	anchor     : \"dateanchor\",
	animation  : false,
	opacity    : 1,
	align      : \"BC/ /l/b/\",
	dateFormat : \"\%Y-\%m-\%d\",
	selection  : Calendar.dateToInt(new Date(${basedate})),
	max        : Calendar.dateToInt(new Date()),
	min        : Calendar.dateToInt(new Date(${mindate})),
	dateInfo   : getDateInfo,
	onSelect   : function() { 
		this.hide();
		if( Calendar.printDate(Calendar.intToDate(this.selection.get()),\"\%Y-\%m-\%d\") != \"".$q->param('arch')."\" ) {
			dateform.submit();
		}
	}
});
</SCRIPT>\n";
	} else {
	# First we list all the archived RRD files, if available.
	my($archroot) = '';
	if($interface and defined $interfaces{$interface}) {
		if($interfaces{$interface}{origrrd}) {
			$archroot = dirname($interfaces{$interface}{origrrd})
				.$pathsep.'archive';
		} elsif($interfaces{$interface}{rrd}) {
			$archroot = dirname($interfaces{$interface}{rrd})
				.$pathsep.'archive';
		}
	}
	if( -d $archroot ) {
		# An archive exists!
		my($rrdfilename);
		if(defined $interfaces{$interface}{origrrd}) {
			$rrdfilename = basename($interfaces{$interface}{origrrd});
		} else {
			$rrdfilename = basename($interfaces{$interface}{rrd});
		}
		my(@days) = ( '0' );
		my(%descs);
		my($dmyfmt);
		if( defined $config{'web-dateonlyformat'} ) {
			$dmyfmt = $config{'web-dateonlyformat'};
		} else { $dmyfmt = "\%d/\%m/\%y" } # could use %x here?
		$debugmessage .= "Dateformat used: $dmyfmt\n";
		$descs{0} = langmsg(5007,'Live data');
		# caching code for speedycgi people
		if( -M $archroot < 0 ) {
			# invalidate archive cache, as a new one has been added.
			%cachedays = ();
			$^T = time; # set 'script init time' to first read of cfg files
			# we also need to clear all other caches since they are tied
			# to the script init time?
			# try without since if they have changed the previous checks will
			# already have picked it up and refreshed them
			#%ifstore = ();      # clean out all cached info
			#%routerscache = (); # clean out all cached info
			#$readinrouters = 0;
		}
		if( defined $cachedays{$rrdfilename} ) {
			@days = @{$cachedays{$rrdfilename}};
			# If we get the list from the cache, we still need to build descs
			# This is because people may have different date formats...
			foreach ( @days ) {
				if( /(\d\d)(\d\d)-(\d\d)-(\d\d)/ ) { 
					if($dmyfmt) {
						$descs{$_} =  
				POSIX::strftime($dmyfmt,0,0,0,$4,($3-1),(($1>19)?($2+100):$2)); 
					} else { $descs{$_} =  "$4/$3/$2"; } #DMY
				}
			}
			$debugmessage .= "fromcache(dates:$rrdfilename)\n";
		} else {
			# Maybe find a better way to do this -- glob is SLOW
			$|=1; # print out what we've done so far
			foreach ( sort rev findarch( $archroot,$rrdfilename ) ) {
				if( /(\d\d)(\d\d)-(\d\d)-(\d\d)/ ) {
					push @days, "$1$2-$3-$4";
					if($dmyfmt) {
						$descs{"$1$2-$3-$4"} =  
				POSIX::strftime($dmyfmt,0,0,0,$4,($3-1),(($1>19)?($2+100):$2)); 
					} else { $descs{"$1$2-$3-$4"} =  "$4/$3/$2"; } #DMY
				}
			}
			$cachedays{$rrdfilename} = [ @days ]; # Cache for later
			$debugmessage .= "cached[dates:$rrdfilename]\n";
		}
		if( $#days > 0 ) {
		print "<nobr><TABLE cellspacing=0 cellpadding=0 border=0 class=sidemenu><TR class=sidemenu><TD class=sidemenu>";
		print "<FORM name=archform method=GET action=$meurlfull target=graph class=sidemenu>";
		print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}calendar-sm.gif",
			width=>15, height=>15, class=>'sidemenuform'  }),"&nbsp;"; # spacer
		my($curd) = $q->param('arch');
		$curd = $opt_a if($opt_a);
		$curd = '0' if(!$curd);
		print $q->popup_menu( -name=>"arch", -values=>\@days,
			-default=>$curd, -labels=>\%descs, 
			-onChange=>'archform.submit();', class=>'sidemenuform');
		print $q->hidden(-name=>'rtr', -default=>"$router", -override=>1);
		print $q->hidden(-name=>'if', -default=>"$interface", -override=>1);
		print $q->hidden(-name=>'page', -default=>'graph', -override=>1);
		print $q->hidden(-name=>'xpage', -default=>'graph', -override=>1); # grr
		print $q->hidden(-name=>'xgtype', -default=>"$gtype", -override=>1);
		print $q->hidden(-name=>'xgstyle', -default=>"$gstyle", -override=>1);
		print $q->hidden(-name=>'xgopts', -default=>"$gopts", -override=>1);
		print $q->hidden(-name=>'bars', -default=>"$baropts", -override=>1);
		print $q->hidden(-name=>'extra', -default=>"$extra", -override=>1);
		print $q->hidden(-name=>'uopts', -default=>"$uopts", -override=>1);
		print "</FORM>\n";
		print "</TD></TR></TABLE></nobr>";
		} else {
			print "<!-- no archive dates -->";
		}
	} else {
		print "<!-- $archroot does not exist -->\n";
	}
	} # new archive method
	# Now all the different daily/weekly/etc graph types
	foreach ( @gorder ) {
		if( defined $interfaces{$interface}
			and defined $interfaces{$interface}{suppress} ) {
			$timeframe = $_; $timeframe =~ s/-//g;
			next if( $interfaces{$interface}{suppress} =~ /$timeframe/ ); 
		}
		print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}clock-sm.gif",
			width=>15, height=>15, class=>'sidemenu'  }),"&nbsp;";
		if($gtype eq $_) {
			print $q->b($gtypes{$_}),$q->br,"\n";
		} elsif((($interface eq "__compact")
			and (length > 2 ))
			or ( $router eq "none" )) {
			print $gtypes{$_},$q->br,"\n";
		} else {
			if( $gstyle =~ /p/ ) {
			print $q->a({ href=>"$meurlfull?".optionstring(
				{ page=>"main", xgtype=>"$_" }), 
				target=>"_top", class=>'sidemenu' }, $gtypes{$_} ), $q->br,"\n";
			} else {
			print $q->a({ href=>"$meurlfull?".optionstring(
	{ xgtype=>"$_" }), target=>"graph", class=>'sidemenu' }, $gtypes{$_} ),$q->br,"\n";
			}
		}
	}
		print $q->br;
	} # ! viewing archive
	print "\n";
	if( @archive ) {
		print "<nobr>";
      	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
	border=>0, width=>15, height=>15, class=>'sidemenu'})."&nbsp;";
		print  $q->img({ 
			src=>"${config{'routers.cgi-iconurl'}}archive-h$iconsuffix.gif", 
			alt=>langmsg(5008,"Archive"), width=>100, height=>20, class=>'sidemenu' }),"</nobr>".$q->br."\n";
		if($archive) {
			print "<NOBR>";
			print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}graph-sm.gif",
					width=>15, height=>15, class=>'sidemenu'  }),"&nbsp;";
			$adesc = langhtml(5007,"Live graph");
			if( $gstyle=~/p/ ) {
				print $q->a({ href=>"$meurlfull?".optionstring( { page=>"main" }), 
					target=>"_top", class=>'sidemenu' }, $adesc );
			} else {
				print $q->a({ href=>"$meurlfull?".optionstring( { page=>"graph" }), 
					target=>"graph", class=>'sidemenu' }, $adesc );
			}
			print "</NOBR>".$q->br."\n";
		}
		foreach ( sort @archive ) {
			if(/(\d+)-(\d+)-(\d+)-(\d+)-(\d+)-(\S+)\.(gif|png)$/) {
				# try to get local formatting
#				$adesc = "$4:$5&nbsp;$3/$2/$1&nbsp;(".$gtypes{$6}.")";
				my( $dformat ) = "%c";
				$dformat = $config{'web-shortdateformat'}
					if(defined $config{'web-shortdateformat'});
				if(!$dformat) {
					$adesc = "$4:$5&nbsp;$3/$2/$1&nbsp;(".$gtypes{$6}.")";
				} else {
					$adesc = POSIX::strftime($dformat,
						0,$5,$4,$3,($2-1),($1-1900))." (".$gtypes{$6}.")";
					$adesc =~ s/ /\&nbsp;/g;
				}
				print "<NOBR>";
		print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}graph-sm.gif",
				width=>15, height=>15, class=>'sidemenu'  }),"&nbsp;";
				if( $gstyle=~/p/ ) {
					print $q->a({ href=>"$meurlfull?".optionstring( { page=>"main",
						archive=>(basename $_), xgtype=>"$6"}), 
						target=>"_top", class=>'sidemenu' }, $adesc );
				} else {
					print $q->a({ href=>"$meurlfull?".optionstring( {
						page=>"graph",
						archive=>(basename $_), xgtype=>"$6"}), 
						target=>"graph", class=>'sidemenu' }, $adesc );
				}
				print "</NOBR>".$q->br."\n";
			} else {
				print "<!-- Error in archive [$_] -->\n";
			}
		}
		print $q->br."\n";
	}

	if( !$archive and $interface ne "__none" and $interface ne "__info"  ) {
		print "<nobr>";
      	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
	border=>0, width=>15, height=>15, class=>'sidemenu'})."&nbsp;";
	print  $q->img({ 
		src=>"${config{'routers.cgi-iconurl'}}styles$iconsuffix.gif", 
		alt=>langmsg(5009,"Styles"), width=>100, height=>20, class=>'sidemenu' })."</nobr>".$q->br."\n";
	foreach ( @sorder ) {
		next if (!defined $gstyles{$_});
		print "<NOBR>";
		print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}pbrush-sm.gif",
			width=>15, height=>15, class=>'sidemenu'  }),"&nbsp;";
		$gs = $gstyles{$_};
		$gs =~ s/ /\&nbsp;/g;
		if($gstyle eq $_) {
			print $q->b($gs);
		} elsif( $router eq "none" ) {
			print $gs;
		} else {
			# PDAs cant be relied on to have javascript support
			if( /p/ ) {
			print $q->a({ href=>"$meurlfull?".optionstring(
	{ page=>"main", xgstyle=>"$_"}), target=>"_top", class=>'sidemenu' }, $gs );
			} else {
			print $q->a({ href=>"$meurlfull?".optionstring(
	{ xgstyle=>"$_"}), target=>"graph", class=>'sidemenu' }, $gs );
			}
		}
		print "</NOBR>".$q->br."\n";
	}
		print $q->br;
	} # ! archive viewing
		print "<nobr>";
      	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
	border=>0, width=>15, height=>15, class=>'sidemenu'})."&nbsp;";
	print  $q->img({ src=>"${config{'routers.cgi-iconurl'}}otherstuff$iconsuffix.gif", alt=>langmsg(5010,"Other Stuff"),
		width=>100, height=>20, class=>'sidemenu' })."</nobr>". $q->br."\n";
	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}prefs-sm.gif",
			width=>15, height=>15, class=>'sidemenu'  }),"&nbsp;";
	print $q->a({href=>"$meurlfull?".optionstring(
	{ page=>"config" }) , target=>"graph", class=>'sidemenu'}, 
		langmsg(5011,"Preferences")),$q->br,"\n";
	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}info-sm.gif", class=>'sidemenu' }),"&nbsp;";
	print $q->a({href=>"$meurlfull?".optionstring({page=>"help"}), target=>"graph", class=>'sidemenu'}, 
		langmsg(5012,"Information")),$q->br,"\n";
#	print $q->img({ src=>"${config{'routers.cgi-iconurl'}}error-sm.gif" }),"&nbsp;";
#	print $q->a({href=>("$meurl?page=verify&rtr="
#		.$q->escape($router)),target=>"_new"},"Configuration&nbsp;check")
#		.$q->br."\n";
	# twin menu
	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}menu-sm.gif", class=>'sidemenu' }),
		"&nbsp;";
	if( $twinmenu ) {
		$uopts=~ s/[tT]//g; $uopts .= "T";
		print $q->a({ href=>"$meurlfull?".optionstring({ page=>"main"}), 
			target=>"_top", class=>'sidemenu' },langhtml(5013,"Close second menu") )
	} else {
		$uopts=~ s/[tT]//g; $uopts .= "t";
		print $q->a({ href=>"$meurlfull?".optionstring({page=>"main"}), 
			target=>"_top", class=>'sidemenu' }, langhtml(5014,"Twin menu view") )
	}
	print $q->br."\n";
	print "</DIV>"; # sidemenuoptions
} else {
	# Devices (Routers) menu list
	#
	if( ! $twinmenu ) {
      	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
	border=>0, width=>15, height=>15, class=>'sidemenu'})."&nbsp;";
		print $q->a({ href=>"$meurlfull?".optionstring(
			{ page=>"menu", xmtype=>"options" }), target=>"_self" ,
		onMouseOver=>"if(options){options.src='${config{'routers.cgi-iconurl'}}options-dn-w.gif'; window.status='Show display options';}", 
		onmouseout=>"if(options){options.src='${config{'routers.cgi-iconurl'}}options-dn$iconsuffix.gif'; window.status='';}", class=>'sidemenu' },
		$q->img({ src=>"${config{'routers.cgi-iconurl'}}options-dn$iconsuffix.gif", alt=>langmsg(5015,"Options"), border=>0, name=>"options", class=>'sidemenu',
			height=>20, width=>100 }))."\n".$q->br."\n";
	}
	# list  devices
      	print $q->img({ src=>"${config{'routers.cgi-smalliconurl'}}nothing-sm.gif", 
	border=>0, width=>15, height=>15, class=>'sidemenu'})."&nbsp;";
	print  $q->img({ src=>"${config{'routers.cgi-iconurl'}}devices$iconsuffix.gif", alt=>langmsg(5004,"Devices"),
			height=>20, width=>100, class=>'sidemenu' }), $q->br,"\n";
	# The 'Find' box
	print "<DIV class=sidemenuoptions>";
	if( !defined $config{'routers.cgi-showfindbox'}
		or $config{'routers.cgi-showfindbox'} =~ /[Yy1]/ ) {
		print "<NOBR><TABLE align=left cellspacing=0 cellpadding=0 border=0 class=sidemenu><TR class=sidemenu><TD nowrap class=sidemenu><FORM method=GET action=$meurlfull target=graph class=sidemenuform>";
      	print $q->img({src=>"${config{'routers.cgi-smalliconurl'}}search-sm.gif", border=>0, width=>15, height=>15, class=>'sidemenu'})."&nbsp;";
		print $q->textfield({-name=>'searchhost', 
			-value=>langmsg(5004,"Device"), -size=>9, class=>'sidemenuform'});
		print $q->hidden(-name=>'page', -default=>"graph", -override=>1);
		print $q->hidden(-name=>'xgtype', -default=>"$gtype", -override=>1);
		print $q->hidden(-name=>'xgstyle', -default=>"$gstyle", -override=>1);
		print $q->hidden(-name=>'xgopts', -default=>"$gopts", -override=>1);
		print $q->hidden(-name=>'bars', -default=>"$baropts", -override=>1);
		print $q->hidden(-name=>'extra', -default=>"$extra", -override=>1);
		print $q->hidden(-name=>'uopts', -default=>"$uopts", -override=>1);
		print $q->submit({ name=>"search", value=>"?", class=>'sidemenuform' });
		print "</FORM></TD></TR></TABLE></NOBR><br clear=both>\n";
	}
	print "</DIV>";
	# grouping
	my($lastgroupdesc,$activegroupdesc);
	$grouping = $multilevel = 0;
	$grouping = 1 if( defined $config{'routers.cgi-group'}
		and $config{'routers.cgi-group'} =~ /[Yy1]/ );
	if($grouping) {
		$group=$lastgroup="";
		$group=$routers{$router}{group} if(defined $routers{$router});
		$gs = ':';
		$gs = $config{'routers.cgi-groupsep'} 
			if(defined $config{'routers.cgi-groupsep'});
		$multilevel = 1 if( defined $config{'routers.cgi-multilevel'} 
			and $config{'routers.cgi-multilevel'}=~/[y1]/i );
		# Prefix to cut off for group names
		$pfx = $config{'routers.cgi-confpath'}.$pathsep;
		# Can't add escapes for some reason
#		$pfx =~ s/\//\\\//g; 
		$pfx =~ s/\\/\\\\/g;

		if($multilevel) {
			if( defined $config{"targetnames-$group"} ) {
				$activegroupdesc = $config{"targetnames-$group"};
			} elsif( defined $config{("targetnames-".(lc $group))} ) {
				$activegroupdesc = $config{("targetnames-".(lc $group))};
			} elsif($group) {
				$activegroupdesc = $group;
				$activegroupdesc =~ s/^$pfx//; # Chop off confpath
				$activegroupdesc = basename( $group,'' ).$pathsep 
					if(!$activegroupdesc);
			} else {
				$activegroupdesc = "None";
			}
		}
	}
	foreach ( sort byshdesc keys(%routers) ) {
		next if(!$routers{$_}{inmenu});
		if( $grouping ) {
			$thisgroup =  $routers{$_}{group};
			if( $thisgroup ne $lastgroup ) {
				my(@grps);
				if( defined $config{"targetnames-$thisgroup"} ) {
					$groupdesc = $config{"targetnames-$thisgroup"};
				} elsif( defined $config{("targetnames-".(lc $thisgroup))} ) {
					$groupdesc = $config{("targetnames-".(lc $thisgroup))};
				} else {
					$groupdesc = $thisgroup;
					$groupdesc =~ s/^$pfx//; # Chop off confpath
					$groupdesc = basename( $thisgroup,'' ).$pathsep if(!$groupdesc);
				}
				if($multilevel) {
					@grps = getgroups($activegroupdesc,$groupdesc,$lastgroupdesc);
				} else {
					@grps = ( [ $groupdesc,1,(($thisgroup eq $group)?1:0) ] );
				}
				foreach my $gg ( @grps ) {
					print "<NOBR>";
					$menulevel = $gg->[1];
					print "&nbsp;&nbsp;" x $menulevel if($menulevel);
					if( $gg->[2] ) {
						print $q->img({
						src=>"${config{'routers.cgi-smalliconurl'}}g-sm.gif",
						width=>15, height=>15, alt=>$gg->[0], class=>'sidemenu' }),"&nbsp;";
						print $q->b($gg->[0]);
					} else {
						$lurl = $meurlfull;
						$lurl = $routers{$_}{redirect}
							if(defined $routers{$_}{redirect});
						if( $gstyle =~ /p/ or defined $routers{$_}{redirect}) {
						print $q->img({ 
						src=>"${config{'routers.cgi-smalliconurl'}}plus-sm.gif",
						width=>15, height=>15, alt=>$gg->[0], class=>'sidemenu',
						border=>0 }),"&nbsp;";
							print $q->a({href=>"$lurl?"
				 				.optionstring({page=>"main",'if'=>"",rtr=>"$_"}), 
								target=>"_top", class=>'sidemenu' },$q->b($gg->[0]) );
						} else {
						print $q->a({ href=>"$lurl?"
							.optionstring({ rtr=>"$_", 'if'=>"" }), 	
							target=>"graph", class=>'sidemenu' }, $q->img({ 
						src=>"${config{'routers.cgi-smalliconurl'}}plus-sm.gif",
						width=>15, height=>15, alt=>$gg->[0], class=>'sidemenu',
						border=>0 }))."&nbsp;";
							print $q->a({ href=>"$lurl?"
								.optionstring({ rtr=>"$_", 'if'=>"" }), 	
								target=>"graph", class=>'sidemenu' },$q->b($gg->[0]) );
						}
					}
					print "</NOBR>".$q->br."\n";
				} # foreach
				$lastgroup = $thisgroup;
				$lastgroupdesc = $groupdesc;
			} # if in new group
			if( $multilevel ) {
				next if(( $thisgroup ne $group ) 
					and ( $activegroupdesc !~ /^$groupdesc$gs/ ));
#				if(( $thisgroup ne $group ) 
#					and ( $activegroupdesc !~ /^$groupdesc$gs/ )) { print "[$activegroupdesc][^$groupdesc$gs]"; }
			} else {
				next if( $thisgroup ne $group ); # only show active group
			}
		} # if grouping
		$rtrdesc = $routers{$_}{shdesc};
		$rtrdesc = $_ if(! $rtrdesc );
		$rtrdesc =~ s/ /\&nbsp\;/g; # stop breaking of line on spaces

		print "<NOBR>";
		if($grouping) { print ( "&nbsp;&nbsp;" x ($menulevel+1)); }
		if( $_ eq $router ) { print $q->a({name=>"top"},""); }
		print $q->img({ src=>($config{'routers.cgi-smalliconurl'}.$routers{$_}{icon}),
			width=>15, height=>15, class=>'sidemenu',
			alt=>( $routers{$_}{shdesc}?$routers{$_}{shdesc}:$_ ) }),"&nbsp;";
		if( $_ eq $router ) {
			print $q->b($rtrdesc);
		} else {
			$lurl = $meurlfull;
			$lurl = $routers{$_}{redirect}
				if(defined $routers{$_}{redirect});
			if( $gstyle =~ /p/ or defined $routers{$_}{redirect}) {
			print $q->a({href=>"$lurl?".optionstring({page=>"main", 'if'=>"",
				rtr=>"$_"}), target=>"_top", class=>'sidemenu' },$rtrdesc );
			} else {
			print $q->a({href=>"$lurl?".optionstring({ rtr=>"$_", 'if'=>"" }),
				target=>"graph", class=>'sidemenu' },$rtrdesc );
			}
		}
		print "</NOBR>".$q->br."\n";
	}
	# Now add any  site links
	my($mkey,$marg,$mdesc,$micon,$murl,$targ,$level,$insec,$noop);
#	my($itemx) = 1;
#	while ( defined $config{"menu-item$itemx"} ) {
#		$marg = $config{"menu-item$itemx"};
#		$mkey = "Item $itemx";	
#		$itemx += 1;
## This way is slower, but more user-friendly
    foreach ( sort keys %config ) {
	  if( /^menu-(\S+)/i ) {
		$mkey = $1;	
		$marg = $config{$_};

		( $mdesc, $murl, $micon, $targ, $level, $insec, $noop ) = 
			parse_ext($marg);
		if($seclevel >= $level ) { # Are we high enough security level?
			if( !$micon and $mdesc =~ /\.gif$/ ) {
				$micon = $mdesc; $mdesc = $mkey;
			}
			$mdesc = $mkey if(!$mdesc); #default
			$micon = "cog-sm.gif" if(!$micon); #default
			if(!$noop and $murl !~ /\.html?$/ ) {
				if( $murl =~ /\?/ ) { $murl .= '&'; } else { $murl .= '?'; }
				$murl .= "fi=".$q->escape($router)
					."&url=".$q->escape($q->url())
					."&t=".$q->escape($targ)."&L=".$seclevel; 
			}
			print "<NOBR>";
			print $q->img({ src=>($config{'routers.cgi-smalliconurl'}.$micon),
				width=>15, height=>15, alt=>"$mdesc", class=>'sidemenu' }),"&nbsp;";
			print $q->a({href=>$murl, target=>$targ, class=>'sidemenu' },$mdesc );
			print "</NOBR>".$q->br."\n";
		} # security level
	  } # if
	} # foreach
}

# Finish off the page
print "</FONT>\n" if( defined $config{'routers.cgi-menufontsize'} );
print "</DIV>\n<!-- Version $VERSION -->\n";
print "<!-- R:[$router] I:[$interface] A:[$archive] U:[$authuser] -->\n";
print "<!--\n$debugmessage\n-->\n" if($debugmessage);
print $q->end_html();
}

############################
# Main frame set

sub do_main()
{
	my( $javascript, $framethree );
	my( $urla, $urlb, $urlc, $urlh );
	my( $menuwidth ) = 150;
	my( $frameopts ) = " marginwidth=2 marginheight=2 bgcolor=$menubgcolour ";
	my( $borderwidth ) = 1;

	$gtype = "" if(!defined $gtype);
	$mtype = "" if(!defined $mtype);
	$gstyle = "" if(!defined $gstyle);
	$gopts = "" if(!defined $gopts);
	$baropts = "cam" if(!defined $baropts);

	$borderwidth = $config{'routers.cgi-borderwidth'}
		if( defined $config{'routers.cgi-borderwidth'} );

	$menuwidth = $config{'routers.cgi-menuwidth'}
		if( defined $config{'routers.cgi-menuwidth'} );
	$menuwidth = 150 if ( $menuwidth < 100 or $menuwidth > 500
		or $menuwidth !~ /^\d+$/ );

# Javasciript funtion to reload the page with a specified set of params.
	$javascript = "
	function makebookmark(rtr,rtrif,xgtype,xgstyle,xgopts,bars,extra,arch) {
		var newurl;
		newurl = '$meurlfull?rtr='+escape(rtr)+'&if='+escape(rtrif);
		if ( xgtype != '' ) { newurl = newurl + '&xgtype='+xgtype; }
		if ( xgstyle != '' ) { newurl = newurl + '&xgstyle='+xgstyle; }
		if ( xgopts  != '' ) { newurl = newurl + '&xgopts='+xgopts ; }
		if ( extra != '' ) { newurl = newurl + '&extra='+escape(extra) ; }
		if ( arch != '' ) { newurl = newurl + '&arch='+escape(arch) ; }
		if ( bars  != '' && rtrif == '__compact' ) { newurl = newurl + '&bars='+bars ; }
		window.location = newurl;
	}
	function makearchmark(rtr,rtrif,extra,arch) {
		var newurl;
		newurl = '$meurlfull?rtr='+escape(rtr)+'&if='+escape(rtrif)
			+'&archive='+arch;
		if ( extra != '' ) { newurl = newurl + '&extra='+escape(extra) ; }
		window.location = newurl;
	}
	var lastaurl;
	var lastburl;
	function setlocationa(url) {
		if( lastaurl != url ) {
			self.menu.location = url;
			lastaurl = url;
		}
		return 0;
	}
	function setlocationb(url) {
		if( self.menub ) {
			if( lastburl != url ) {
				self.menub.location = url;
				lastburl = url;
			}
		}
		return 0;
	}
";

	$urlb = $meurlfull."?".optionstring({ page=>"graph", nomenu=>1 });

	if( $twinmenu ) {	
		$urla = $meurlfull."?".optionstring({ page=>"menu", xmtype=>"routers"
			  }) ."#top";
		$urlc = $meurlfull."?".optionstring({ page=>"menub", xmtype=>"options"
			 }) ."#top";
		$framethree = "<FRAMESET border=$borderwidth  $frameopts
	cols=$menuwidth,*,$menuwidth class=main>
  <FRAME name=menu src=$urla scrolling=auto nowrap $frameopts class=main id=leftframe>
  <FRAME name=graph src=$urlb scrolling=auto $frameopts class=main id=graphframe>
  <FRAME name=menub src=$urlc scrolling=auto nowrap $frameopts class=main id=rightframe>
 </FRAMESET>\n";
	} else {
		$urla = $meurlfull."?".optionstring({ page=>"menu", nomenu=>1 })."#top";
		$framethree = "<FRAMESET border=$borderwidth  $frameopts
cols=$menuwidth,* >
  <FRAME name=menu src=$urla scrolling=auto nowrap $frameopts class=main id=leftframe>
  <FRAME name=graph src=$urlb scrolling=auto $frameopts class=main id=graphframe>
 </FRAMESET>\n";
	}

	$urlh = $meurlfull."?".optionstring({ page=>"head" });

	if($q->cookie('auth')) {
		print "<!-- ".$q->cookie('auth')." -->\n";
	}

	print "<HTML><HEAD>\n<!-- $pagetype -->\n";
	print "<LINK rel=\"stylesheet\" type=\"text/css\" href=\""
		.$config{"routers.cgi-stylesheet"}."\" />\n"
		if($config{"routers.cgi-stylesheet"});
	print "<TITLE>$windowtitle</TITLE></HEAD><SCRIPT language=JavaScript><!--\n$javascript\n//--></SCRIPT>\n";
	if(! $q->param('noheader') ) {
		print "<FRAMESET border=$borderwidth $frameopts rows=50,* bgcolor=$menubgcolour class=main>\n";
		print "<FRAME name=head src=$urlh resize scrolling=no $frameopts class=main id=topframe>\n";
	}
  	print "$framethree\n";
	if(! $q->param('nohead') ) { print "</FRAMESET>\n"; }
	print <<EOT
<NOFRAMES>
 <BODY>
  Sorry, routers.cgi does not support non-frames browsers.  
  Upgrade to Netscape 4.x or later, or MSIE 4.x or later.
 </BODY>
</NOFRAMES>
<!-- Language $language -->
<!-- User $authuser -->
<!-- Version $VERSION -->
<!-- $debugmessage -->
<!-- NOTE:
     You should not normally run routers.cgi from the command line.  It is 
     intended to be used as a CGI script, called by your Web Server.  When 
     installed in this way, you should be able to view the output in your 
     web browser by calling the CGI script through your web server.
     You may want to call it from the command line with the -A parameter
     in order to manually create Archived graphs.  In this case, use -D and
     -T to specify Device and Target, and -s, -t for Style and Type.
     Similarly, the -C option will export CSV data to standard output.
     You can use the -U option to specify an authenticated username if required.
  -->
</HTML>
EOT
;
# now clean up the verify stuff if it's there
# we cant do this in the do_verify subroutine because the file is required
# by a future connection.
unlink ($config{'routers.cgi-graphpath'}.$pathsep."redsquare.png")
	if( -f $config{'routers.cgi-graphpath'}.$pathsep."redsquare.png" );

}

########################
# Is this target 'active'?
# return 0 (inactive), 1 (active), error message
sub isactive($) {
	my($curif) = $_[0];
	my($start,$end,$interval,$rrd,$data,$names);
	my($e,$line,$val);
	my(@params)=('MAX'); # Should we use MAX?  Might be confused with -ve data 
#	my(@params)=('AVG');  
	my($dwmy,$lastupdate);

	# Userdefined!
	return "Summaries are always active!"
		 if( $interfaces{$curif}{issummary} ); # should never happen
	if( $interfaces{$curif}{usergraph} ) {
		my ( @ctgt, $t, $r );
		foreach $t ( @{$interfaces{$curif}{targets}} ) {
			next if( $interfaces{$t}{usergraph} ); # prevent looping
			return 1 if( isactive($t) ); # optimise if possible
		}	
		return 0;
	}

	# If this is an archive, then uselastupdate=2 and rrd is already changed
	$rrd = $interfaces{$curif}{rrd};
	if($rrdcached and $rrdcached!~/^unix:/) {
		my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
		$rrd =~ s/^$pth\/*//;
	}
	$dwmy = $gtype;
	
	$end = 'now';
	if($uselastupdate) {
		$lastupdate = RRDs::last($rrd,@rrdcached);
		if($lastupdate) { $end = $lastupdate; }
		$end = $archivetime 
			if($uselastupdate > 1 and $archivetime);
		$end = $basetime if($basetime);
	}
	if( $dwmy =~ /-/ ) {
		if ( $dwmy =~ /6/ ) { push @params, "-e", "$end-6h"; }
		elsif ( $dwmy =~ /d/ ) { push @params, "-e", "$end-24h";}
		elsif ( $dwmy =~ /w/ ) { push @params, "-e", "$end-7d"; }
		elsif ( $dwmy =~ /m/ ) { push @params, "-e", "$end-30d";}
		elsif ( $dwmy =~ /y/ )  { push @params, "-e", "$end-365d";}
	} else {
		push @params, '-e', $end;
	}
	if ( $dwmy =~ /6/ ) { $interval = "60"; }
	elsif ( $dwmy =~ /d/ ) { $interval = "300"; }
	elsif ( $dwmy =~ /w/ ) { $interval = "1800"; }
	elsif ( $dwmy =~ /m/ ) { $interval = "7200"; }
	elsif ( $dwmy =~ /y/ ) { $interval = "86400"; }

	push @params,'-r',86400; # always use daily max RRA
	push @params,'-s',"end-".($interval*400);# just back to start of this graph

	($start,$interval,$names,$data) = RRDs::fetch($rrd,@params,@rrdcached);
	$e = RRDs::error();
	return "Error: $e" if($e); # so erroring targets display by default
	foreach $line ( @$data ) {
		foreach $val ( @$line ) { return 1 if($val); }
	}
	return 0;  # not active: no values other than 0 or UNKN were found
}

##########################
# Graph panel

sub sinout {
	my($interface);
	my($sin,$sout,$sext);
	my($ssin,$ssout,$ssext);
	my($l,$escunit,$escunit2);
	my($alt);

	($interface,$alt,$l) = @_;

	$escunit = $interfaces{$interface}{unit};
	$escunit =~ s/%/%%/g;
	$escunit =~ s/:/\\:/g;
	$escunit =~ s/&nbsp;/ /g;
	$escunit2 = $interfaces{$interface}{unit2};
	$escunit2 =~ s/%/%%/g;
	$escunit2 =~ s/:/\\:/g;
	$escunit2 =~ s/&nbsp;/ /g;

	$sin=langmsg(6403,"In: "); $sout=langmsg(6404,"Out:"); $sext = "Ext:";
	$ssext = $ssin = $ssout = "";
	$sin = $interfaces{$interface}{legendi}
		if( defined $interfaces{$interface}{legendi} );
	$sout= $interfaces{$interface}{legendo}
		if( defined $interfaces{$interface}{legendo} );
	$sext = $interfaces{$interface}{legendx}
		if( defined $interfaces{$interface}{legendx} );

	if( $alt and $interfaces{$alt}{overridelegend}
		and $interfaces{$interface}{shdesc}
		and ( $interfaces{$interface}{noo} or $interfaces{$interface}{noi} 
		or  $interfaces{$alt}{noo} or $interfaces{$alt}{noi} )
	) {
		$sin = $sout = $interfaces{$interface}{shdesc}.':';
	}

	if(!$l) {
		$l = length $sin; $l = length $sout if($l < length $sout);
	}
	$sin = substr($sin.'                ',0,$l);
	$sout= substr($sout.'                ',0,$l);
	$sin =~ s/:/\\:/g; $sout =~ s/:/\\:/g;
	$sin =~ s/%/%%/g; $sout =~ s/%/%%/g;
	if( $interfaces{$interface}{integer} ) {
		$ssin = "%5.0lf"; $ssout = "%5.0lf"; $ssext = "%5.0lf";
	} elsif( $interfaces{$interface}{fixunits} 
		and !$interfaces{$interface}{exponent} ) {
		$ssin = "%7.2lf "; $ssout = "%7.2lf "; $ssext = "%7.2lf";
	} else {
		$ssin = "%6.2lf %s"; $ssout = "%6.2lf %s"; $ssext = "%6.2lf %s";
	}
	if( defined $config{'routers.cgi-legendunits'}
		and $config{'routers.cgi-legendunits'} =~ /y/i ) {
		$ssin .= $escunit; $ssout .= $escunit2;
	}
	$sin .= $ssin; $sout .= $ssout;
	if( $interfaces{$interface}{mode} eq "SERVER"
		and $interface eq "CPU" ) {
		$sin = "usr\\:%6.2lf%%"; $sout = "sys\\:%6.2lf%%"; 
		$sext = "wa\\: %6.2lf%%"; 
		$ssin = $ssout = $ssext = "%6.2lf%%"; 
	}

	return ( $sin,$sout,$sext, $ssin,$ssout,$ssext );
}

sub usr_params(@)
{
	my($ds0,$ds1,$mds0,$mds1);
	my($lin, $lout);
	my($dwmy,$interface) = @_;
	my($ssin, $ssout, $sin, $sout, $sext, $ssext);
	my($l,$defrrd, $curif);
	my($legendi,$legendo);
	my(@clr,$ifcnt, $c, $escunit);
	my($totindef,$totoutdef,$incnt, $outcnt);
	my($totin,$totout) = ("totin","totout");
	my($stacking) = 0;
	my($mirroring) = 0;
	my($max1, $max2);
	my($greydef) = "0"; # extra RPN is added if necessary
	my($havepeaks) = 0;
	my($workday) = 0;
#	my($timezone) = 0; # use the global
	my(@wdparams) = ();
	my($maxlbl,$avglbl,$curlbl,$lastlbl) = ('Max','Avg','Cur','Last');
	my($gmaxlbl,$gavglbl,$gcurlbl,$glastlbl);
	my(@extraparams) = ();
	my($titlemaxlen) = 128;
	my($daemonsuffix) = "";
	my(@sorted);
	my($leglen) = 0; # length of legends

	if($rrdcached) {
		$daemonsuffix = "daemon=$rrdcached";
		$daemonsuffix =~ s/:/\\:/g;
		$daemonsuffix = ":$daemonsuffix";
	}

	$titlemaxlen = $config{'routers.cgi-maxtitle'}?$config{'routers.cgi-maxtitle'}:128;

	$maxlbl = langmsg(2200,$maxlbl); $avglbl = langmsg(2201,$avglbl);
	$curlbl = langmsg(2202,$curlbl); $lastlbl = langmsg(2203,$lastlbl);
	$gmaxlbl = langmsg(6200,$maxlbl); $gavglbl = langmsg(6201,$avglbl);
	$gcurlbl = langmsg(6202,$curlbl); $glastlbl = langmsg(6203,$lastlbl);

	if( defined $config{'routers.cgi-daystart'} 
		and defined $config{'routers.cgi-dayend'}
		and $config{'routers.cgi-daystart'}<$config{'routers.cgi-dayend'}
		and $dwmy !~ /y/ ){
		$workday = 1;
	}

	# stacking?
	if( defined $interfaces{$interface}{graphstyle}
		and $interfaces{$interface}{graphstyle} =~ /stack/i ) { 
		$stacking = 1; # first is AREA, then STACK
	}
	if( defined $interfaces{$interface}{graphstyle}
		and $interfaces{$interface}{graphstyle} =~ /mirror/i ) { 
		$mirroring = 1; 
	}
	# identify colours
	if( defined $interfaces{$interface}{colours} ) {
		@clr = @{$interfaces{$interface}{colours}};
	}
	if(! @clr ) {
		if( $gstyle =~ /b/ ) {
		@clr = ( "#000000","#888888","#cccccc","#dddddd","#666666","#444444",
		"#222222", "#aaaaaa", "#eeeeee", "#bbbbbb", "#555555", "#333333" );
		} else {
		@clr = ( "#0000ff","#00ff00","#ff0000","#00cccc","#cccc00","#cc00cc",
		"#8800ff", "#88ff00", "#ff8800", "#0088ff", "#ff0088", "#00ff88" );
		}
	}
	$ifcnt = $#{$interfaces{$interface}{targets}};

# Now the workday highlights, if required
	if( $workday ) {
		# note we must have a DS in there even if it is not used
		push @wdparams, "CDEF:wdtest=in1,POP,"
			."TIME,3600,/,$timezone,+,DUP,24,/,7,%,DUP,4,LT,EXC,2,GE,+,2,LT,"
			."EXC,24,%,DUP,"
			.trim($config{'routers.cgi-daystart'}).",GE,EXC,"
			.trim($config{'routers.cgi-dayend'}).",LT,+,2,EQ,1,"
			."0,IF,0,IF"; # Set to 1 if in working day
		# mark the working day background, if not in b&w mode
		if( $gstyle !~ /b/ ) {
			push @wdparams, "CDEF:wd=wdtest,INF,0,IF", "AREA:wd#ffffcc";
			push @wdparams, "CDEF:mwd=wd,-1,*", "AREA:mwd#ffffcc" ;
#				if($mirroring);
		}
	}

	while( $#clr < $ifcnt ) { push @clr, @clr; }

	$totindef = "CDEF:$totin=0"; $totoutdef = "CDEF:$totout=0";
	$ifcnt = 0; $incnt = $outcnt = 0;

	if( $interfaces{$interface}{sortby} ) {
		@sorted = sorttargets($interface,$dwmy,$interfaces{$interface}{sortby});
	} else {
		@sorted = @{$interfaces{$interface}{targets}};
	}
	
	foreach $curif ( @sorted ) {
		if(!$interfaces{$interface}{noo} and !$interfaces{$curif}{noo}) {
			my $olen = length $interfaces{$curif}{legendo};
			$leglen = $olen if($olen > $leglen);
		}
		if(!$interfaces{$interface}{noi} and !$interfaces{$curif}{noi}) {
			my $ilen = length $interfaces{$curif}{legendi};
			$leglen = $ilen if($ilen > $leglen);
		}
	}
	$leglen = 20 if($leglen > 20); # sanity check

	###################################################
	# MAIN LOOP THROUGH COMPONENT TARGETS STARTS HERE #
	###################################################
	foreach $curif ( @sorted ) {
		# loop through all interfaces	

		if($interfaces{$interface}{active}) {
			next if(!isactive($curif));
		}
		$ifcnt++;

	$defrrd = $interfaces{$curif}{rrd};
	$defrrd =~ s/:/\\:/g;
	if($rrdcached and $rrdcached!~/^unix:/) {
		my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
		$defrrd =~ s/^$pth\/*//;
	}

#	$debugmessage .= "RRD: $defrrd\n";

	($sin,$sout,$sext ,$ssin,$ssout,$ssext) = sinout($curif,$interface,$leglen);

	if ( $dwmy =~ /s/ ) {
		$lin=""; $lout="";
	} else {
		$lin = langmsg(6405,"Inbound"); $lout = langmsg(6406,"Outbound");
		$lin = $interfaces{$curif}{legend1}
			if( defined $interfaces{$curif}{legend1} );
		$lout = $interfaces{$curif}{legend2}
			if( defined $interfaces{$curif}{legend2} );
		if( $interfaces{$interface}{noo} or $interfaces{$interface}{noi} ) {
			$lin = $interfaces{$curif}{desc}." ($lin)"
				if($lin ne $interfaces{$curif}{desc});
			$lout= $interfaces{$curif}{desc}." ($lout)"
				if($lout ne $interfaces{$curif}{desc});
		}
		$lin =~ s/:/\\:/g; $lout=~ s/:/\\:/g;
		$lin = ':'.$lin; $lout = ':'.$lout;
		if($interfaces{$interface}{noo} or $interfaces{$curif}{noo}) {
 			$lin .= "\\l" 
		} else { $lout .= "\\l"; }
	}
	$lin = substr( $lin."                                ",0,30 ) 
		if($lin and !$interfaces{$interface}{noo} and !$interfaces{$curif}{noo});

	if( $interfaces{$interface}{nolegend} or
		$interfaces{$interface}{nodetails} ) {
		$lin = $lout = "";
	}

	($ds0, $ds1) = ("ds0", "ds1");
	push @params,
		"DEF:in$ifcnt=".$defrrd.":$ds0:"
		.($interfaces{$interface}{cf}?$interfaces{$interface}{cf}:"AVERAGE")
		.$daemonsuffix, 
		"DEF:out$ifcnt=".$defrrd.":$ds1:"
		.($interfaces{$interface}{cf}?$interfaces{$interface}{cf}:"AVERAGE")
		.$daemonsuffix;
	($ds0, $ds1) = ("in$ifcnt", "out$ifcnt");

	# Now for unknasprev
	if( $interfaces{$curif}{unknasprev} 
		or $interfaces{$interface}{unknasprev} ) {
		if($RRDs::VERSION >= 1.00039 ) {
			push @params,
				"CDEF:unpin$ifcnt=$ds0,UN,PREV,$ds0,IF", 
				"CDEF:unpout$ifcnt=$ds1,UN,PREV,$ds1,IF";
			($ds0, $ds1) = ("unpin$ifcnt", "unpout$ifcnt");
		}
	}
	# Now for unknaszero
	elsif( $interfaces{$curif}{unknaszero}
		or  $interfaces{$interface}{unknaszero} ) {
		push @params,
			"CDEF:unin$ifcnt=$ds0,UN,0,$ds0,IF", 
			"CDEF:unout$ifcnt=$ds1,UN,0,$ds1,IF";
		($ds0, $ds1) = ("unin$ifcnt", "unout$ifcnt");
	} else {
		if($RRDs::VERSION >= 1.00039 ) {
			my($step) = $routers{$router}{interval};
			if($step) { $step *= 60; } else { $step = 300; }
			push @params,
				"CDEF:unxin$ifcnt=NOW,TIME,-,$step,LT,$ds0,UN,+,2,EQ,PREV,$ds0,IF", 
				"CDEF:unxout$ifcnt=NOW,TIME,-,$step,LT,$ds1,UN,+,2,EQ,PREV,$ds1,IF";
			($ds0, $ds1) = ("unxin$ifcnt", "unxout$ifcnt");
		}
	}

	# Needs to be here because ds1 must be defined
	push @params, @wdparams if($workday and ($ifcnt == 1));

### do this if we are using BITS
	if( $interfaces{$curif}{mult} and ($interfaces{$curif}{mult} != 1) ) {
		push @params, "CDEF:fin$ifcnt=$ds0,".$interfaces{$curif}{mult}.",*", 
			"CDEF:fout$ifcnt=$ds1,".$interfaces{$curif}{mult}.",*";
		($ds0, $ds1) = ("fin$ifcnt", "fout$ifcnt");
	}
	if( $interfaces{$curif}{factor} and $interfaces{$curif}{factor}!=1) {
		push @params, "CDEF:ffin$ifcnt=$ds0,".$interfaces{$curif}{factor}.",*", 
			"CDEF:ffout$ifcnt=$ds1,".$interfaces{$curif}{factor}.",*";
		($ds0, $ds1) = ("ffin$ifcnt", "ffout$ifcnt");
	}
	if( $interfaces{$interface}{factor} 
		and $interfaces{$interface}{factor}!=1) {
		push @params, "CDEF:ffinx$ifcnt=$ds0,".$interfaces{$interface}{factor}.",*", 
			"CDEF:ffoutx$ifcnt=$ds1,".$interfaces{$interface}{factor}.",*";
		($ds0, $ds1) = ("ffinx$ifcnt", "ffoutx$ifcnt");
	}
	if( $interfaces{$curif}{c2fi} ) {
		push @params, "CDEF:c2fin$ifcnt=$ds0,1.8,*,32,+"; 
		$ds0 = "c2fin$ifcnt";
	}
	if( $interfaces{$curif}{c2fo} ) {
		push @params, "CDEF:c2fout$ifcnt=$ds1,1.8,*,32,+"; 
		$ds1 = "c2fout$ifcnt";
	}

	# For later referral by userdefined calculations
	$interfaces{$curif}{ds0} = $ds0;
	$interfaces{$curif}{ds1} = $ds1;

	if(!$interfaces{$curif}{noi} ) { 
		if($RRDs::VERSION < 1.00039 ) {
			$totindef .= ",$ds0,UN,0,$ds0,IF,+";  
		} else {
#			$totindef .= ",$ds0,DUP,UN,EXC,PREV($ds0),DUP,UN,EXC,0,EXC,IF,EXC,IF,+";
			$totindef .= ",NOW,TIME,-,300,LT,$ds0,UN,+,2,EQ,PREV($ds0),DUP,UN,EXC,0,EXC,IF,$ds0,IF,+";
		}
		$incnt++;
		if( !$interfaces{$curif}{unknasprev} 
			and !$interfaces{$interface}{unknasprev} 
			and !$interfaces{$curif}{unknaszero} ) {
			$greydef .= ",in$ifcnt,UN,+"; 
		}
	}
	if(!$interfaces{$curif}{noo} ) { 
		if($RRDs::VERSION < 1.00039 ) {
			$totoutdef .= ",$ds1,UN,0,$ds1,IF,+"; 
		} else {
#			$totoutdef.= ",$ds1,DUP,UN,EXC,PREV($ds1),DUP,UN,EXC,0,EXC,IF,EXC,IF,+";
			$totoutdef .= ",NOW,TIME,-,300,LT,$ds1,UN,+,2,EQ,PREV($ds1),DUP,UN,EXC,0,EXC,IF,$ds1,IF,+";
		}
		$outcnt++;  
		if( !$interfaces{$curif}{unknasprev} 
			and !$interfaces{$interface}{unknasprev} 
			and !$interfaces{$curif}{unknaszero} ) {
			$greydef .= ",out$ifcnt,UN,+"; 
		}
	}
#	now for the peaks stuff
	($mds0, $mds1) = ("ds0", "ds1");
	push @params,
		"DEF:min$ifcnt=".$defrrd.":$mds0:MAX".$daemonsuffix
			.(($RRDs::VERSION >= 1.4)?":reduce=MAX":""), 
		"DEF:mout$ifcnt=".$defrrd.":$mds1:MAX".$daemonsuffix
			.(($RRDs::VERSION >= 1.4)?":reduce=MAX":"");
	($mds0, $mds1) = ("min$ifcnt", "mout$ifcnt");
### Do this if we are using BITS
	if( $interfaces{$curif}{mult} ne 1 ) {
		push @params, "CDEF:fmin$ifcnt=$mds0,".$interfaces{$curif}{mult}.",*", 
			"CDEF:fmout$ifcnt=$mds1,".$interfaces{$curif}{mult}.",*";
		($mds0, $mds1) = ("fmin$ifcnt", "fmout$ifcnt");
	}
	if( $interfaces{$curif}{factor} and $interfaces{$curif}{factor}!=1) {
		push @params,"CDEF:ffmin$ifcnt=$mds0,"
				.$interfaces{$curif}{factor}.",*", 
			"CDEF:ffmout$ifcnt=$mds1,".$interfaces{$curif}{factor}.",*";
		($mds0, $mds1) = ("ffmin$ifcnt", "ffmout$ifcnt");
	}
	if( $interfaces{$interface}{factor} and $interfaces{$interface}{factor}!=1 ) {
		push @params,"CDEF:ffminx$ifcnt=$mds0,"
				.$interfaces{$interface}{factor}.",*", 
			"CDEF:ffmoutx$ifcnt=$mds1,".$interfaces{$interface}{factor}.",*";
		($mds0, $mds1) = ("ffminx$ifcnt", "ffmoutx$ifcnt");
	}
	if( $interfaces{$curif}{c2fi} ) {
		push @params, "CDEF:mc2fin$ifcnt=$mds0,1.8,*,32,+"; 
		$mds0 = "mc2fin$ifcnt";
	}
	if( $interfaces{$curif}{c2fo} ) {
		push @params, "CDEF:mc2fout$ifcnt=$mds1,1.8,*,32,+"; 
		$mds1 = "mc2fout$ifcnt";
	}

	# For later referral by userdefined calculations
	$interfaces{$curif}{mds0} = $mds0;
	$interfaces{$curif}{mds1} = $mds1;
###
# And the percentages
	$max1 = $max2 = $interfaces{$curif}{max};
	$max1 = $interfaces{$curif}{max1} if(defined $interfaces{$curif}{max1});
	$max2 = $interfaces{$curif}{max2} if(defined $interfaces{$curif}{max2});
	if( $max1 && $dwmy !~ /s/ ) {
		push @params,
			"CDEF:pcin$ifcnt=$ds0,100,*,".$max1.",/",
			"CDEF:mpcin$ifcnt=$mds0,100,*,".$max1.",/";
	}
	if( $max2 && $dwmy !~ /s/ ) {
		push @params,
			"CDEF:pcout$ifcnt=$ds1,100,*,".$max2.",/",
			"CDEF:mpcout$ifcnt=$mds1,100,*,".$max2.",/";
	}

	# For scaleshift
	if( defined $interfaces{$interface}{scaleshift}
		and ($RRDs::VERSION >= 1.3) ) {
		if(!$interfaces{$interface}{altscale} or $interfaces{$curif}{altscale}){
			push @params, 
				"CDEF:x$ds1=$ds1,"
					.$interfaces{$interface}{shift}.",-,"
					.$interfaces{$interface}{scale}.",/";
#				"CDEF:x$mds1=$mds1,".$interfaces{$interface}{scale}.",/,"
#					.$interfaces{$interface}{shift}.",-"; 
		} else {
			push @params, "CDEF:x$ds1=$ds1";
#				, "CDEF:x$mds1=$mds1";
		}
		if($interfaces{$interface}{altscale} and $interfaces{$curif}{altscale}){
			push @params, 
				"CDEF:x$ds0=$ds0,"
					.$interfaces{$interface}{shift}.",-,"
					.$interfaces{$interface}{scale}.",/";
#				"CDEF:x$mds0=$mds0,".$interfaces{$interface}{scale}.",/,"
#					.$interfaces{$interface}{shift}.",-"; 
		} else {
			push @params, "CDEF:x$ds0=$ds0";
#				, "CDEF:x$mds0=$mds0";
		}
	} else {
		push @params, "CDEF:x$ds1=$ds1";
#			, "CDEF:x$mds1=$mds1";
		push @params, "CDEF:x$ds0=$ds0";
#			, "CDEF:x$mds0=$mds0";
	}

	if($mirroring and $lin and $lout ) {
		$lout = "";
		$lin = $interfaces{$curif}{desc}; 
		$lin = substr($lin,0,$titlemaxlen) if(length($lin)>$titlemaxlen);
		$lin =~ s/:/\\:/g;
		$lin = ":$lin\\l";
	} else {
		if( !$interfaces{$interface}{nolegend} and 
			!$interfaces{$interface}{nodetails} and 
			!$interfaces{$interface}{nodesc} and 
			$dwmy !~ /s/ and
			!$interfaces{$interface}{noi} and 
			!$interfaces{$interface}{noo}) {
				my($tmpt) = $interfaces{$curif}{desc};
				$tmpt = substr($tmpt,0,$titlemaxlen) 
					if(length($tmpt)>$titlemaxlen);
				push @params, "COMMENT:".decolon("$tmpt:\\l");
		}
	}
	if(! $interfaces{$interface}{nolines} ) {
	$c="";
	if(!$interfaces{$interface}{noi} and !$interfaces{$curif}{noi}) {
		$c = shift @clr; push @clr, $c;
		if( !$stacking ) {
			push @params, "LINE$linewidth:x$ds0$c$lin" ;
		} elsif( $stacking > 1 ) {
			push @params, "STACK:$ds0$c$lin" ;
		} else {
			push @params, "AREA:$ds0$c$lin" ;
			$stacking = 2;
		}
	}
	if(!$interfaces{$interface}{noo} and !$interfaces{$curif}{noo}) {
		my($tmpds) = $ds1;
		$c = "" if( $c and !$mirroring );
		if(!$c) { $c = shift @clr; push @clr, $c; }
		if($mirroring) {
			push @params, "CDEF:mirror$ifcnt=$ds1,-1,*";
			$tmpds = "mirror$ifcnt";
		} elsif(!$stacking) { $tmpds = "x$ds1"; }
		if( !$stacking ) {
			push @params, "LINE$linewidth:$tmpds$c$lout" ;
		} elsif($mirroring) {
			if(@extraparams) {
				push @extraparams, "STACK:$tmpds$c$lout";
			} else {
				push @extraparams, "AREA:$tmpds$c$lout";
			}
		} elsif( $stacking > 1 ) {
			push @params, "STACK:$tmpds$c$lout";
		} else {
			push @params, "AREA:$tmpds$c$lout";
			$stacking = 2;
		}
	}
	} # nolines

#	now for the labels at the bottom
	if( !$interfaces{$interface}{nolegend} and
		!$interfaces{$interface}{nodetails} ) {
	if( $dwmy !~ /s/ ) {
		if( $max1 ) {
			if(!$interfaces{$interface}{noi}
				and !$interfaces{$curif}{noi}) {
				push @params, "GPRINT:$mds0:MAX:$gmaxlbl $sin\\g" ;
				push @params ,"GPRINT:mpcin$ifcnt:MAX: (%2.0lf%%)\\g"
					if($interfaces{$curif}{percent});
				push @params,"GPRINT:$ds0:AVERAGE:  $gavglbl $sin\\g" ;
				push @params ,"GPRINT:pcin$ifcnt:AVERAGE: (%2.0lf%%)\\g"
					if($interfaces{$curif}{percent});
				push @params,"GPRINT:$ds0:LAST:  $gcurlbl $sin\\g" ;
				push @params ,"GPRINT:pcin$ifcnt:LAST: (%2.0lf%%)\\g"
					if($interfaces{$curif}{percent});
				push @params, "COMMENT:\\l" ;
			}
			if(!$interfaces{$interface}{noo}
				and !$interfaces{$curif}{noo}) {
				push @params, "GPRINT:$mds1:MAX:$gmaxlbl $sout\\g" ;
				push @params ,"GPRINT:mpcout$ifcnt:MAX: (%2.0lf%%)\\g"
					if($interfaces{$curif}{percent});
				push @params,"GPRINT:$ds1:AVERAGE:  $gavglbl $sout\\g" ;
				push @params ,"GPRINT:pcout$ifcnt:AVERAGE: (%2.0lf%%)\\g"
					if($interfaces{$curif}{percent});
				push @params,"GPRINT:$ds1:LAST:  $gcurlbl $sout\\g" ;
				push @params ,"GPRINT:pcout$ifcnt:LAST: (%2.0lf%%)\\g"
					if($interfaces{$curif}{percent});
				push @params, "COMMENT:\\l" ;
			}
		} else {
			push @params,
			"GPRINT:$mds0:MAX:$gmaxlbl $sin\\g",
			"GPRINT:$ds0:AVERAGE:  $gavglbl $sin\\g",
			"GPRINT:$ds0:LAST:  $gcurlbl $sin\\l" 
					if(!$interfaces{$interface}{noi}
						and !$interfaces{$curif}{noi});
			push @params,
			"GPRINT:$mds1:MAX:$gmaxlbl $sout\\g",
			"GPRINT:$ds1:AVERAGE:  $gavglbl $sout\\g",
			"GPRINT:$ds1:LAST:  $gcurlbl $sout\\l"
					if(!$interfaces{$interface}{noo}
						and !$interfaces{$curif}{noo});
		}
	} else {
		($legendi,$legendo)=(langmsg(2204,"IN:"),langmsg(2205,"OUT:"));
		$legendi = $interfaces{$curif}{legendi} if(defined $interfaces{$curif}{legendi});
		$legendo = $interfaces{$curif}{legendo} if(defined $interfaces{$curif}{legendo});
		if( $interfaces{$interface}{overridelegend}
			and $interfaces{$curif}{shdesc}
			and ( $interfaces{$interface}{noo} or $interfaces{$interface}{noi} 
			or  $interfaces{$curif}{noo} or $interfaces{$curif}{noi} )
		) {
			$legendi = $legendo = $interfaces{$curif}{shdesc}.':';
		}
		$legendi =~ s/:/\\:/g; $legendo =~ s/:/\\:/g;
		$legendi =~ s/%/%%/g; $legendo =~ s/%/%%/g;
		
#		my $meurlfullesc = $meurlfull;
#		$meurlfullesc =~ s/:/\\:/g;
		push @params,
#			"PRINT:$mds0:MAX:".$q->a({href=>"$meurlfullesc?"
#					.optionstring({if=>$curif})},
#				$q->b($legendi))." $maxlbl $ssin, ",
			"PRINT:$mds0:MAX:".$q->b($legendi)." $maxlbl $ssin, ",
			"PRINT:$ds0:AVERAGE:$avglbl $ssin, ",
			"PRINT:$ds0:LAST:$lastlbl $ssin ".$q->br
					if(!$interfaces{$interface}{noi}
						and !$interfaces{$curif}{noi});
		push @params,
#			"PRINT:$mds1:MAX:".$q->a({href=>"$meurlfullesc?"
#					.optionstring({if=>$curif})},
#				$q->b($legendo))." $maxlbl $ssout, ",
			"PRINT:$mds1:MAX:".$q->b($legendo)." $maxlbl $ssout, ",
			"PRINT:$ds1:AVERAGE:$avglbl $ssout, ",
			"PRINT:$ds1:LAST:$lastlbl $ssout ".$q->br
					if(!$interfaces{$interface}{noo}
						and !$interfaces{$curif}{noo});
	} # s mode
	} # not nolegend mode
	} # end of loop through interfaces

	# Add onto the end extra interface stuff (for mirroring mainly)
	push @params, @extraparams;

	# add total line(s) if necessary
	if($interfaces{$interface}{withtotal} 
		or $interfaces{$interface}{withaverage} ) {
		push @params, $totindef if(!$interfaces{$interface}{noi} and $incnt);
		push @params, $totoutdef if(!$interfaces{$interface}{noo} and $outcnt);
		if($interfaces{$interface}{nogroup} and $incnt and $outcnt) {
			push @params,"CDEF:totinout=$totin,$totout,+";
			$incnt += $outcnt;
			$outcnt = 0;
			($totin,$totout) = ("totinout","");
		}
		if(!$interfaces{$interface}{noo} and $outcnt) {
			if($interfaces{$interface}{scaleshift} 
				and !$interfaces{$interface}{altscale}) {
				push @params,
					"CDEF:x$totout=$totout,"
					.$interfaces{$interface}{shift}.",-,"
					.$interfaces{$interface}{scale}.",/";
			} else {
				push @params,"CDEF:x$totout=$totout" ;
			}
		}
		($sin,$sout,$sext ,$ssin,$ssout,$ssext) = sinout($interface,0);
		$lin = langmsg(6100,"Total")." ".$interfaces{$interface}{legend1}; 
		$lin = $interfaces{$interface}{legendti} 
			if($interfaces{$interface}{legendti});
		$lin = substr($lin.'                          ',0,30);
		if($interfaces{$interface}{noo} or !$outcnt) { $lin .= "\\l"; } 
		$lout = langmsg(6100,"Total")." ".$interfaces{$interface}{legend2}."\\l";
		$lout = $interfaces{$interface}{legendto}."\\l"
			if($interfaces{$interface}{legendto});
		$lin =~ s/:/\\:/g; $lout=~ s/:/\\:/g;
		$lin = ':'.$lin if($lin); $lout = ':'.$lout if($lout);
		if($interfaces{$interface}{withtotal} ) {
			if($interfaces{$interface}{nolegend} or $dwmy =~ /s/ ) {
				$lin = $lout = "";
			} elsif($mirroring) {
				$lout = "";
				$lin = langmsg(6101,"Total values"); $lin =~ s/:/\\:/g;
				$lin = ":$lin\\l";
			} else {
				push @params, "COMMENT:"
					.decolon(langmsg(6101,"Total values").":\\l")
					if(!$interfaces{$interface}{noi} 
						and !$interfaces{$interface}{noo}
						and !$interfaces{$interface}{nodesc} 
						and !$interfaces{$interface}{nodetails});
			}
			$c = "";
			if(!$interfaces{$interface}{noi} and $incnt ) {
				$c = shift @clr; push @clr, $c;
				push @params, "LINE$linewidth:$totin$c$lin";
			}
			if(!$interfaces{$interface}{noo} and $outcnt ) {
				$c = "" if( $c and !$mirroring );
				if(!$c) { $c = shift @clr; push @clr, $c;}
				if($mirroring) {
					push @params, "CDEF:mtotout=$totout,-1,*";
					push @params, "LINE$linewidth:mtotout$c$lout";
				} else {
					push @params, "LINE$linewidth:x$totout$c$lout";
				}
			}
			if( $dwmy !~ /s/ ) {
				if(!$interfaces{$interface}{nolegend} ) {
				push @params,
				"GPRINT:$totin:MAX:$gmaxlbl $sin\\g",
				"GPRINT:$totin:AVERAGE:  $gavglbl $sin\\g",
				"GPRINT:$totin:LAST:  $gcurlbl $sin\\l" 
					if(!$interfaces{$interface}{noi} and $incnt);
				push @params,
				"GPRINT:$totout:MAX:$gmaxlbl $sout\\g",
				"GPRINT:$totout:AVERAGE:  $gavglbl $sout\\g",
				"GPRINT:$totout:LAST:  $gcurlbl $sout\\l"
					if(!$interfaces{$interface}{noo} and $outcnt);
				}
			} else {
				($legendi,$legendo)=(langmsg(2204,"IN:"),langmsg(2205,"OUT:"));
				$legendi = $interfaces{$interface}{legendi} 
					if(defined $interfaces{$interface}{legendi});
				$legendo = $interfaces{$interface}{legendo} 
					if(defined $interfaces{$interface}{legendo});

				$legendi =~ s/:/\\:/g;
				$legendo =~ s/:/\\:/g;
				push @params,
					"PRINT:$totin:MAX:".$q->b(langmsg(2100,"Total")."\\:")." $maxlbl $ssin, ",
					"PRINT:$totin:AVERAGE:$avglbl $ssin, ",
					"PRINT:$totin:LAST:$lastlbl $ssin ".$q->br
							if(!$interfaces{$interface}{noi} and $incnt);
				push @params,
					"PRINT:$totout:MAX:".$q->b(langmsg(2100,"Total")."\\:")." $maxlbl $ssout, ",
					"PRINT:$totout:AVERAGE:$avglbl $ssout, ",
					"PRINT:$totout:LAST:$lastlbl $ssout ".$q->br
							if(!$interfaces{$interface}{noo} and $outcnt);
			}
		}
	}

	# add average line if necessary
	if($interfaces{$interface}{withaverage} ) {
		# set avg to UNKN if we're in greyout, IE we have no data.
		push @params,"CDEF:avgin=$greydef,$incnt,$outcnt,+,EQ,UNKN,$totin,$incnt,/,IF"
			if(!$interfaces{$interface}{noi} and $incnt);
		if(!$interfaces{$interface}{noo} and $outcnt) {
			push @params,
				"CDEF:avgout=$greydef,$incnt,$outcnt,+,EQ,UNKN,$totout,$outcnt,/,IF";
			if($interfaces{$interface}{scaleshift} 
				and !$interfaces{$interface}{altscale}) {
				push @params,
					"CDEF:xavgout=avgout,"
					.$interfaces{$interface}{shift}.",-,"
					.$interfaces{$interface}{scale}.",/";
			} else {
				push @params,"CDEF:xavgout=avgout" ;
			}
		}
		$lin = "Average ".$interfaces{$interface}{legend1}; 
		$lin = $interfaces{$interface}{legendai} 
			if($interfaces{$interface}{legendai});
		$lin = substr($lin.'                          ',0,30);
		$lout= "Average ".$interfaces{$interface}{legend2}."\\l";
		if($interfaces{$interface}{noo} or !$outcnt){ $lin .= "\\l"; } 
		$lout = $interfaces{$interface}{legendao}."\\l"
			if($interfaces{$interface}{legendao});
		$lin =~ s/:/\\:/g; $lout=~ s/:/\\:/g;
		$lin = ':'.$lin if($lin); $lout = ':'.$lout if($lout);
		if($interfaces{$interface}{nolegend} or $dwmy=~ /s/ ) {
			$lin = $lout = "";
		} elsif($mirroring) {
			$lout = "";
			$lin = langmsg(6901,"Average values"); $lin =~ s/:/\\:/g;
			$lin = ":$lin\\l";
		} else {
			push @params, "COMMENT:"
				.decolon(langmsg(6901,"Average values").":\\l")
				if(!$interfaces{$interface}{noi} 
					and !$interfaces{$interface}{noo}
					and !$interfaces{$interface}{nodesc} 
					and !$interfaces{$interface}{nodetails});
		}
		$c = "";
		if(!$interfaces{$interface}{noi} and $incnt) {
			$c = shift @clr; push @clr, $c;
			push @params, "LINE$linewidth:avgin$c$lin";
		}
		if(!$interfaces{$interface}{noo} and $outcnt) {
			$c = "" if( $c and !$mirroring );
			if(!$c) { $c = shift @clr; push @clr, $c;}
			if($mirroring) {
				push @params, "CDEF:mavgout=avgout,-1,*";
				push @params, "LINE$linewidth:mavgout$c$lout";
			} else {
				push @params, "LINE$linewidth:xavgout$c$lout";
			}
		}
		if( $dwmy !~ /s/ ) {
			if(!$interfaces{$interface}{nolegend} ) {
				push @params,
				"GPRINT:avgin:MAX:$gmaxlbl $sin\\g",
				"GPRINT:avgin:AVERAGE:  $gavglbl $sin\\g",
				"GPRINT:avgin:LAST:  $gcurlbl $sin\\l" 
					if(!$interfaces{$interface}{noi} and $incnt);
				push @params,
				"GPRINT:avgout:MAX:$gmaxlbl $sout\\g",
				"GPRINT:avgout:AVERAGE:  $gavglbl $sout\\g",
				"GPRINT:avgout:LAST:  $gcurlbl $sout\\l"
					if(!$interfaces{$interface}{noo} and $outcnt);
			}
		} else {
			($legendi,$legendo)=(langmsg(2204,"IN:"),langmsg(2205,"OUT:"));
			$legendi = $interfaces{$interface}{legendi} 
				if(defined $interfaces{$interface}{legendi});
			$legendo = $interfaces{$interface}{legendo} 
				if(defined $interfaces{$interface}{legendo});
			$legendi =~ s/:/\\:/g;
			$legendo =~ s/:/\\:/g;
			push @params,
				"PRINT:avgin:MAX:".$q->b("$avglbl\\:")." $maxlbl $ssin, ",
				"PRINT:avgin:AVERAGE:$avglbl $ssin, ",
				"PRINT:avgin:LAST:$lastlbl $ssin ".$q->br
						if(!$interfaces{$interface}{noi} and $incnt);
			push @params,
				"PRINT:avgout:MAX:".$q->b("$avglbl\\:")." $maxlbl $ssout, ",
				"PRINT:avgout:AVERAGE:$avglbl $ssout, ",
				"PRINT:avgout:LAST:$lastlbl $ssout ".$q->br
						if(!$interfaces{$interface}{noo} and $outcnt);
		} # small graph
	} # with average line
	
	# if there were no lines AT ALL, we need to add a dummy one else
	# RRDtool gets unhappy
	if(!$ifcnt or (!$incnt and !$outcnt)) {
		my($t) = $interfaces{$interface}{targets}[0];
		$greydef = "x,x,-"; # this is 'positive' but zero to trigger next sec
		$defrrd = $interfaces{$t}{rrd};
		$defrrd =~ s/:/\\:/g;
		if($daemonsuffix) {
			my($pth) = $config{'routers.cgi-dbpath'};
			$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
			$defrrd =~ s/$pth\/*//;
		}
		push @params, "DEF:x=$defrrd:ds0:AVERAGE".$daemonsuffix;
		$ifcnt = $incnt = $outcnt = 0; # just in case
#		$debugmessage .= "Dummy target = $t\nDummy RRD = $defrrd\n";
	}

	# Greyout if no data at all.
	if($greydef) { 
		$greydef = "CDEF:greyout=$greydef,$incnt,$outcnt,+,EQ,INF,0,IF";
		push @params, $greydef, "AREA:greyout#d0d0d0";
		if( !$interfaces{$interface}{unknasprev} 
		    and !$interfaces{$interface}{unknazero}) {
			$greydef = "CDEF:mgreyout=greyout,-1,*";
			push @params, $greydef, "AREA:mgreyout#d0d0d0";
			push @params, "HRULE:0#000000"; # redraw axis
		}
	}
	
} # usr_params

sub rtr_params(@)
{
	my($ds0,$ds1,$ds2,$mds0,$mds1, $mds2)=("","","","","","");
	my($lin, $lout, $mlin, $mlout, $lextra);
	my($dwmy,$interface) = @_;
	my($ssin, $ssout, $sin, $sout, $ssext, $sext);
	my($l,$defrrd);
	my($workday) = 0;
	my($legendi,$legendo, $legendx);
	my(@clr, $escunit);
	my($max1, $max2);
	my($havepeaks) = 0;
	my($graphstyle) = "";
	my($maxlbl,$avglbl,$curlbl,$lastlbl) = ('Max','Avg','Cur','Last');
	my($gmaxlbl,$gavglbl,$gcurlbl,$glastlbl);
	my($cf) = "AVERAGE";
	my($daemonsuffix) = "";

	if($rrdcached) {
		$daemonsuffix = "daemon=$rrdcached";
		$daemonsuffix =~ s/:/\\:/g;
		$daemonsuffix = ":$daemonsuffix";
	}

	$maxlbl = langmsg(2200,$maxlbl); $avglbl = langmsg(2201,$avglbl);
	$curlbl = langmsg(2202,$curlbl); $lastlbl = langmsg(2203,$lastlbl);
	$gmaxlbl = langmsg(6200,$maxlbl); $gavglbl = langmsg(6201,$avglbl);
	$gcurlbl = langmsg(6202,$curlbl); $glastlbl = langmsg(6203,$lastlbl);

	$graphstyle = lc $interfaces{$interface}{graphstyle} 
		if( $interfaces{$interface}{graphstyle} );
	# are we going to add peak lines on this graph?
	if($graphstyle !~ /stack/ ) {
		if(!defined $config{'routers.cgi-withpeak'} 
			or $config{'routers.cgi-withpeak'} =~ /y/i ) {
			if( $dwmy =~ /[wmy]/ or ( $dwmy =~ /d/ and $usesixhour )) {
				my($pat) = '';
				if( defined $interfaces{$interface}{withpeak} ) {
					$pat = '[a'.$interfaces{$interface}{withpeak}.']';
					$havepeaks = 1 if( $dwmy =~ /$pat/i );
				} else { $havepeaks = 1; }
			}
		}
	}

	# are we going to work out the 'working day' averages as well?
	if( defined $config{'routers.cgi-daystart'} 
		and defined $config{'routers.cgi-dayend'}
		and $config{'routers.cgi-daystart'}<$config{'routers.cgi-dayend'}
		and $dwmy !~ /y/ ){
		$workday = 1;
	}

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

	$defrrd = $interfaces{$interface}{rrd};
	$defrrd =~ s/:/\\:/g;
	if($rrdcached and $rrdcached!~/^unix:/) {
		my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
		$defrrd =~ s/^$pth\/*//;
	}

	$debugmessage .= "RRD: $defrrd\n";

	$escunit = $interfaces{$interface}{unit};
	$escunit =~ s/%/%%/g;
	$escunit =~ s/:/\\:/g;
	$escunit =~ s/&nbsp;/ /g;

	($sin,$sout,$sext,$ssin,$ssout,$ssext) = sinout($interface,0);
	
	if ( $dwmy =~ /s/ ) {
		$lin=""; $lout=""; $lextra="";
		$mlin=""; $mlout="";
	} else {
		$lin = langmsg(6405,"Inbound"); $lout = langmsg(6406,"Outbound");
		$mlin = langmsg(6407,"Peak Inbound"); 
		$mlout = langmsg(6408,"Peak Outbound");
		$lin = $interfaces{$interface}{legend1}
			if( defined $interfaces{$interface}{legend1} );
		$lout = $interfaces{$interface}{legend2}
			if( defined $interfaces{$interface}{legend2} );
		$mlin = $interfaces{$interface}{legend3}
			if( defined $interfaces{$interface}{legend3} );
		$mlout = $interfaces{$interface}{legend4}
			if( defined $interfaces{$interface}{legend4} );
		if($interfaces{$interface}{noo} or $havepeaks
			or ( $graphstyle =~ /range/i )) {
				$lin .= "\\l";  
		}
		$lextra = "Other\\l";
		$lextra = $interfaces{$interface}{legend5}."\\l"
			if( defined $interfaces{$interface}{legend5} );
		$lin =~ s/:/\\:/g; $mlin =~ s/:/\\:/g;
		$lout =~ s/:/\\:/g; $mlout =~ s/:/\\:/g;
		$lin = ':'.$lin; $lout = ':'.$lout;
		$mlin = ':'.$mlin; $mlout = ':'.$mlout;
		$lextra = ':'.$lextra;
	}
	$lout .= "\\l" if($lout); 
	$lin = substr( $lin."                                ",0,30 ) 
		if($lin and !$interfaces{$interface}{noo}
			and $lin !~ /\\l$/ );
	$mlout = substr( $mlout."                                ",0,30 ) 
		if ($mlout);
	$mlin = substr( $mlin."                                ",0,30 ) 
		if ($mlin);

	if( $interfaces{$interface}{nolegend} ) { $mlin = $lin = $mlout = $lout = ""; }

	($ds0, $ds1) = ("ds0", "ds1");
	if( $interfaces{$interface}{mode} eq "SERVER" ) {
		($ds0, $ds1, $ds2) = ("user", "system", "wait") if($interface eq "CPU");
		($ds0, $ds1) = ("page", "page") if($interface eq "Page");
		($ds0, $ds1) = ("usercount", "usercount") if($interface eq "Users");
	}
	push @params,
		"DEF:in=".$defrrd.":$ds0:"
		.($interfaces{$interface}{cf}?$interfaces{$interface}{cf}:"AVERAGE")
		.$daemonsuffix, 
		"DEF:out=".$defrrd.":$ds1:"
		.($interfaces{$interface}{cf}?$interfaces{$interface}{cf}:"AVERAGE")
		.$daemonsuffix;
	push @params,
		"DEF:extra=".$defrrd.":$ds2:"
		.($interfaces{$interface}{cf}?$interfaces{$interface}{cf}:"AVERAGE")
		.$daemonsuffix  
			if($ds2);
	($ds0, $ds1) = ("in", "out");
	$ds2 = "extra" if($ds2);
# Try to get around the race condition... This also hides the first UNK point
#	if($RRDs::VERSION >= 1.00039 ) {
#		push @params, 
#			"CDEF:racein=$ds0,UN,PREV($ds0),$ds0,IF",
#			"CDEF:raceout=$ds1,UN,PREV($ds1),$ds1,IF";
#		($ds0, $ds1) = ("racein", "raceout");
#	}
# Now for unknasprev
	if( $interfaces{$interface}{unknasprev} ) {
		if($RRDs::VERSION >= 1.00039 ) {
			push @params,
				"CDEF:unpin=$ds0,UN,PREV,$ds0,IF", 
				"CDEF:unpout=$ds1,UN,PREV,$ds1,IF";
			($ds0, $ds1) = ("unpin", "unpout");
		}
	} elsif( $interfaces{$interface}{unknaszero} ) {
# Now for unknaszero
		push @params,
			"CDEF:unin=$ds0,UN,0,$ds0,IF", 
			"CDEF:unout=$ds1,UN,0,$ds1,IF";
		($ds0, $ds1) = ("unin", "unout");
	} else {
		if($RRDs::VERSION >= 1.00039 ) {
			my($step) = $routers{$router}{interval};
			if($step) { $step *= 60; } else { $step = 300; }
			push @params,
				"CDEF:unxin=NOW,TIME,-,$step,LT,$ds0,UN,+,2,EQ,PREV,$ds0,IF", 
				"CDEF:unxout=NOW,TIME,-,$step,LT,$ds1,UN,+,2,EQ,PREV,$ds1,IF";
			($ds0, $ds1) = ("unxin", "unxout");
		}
	}
	if( $interfaces{$interface}{c2fi} ) {
		push @params, "CDEF:c2fin=$ds0,1.8,*,32,+"; 
		$ds0 = "c2fin";
	}
	if( $interfaces{$interface}{c2fo} ) {
		push @params, "CDEF:c2fout=$ds1,1.8,*,32,+"; 
		$ds1 = "c2fout";
	}
### do this if we are using BITS
	if( $interfaces{$interface}{mult} and ($interfaces{$interface}{mult}!=1) ) {
		push @params, "CDEF:fin=$ds0,".$interfaces{$interface}{mult}.",*", 
			"CDEF:fout=$ds1,".$interfaces{$interface}{mult}.",*";
		($ds0, $ds1) = ("fin", "fout");
	}
###
	if( defined $interfaces{$interface}{factor} and $interfaces{$interface}{factor}!=1 ) {
		push @params, "CDEF:ffin=$ds0,".$interfaces{$interface}{factor}.",*", 
			"CDEF:ffout=$ds1,".$interfaces{$interface}{factor}.",*";
		($ds0, $ds1) = ("ffin", "ffout");
	}
#	now for the peaks stuff
	($mds0, $mds1) = ("ds0", "ds1");
	if( $interfaces{$interface}{mode} eq "SERVER" ) {
		($mds0,$mds1,$mds2) = ("user","system","wait") if($interface eq "CPU");
		($mds0,$mds1) = ("page", "page") if($interface eq "Page");
		($mds0,$mds1) = ("usercount", "usercount") if($interface eq "Users");
	}
	push @params,
		"DEF:min=".$defrrd.":$mds0:MAX".$daemonsuffix 
			.(($RRDs::VERSION >= 1.4)?":reduce=MAX":""), 
		"DEF:mout=".$defrrd.":$mds1:MAX".$daemonsuffix
			.(($RRDs::VERSION >= 1.4)?":reduce=MAX":"");
	($mds0, $mds1) = ("min", "mout");
	if( $interfaces{$interface}{mode} eq "SERVER" and $mds2 ) {
		push @params, "DEF:mx=".$defrrd.":$mds2:MAX".$daemonsuffix
			.(($RRDs::VERSION >= 1.4)?":reduce=MAX":"");
		$mds2 = "mx";
	}
### Do this if we are using BITS
	if( $interfaces{$interface}{mult} and ($interfaces{$interface}{mult}!=1)) {
		push @params, "CDEF:fmin=$mds0,".$interfaces{$interface}{mult}.",*", 
			"CDEF:fmout=$mds1,".$interfaces{$interface}{mult}.",*";
		($mds0, $mds1) = ("fmin", "fmout");
	}
###
	if( defined $interfaces{$interface}{factor} and $interfaces{$interface}{factor}!=1 ) {
		push @params, "CDEF:ffmin=$mds0,".$interfaces{$interface}{factor}.",*", 
			"CDEF:ffmout=$mds1,".$interfaces{$interface}{factor}.",*";
		($mds0, $mds1) = ("ffmin", "ffmout");
	}
	if( $interfaces{$interface}{c2fi} ) {
		push @params, "CDEF:mc2fin=$mds0,1.8,*,32,+"; 
		$mds0 = "mc2fin";
	}
	if( $interfaces{$interface}{c2fo} ) {
		push @params, "CDEF:mc2fout=$mds1,1.8,*,32,+"; 
		$mds1 = "mc2fout";
	}

# Do the maxima
	$max1 = $max2 = $interfaces{$interface}{max};
	$max1 = $interfaces{$interface}{max1} 
		if(defined $interfaces{$interface}{max1});
	$max2 = $interfaces{$interface}{max2} 
		if(defined $interfaces{$interface}{max2});
# Reverse calculations
	if($interfaces{$interface}{'reverse'}) {
		push @params,
			"CDEF:rin=$max1,$ds0,-",
			"CDEF:mrin=$max1,$mds0,-",
			"CDEF:rout=$max2,$ds1,-",
			"CDEF:mrout=$max2,$mds1,-";
		($ds0, $ds1) = ("rin", "rout");
		($mds0, $mds1) = ("mrin", "mrout");
	}
# And the percentages
	if($interfaces{$interface}{aspercent}) {
		push @params,
			"CDEF:pcin=$ds0,100,*,$max1,/",
			"CDEF:mpcin=$mds0,100,*,$max1,/",
			"CDEF:pcout=$ds1,100,*,$max2,/",
			"CDEF:mpcout=$mds1,100,*,$max2,/";
		($mds0, $mds1) = ("mpcin", "mpcout");
		($ds0, $ds1) = ("pcin", "pcout");
	} elsif($interfaces{$interface}{dorelpercent}) {
		# what if ds1=0? No way to avoid potential /0
		push @params,
			"CDEF:pcin=$ds0,100,*,$ds1,/",
			"CDEF:mpcin=$mds0,100,*,$mds1,/";
		$mds0 = "mpcin"; # note we don't care about OUT as this implies NOO
		$ds0 = "pcin";
	} else {
		if( $max1 && $dwmy !~ /s/ ) {
			push @params,
				"CDEF:pcin=$ds0,100,*,$max1,/",
				"CDEF:mpcin=$mds0,100,*,$max1,/";
		}
		if( $max2 && $dwmy !~ /s/ ) {
			push @params,
				"CDEF:pcout=$ds1,100,*,$max2,/",
				"CDEF:mpcout=$mds1,100,*,$max2,/";
		}
	}

# Now the workday averages, if required
	if( $workday ) {
		# note we must have a DS in there even if it is not used
		push @params, "CDEF:wdtest=$ds0,POP,"
			."TIME,3600,/,$timezone,+,DUP,24,/,7,%,DUP,4,LT,EXC,2,GE,+,2,LT,"
			."EXC,24,%,DUP,"
			.trim($config{'routers.cgi-daystart'}).",GE,EXC,"
			.trim($config{'routers.cgi-dayend'}).",LT,+,2,EQ,1,"
			."0,IF,0,IF"; # Set to 1 if in working day
		push @params, "CDEF:wdin=wdtest,$ds0,UNKN,IF",
			"CDEF:wdout=wdtest,$ds1,UNKN,IF";
		push @params, "CDEF:wdx=wdtest,$ds2,UNKN,IF" if($ds2);
		# mark the working day background, if not in b&w mode
		if( $gstyle !~ /b/ ) {
			push @params, "CDEF:wd=wdtest,INF,0,IF", "AREA:wd#ffffcc";
#			if($graphstyle=~/mirror/) {
				push @params, "CDEF:mwd=wd,-1,*", "AREA:mwd#ffffcc";
#			}
		}
	}

	if( $interfaces{$interface}{available} ) {
		# availability percentage
		push @params, "CDEF:apc=in,UN,out,UN,+,2,EQ,0,100,IF";
		# Now, the average of apc is the percentage availability!
	}

	# For the scaleshift
	if( defined $interfaces{$interface}{scaleshift}
		and ($RRDs::VERSION >= 1.3) ) {
		push @params, 
			"CDEF:x$ds1=$ds1,"
				.$interfaces{$interface}{shift}.",-,"
				.$interfaces{$interface}{scale}.",/",
			"CDEF:x$mds1=$mds1,"
				.$interfaces{$interface}{shift}.",-," 
				.$interfaces{$interface}{scale}.",/";
	} else {
		push @params, "CDEF:x$ds1=$ds1", "CDEF:x$mds1=$mds1";
	}

	if( $interfaces{$interface}{mode} eq "SERVER" and $ds2 ) {
		push @params, "AREA:$ds0".$clr[0].$lin,
			"STACK:$ds1".$clr[1].$lout,
			"STACK:$ds2".$clr[4].$lextra;
	} else {
#	now for the actual lines : put the peaklines for d only if we have a 6 hr
#	dont forget to use more friendly colours if this is black and white mode
		push @params, "LINE$linewidth:$mds0".$clr[2].$mlin 
			if($havepeaks and !$interfaces{$interface}{noi});
			# outbound is done later...
		if(!$interfaces{$interface}{noi}) {
			if( $graphstyle =~ /lines/i ) {
				push @params, "LINE$linewidth:$ds0".$clr[0].$lin;
			} else {
				push @params, "AREA:$ds0".$clr[0].$lin;
			}
		}
		if(!$interfaces{$interface}{noo}) {
			if( $graphstyle =~ /stack/i ) {
				push @params, "STACK:$ds1".$clr[1].$lout;
			} elsif( $graphstyle =~ /range/i ) {
				push @params, "AREA:$ds1#ffffff"; # erase lower part
				# if workingday active, put HIGHLIGHTED lower in
				if( $workday and $gstyle !~ /b/) {
					push @params, "CDEF:lwday=wdin,UN,0,$ds1,IF",
						"AREA:lwday#ffffcc";
				}
				push @params, "LINE$linewidth:$ds1".$clr[0]; # replace last pixel
			} elsif( $graphstyle =~ /mirror/i ) {
				if($havepeaks) {
					push @params, "CDEF:mmirror=$mds1,-1,*";
					push @params, "LINE$linewidth:mmirror".$clr[3].$mlout;
				} 
				push @params, "CDEF:mirror=$ds1,-1,*";
				push @params, "AREA:mirror".$clr[1].$lout;
			} else {
				# we do it here so it isnt overwritten by the incoming area
				if($havepeaks) {
					push @params, "LINE$linewidth:x$mds1".$clr[3].$mlout;
				} # with peaks
				push @params, "LINE$linewidth:x$ds1".$clr[1].$lout;
			}
		}
	} # server mode

# data unavailable
	if(!$interfaces{$interface}{unknaszero}
		and !$interfaces{$interface}{unknasprev}) {
		push @params,
		"CDEF:down=in,UN,out,UN,+,2,EQ,INF,0,IF","AREA:down#d0d0d0";
#		if($graphstyle=~/mirror/i) {
		push @params, "CDEF:mdown=down,-1,*","AREA:mdown#d0d0d0";
		push @params, "HRULE:0#000000";
#		}
	}
# thresholds
	if( $dwmy !~ /s/ and !$interfaces{$interface}{nothresholds} ) {
	my($tdone) = 0; my( $tlab ) = "";
	my($tlabbit);
	foreach ( qw/i o/ ) {
		$tlabbit = "";
		if(defined $interfaces{$interface}{"threshmin$_"}) {
			$tlabbit = doformat($interfaces{$interface}{"threshmin$_"},
					$interfaces{$interface}{fixunits},0) 
				.$interfaces{$interface}{unit};
		}
		if(defined $interfaces{$interface}{"threshmax$_"}) {
			$tlabbit .= ", " if($tlabbit);
			$tlabbit .= doformat($interfaces{$interface}{"threshmax$_"},
					$interfaces{$interface}{fixunits},0) 
				.$interfaces{$interface}{unit};
		}
		if($tlabbit) {
			$tlab .= " (".$interfaces{$interface}{"legend$_"}." ".$tlabbit.")";
		}
	}
	$tlab =~ s/:/\\:/g;
	foreach my $thresh ( qw/maxi maxo mini mino/ ) {
		if(defined $interfaces{$interface}{"thresh$thresh"} ) {
			my($tval) = $interfaces{$interface}{"thresh$thresh"};
			if( $graphstyle =~ /mirror/ and $thresh =~ /o$/ ) {
				$tval = -$tval;
			}
			if($tdone) {
				push @params, "HRULE:".$tval."#ffa0a0";
			} else {
				push @params, "HRULE:".$tval."#ffa0a0:"
					.langmsg(6105,"Thresholds")."$tlab\\l";
				$tdone = 1;
			}
		}
	} # foreach
	} # dwmy != s
# the max line
	if($interfaces{$interface}{aspercent} 
		or $interfaces{$interface}{dorelpercent}) {
		$interfaces{$interface}{max} = 100;
		$interfaces{$interface}{max1} = 100;
		$interfaces{$interface}{max2} = 100;
	}
	if( $interfaces{$interface}{max} 
		and ! ( defined $config{'routers.cgi-maxima'}
			and  $config{'routers.cgi-maxima'} =~ /n/i )
		and !$interfaces{$interface}{nomax}
	) {
		my( $lmax ) = "";
		my( $lamax ) = "";
		my( $lcol ) = "#ff0000";
		$lcol = "#cccccc" if( $gstyle =~ /b/ );
		if( $dwmy !~ /s/ ) {
			if( defined $interfaces{$interface}{mblegend} ) {
				$lmax = $interfaces{$interface}{mblegend};
				$lmax =~ s/:/\\:/g; $lmax = ':'.$lmax;
			} elsif( $interfaces{$interface}{isif} ) {
				$lmax =":100% ".langmsg(6103,"Bandwidth");
			} else { $lmax =":".langmsg(6102,"Maximum"); } 
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
				} else { $lamax =":".langmsg(6104,"Hard Maximum"); } 
				$lamax .= " (".doformat($interfaces{$interface}{absmax},
					$interfaces{$interface}{fixunits},1) 
					.$interfaces{$interface}{unit}.")\\l";
			}
			if($interfaces{$interface}{aspercent}
				or $interfaces{$interface}{aspercent}) { $lmax=""; }
		}
		if( $graphstyle =~ /mirror/ ) {
			$max1 = $interfaces{$interface}{max} if(!$max1);
			$max2 = -$interfaces{$interface}{max} if(!$max2);
			$max2 = -$max2 if($max2>0); # put it below the axis!
		}
		if( $max1 and $max2 and ($max1 != $max2)) {
			push @params, "HRULE:".$max1.$lcol.$lmax;
			push @params, "HRULE:".$max2.$lcol;
		} else {
			push @params, "HRULE:".$interfaces{$interface}{max}.$lcol.$lmax;
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
			if( $graphstyle =~ /mirror/ ) {
				if( $gstyle =~ /b/ ) {
					push @params, "HRULE:-".$interfaces{$interface}{absmax}
						."#aaaaaa";
				} else {
					push @params, "HRULE:-".$interfaces{$interface}{absmax}
						."#ff0080";
				}
			}
		}
	}
#	now for the labels at the bottom
	if( $dwmy !~ /s/ 
		and !$interfaces{$interface}{nodetails} 
		and !$interfaces{$interface}{nolegend} 
	) {
		if( $max1 ) {
			if(!$interfaces{$interface}{noi}) {
				push @params, "GPRINT:$mds0:MAX:$gmaxlbl $sin\\g" ;
				push @params ,"GPRINT:mpcin:MAX: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params,"GPRINT:$ds0:AVERAGE:  $gavglbl $sin\\g" ;
				push @params ,"GPRINT:pcin:AVERAGE: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params,"GPRINT:$ds0:LAST:  $gcurlbl $sin\\g" ;
				push @params ,"GPRINT:pcin:LAST: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params, "COMMENT:\\l" ;
			}
			if(!$interfaces{$interface}{noo}) {
				push @params, "GPRINT:$mds1:MAX:$gmaxlbl $sout\\g" ;
				push @params ,"GPRINT:mpcout:MAX: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params,"GPRINT:$ds1:AVERAGE:  $gavglbl $sout\\g" ;
				push @params ,"GPRINT:pcout:AVERAGE: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params,"GPRINT:$ds1:LAST:  $gcurlbl $sout\\g" ;
				push @params ,"GPRINT:pcout:LAST: (%2.0lf%%)\\g"
					if($interfaces{$interface}{percent});
				push @params, "COMMENT:\\l" ;
			}
			if($ds2) {
				push @params, "GPRINT:$mds2:MAX:$gmaxlbl $sext\\g" ;
				push @params,"GPRINT:$ds2:AVERAGE:  $gavglbl $sext\\g" ;
				push @params,"GPRINT:$ds2:LAST:  $gcurlbl $sext\\g" ;
				push @params, "COMMENT:\\l" ;
			}
			if($workday) {
				push @params, "COMMENT:".decolon(langmsg(6106,"Working day averages")."\\g");
				push @params,"GPRINT:wdin:AVERAGE: $sin\\g"
					if(!$interfaces{$interface}{noi});
				push @params,"GPRINT:wdout:AVERAGE: $sout\\g"
					if(!$interfaces{$interface}{noo});
				push @params,"GPRINT:wdx:AVERAGE: $sext\\g"
					if($ds2);
				push @params, "COMMENT:\\l";
			}
			if( defined $config{'routers.cgi-maxima'}
				and $config{'routers.cgi-maxima'} =~ /n/i
				and !$interfaces{$interface}{nomax} ) {
				my( $comment );
				if(defined $interfaces{$interface}{mblegend}) {
					$comment = $interfaces{$interface}{mblegend};
					$comment = "COMMENT:".decolon($comment);
				} elsif($interfaces{$interface}{isif}) {
					$comment = "COMMENT:100% ".decolon(langmsg(6103,"Bandwidth"));
				} else {
					$comment = "COMMENT:".decolon(langmsg(6102,"Maximum value"));
				}
				$comment .= decolon(" ".doformat($interfaces{$interface}{max},
						$interfaces{$interface}{fixunits},0)
					.$escunit."\\l");
				push @params, $comment;
 		 	}
		} else {
			push @params,
				"GPRINT:$mds0:MAX:$gmaxlbl $sin\\g",
				"GPRINT:$ds0:AVERAGE:  $gavglbl $sin\\g",
				"GPRINT:$ds0:LAST:  $gcurlbl $sin\\l" 
					if(!$interfaces{$interface}{noi});
			push @params,
				"GPRINT:$mds1:MAX:$gmaxlbl $sout\\g",
				"GPRINT:$ds1:AVERAGE:  $gavglbl $sout\\g",
				"GPRINT:$ds1:LAST:  $gcurlbl $sout\\l"
					if(!$interfaces{$interface}{noo});
			push @params,
				"GPRINT:$mds2:MAX:$gmaxlbl $sext\\g",
				"GPRINT:$ds2:AVERAGE:  $gavglbl $sext\\g",
				"GPRINT:$ds2:LAST:  $gcurlbl $sext\\l"
					if($ds2);
			if($workday) {
				push @params, "COMMENT:".decolon(langmsg(6106,"Working day averages")."\\g");
				push @params,"GPRINT:wdin:AVERAGE: $sin\\g"
					if(!$interfaces{$interface}{noi});
				push @params,"GPRINT:wdout:AVERAGE: $sout\\g"
					if(!$interfaces{$interface}{noo});
				push @params,"GPRINT:wdx:AVERAGE: $sext\\g"
					if($ds2);
				push @params, "COMMENT:\\l";
			}
		}
		if( $interfaces{$interface}{available} ) {
			push @params, "GPRINT:apc:AVERAGE:".langmsg(6107,"Data availability")."\\: %.2lf%%\\l";
		}
	} else {
		($legendi,$legendo,$legendx)
			= (langmsg(2204,"IN:"),langmsg(2205,"OUT:"),"");
		$legendi = $interfaces{$interface}{legendi} 
			if(defined $interfaces{$interface}{legendi});
		$legendo = $interfaces{$interface}{legendo} 
			if(defined $interfaces{$interface}{legendo});
		$legendx = $interfaces{$interface}{legendx} 
			if(defined $interfaces{$interface}{legendx});
		$legendi =~ s/:/\\:/g; $legendo =~ s/:/\\:/g; $legendx=~s/:/\\:/g;
		$legendi =~ s/%/%%/g; $legendo =~ s/%/%%/g; $legendx=~s/%/%%/g;
		
		push @params,
			"PRINT:$mds0:MAX:".$q->b($legendi)." $maxlbl $ssin, ",
			"PRINT:$ds0:AVERAGE:$avglbl $ssin, ",
			"PRINT:$ds0:LAST:$lastlbl $ssin ".$q->br
					if(!$interfaces{$interface}{noi});
		push @params,
			"PRINT:$mds1:MAX:".$q->b($legendo)." $maxlbl $ssout, ",
			"PRINT:$ds1:AVERAGE:$avglbl $ssout, ",
			"PRINT:$ds1:LAST:$lastlbl $ssout ".$q->br
					if(!$interfaces{$interface}{noo});
		push @params,
			"PRINT:$mds2:MAX:".$q->b($legendx)." $maxlbl $ssext, ",
			"PRINT:$ds2:AVERAGE:$avglbl $ssext, ",
			"PRINT:$ds2:LAST:$lastlbl $ssext ".$q->br
					if($legendx and $ds2);
		
		if($workday) {
			my($pfx) = "<TR><TD>".langmsg(3201,"Working day average")."\\:</TD>";
			my($sfx) = "";
			if(!$interfaces{$interface}{noi}) {
				$sfx = "</TR>" if($interfaces{$interface}{noo});
				push @params, 
					"PRINT:wdin:AVERAGE:$pfx<TD align=right>$ssin"
					."</TD>$sfx";
				$pfx = "";
			}
			push @params,
				"PRINT:wdout:AVERAGE:$pfx<TD align=right>$ssout"
					."</TD>$sfx"
				if(!$interfaces{$interface}{noo});
			push @params,
				"PRINT:wdx:AVERAGE:$pfx<TD align=right>$ssext"
					."</TD>$sfx"
				if($ds2);
		}
	}
}

sub jscript_actuals($$$$@) {
	my($interface,$dwmy,$starttime,$endtime,@p) = @_;	
	my($idx) = 0;
	my($js) = "";
	my( $start, $step, $names, $values, $e );
	my($t,$i,$dp,$factor,$incr);
	my($rrd);
	my($max1,$max2);
	my($intf);

	# if we're in a summary
	return if($dwmy =~/s/);
	# Here, we can add the javascript to define the actual arrays for the
	# popup, if necessary.
	$factor = 1; 
	$factor *= $interfaces{$interface}{mult} if($interfaces{$interface}{mult});
	$factor *= $interfaces{$interface}{factor} if($interfaces{$interface}{factor});
	$dp = 2; $dp = 0 if($interfaces{$interface}{integer});
	if($dwmy=~/d/) { $idx=1; }
	elsif($dwmy=~/w/) { $idx=2; }
	elsif($dwmy=~/m/) { $idx=3; }
	elsif($dwmy=~/y/) { $idx=4; }
	$rrd = $interfaces{$interface}{rrd};
	if($rrdcached and $rrdcached!~/^unix:/) {
		my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
		$rrd =~ s/^$pth\/*//;
	}
	if( $config{'web-debug'} ) {
		print "\n<!-- Extraction params: $rrd ".(join " ",@p)." -->\n";
	}
	( $start, $step, $names, $values ) = RRDs::fetch($rrd,"AVERAGE",@p,@rrdcached);
	$e = RRDs::error();
	if($e) {
		print "<!-- Error fetching: $e -->\n";
		return; 
	}
	if( $config{'web-debug'} ) {
		print "<!-- Asked for: $starttime to $endtime, 400 values-->\n";
		print "<!-- Asked for: ".longdate($starttime)." to ".longdate($endtime)." -->\n";
		print "<!-- Retrieved: $start to ".($start+$step*$#$values).", ".$#$values." values -->\n";
		print "<!-- Retrieved: ".longdate($start)." to ".longdate($start+$step*$#$values)." -->\n";
#		print "<!-- Step: asked for ".$p[5]." retrieved $step -->\n";
	}

	$js = "xactual[$idx]=1;\nactual[$idx]=new Array(400);\n";
	$i = 0; $t = $start;
	$incr = ($endtime-$starttime)/400;
	$max1 = $max2 = $interfaces{$interface}{max};
	$max1 = $interfaces{$interface}{max1} 
		if(defined $interfaces{$interface}{max1});
	$max2 = $interfaces{$interface}{max2} 
		if(defined $interfaces{$interface}{max2});
	$intf = 0;
	$intf = $interfaces{$interface}{integer} 
		if(defined $interfaces{$interface}{integer});
	foreach my $row ( @$values ) {
		$i = int(($t-$starttime)/$incr);
		if(!defined $row->[0]) { $js .= "actual[$idx][$i] = \"\"\n"; } 
		else {
			$js .= "actual[$idx][$i] = \"";
			if($interfaces{$interface}{dorelpercent}) {
				$js .= doformat(($row->[0]/$row->[1]*100.0),1,$intf)."\%"
					if($row->[1]);
			} elsif($interfaces{$interface}{aspercent}) {
			$js .= doformat($row->[0]/$interfaces{$interface}{maxbytes}*100.0,
				1,$intf)."\%" unless($interfaces{$interface}{noi});
			$js .= ",<BR>" unless($interfaces{$interface}{noi} 
				or $interfaces{$interface}{noo});
			$js .= doformat($row->[1]/$interfaces{$interface}{maxbytes}*100.0,
				1,$intf)."\%" unless($interfaces{$interface}{noo});
			} elsif($interfaces{$interface}{'reverse'}) {
				$js .= doformat(($max1-$row->[0])*$factor,
					$interfaces{$interface}{fixunits},$intf)
					.$interfaces{$interface}{unit} 
					unless($interfaces{$interface}{noi});
				$js .= ",<BR>" unless($interfaces{$interface}{noi} 
					or $interfaces{$interface}{noo});
				$js .= doformat(($max2-$row->[1])*$factor,
					$interfaces{$interface}{fixunits},$intf)
					.$interfaces{$interface}{unit2} 
					unless($interfaces{$interface}{noo});
			} else {
				$js .= doformat(($interfaces{$interface}{c2fi}?
					(($row->[0]*$factor*1.8)+32):$row->[0]*$factor),
					$interfaces{$interface}{fixunits},$intf)
					.$interfaces{$interface}{unit} 
					unless($interfaces{$interface}{noi});
				$js .= ",<BR>" unless($interfaces{$interface}{noi} 
					or $interfaces{$interface}{noo});
				$js .= doformat(($interfaces{$interface}{c2fo}?
					(($row->[1]*$factor*1.8)+32):$row->[1]*$factor),
					$interfaces{$interface}{fixunits},$intf)
					.$interfaces{$interface}{unit2} 
					unless($interfaces{$interface}{noo});
			}
			$js .= "\";\n";
		}
		$t += $step;
	}

	# and output
	print "\n<SCRIPT type=\"text/javascript\">//<![CDATA[\n$js\n//]></SCRIPT>\n";
}
########################################################################
# Actually create the necessary graph, and output the IMG tag.

sub make_graph(@)
{
	my($e, $thisgraph, $thisurl, $s, $autoscale);
	my($tstr, $gheight, $width, $gwidth, $gtitle, $col);
	my($titlemaxlen);
	my($maxwidth) = 30;
	my($endtime, $starttime, @tparams, $interval, $end, $start);
	my($inhtml,$dwmy,$graphif) = @_;
	my($optsuffix) = "";
	my(@ctgt) = ();
	my($js) = "";

	$debugmessage .= "Graph: $graphif\n";

# Verify that the rrd file exists
	if(!$rrdcached) {
	if( $interfaces{$graphif}{usergraph} ) {
		# several to check
		@ctgt =  @{$interfaces{$graphif}{targets}};
	} else {
		@ctgt = ( $graphif );
	}
	foreach (@ctgt) {
		if(!-r $interfaces{$_}{rrd}) {
			if ( $pagetype =~ /image/ ) {
				if($opt_I) {
					print "Interface: $graphif($_)\nDevice: $router\nError: RRD does not exist\nRRD: ".$interfaces{$_}{rrd}."\n";
				} else {
					print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
				}
			} else {
				print $q->h1(langmsg(3003,"RRD database file not found"))."\n";
				print "The file ".$interfaces{$_}{rrd}
					." does not exist, or is unreadable.  This file is created by MRTG when it first runs successfully on the "
					.$routers{$router}{file}." file.\n".$q->br
					."Please check that you have collected data via MRTG and stored it into the RRD database without errors.".$q->br."\n";
			}
			return;
		}
	}
	} # rrdcached

# Shall we scale it, etc
	$autoscale = 1;
	$s = $dwmy; $s =~ s/[^dwmy6]//g; # get rid of excess stuff
	if( $interfaces{$graphif}{unscaled} ) {
		$autoscale = 0 if ($interfaces{$graphif}{unscaled} =~ /$s/i);
	}

	$tstr = "6-hour" if( $dwmy =~ /6/ ) ;
	$tstr = "Daily" if( $dwmy =~ /d/ ) ;
	$tstr = "Weekly" if( $dwmy =~ /w/ ) ;
	$tstr = "Monthly" if( $dwmy =~ /m/ ) ;
	$tstr = "Yearly" if( $dwmy =~ /y/ ) ;

	$gtitle = $interfaces{$graphif}{desc};
	if( ($dwmy.$gstyle)=~/s/ ) {
		if($gstyle=~/y/) { $maxwidth = 60; }
		elsif($gstyle=~/x/) { $maxwidth = 50; }
		elsif($gstyle=~/l/) { $maxwidth = 40; }
		else { $maxwidth = 30; }
	}
	if(!$gtitle or ((length($gtitle)>$maxwidth)and(($dwmy.$gstyle) =~ /s/))) {
		$gtitle = "";
		$gtitle .= $routers{$router}{shdesc}.": " 
				if( defined $routers{$router}{shdesc});
		$gtitle .= $interfaces{$graphif}{shdesc};
	}
	$gtitle = $q->unescape($gtitle);
	$gtitle =~ s/&nbsp;/ /g; $gtitle =~ s/&amp;/&/g;

	@params = ();
	$optsuffix = "r1" if($uopts =~ /r/ );
	$optsuffix = "r2" if($uopts =~ /R/ );
	$optsuffix = "-$optsuffix" if($optsuffix);
	$thisgraph = "${router}-${graphif}-${dwmy}-${gstyle}${optsuffix}.${graphsuffix}";
	$thisgraph = "${archdate}-${thisgraph}" if($archdate);
	$thisgraph = "${language}-${thisgraph}" if($language);
	$thisgraph =~ s/[\?#\/\\]//g;
	$thisurl   = $config{'routers.cgi-graphurl'}."/".$q->escape($thisgraph);
	$thisgraph = $config{'routers.cgi-graphpath'}.$pathsep.$thisgraph;

	# width is the data unit width (400 max). gwidth is the pixel width of
	# the actual graph.  Thus, if gwidth > width, it is stretched.
	# Short: for PDAs, unstretched, shorter data window
	# Stretch: normal graph size, short data window (for easier viewing)
	# Long: normal data width, slightly bigger graph (for 800/600 screens)
	# Xlong: normal data width, double graph size (for 1024/768 screens)
	# v and w are thumbnail sizes, with half/quarter data width intended to
	# be used with the 'g' graph-only option.
	# gheight is the height of the graphic.  
	# The 1st char is the width indicator s,t,n,l,x,y,v,w
	# then optional height indicator -,0,2,3
	# Then opional b (monochrome), g (graph only), p (no javascript)
	# Also D,H,Q for double/half/quarter data width ( t == nH )
	# A == w-g, B == v0g (thumbnails)
	# Note that the graph TYPE (dwmy) can have a trailing s to indicate
	# summary, which will reduce the size and data width and suppress the
	# legend.
	if ( $gstyle =~ /^s/ ) { $width = 200; $gwidth = 200; } #short
	elsif ( $gstyle =~ /^t/ ) { $width = 200; $gwidth = 400; } #stretch
	elsif ( $gstyle =~ /^l/ ) { $width = 400; $gwidth = 530; } #long
	elsif ( $gstyle =~ /^x/ ) { $width = 400; $gwidth = 800; } #xlong
	elsif ( $gstyle =~ /^y/ ) { $width = 400; $gwidth = 1000; } #supersize
	elsif ( $gstyle =~ /^[wA]/i ) { $width = 100; $gwidth = 50; } #thumbnail
	elsif ( $gstyle =~ /^[vB]/i ) { $width = 200; $gwidth = 100; } #thumbnail
	else { $width = 400; $gwidth = 400; } # default (normal)
	if ( $gstyle =~ /2/ ) { $gheight = 200; } # double height
	elsif ( $gstyle =~ /3/ ) { $gheight = 300; } # triple height
	elsif ( $gstyle =~ /[-A]/ ) { $gheight = 30; } # thumbnail
	elsif ( $gstyle =~ /[0B]/ ) { $gheight = 50; } # half height
	else { $gheight = 100; } # normal height
	if    ( $gstyle =~ /D/ ) { $width *= 2; } # double data width, so n=tD
	elsif ( $gstyle =~ /H/ ) { $width /= 2; } # half data width, so t=nH
	elsif ( $gstyle =~ /Q/ ) { $width /= 2; } # quarter data width
	elsif ( $gstyle =~ /T/ ) { $width *= 3; } # triple data width
	# now, if $dwmy contains an s, this is a summary graph, and should be
	# half of the expected data width and half the expected screen width.
	# We also force the graph to be half height, or 100 (whichever is greater).
	# The magic 120 in the graph width is the width of the axis, as gwidth is
	# the width of the AXIS, not the width of the graphic.
	if ( $dwmy =~ /s/ ) { 
		my $ratio = 0.5;
		if( $interfaces{$interface}{nodetails} ) { $ratio = 0.5; }
		elsif($gwidth>800) { $ratio = 0.75; } # y
		elsif($gwidth>400) { $ratio = 0.65; } # x,l
		elsif($gwidth>200) { $ratio = 0.5; } # n,s
		$width *= $ratio; $gwidth = ($gwidth+120)*$ratio - 120; 
		$gheight/=2; $gheight = 100 if($gheight<100); 
	}

	push @params,"--only-graph" if($gstyle=~/[gAB]/);
	push @params, $thisgraph;
	if( $graphsuffix eq "png" ) {
		push @params, '--imgformat',uc $graphsuffix;
	}
	if($interfaces{$graphif}{kilo}) {
		push @params,"--base", $interfaces{$graphif}{kilo};	
	} else {
		push @params,"--base", $k;	
	}
	push @params,"--lazy" if($dwmy !~ /s/ and $RRDs::VERSION != 1.3 
		and (!defined $config{'routers.cgi-lazy'}
			or $config{'routers.cgi-lazy'}=~/[y1]/i)); 
		# only if we dont need PRINT, and avoid RRD v1.3.0 bug
	push @params, "--interlaced"; # -l 0 removed
	if($interfaces{$graphif}{fixunits} and $RRDs::VERSION >= 1.00030 ) {
		if($interfaces{$graphif}{exponent}) {
			push @params,"--units-exponent",$interfaces{$graphif}{exponent};
		} else {
			push @params,"--units-exponent",0;
		}
	}

	push @params,"--force-rules-legend" if($RRDs::VERSION >= 1.00047);
	push @params,"--slope-mode" if(($RRDs::VERSION >= 1.2 )
		and defined $config{'routers.cgi-slope'}
		and ($config{'routers.cgi-slope'}=~/[y1]/i) );

	# time window: save these, we may need them again
	@tparams = ();
	$end = 'now'; $endtime = time;
#	$debugmessage .= "Endtime = $endtime\n";
	if($basetime) {
		$end = $endtime = $basetime;
	} elsif($uselastupdate > 1  and $archivetime) {
		$end = $endtime = $archivetime;
	} elsif($lastupdate and $uselastupdate) {
		$end = $endtime = $lastupdate;
	} elsif( $interval ) {
		# Cannot be done because interval not yet set!
		$end = $endtime = $interval*int($endtime/$interval); # boundary
	} elsif( $dwmy =~ /6/ ) { 
		$end = $endtime = 60*int($endtime/60);  # 1min boundary
	} else { 
		$end = $endtime = 300*int($endtime/300);  # 5min boundary
	}
#	$debugmessage .= "Endtime = $endtime\n";
	if( $dwmy =~ /-/ ) {
		if ( $dwmy =~ /6/ ) {
			push @tparams, "-e", "$end-6h"; $endtime -= (6*3600); }
		if ( $dwmy =~ /d/ ) {
			push @tparams, "-e", "$end-24h"; $endtime -= (24*3600); }
		if ( $dwmy =~ /w/ ) {
			push @tparams, "-e", "$end-7d"; $endtime -= (7*24*3600); }
		if ( $dwmy =~ /m/ ) {
			push @tparams, "-e", "$end-30d"; $endtime -= (30*24*3600); }
		if ( $dwmy =~ /y/ )  {
			push @tparams, "-e", "$end-365d"; $endtime -= (365*24*3600); }
	} else {
		push @tparams, "-e", $end;
	}
	if ( $dwmy =~ /6/ ) {
		$interval = 60;
		$starttime = $endtime - $interval*$width;
		push @tparams, "-s", "end".(-1 * $width)."m"  ;
	} elsif ( $dwmy =~ /d/ ) {
		$interval = 300;
		$starttime = $endtime - $interval*$width;
		push @tparams, "-s", "end".(-5 * $width)."m" ;
	} elsif ( $dwmy =~ /w/ ) {
		$interval = 1800;
		$starttime = $endtime - 1500*$width; # dont use $interval
		push @tparams, "-s", "end".(-25 * $width)."m" ; # dont set to 30
	} elsif ( $dwmy =~ /m/ ) {
		$interval = 7200;
		$starttime = $endtime - $interval*$width;
		push @tparams, "-s", "end".(-2 * $width)."h"  ;
	} elsif ( $dwmy =~ /y/ ) {
		$interval = 86400;
		$starttime = $endtime - $interval*$width;
		push @tparams, "-s", "end".(-1 * $width)."d"   ;
	}

	push @params, @tparams;

	# only force the minimum upper-bound of graph if we have a max,
	# and we dont have maxima=n, and we dont have unscaled=n
	if( $uopts =~ /r/i ) {
		# force upper limit to be 2xMax(avgs) if r, and Max(avgs) if R
		my($ulim) = 0;
		my($llim) = 0;
		my($ai,$ao, $e, $start, $names, $data);
		my(@t) = ($graphif);
		my($thistarg, $thislim,$lookback);
		# multiple targets?
		@t = @{$interfaces{$graphif}{targets}}
			if($interfaces{$graphif}{usergraph});
		# find out average value
		$e = int($lastupdate/$interval)*$interval;
		$lookback = 10;
		$lookback = 200 if($uopts =~ /r/); # look back further
		# this _should_ return only one line of values... 
		foreach $thistarg ( @t ) {
			my($trrd) = $interfaces{$thistarg}{rrd};
			if($rrdcached and $rrdcached!~/^unix:/) {
				my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
				$trrd =~ s/^$pth\/*//;
			}
			($start,$interval,$names,$data) = 
				RRDs::fetch($trrd, "AVERAGE",
				"-r", $interval, "-s", "end-".($lookback*$interval), "-e", $e,
				@rrdcached);	
			($ai,$ao) = get_avg($data);
			if( defined $interfaces{$interface}{graphstyle}
				and $interfaces{$interface}{graphstyle} =~ /mirror/i ) { 
				if(!$interfaces{$thistarg}{noo}) {
					if( $interfaces{$graphif}{withtotal} 
						and $interfaces{$graphif}{usergraph} ) {
						$ulim += $ao;
					} else {
						$ulim = $ao if($ao > $ulim);
					}
				}
				if(!$interfaces{$thistarg}{noi}) {
					if( $interfaces{$graphif}{withtotal} 
						and $interfaces{$graphif}{usergraph} ) {
						$llim += $ai;
					} else {
						$llim = $ai if($ai > $llim);
					}
				}
			} else {
				if($ao > $ai) { $thislim = $ao; } else { $thislim = $ai; }
				$thislim = $ao if($interfaces{$thistarg}{noi});
				$thislim = $ai if($interfaces{$thistarg}{noo});
				if( $interfaces{$graphif}{withtotal} 
					and $interfaces{$graphif}{usergraph} ) {
					$ulim += $thislim;
				} else {
					$ulim = $thislim if($thislim > $ulim);
				}
			}
		}
		$ulim *= 1.1; # just give a little more space
		# now we need to multiply, if appropriate
		$ulim *= $interfaces{$graphif}{mult}
			if($interfaces{$graphif}{mult});
		$ulim *= $interfaces{$graphif}{factor}
			if(defined $interfaces{$graphif}{factor});
		$ulim = int(2.0 * $ulim + 0.5) if($uopts =~ /r/);
		push @params, '-r', '-u', $ulim if($ulim > 0);
		if( defined $interfaces{$interface}{graphstyle}
			and $interfaces{$interface}{graphstyle} =~ /mirror/i ) { 
			$llim *= -1.1; # just give a little more space
			$llim *= $interfaces{$graphif}{mult}
				if($interfaces{$graphif}{mult});
			$llim *= $interfaces{$graphif}{factor}
				if(defined $interfaces{$graphif}{factor});
			$llim = int(2.0 * $llim + 0.5) if($uopts =~ /r/);
			push @params, '-l', $llim if($llim < 0);
		}
	} else {
		if($interfaces{$graphif}{upperlimit}) {
			push @params, '-u', $interfaces{$graphif}{upperlimit};
		} elsif( ! $autoscale ) {
			if( $interfaces{$graphif}{max} and ( 
				!defined $config{'routers.cgi-maxima'}
				or $config{'routers.cgi-maxima'} !~ /n/i
			) ) {
				push @params, '-u', $interfaces{$graphif}{max} ;
			} else {
				push @params, '-u', 0.1; # For sanity
			}
		} else {
			push @params, '-u', 0.1; # For sanity
		}
		# could have added a "-r" there to enforce the upper limit rigidly
		push @params, '--rigid' if($interfaces{$graphif}{rigid});
		if($interfaces{$graphif}{lowerlimit}) {
			push @params, '--lower-limit', $interfaces{$graphif}{lowerlimit};
		}
	}
	push @params, "-w", $gwidth, "-h", $gheight;

	push @params,'--alt-y-grid' 
		if($RRDs::VERSION>=1.2 and defined $config{'routers.cgi-altygrid'}
		and $config{'routers.cgi-altygrid'}=~/[y1]/i);

	push @params,"--x-grid","MINUTE:15:HOUR:1:HOUR:1:0:$dailylabel"  
		if ( $dwmy =~ /6/ );
	push @params,"--x-grid","HOUR:1:HOUR:24:HOUR:2:0:$dailylabel"  
		if ( $dwmy =~ /d/ );
	push @params,"--x-grid","HOUR:6:DAY:1:DAY:1:86400:%a" 
		if ( $dwmy =~ /w/ );
	push @params,"--x-grid","DAY:1:WEEK:1:WEEK:1:604800:Week"
			.(($NT and $RRDs::VERSION < 1.00039)?"_":" ").$monthlylabel  
		if ( $dwmy =~ /m/ and $RRDs::VERSION >= 1.00029  );
	$titlemaxlen = $config{'routers.cgi-maxtitle'}?$config{'routers.cgi-maxtitle'}:128;
	$gtitle = substr($gtitle,0,$titlemaxlen) if(length($gtitle)>$titlemaxlen);
	push @params,"--title", $gtitle;

	if ( defined $interfaces{$graphif}{ylegend} ) {
		push @params, "--vertical-label", $interfaces{$graphif}{ylegend};
#		push @params, "-U", $interfaces{$graphif}{unit} 
#			if($interfaces{$graphif}{unit});
	} else {
		push @params, "--vertical-label", $interfaces{$graphif}{unit};
	}

	# Horizontal rules
	if( defined $interfaces{$graphif}{hrule} and $dwmy!~/s/ ) {	
		$col = 4;
		foreach ( @{$interfaces{$graphif}{hrule}} ) {
			push @params, "HRULE:".$_->{value}."#"
				.($_->{colour}?$_->{colour}:((sprintf "%x",$col) x 6))
				.":".$_->{desc}." ( "
				.doformat($_->{value},$interfaces{$graphif}{fixunits},0)
				.$interfaces{$graphif}{unit} .")\\l";
			$col += 1;
		}
	}

	# Scale modes and secondary axis
	push @params, "--logarithmic", "--units=si"
		if($interfaces{$graphif}{logscale});
	push @params, "--right-axis-label", $interfaces{$graphif}{ylegend2}
		if($interfaces{$graphif}{ylegend2} and ($RRDs::VERSION >= 1.3));
	push @params, "--right-axis", 
		$interfaces{$graphif}{scale}.':'.$interfaces{$graphif}{shift}
		if($interfaces{$graphif}{scaleshift} and ($RRDs::VERSION >= 1.3));
	push @params, "-P" if(defined $config{'routers.cgi-pango'}
		and $config{'routers.cgi-pango'}=~/[y1]/i);

	push @params, "--watermark", "Generated by routers2.cgi Version $VERSION"
		if($RRDs::VERSION>=1.3004 and $dwmy !~ /s/);

	push @params, "HRULE:0#000000"; # redraw zero axis

	if( $interfaces{$graphif}{usergraph} ) {
		usr_params($dwmy,$graphif);
	} else {
		rtr_params($dwmy,$graphif);
	}

	if( defined $interfaces{$graphif}{comment} ) {
		foreach ( @{$interfaces{$graphif}{comment}} ) {
			push @params, "COMMENT:".decolon(expandvars($_))."\\l";
		}
	}

	if ( defined $config{'routers.cgi-withdate'}
		and $config{'routers.cgi-withdate'}=~/[1y]/ ) {
		push @params, "COMMENT:".decolon(shortdate($endtime))."\\r";
	}

	( $rrdoutput, $rrdxsize, $rrdysize ) = RRDs::graph(@params);
	$e = RRDs::error();
	if ( $pagetype =~ /image/ ) {
		if($e or ! -f $thisgraph) {
			if($opt_I) {
				print "Device: $router\nTarget: $graphif\n";
				print "Error: $e\n";
			} else {
		print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
			}
		} else {
			# output the graphic directly from disk
			open GRAPH, "<$thisgraph";
			binmode GRAPH;
			binmode STDOUT;
			print $q->header({ -type=>"image/$graphsuffix", -expires=>"now",
				'-Content-Disposition'=>"filename=\"image.$graphsuffix\"" })
				if(!$opt_I);
			while( <GRAPH> ) { print; }
			close GRAPH;
		}
		return;	
	}
	if ( $e ) {
		if( $inhtml ) {
			if($config{'web-paranoia'}
				and $config{'web-paranoia'}=~/[yY1]/) {
				print $q->p("RRD Error!"),"\n";
			} else {
				print $q->p("RRD Error: $e"),"\n";
				print $q->p("You can visit the configuration verification page "
					.$q->a({href=>("$meurlfull?page=verify&rtr="
						.$q->escape($router)),target=>"_new"},"here."));
				print $q->p("RRD: ".$interfaces{$graphif}{rrd}.$q->br.
					"Device: [$router] ".$routers{$router}{desc}.$q->br.
					"Interface: $graphif".$q->br.
						"Interfaces: ".(join ",",keys(%interfaces))
					);
				print "Params: ".(join " ",@params).$q->br;
			}
		} else {
			print "Error generating graph:\n$e\n";
		}
	} elsif( ! -f $thisgraph ) {
		if( $inhtml ) {
			print $q->h2("Graph was not created!");
			print $q->p("Probably, no data is available for the requested time period.");
			print $q->p("RRD: ".$interfaces{$graphif}{rrd}.$q->br.
				"Device: [$router] ".$routers{$router}{desc}.$q->br.
				"Interface: $graphif"
			);
		} else {
			print "Error generating graph: Probably no data available for that time period.\n";
		}
	} else {
		print "<!-- RRD: ".$interfaces{$graphif}{rrd}." -->\n"
			."<!-- OrigRRD: ".$interfaces{$graphif}{origrrd}." -->\n"
			."<!-- ArchiveDate: $archdate -->\n"
			if( $config{'web-debug'} );
		if($inhtml) {
			my($element) = "igraph$dwmy";
			my($tzoffset) = ($timezone*3600); # default to server's timezone
			if($interfaces{$graphif}{timezone}) {
				my($savetz) = $ENV{TZ};
				$ENV{TZ}=$interfaces{$graphif}{timezone};
				POSIX::tzset();
				$tzoffset = (localtime(86400))[2]; # -0
				$tzoffset -= 24 if( (localtime(86400))[3] != 2 );
				$tzoffset *= 3600;
				$ENV{TZ}=$savetz;
				POSIX::tzset();
				print "<!-- Timezone: ".$interfaces{$graphif}{timezone}
					." = $tzoffset -->\n";
			}
			# If we're able, get the actuals data
			# only if enabled, a simple graph, and not summary
			if(! $interfaces{$graphif}{usergraph} 
				and ! $interfaces{$graphif}{issummary} 
				and defined $config{'routers.cgi-actuals'}
				and $config{'routers.cgi-actuals'}=~/[y1]/i
				and (!defined $config{'routers.cgi-javascript'}
					or $config{'routers.cgi-javascript'}=~/[y1]/i)
				and $dwmy !~ /s/
			) {
				jscript_actuals($graphif,$dwmy,$starttime,$endtime,
					@tparams,'-r',$interval);
			}
			# Print out the actual image tag
			if($rrdxsize and $rrdysize and $rrdxsize < 10000 and $rrdysize < 10000 ) {
			print $q->img({src=>$thisurl,alt => $gtitle,border => 0,
				width => $rrdxsize, height => $rrdysize, name => $element,
				onMouseOver => "timepopup(this,'$element',$gwidth,$gheight,$interval,$endtime,$width,$tzoffset)", 
				onMouseMove => "mousemove(event)",
				onMouseOut => "clearpopup()" });
			} else { # avoid problems with RRD v1.3.0
			print $q->img({src=>$thisurl,alt => $gtitle,border => 0,
				name => $element,
				onMouseOver => "timepopup(this,'$element',$gwidth,$gheight,$interval,$endtime,$width,$tzoffset)", 
				onMouseMove => "mousemove(event)",
				onMouseOut => "clearpopup()" });
			}
			
		}
		if( $archiveme ) {
			# copy this graph into the archive dir, 
			# graphdir/file/target/ymdhm-siz.ext
			my( $arch ) = "";
			my( $sec, $min, $hour, $mday, $mon, $year ) = localtime(time);
			$year += 2000 if($year < 100);
			$year += 1900 if($year < 1000);
			$arch = $router; $arch =~ s/[\?#\/\\]//g;
			$arch = $config{'routers.cgi-graphpath'}.$pathsep.$arch;
			mkdir $arch,0755 if(! -d $arch);
			$arch .= $pathsep.$graphif;
			mkdir $arch,0755 if(! -d $arch);
			$min = '0'.$min if($min < 10);
			$mday = '0'.$mday if($mday < 10);
			$mon += 1; $mon = '0'.$mon if($mon < 10);
			$arch .= $pathsep.$year.'-'.$mon.'-'
				.$mday.'-'.$hour.'-'.$min.'-'.$dwmy.'.'.$graphsuffix;
			print "<!-- Archiving $thisgraph\ninto $arch -->\n"
				if( $config{'web-debug'} );
			if( open ARCH, '>'.$arch ) {
				binmode ARCH;
				if( open GRAPH, '<'.$thisgraph ) {
					binmode GRAPH;
					while ( <GRAPH> ) { print ARCH; }
					if($inhtml) {
					print $q->br.$q->b(langmsg(9001,"Archived OK")).$q->br."\n";
					} else { print langmsg(9001,"Graph archive OK.")."\n"; }
					close GRAPH;
				} else {
					if($inhtml) {
					print $q->br.$q->b(langmsg(8001,"Archiving FAILED")." (cannot read?!)");
					} else { print "Graph archive FAILED (cannot read?!).\n"; }
				}
				close ARCH;
			} else {
				if($inhtml) {
					print $q->br.$q->b(langmsg(8001,"Archiving FAILED")." (cannot write)");
				} else { print "Graph archive FAILED (cannot write).\n"; }
			}
		}
	}
	if($js and $inhtml) {
		# Now, load the values into the array
		print "<script type=\"text/javascript\">//<![CDATA[\n"
			.$js."\n//]]></script>\n";
	}
	if( $config{'web-debug'} ) {
		print "\n<!-- Start comment -->\n<!-- \nrrdtool graph ";	
		print (join "\n  ",@params); # For some browsers, this creates a
		                          # line too long and makes an error
		print "\n-->\n<!-- end comment -->\n";
	}
}

###############
# Calculations of average and max from fetched data
sub get_max($)
{
	my($rows) = $_[0];
	my($maxin, $maxout) = (0,0);

	foreach ( @$rows ) {
		$maxin = $$_[0] if($$_[0]>$maxin);
		$maxout = $$_[1] if($$_[1]>$maxout);
	}
	return ($maxin, $maxout);
}
sub get_avg($)
{
	my($rows) = $_[0];
	my($avgin, $avgout) = (0,0);
	my($numrows) = $#$rows;

	return (0,0) if($numrows < 1);
	foreach ( @$rows ) { 
		$avgin += $$_[0];
		$avgout += $$_[1];
	}
	$avgin /= ($numrows+1);
	$avgout /= ($numrows+1);

	return ($avgin,$avgout);
}
#######################################################
# For the compact summary.  This will call the bar function a lot!
# bar images are: $meurl?page=bar&IN=xx&OUT=yy for percentages xx yy
# images are 400x15 pixels
sub do_compact($)
{
my ($csvmode) = $_[0];
my ($javascript);
my ($curif);
my ($e, $interval, $resolution, $rrd, $seconds);
my ($curin, $curout, $avgin, $avgout, $maxin, $maxout );
my ($curinpc, $curoutpc, $avginpc, $avgoutpc, $maxinpc, $maxoutpc );
my ($perinpc, $peroutpc, $perin, $perout);
my ($start, $from, $step, $names, $values);
my ($c,$a,$m,$p,$io, $heading);
my ($d, $inarr, $outarr,$barlen);
my (@iforder);
my ($legendi,$legendo,$fix,$intf);
my ($unit) = "";
my ($max1, $max2);

if(!$csvmode) {
	$javascript = make_javascript({});
	start_html_ss({ -expires => "+5s",  -script => $javascript,
		-onload => "LoadMenu()", -class=>'compact' });
	print "<DIV class=pagetop>";
	print expandvars($config{'routers.cgi-pagetop'}),"\n"
		if( defined $config{'routers.cgi-pagetop'} );
	print "</DIV>";
} else {
	$comma = substr( $config{'web-comma'},0,1 )
		if(defined $config{'web-comma'});
	$comma = ',' if(!$comma);
	print "Target".$comma."Description".$comma."Type".$comma
		."Metric 1".$comma."Metric 2\n";
}
#
# Now for the RRD stuff
eval { require RRDs; };
if( $@ ) {
	if($csvmode) { print "".langmsg(8999,"Error").$comma
		."Cannot find RRDs.pm: $@\n";
		return;
	}
	if($config{'web-paranoia'}
		and $config{'web-paranoia'}=~/[yY1]/) {
		print $q->h1(langmsg(8999,"Error"))."<CODE>Cannot find RRDs.pm</CODE>\n";
	} else {
		print $q->h1(langmsg(8999,"Error"))."<CODE>Cannot find RRDs.pm in ".(join " ",@INC )."</CODE>\n";
		print $q->p("You can visit the configuration verification page "
			.$q->a({href=>("$meurlfull?page=verify&rtr=".$q->escape($router)),
			target=>"_new"},"here."));
	}
	do_footer();
	return;
}

# First, the header to select which are visible:
($c,$a,$m,$p,$io) = ("","","","","i");
$c = $1 if( $baropts =~ /(c)/i ); # this preserves the case
$a = $1 if( $baropts =~ /(a)/i );
$m = $1 if( $baropts =~ /(m)/i );
$p = $1 if( $baropts =~ /(p)/i );
if( $baropts =~ /o/i ) { $io = "o"; } else { $io = "i"; }
if(!$csvmode) {
print "<DIV class=icons>";
print "<TABLE width=100% border=0 cellspacing=0 cellpadding=0 class=compactmenu><TR>\n";
print "<TD><SMALL>".langmsg(2302,"Last:")." "
	.$q->a({href=>"$meurlfull?".optionstring({bars=>"Ci".(lc "$a$m$p")})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}sort-g-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Sort by current incoming"})
	).$q->a({href=>"$meurlfull?".optionstring({bars=>"Co".(lc "$a$m$p")})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}sort-b-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Sort by current outgoing"})
	);
if( $c ) {
	print $q->a({href=>"$meurlfull?".optionstring({bars=>"$a$m$p$io"})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}tick-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Remove current bar"})
	);
} else {
	print $q->a({href=>"$meurlfull?".optionstring({bars=>"c$a$m$p$io"})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}cross-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Add Current bar"})
	);
}
print "</SMALL></TD>\n";
print "<TD><SMALL>".langmsg(2303,"Average:")." "
	.$q->a({href=>"$meurlfull?".optionstring({bars=>"Ai".(lc "$c$m$p")})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}sort-g-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Sort by average incoming"})
	).$q->a({href=>"$meurlfull?".optionstring({bars=>"Ao".(lc "$c$m$p")})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}sort-b-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Sort by average outgoing"})
	);
if( $a ) {
	print $q->a({href=>"$meurlfull?".optionstring({bars=>"$c$m$p$io"})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}tick-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Remove Average bar"})
	);
} else {
	print $q->a({href=>"$meurlfull?".optionstring({bars=>"a$c$m$p$io"})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}cross-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Add Average bar"}));
}
print "</SMALL></TD>\n";
print "<TD><SMALL>".langmsg(2304,"Maximum:")." "
	.$q->a({href=>"$meurlfull?".optionstring({bars=>"Mi".(lc "$c$a$p")})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}sort-g-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Sort by Maximum incoming"})
	).$q->a({href=>"$meurlfull?".optionstring({bars=>"Mo".(lc "$c$a$p")})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}sort-b-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Sort by Maximum outgoing"})
	);
if( $m ) {
	print $q->a({href=>"$meurlfull?".optionstring({bars=>"$a$c$p$io"})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}tick-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Remove Maximum bar"}));
} else {
	print $q->a({href=>"$meurlfull?".optionstring({bars=>"m$a$c$p$io"})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}cross-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Add Maximum bar"}));
}
print "</SMALL></TD>\n";
if( defined $config{'routers.cgi-percentile'}
	and $config{'routers.cgi-percentile'} =~ /y/i ) {
	print "<TD><SMALL>".langmsg(2305,"$PERCENT<SUP>th</SUP> Percentile:")." "
		.$q->a({href=>"$meurlfull?".optionstring({bars=>"Pi".(lc "$c$a$m")})},
			$q->img({src=>"${config{'routers.cgi-smalliconurl'}}sort-g-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Sort by Incoming ${PERCENT}th percentile"})
		).$q->a({href=>"$meurlfull?".optionstring({bars=>"Po".(lc "$c$a$m")})},
			$q->img({src=>"${config{'routers.cgi-smalliconurl'}}sort-b-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Sort by Outgoing ${PERCENT}th percentile"})
		);
	if( $p ) {
		print $q->a({href=>"$meurlfull?".optionstring({bars=>"$a$m$c$io"})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}tick-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Remove ${PERCENT}th percentile bar"}));
	} else {
		print $q->a({href=>"$meurlfull?".optionstring({bars=>"p$a$m$c$io"})},
		$q->img({src=>"${config{'routers.cgi-smalliconurl'}}cross-vsm.gif",
			border=>0,height=>10,width=>10,alt=>"Add ${PERCENT}th percentile bar"}));
	}
	print "</SMALL></TD>\n";
}
print "</TR></TABLE></DIV>\n";
} # end if csvmode

# Now, we set up the necessary resolution variables to use in the fetch:
$resolution = 60; $interval = "6h"; $seconds = 6*3600;
$heading = langmsg(2310,"Six hourly calculations");
if ( $gtype =~ /d/ ) { $resolution=300; $interval="24h"; $seconds=86400; 
	$heading = langmsg(2311,"Daily calculations"); }
elsif ($gtype =~ /w/){ $resolution=1800; $interval="7d"; $seconds=7*86400; 
	$heading = langmsg(2312,"Weekly calculations"); }
elsif ($gtype =~ /m/){ $resolution=7200; $interval="1month"; $seconds=30*86400;
	$heading = langmsg(2313,"Monthly calculations"); }
elsif ($gtype =~ /y/){ $resolution=86400; $interval="1y"; $seconds=365*86400;
	$heading = langmsg(2314,"Yearly calculations"); }

if(!$csvmode) {
print $q->center($q->h2({class=>'compact'},$routers{$router}{desc}))."\n"
	if($routers{$router}{desc});
print $q->h3({class=>'compact'},$heading);
}

# we now process each interface with incompact=>1 in turn.
foreach $curif ( keys(%interfaces) ) {
	next if(!$curif); # avoid rogue records
	next if(!$interfaces{$curif}{incompact});
	next if(!$interfaces{$curif}{max});
	next if($interfaces{$curif}{nomax});

	$interfaces{$curif}{errors} = "";

	# now we fetch the necessary information from the RRD
	$curin = $maxin = $avgin = -1; # error
	$curout= $maxout= $avgout= -1; # error
	$from = "now"; $e = 0;
	$rrd = $interfaces{$curif}{rrd};
	if($rrdcached and $rrdcached!~/^unix:/) {
		my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
		$rrd =~ s/^$pth\/*//;
	}
	if($basetime) {
		$from = $basetime;
	} elsif( $gtype =~ /-/ ) {
		$from = "now-$interval";
	} elsif($uselastupdate > 1 and $archivetime) {
		$from = $archivetime;
	} elsif($uselastupdate) {
		$from = RRDs::last($rrd,@rrdcached);
		$e = RRDs::error();
		if($e) {
			$from = "now";
			$interfaces{$curif}{errors}.= $q->br.$q->small(langmsg(8999,"Error").": $e")."\n";
		}
	} else {
		$from = "now-5min";
	}
	$max1 = $max2 = $interfaces{$curif}{max};
	$max1 = $interfaces{$curif}{max1} if(defined $interfaces{$curif}{max1});
	$max2 = $interfaces{$curif}{max2} if(defined $interfaces{$curif}{max2});
	$lastupdate = $from;
	if( $c ) {
	( $start, $step, $names, $values ) = 
		RRDs::fetch($rrd,"AVERAGE","-s","$from-$resolution",
			"-e",$from,"-r",$resolution,@rrdcached);
	$e = RRDs::error();
	if($e) { 
		$interfaces{$curif}{errors} .= $q->br.$q->small(langmsg(8999,"Error").": $e");
	} else {
		( $curin, $curout ) = @{$values->[0]};
		$curin *= $interfaces{$curif}{mult}; 
		$curout *= $interfaces{$curif}{mult};
		$curin *= $interfaces{$curif}{factor} if($interfaces{$curif}{factor}); 
		$curout *= $interfaces{$curif}{factor} if($interfaces{$curif}{factor});
		$curin = 0 if($interfaces{$curif}{noi});
		$curout= 0 if($interfaces{$curif}{noo} and !$interfaces{$curif}{dorelpercent});
	}
	if( $interfaces{$curif}{dorelpercent} ) {
		if(defined $curin and $curout) {
			$curinpc = 100.0 * $curin / $curout;
			$curin = $curinpc;	
		} else {
			$curinpc = 0; $curin = -1;
		}
		$curoutpc = 0;
		$curout = -1;
	} else {
		if(defined $curin) { $curinpc = $curin*100.0/$max1; }
		else { $curin = -1; $curinpc = 0; }
		if(defined $curout) { $curoutpc = $curout*100.0/$max2; }
		else { $curout = -1; $curoutpc = 0; }
	}
	$interfaces{$curif}{barcurin}    = $curin;
	$interfaces{$curif}{barcurinpc}  = $curinpc;
	$interfaces{$curif}{barcurout}   = $curout;
	$interfaces{$curif}{barcuroutpc} = $curoutpc;
	} # c
	if( $a ) {
	( $start, $step, $names, $values ) = 
		RRDs::fetch($rrd,"AVERAGE","-s","$from-$interval",
			"-e",$from,"-r",$seconds,@rrdcached);
	$e = RRDs::error();
	if($e) { 
		$interfaces{$curif}{errors} .= $q->br.$q->small(langmsg(8999,"Error").": $e");
	} else {
		($avgin, $avgout) = get_avg($values);
		$avgin *= $interfaces{$curif}{mult}; 
		$avgout *= $interfaces{$curif}{mult};
		$avgin *= $interfaces{$curif}{factor} if($interfaces{$curif}{factor}); 
		$avgout *= $interfaces{$curif}{factor} if($interfaces{$curif}{factor});
		$avgin = 0 if($interfaces{$curif}{noi});
		$avgout= 0 if($interfaces{$curif}{noo} and !$interfaces{$curif}{dorelpercent});
	}
	if( $interfaces{$curif}{dorelpercent} ) {
		if(defined $avgin and $avgout) {
			$avginpc = 100.0 * $avgin / $avgout;
			$avgin = $avginpc;
		} else {
			$avginpc = 0; $avgin = -1;
		}
		$avgoutpc = 0;
		$avgout = -1;
	} else {
		if(defined $avgin) { $avginpc = $avgin*100.0/$max1; }
		else { $avgin = -1; $avginpc = 0; }
		if(defined $avgout) { $avgoutpc = $avgout*100.0/$max2; }
		else { $avgout = -1; $avgoutpc = 0; }
	}
	$interfaces{$curif}{baravgin}    = $avgin;
	$interfaces{$curif}{baravgout}   = $avgout;
	$interfaces{$curif}{baravginpc}  = $avginpc;
	$interfaces{$curif}{baravgoutpc} = $avgoutpc;
	} # a
	if( $m ) {
	( $start, $step, $names, $values ) = 
		RRDs::fetch($rrd,"MAX","-s","$from-$interval",
			"-e",$from,"-r",$seconds,@rrdcached);
	$e = RRDs::error();
	if($e) { 
		$interfaces{$curif}{errors} .= $q->br.$q->small(langmsg(8999,"Error").": $e");
	} else {
		($maxin, $maxout) = get_max($values);
		$maxin *= $interfaces{$curif}{mult}; 
		$maxout *= $interfaces{$curif}{mult};
		$maxin *= $interfaces{$curif}{factor} if($interfaces{$curif}{factor}); 
		$maxout *= $interfaces{$curif}{factor} if($interfaces{$curif}{factor});
		$maxin = 0 if($interfaces{$curif}{noi});
		$maxout= 0 if($interfaces{$curif}{noo} and !$interfaces{$curif}{dorelpercent});
	}
	if( $interfaces{$curif}{dorelpercent} ) {
		if(defined $maxin and $maxout) {
			$maxinpc = 100.0 * $maxin / $maxout;
			$maxin = $maxinpc;
		} else {
			$maxinpc = 0; $maxin = -1;
		}
		$maxoutpc = 0;
		$maxout = -1;
	} else {
		if(defined $maxin) { $maxinpc = $maxin*100.0/$max1; }
		else { $maxin = -1; $maxinpc = 0; }
		if(defined $maxout) { $maxoutpc = $maxout*100.0/$max2; }
		else { $maxout = -1; $maxoutpc = 0; }
	}
	$interfaces{$curif}{barmaxin}    = $maxin;
	$interfaces{$curif}{barmaxout}   = $maxout;
	$interfaces{$curif}{barmaxinpc}  = $maxinpc;
	$interfaces{$curif}{barmaxoutpc} = $maxoutpc;
	} # m
	if( $p ) {
		($d,$inarr,$outarr) = calc_percentile($curif,$gtype,$PERCENT);
		$perin = ${$inarr}[0];
		$perout= ${$outarr}[0];
		if( $interfaces{$curif}{dorelpercent} ) {
			if(defined $perin and $perout) {
				$perinpc = 100.0 * $perin / $perout;
				$perin = $perinpc;
			} else {
				$perinpc = 0; $perin = -1;
			}
			$peroutpc = 0;
			$perout = -1;
		} else {
			$perin = 0 if($interfaces{$curif}{noi});
			$perout= 0 if($interfaces{$curif}{noo});
			if(defined $perin) { $perinpc = $perin*100.0/$max1; }
			else { $perin = -1; $perinpc = -1; }
			if(defined $perout) { $peroutpc = $perout*100.0/$max2; }
			else { $perout = -1; $peroutpc = -1; }
		}
		$interfaces{$curif}{barperin}    = $perin;
		$interfaces{$curif}{barperout}   = $perout;
		$interfaces{$curif}{barperinpc}  = $perinpc;
		$interfaces{$curif}{barperoutpc} = $peroutpc;
		if(!$d) {
			$interfaces{$curif}{errors} .= $q->br.$q->small($$inarr[2])
				.$q->br.$q->small($$outarr[2]);
		}
	} # p
} # end of data collection
	
# Work out the order of the interfaces
$traffic = "";
if ( $c eq "C" ) {
	$traffic = "cur";
} elsif( $a eq "A" ) {
	$traffic = "avg";
} elsif( $m eq "M" ) {
	$traffic = "max";
} elsif( $p eq "P" and defined $config{'routers.cgi-percentile'}
  and $config{'routers.cgi-percentile'} =~ /y/i ) {
	$traffic = "per";
}
if($traffic) {
	$traffic .= 'in' if( $io eq "i" );
	$traffic .= 'out' if( $io eq "o" );
	$traffic = 'bar'.$traffic.'pc';
	@iforder = sort bytraffic keys(%interfaces);
} else {
	@iforder = sort byifdesc keys(%interfaces);
}

# we now print the bars.
$barlen = 400;                            # 800x600
$barlen = 600 if ( $gstyle =~ /x/i );     # 1024x768
$barlen = 280 if ( $gstyle =~ /[nts]/i ); # 640x480 and pda
print "<TABLE border=0 cellpadding=0 cellspacing=0 nowrap class=compact>\n"
	if(!$csvmode);
foreach $curif ( @iforder ) {
	next if(!$curif); # avoid rogue records
	next if(!$interfaces{$curif}{incompact});

	# the unit string, if any
	$unit = "";
	$unit = $interfaces{$curif}{unit}
		if(!defined $config{'routers.cgi-legendunits'}
			or $config{'routers.cgi-legendunits'} =~ /y/i );
	$fix = $interfaces{$curif}{fixunits};
	$fix = 0 if(!defined $fix);
	$intf = $interfaces{$curif}{integer};
	$intf = 0 if(!defined $intf);

	# the legends
	($legendi,$legendo)=(langmsg(2204,"IN"),langmsg(2205,"OUT"));
	$legendi = $interfaces{$curif}{legendi} if(defined $interfaces{$curif}{legendi});
	$legendo = $interfaces{$curif}{legendo} if(defined $interfaces{$curif}{legendo});
	$legendi = "" if($interfaces{$curif}{noi});
	$legendo = "" if($interfaces{$curif}{noo});

	if(!$csvmode) {
	print "<TR class=compact><TD align=left colspan=2 width=$barlen class=compact>\n";
	print $q->a({href=>"$meurlfull?".optionstring({if=>$curif})},
		$q->small($interfaces{$curif}{desc}
		.(($interfaces{$curif}{desc} ne $interfaces{$curif}{shdesc})?
			(" (".$interfaces{$curif}{shdesc}.")"):"")
		))."\n";
	print $interfaces{$curif}{errors};
	print "</TD><TD align=center valign=bottom><B><FONT color=#00d000><SMALL>$legendi</SMALL></FONT></B></TD><TD align=center valign=bottom><B><FONT color=#0000ff><SMALL>$legendo</SMALL></FONT></B></TD></TR>\n";
	} # csvmode

	# now print the bar graphs up
	if( $c ) {
	$curin =   $interfaces{$curif}{barcurin};
	$curout=   $interfaces{$curif}{barcurout};
	$curinpc = $interfaces{$curif}{barcurinpc};
	$curoutpc= $interfaces{$curif}{barcuroutpc};
	if($csvmode) {
		print $curif.$comma.'"'.$interfaces{$curif}{desc}.'"'.$comma
			.'"'.langmsg(2203,"Last").'"'.$comma
			.($legendi?doformat($curin,$fix,$intf):"").$comma
			.($legendo?doformat($curout,$fix,$intf):"").$comma
			."\n";
	} else {
	print "<TR><TD align=left><SMALL>".langmsg(2203,"Last")
		."</SMALL></TD>";
	do_bar_html($barlen,dp($curinpc,1),dp($curoutpc,1),$legendi,$legendo);
	print "<TD align=right nowrap>";
	print $q->small("&nbsp;&nbsp;<FONT color=#00d000>"
		.doformat($curin,$fix,$intf)."$unit</FONT>")
		if($curin>=0 and $legendi);
	print $q->small(" <FONT color=#00d000>(".doformat($curinpc,1,0)."%)</FONT>")
		if($curinpc>=0 and $legendi and $interfaces{$curif}{percent});
	print "</TD><TD align=right nowrap>";
	print $q->small("&nbsp;&nbsp;<FONT color=#0000ff>"
		.doformat($curout,$fix,$intf)."$unit</FONT>")
		if($curout>=0 and $legendo);
	print $q->small(" <FONT color=#0000ff>(".doformat($curoutpc,1,0)."%)</FONT>")
		if($curoutpc>=0 and $legendo and $interfaces{$curif}{percent});
	print "</TD></TR>\n";
	} # csvmode
	} # c
	if( $a ) {
	$avgin =   $interfaces{$curif}{baravgin};
	$avgout=   $interfaces{$curif}{baravgout};
	$avginpc = $interfaces{$curif}{baravginpc};
	$avgoutpc= $interfaces{$curif}{baravgoutpc};
	if($csvmode) {
		print $curif.$comma.'"'.$interfaces{$curif}{desc}.'"'.$comma
			.'"'.langmsg(2201,"Avg").'"'.$comma
			.($legendi?doformat($avgin,$fix,$intf):"").$comma
			.($legendo?doformat($avgout,$fix,$intf):"").$comma
			."\n";
	} else {
	print "<TR><TD align=left><SMALL>".langmsg(2201,"Avg")
		."</SMALL></TD>";
	do_bar_html($barlen,dp($avginpc,1),dp($avgoutpc,1),$legendi,$legendo);
	print "<TD align=right nowrap>";
	print $q->small("&nbsp;&nbsp;<FONT color=#00d000>".doformat($avgin,$fix,$intf)."$unit</FONT>")
		if($avgin>=0 and $legendi);
	print $q->small(" <FONT color=#00d000>(".doformat($avginpc,1,0)."%)</FONT>")
		if($avginpc>=0 and $legendi and $interfaces{$curif}{percent});
	print "</TD><TD align=right nowrap>";
	print $q->small("&nbsp;&nbsp;<FONT color=#0000ff>".doformat($avgout,$fix,$intf)."$unit</FONT>")
		if($avgout>=0 and $legendo);
	print $q->small(" <FONT color=#0000ff>(".doformat($avgoutpc,1,0)."%)</FONT>")
		if($avgoutpc>=0 and $legendo and $interfaces{$curif}{percent});
	print "</TD></TR>\n";
	} # csvmode
	} # a
	if( $m ) {
	$maxin =   $interfaces{$curif}{barmaxin};
	$maxout=   $interfaces{$curif}{barmaxout};
	$maxinpc = $interfaces{$curif}{barmaxinpc};
	$maxoutpc= $interfaces{$curif}{barmaxoutpc};
	if($csvmode) {
		print $curif.$comma.'"'.$interfaces{$curif}{desc}.'"'.$comma
			.'"'.langmsg(2200,"Max").'"'.$comma
			.($legendi?doformat($maxin,$fix,$intf):"").$comma
			.($legendo?doformat($maxout,$fix,$intf):"").$comma
			."\n";
	} else {
	print "<TR><TD align=left><SMALL>"
		.langmsg(2200,"Max")."</SMALL></TD>";
	do_bar_html($barlen,dp($maxinpc,1),dp($maxoutpc,1),$legendi,$legendo);
	print "<TD align=right nowrap>";
	print $q->small("&nbsp;&nbsp;<FONT color=#00d000>".doformat($maxin,$fix,$intf)."$unit</FONT>")
		if($maxin>=0 and $legendi);
	print $q->small(" <FONT color=#00d000>(".doformat($maxinpc,1,0)."%)</FONT>")
		if($maxinpc>=0 and $legendi and $interfaces{$curif}{percent});
	print "</TD><TD align=right nowrap>";
	print $q->small("&nbsp;&nbsp;<FONT color=#0000ff>".doformat($maxout,$fix,$intf)."$unit</FONT>")
		if($maxout>=0 and $legendo);
	print $q->small(" <FONT color=#0000ff>(".doformat($maxoutpc,1,0)."%)</FONT>")
		if($maxoutpc>=0 and $legendo and $interfaces{$curif}{percent});
	print "</TD></TR>\n";
	} # csvmode
	} # m
	if( $p ) {
	$perin =   $interfaces{$curif}{barperin};
	$perout=   $interfaces{$curif}{barperout};
	$perinpc = $interfaces{$curif}{barperinpc};
	$peroutpc= $interfaces{$curif}{barperoutpc};
	if($csvmode) {
		print $curif.$comma.'"'.$interfaces{$curif}{desc}.'"'.$comma
			.'"'.langmsg(2206,$PERCENT."th").'"'.$comma
			.($legendi?doformat($perin,$fix,$intf):"").$comma
			.($legendo?doformat($perout,$fix,$intf):"").$comma
			."\n";
	} else {
	print "<TR><TD align=left><SMALL>".langmsg(2206,"$PERCENT<sup>th</sup>")
		."</SMALL></TD>";
	do_bar_html($barlen,dp($perinpc,1),dp($peroutpc,1),$legendi,$legendo);
	print "<TD align=right nowrap>";
	print $q->small("&nbsp;&nbsp;<FONT color=#00d000>".doformat($perin,$fix,$intf)."$unit</FONT>")
		if($perin>=0 and $legendi);
	print $q->small(" <FONT color=#00d000>(".doformat($perinpc,1,0)."%)</FONT>")
		if($perinpc>=0 and $legendi and $interfaces{$curif}{percent});
	print "</TD><TD align=right nowrap>";
	print $q->small("&nbsp;&nbsp;<FONT color=#0000ff>".doformat($perout,$fix,$intf)."$unit</FONT>")
		if($perout>=0 and $legendo);
	print $q->small(" <FONT color=#0000ff>(".doformat($peroutpc,1,0)."%)</FONT>")
		if($peroutpc>=0 and $legendo and $interfaces{$curif}{percent});
	print "</TD></TR>\n";
	} # csvmode
	} # p
} # foreach interface
print "</TABLE>\n" if(!$csvmode);

# Page foot
if(!$csvmode) {
print "<DIV class=pagefoot>";
print expandvars($config{'routers.cgi-pagefoot'}),"\n"
	if( defined $config{'routers.cgi-pagefoot'} );
print "</DIV>";
if( $gstyle !~ /p/ ) {
	my( $ngti, $ngto ) = ("","");
	print "<DIV class=icons>".$q->hr;
	print "\n",$q->a({href=>"javascript:location.reload(true)"},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}refresh.gif",
		alt=>langmsg(5003,"Refresh"),border=>"0",width=>100,height=>20})),"&nbsp;\n"
		if(!$archdate);
#	print $q->a({href=>"javascript:parent.makebookmark('"
#		.$q->escape($router)."','__compact','$gtype','$gstyle','$gopts','$baropts','".$q->escape($extra)."')"},
#		$q->img({src=>"${config{'routers.cgi-iconurl'}}bookmark.gif",
#		alt=>"Bookmark",border=>"0",width=>100,height=>20})),"&nbsp;\n";
	print $q->a({href=>"$meurlfull?".optionstring({page=>"", xmtype=>"",
		if=>"__compact", xgstyle=>""}), target=>"_top" },
		$q->img({src=>"${config{'routers.cgi-iconurl'}}bookmark.gif",
		alt=>langmsg(5016,"Bookmark"),border=>"0",width=>100,height=>20})),"&nbsp;\n";
	print $q->a({href=>"$meurlfull?".optionstring({page=>"compactcsv"}), target=>"graph"},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}csv.gif",
		alt=>langmsg(5019,"CSV Download"),border=>"0",width=>100,height=>20})),"\n";
	if( $gtype eq "6" ) { $ngto = "d"; }
	elsif( $gtype eq "d" ) { $ngto = "w"; $ngti = "6" if($usesixhour); }
	elsif( $gtype eq "w" ) { $ngti = "d"; $ngto = "m"; }
	elsif( $gtype eq "m" ) { $ngti = "w"; $ngto = "y"; }
	elsif( $gtype eq "y" ) { $ngti = "m"; }
	if( $ngti ) {
		print $q->a({href=>"$meurlfull?".optionstring({xgtype=>"$ngti"}), target=>"graph"},
			$q->img({src=>"${config{'routers.cgi-iconurl'}}zoomin.gif",
			alt=>langmsg(5017,"Zoom In"),border=>"0",width=>100,height=>20})),"&nbsp;\n";
	}
	if( $ngto ) {
		print $q->a({href=>"$meurlfull?".optionstring({xgtype=>"$ngto"}), target=>"graph"},
			$q->img({src=>"${config{'routers.cgi-iconurl'}}zoomout.gif",
			alt=>langmsg(5018,"Zoom Out"),border=>"0",width=>100,height=>20})),"&nbsp;\n";
	}
	print "</DIV>";
	print $q->br,"\n";
	} # csvmode
}
		
if(!$csvmode){
	print "<!-- CAMPIO=[$c][$a][$m][$p][$io] gtype=$gtype baropts=$baropts -->\n";
	do_footer();
} # csvmode
}

#######################################################
# This is for the summary of interfaces view
sub do_summary()
{
# Start off.  We use onload() and Javascript to force reload the 
# lefthand (menu) panel.
my ($javascript, $e);
my ($rrd, $curif);
my ($m, $a, $l );
my ($start,$step, $names, $data);
my ($savetz) = "";
my ($legendi, $legendo, $legendx);
my ($donehead) = 0;
my ($withdetails) = 1;
my ($doneone) = 0;
my ($inhtml) = 1;
my (@sorted);
my ($gheight) = 100;

calctimezone();

$javascript = make_javascript({}).graphpopupscript();

$withdetails = 0 if($interfaces{$interface}{nodetails});

if ( $gstyle =~ /2/ ) { $gheight = 200; } # double height
elsif ( $gstyle =~ /3/ ) { $gheight = 300; } # triple height
else { $gheight = 100; } # normal height

start_html_ss({  -expires => "+5s",  -script => $javascript,
	-onload => "LoadMenu()", -class=>'summary' },
	$interfaces{$interface}{xbackground}?$interfaces{$interface}{xbackground}:"");

print $q->center($q->h2($routers{$router}{desc}))."\n"
	if($routers{$router}{desc});

print "<DIV class=pagetop>";
print expandvars($config{'routers.cgi-pagetop'}),"\n"
	if( defined $config{'routers.cgi-pagetop'} );
if( defined $config{'routers.cgi-mrtgpagetop'} 
	and $config{'routers.cgi-mrtgpagetop'} =~ /y/i 
	and $interfaces{$interface}{pagetop}) {
	print expandvars($interfaces{$interface}{pagetop}),"\n";
}
print "</DIV>";
#
# Now for the RRD stuff
eval { require RRDs; };
if( $@ ) {
	if($config{'web-paranoia'}
		and $config{'web-paranoia'}=~/[yY1]/) {
		print $q->h1(langmsg(8999,"Error"))."<CODE>Cannot find RRDs.pm</CODE>\n";
	} else {
	print $q->h1(langmsg(8999,"Error"))."<CODE>Cannot find RRDs.pm in ".(join " ",@INC )."</CODE>\n";
		print $q->p("You can visit the configuration verification page "
			.$q->a({href=>("$meurlfull?page=verify&rtr=".$q->escape($router)),
			target=>"_new"},"here."));
	}
	do_footer();
	return;
}

if( $interfaces{$interface}{sortby} ) {
	@sorted = sorttargets($interface,$gtype,$interfaces{$interface}{sortby});
} else {
	# for historical compatibility
	@sorted = sort byifdesc @{$interfaces{$interface}{targets}};
}

print "<TABLE border=0 width=100% align=center class=summary>\n";

$savetz = $ENV{TZ};
$doneone = 0;
foreach $curif ( @sorted ) {
	next if(!$curif); # avoid rogue records

	if($interfaces{$interface}{active}) {
		next if(!isactive($curif));
	}

	($legendi,$legendo,$legendx)=(langmsg(2204,"IN:"),langmsg(2205,"OUT:"),"");
	$legendi = $interfaces{$curif}{legendi} 
		if(defined $interfaces{$curif}{legendi});
	$legendo = $interfaces{$curif}{legendo} 
		if(defined $interfaces{$curif}{legendo});
	$legendx = $interfaces{$curif}{legendx} 
		if(defined $interfaces{$curif}{legendx});

	if($interfaces{$interface}{overridelegend} and $interfaces{$curif}{shdesc}
		and ( $interfaces{$interface}{noo} or $interfaces{$interface}{noi} 
		or  $interfaces{$curif}{noo} or $interfaces{$curif}{noi} )
	){
		$legendi = $legendo = $interfaces{$curif}{shdesc}.':';
	}

	# timezone information
	if($interfaces{$curif}{timezone}) {
		$ENV{TZ} = $interfaces{$curif}{timezone} ;
		POSIX::tzset();
	}

	print "<TR WIDTH=100% VALIGN=TOP>" if($withdetails or !$doneone);
	print "<TD VALIGN=TOP>";

	if( $interfaces{$curif}{usergraph} ) {
		$rrd = $interfaces{$interfaces{$interface}{targets}->[0]}{rrd};
	} elsif( defined $interfaces{$curif}{rrd} ) {
		$rrd = $interfaces{$curif}{rrd};
	} else {
		$rrd = "";
	}
	if($rrdcached and $rrd and $rrdcached!~/^unix:/) {
		my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
		$rrd =~ s/^$pth\/*//;
	}
	if( $interfaces{$curif}{usergraph} ) {
		$lastupdate = RRDs::last($rrd,@rrdcached);
		$e = RRDs::error();
	} elsif( defined $interfaces{$curif}{rrd} ) {
		# Last update stuff.
		$lastupdate = RRDs::last($rrd,@rrdcached);
		$e = RRDs::error();
	} else {
		$e = langmsg(8002,"No RRD file defined for interface")." '$curif'";
	}
	if( $e ) {
		print $q->p($q->b(langmsg(8003,"Error reading RRD database")." $rrd")
			.$q->br."<I>$e</I>".$q->br
			."Check that MRTG has run successfully on this device, and has created the RRD file.")."\n";
		print $q->p("Check that rrdcached is running correctly on $rrdcached")
			if($rrdcached and ($e=~/No such file/));
		if(!$withdetails) {
			print "</TD>";
			if($doneone) { print "</TR>\n" ; $doneone = 0; } 
			else { $doneone = 1; }
		} else {
			print "</TD><TD>\n";
			print $q->h3($interfaces{$curif}{shdesc}),"\n";
			print $q->p($interfaces{$curif}{desc}),$q->br;
#		print $q->dump;
			print "</TD></TR>\n";
		}
		next;
	} 
	if(!$withdetails) {
		if($interfaces{$interface}{withtop}) {
			print $q->br."\n".$interfaces{$curif}{pagetop}.$q->br
				if($interfaces{$curif}{pagetop});
		}
	}
	print "<A href=".$meurlfull."?".optionstring({if=>"$curif"},
		target=>"graph").">";
	make_graph($inhtml,$gtype."s",$curif);
	print "</A>";
	if($interfaces{$curif}{usergraph}) {
		print $q->br.$q->small("User Graph: ".$q->i($curif));
	} else {
	print $q->br.$q->small("Target: ".$q->i($interfaces{$curif}{target}))
		if($interfaces{$curif}{target});
	}
	if(!$withdetails) {
		if($interfaces{$interface}{withfoot}) {
			print $q->br."\n".$interfaces{$curif}{pagefoot}
				if($interfaces{$curif}{pagefoot});
		}
		print "</TD>\n"; 
		if($doneone) { print "</TR>\n" ; $doneone = 0; } 
		else { $doneone = 1; }
		next;
	}
	print "</TD><TD>\n";
	print "<DIV class=summarydetails style=\"max-height: ${gheight}px;\" >";
	print $q->a({href=>"$meurlfull?".optionstring({if=>"$curif"}), 
		target=>"graph"}, $q->b($interfaces{$curif}{desc}));
	if($interfaces{$interface}{withtop} and $interfaces{$curif}{pagetop}) {
		print $q->br.$interfaces{$curif}{pagetop}."\n";
	}
	print $q->br,langmsg(3203,"Last update").": ".longdate($lastupdate),
		$q->br,"\n";
	print langmsg(3204,"Timezone").": ".$interfaces{$curif}{timezone}.$q->br."\n"
		if($interfaces{$curif}{timezone});

	if($interfaces{$curif}{usergraph}) {
		if($rrdoutput) {
			$donehead = 0;
			foreach ( @$rrdoutput ) {
				if( /^<TR>/i and !$donehead ) { 
					$donehead = 1; next;
				}
				print if(!$donehead);
			}
		}
	} else {
		if ( $interfaces{$curif}{max} 
			and !$interfaces{$curif}{nomax} ) {
				if ( defined $interfaces{$curif}{mblegend} ) { 
					print $interfaces{$curif}{mblegend}; 
				} elsif ( $interfaces{$curif}{isif} ) { print langmsg(2103,"Bandwidth"); }
				else { print langmsg(2102,"Maximum"); }
				if(defined $interfaces{$curif}{max1} 
					and defined $interfaces{$curif}{max2}) {
					print ": ".doformat( $interfaces{$curif}{max1},
						$interfaces{$curif}{fixunits},0)
						.$interfaces{$curif}{unit}."/"
						.doformat( $interfaces{$curif}{max2}, 
							$interfaces{$curif}{fixunits},0)
						.$interfaces{$curif}{unit}.$q->br,"\n";
				} else {
					print ": ".doformat( $interfaces{$curif}{max},
						$interfaces{$curif}{fixunits},0);
					print $interfaces{$curif}{unit}.$q->br,"\n";
				}
				if( defined $interfaces{$curif}{absmax} 
					and !$interfaces{$curif}{noabsmax} ) {
					if ( defined $interfaces{$curif}{amlegend} ) { 
						print $interfaces{$curif}{amlegend}; 
					} else { print langmsg(2104,"Hard Maximum"); }
					print ": ".doformat ($interfaces{$curif}{absmax},
						$interfaces{$curif}{fixunits},0)
						.$interfaces{$curif}{unit}.$q->br,"\n";
				}
			}
			print "Address: ".$interfaces{$curif}{address},$q->br,"\n"
				if ( $interfaces{$curif}{address} );
			print "Interface IP: ".$interfaces{$curif}{ipaddress},$q->br,"\n"
				if ( $interfaces{$curif}{ipaddress} );
			print "Interface # ".$interfaces{$curif}{ifno},$q->br,"\n" 
				if(defined $interfaces{$curif}{ifno});
			print "Interface name: ".$interfaces{$curif}{ifdesc},$q->br,"\n" 
				if($interfaces{$curif}{ifdesc});
# insert here the last/current/max values.
#			print @$rrdoutput if($rrdoutput);
		$donehead = 0;
		if($rrdoutput) {
			foreach ( @$rrdoutput ) {
				if( /^<TR>/i and !$donehead ) { 
					$donehead = 1;
					print "<TABLE border=1 cellspacing=0 class=summarydata><TR><TD></TD>";
				print $q->td($q->b($legendi)) if(!$interfaces{$curif}{noi});
				print $q->td($q->b($legendo)) if(!$interfaces{$curif}{noo});
				print $q->td($q->b($legendx)) if($legendx);
					print "</TR>\n";
				}
				print;
			}
		}
# now the 95th percentile, if required
		if(
#			( defined $config{'routers.cgi-percentile'}
#			and $config{'routers.cgi-percentile'} =~ /y/i )
			 $interfaces{$curif}{total}
			or $interfaces{$curif}{percentile}
		) {
			my( $pcdesc, $inarr, $outarr );
			if(!$donehead) {
				print "<TABLE border=1 cellspacing=0 class=summarydata><TR><TD></TD>";
				print $q->td($q->b($legendi)) if(!$interfaces{$curif}{noi});
				print $q->td($q->b($legendo)) if(!$interfaces{$curif}{noo});
				print $q->td($q->b($legendx)) if($legendx);
				print "</TR>\n";
				$donehead = 1;
			}
			( $pcdesc, $inarr, $outarr ) = calc_percentile($curif,$gtype,$PERCENT);	
			if($pcdesc) {
				if($interfaces{$curif}{total}) {
					print "<TR>".$q->td(langmsg(2301,"Total over")." $pcdesc:");
					print $q->td({ align=>"right"},doformat($$inarr[1],
$interfaces{$curif}{fixunits},$interfaces{$curif}{integer}) 
	.$interfaces{$curif}{totunit}) if(!$interfaces{$curif}{noi});
					print $q->td({ align=>"right"},doformat($$outarr[1],
$interfaces{$curif}{fixunits},$interfaces{$curif}{integer})
	.$interfaces{$curif}{totunit2}) if(!$interfaces{$curif}{noo});
					print "</TR>\n";
				}
				if($interfaces{$curif}{percentile}) {
					print "<TR>".$q->td(langmsg(2300,$PERCENT."th Percentile for")." $pcdesc:");
					print $q->td({ align=>"right"},doformat($$inarr[0],
$interfaces{$curif}{fixunits},0)
	.$interfaces{$curif}{unit}) if(!$interfaces{$curif}{noi});
					print $q->td({ align=>"right"},doformat($$outarr[0],
$interfaces{$curif}{fixunits},0)
	.$interfaces{$curif}{unit2}) if(!$interfaces{$curif}{noo});
				}
			} else {
				print "<TR>".$q->td(langmsg(8004,"Error in ${PERCENT}th percentile calcs").":")
					.$q->td($$inarr[2]).$q->td($$outarr[2])."\n";
			}
		}
		print "</TABLE>".$q->br."\n" if($donehead);
	} # not usergraph
	if($interfaces{$interface}{withfoot} and $interfaces{$curif}{pagefoot}) {
		print $interfaces{$curif}{pagefoot}."\n";
	}
	print "</DIV>";
	print "</TD></TR>\n";
	if($savetz){ $ENV{TZ}=$savetz; POSIX::tzset(); }
} # foreach
print "<TD></TD></TR>" if(!$withdetails and $doneone);
print "</TABLE>\n";

# Page foot
print "<DIV class=pagefoot>";
if( defined $config{'routers.cgi-mrtgpagefoot'} 
	and $config{'routers.cgi-mrtgpagefoot'} =~ /y/i 
	and $interfaces{$interface}{pagefoot}) {
	print expandvars($interfaces{$interface}{pagefoot}),"\n";
}
print expandvars($config{'routers.cgi-pagefoot'}),"\n"
	if( defined $config{'routers.cgi-pagefoot'} );
print "</DIV><DIV class=icons>";
if( $gstyle !~ /p/ ) {
	my( $u, $ngti, $ngto ) = ("","","");
	print $q->hr;
	print "\n",$q->a({href=>"javascript:location.reload(true)"},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}refresh.gif",
		alt=>langmsg(5003,"Refresh"),border=>"0",width=>100,height=>20})),"&nbsp;\n"
		if(!$archdate);
	print $q->a({href=>"$meurlfull?".optionstring({page=>"", bars=>"", xmtype=>"",
		xgstyle=>""}), target=>"_top" },
		$q->img({src=>"${config{'routers.cgi-iconurl'}}bookmark.gif",
		alt=>langmsg(5016,"Bookmark"),border=>"0",width=>100,height=>20})),"&nbsp;\n";
	if( $gtype eq "6" ) { $ngto = "d"; }
	elsif( $gtype eq "d" ) { $ngto = "w"; $ngti = '6' if($usesixhour); }
	elsif( $gtype eq "w" ) { $ngti = "d"; $ngto = "m"; }
	elsif( $gtype eq "m" ) { $ngti = "w"; $ngto = "y"; }
	elsif( $gtype eq "y" ) { $ngti = "m"; }
	if( $ngti ) {
		print $q->a({href=>"$meurlfull?".optionstring({xgtype=>"$ngti"}), target=>"graph"},
			$q->img({src=>"${config{'routers.cgi-iconurl'}}zoomin.gif",
			alt=>langmsg(5017,"Zoom In"),border=>"0",width=>100,height=>20})),"&nbsp;\n";
	}
	if( $ngto ) {
		print $q->a({href=>"$meurlfull?".optionstring({xgtype=>"$ngto"}), target=>"graph"},
			$q->img({src=>"${config{'routers.cgi-iconurl'}}zoomout.gif",
			alt=>langmsg(5018,"Zoom Out"),border=>"0",width=>100,height=>20})),"&nbsp;\n";
	}
		
	print $q->br,"\n";
}
print "</DIV>";
do_footer();
}

sub do_empty()
{
	my ($javascript);

	$javascript = make_javascript({});

	start_html_ss({ -expires => "+5s",  -script => $javascript,
		-onload => "LoadMenu()", -bgcolor => "#ffffff", -class=>'empty' });

	if( $router eq "none" ) {
		print $q->h3(langmsg(9002,"Please select a device"));
	} else {	
		print $q->h3(langmsg(9003,"Please select a target"));
	}
	do_footer();
}

sub do_graph($)
{
# Start off.  We use onload() and Javascript to force reload the 
# lefthand (menu) panel.
my ($javascript, $e);
my ($rrd, $curif);
my ($iconsuffix) = "";
my ($bgcolor,$legendi,$legendo,$legendx);
my ($inhtml) = $_[0]; # true if we want HTML page

calctimezone();

$iconsuffix = "-bw" if( $gstyle =~ /b/ );

$javascript = make_javascript({}).graphpopupscript();
# We need to subsequently add the javascript for the actuals array if necessary
$bgcolor = $defbgcolour;
$bgcolor = $interfaces{$interface}{background} if($interface and defined $interfaces{$interface} and defined $interfaces{$interface}{background});

if($inhtml) {
	my($class) = $interfaces{$interface}{mode}?$interfaces{$interface}{mode}:'generic';
	$class =~ s/^\177_//;
	start_html_ss({ -expires => "+5s",  -script => $javascript,
		-onload => "LoadMenu()", -bgcolor => $bgcolor,
		-class => $class },
	$interfaces{$interface}{xbackground}?$interfaces{$interface}{xbackground}:"");
}

# Catch for if there are NO cfg files.
if( ! $interface or ! $router
    or $interface eq "none" or $interface =~ /^__/  
	or $router eq "none" ) {
	if(!$inhtml) {
		if($opt_I) {
			print "Device: $router\nTarget: $interface\nError: no valid target was specified!\n";
		} else {
		print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
		}
		return;
	}
	print $q->h3(langmsg(9004,"No valid target is selected"));
	if( $#cfgfiles eq -1 
		and $config{'routers.cgi-cfgfiles'} ne 'none' ) {
		print $q->p("You have no valid MRTG configuration files.  You should check your configuration in $conffile.".$q->br."["
			.$config{'routers.cgi-confpath'}.$pathsep
			.$config{'routers.cgi-cfgfiles'}."]"),"\n";
		print $q->p("NT users should check that this includes the correct drive letter.")."\n" if($config{'web-NT'});
		print $q->p("confpath = ".$config{'routers.cgi-confpath'});
		print $q->p("cfgfiles = ".$config{'routers.cgi-cfgfiles'});
	}
	do_footer();
	return;
}

# Now for the RRD stuff
eval { require RRDs; };
if( $@ ) {
	if(!$inhtml) {
		if($opt_I) {
			print "Error: $@\n";
		} else {
		print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
		}
		return;
	}
	if($config{'web-paranoia'}
		and $config{'web-paranoia'}=~/[yY1]/) {
	print $q->h1(langmsg(8999,"Error")),"<CODE>cannot find RRDs.pm</CODE>\n";
	} else {
	print $q->h1(langmsg(8999,"Error")),"<CODE>cannot find RRDs.pm in ".(join " ",@INC)."</CODE>\n";
		print $q->p("You can visit the configuration verification page "
			.$q->a({href=>("$meurlfull?page=verify&rtr=".$q->escape($router)),
			target=>"_new"},"here."));
	}
	do_footer();
	return 0;
}
# Now, we have to do this differently depending on which gtype we have
# We do a switch for the different graphs.
# We have to call RRD to create them, and the IMG tag is created ready to
# stuff into the page!
$rrd = "";
if ( $interface =~ /^__/ ) { # compact and summary
	$curif = (keys(%interfaces))[0];
	$rrd = $interfaces{$curif}{rrd};
} elsif ( $interfaces{$interface}{usergraph} ) { #  user defined
	$rrd = $interfaces{$interfaces{$interface}{targets}->[0]}{rrd};
} else { 
	$rrd = $interfaces{$interface}{rrd}
		if( defined $interfaces{$interface}{rrd} );
}
if($rrd and $rrdcached and $rrdcached!~/^unix:/) {
	my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
	$rrd =~ s/^$pth\/*//;
}

# Timezone
if($interfaces{$interface}{timezone}) {
	$ENV{TZ} = $interfaces{$interface}{timezone} ;
	POSIX::tzset();
}

# Last update stuff.
if( $rrd ) {
	$lastupdate = RRDs::last($rrd,@rrdcached);
	$e = RRDs::error();
} else {
	$e = langmsg(8002,"No RRD file defined for interface")." '$interface'";
}
if( $e ) {
	if(!$inhtml) {
		if($opt_I) {
			print "Error: $e\n";
		} else {
		print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
		}
		return;
	}
	print $q->h3("$interfaces{$interface}{shdesc}"),"\n";
	print $q->p("$interfaces{$interface}{desc}"),"\n";
	if($config{'web-paranoia'}
		and $config{'web-paranoia'}=~/[yY1]/) {
	print $q->p($q->b(langmsg(8003,"Error reading RRD database")).$q->br."Check that MRTG has run successfully on this device, and has created the RRD file.  If using rrdcached, check that this is running and available.")."\n";
	} else {
	print $q->p($q->b(langmsg(8003,"Error reading RRD database")." $rrd").$q->br.$e.$q->br."Check that MRTG has run successfully on this device, and has created the RRD file.")."\n";
	print $q->p("Check that rrdcached is running on $rrdcached")
		if($rrdcached and ($e=~/No such file/));
	# We may need to give a more helpful error message here if the
	# user is asking for a nonexistant archive date
	print $q->p("You can visit the configuration verification page "
		.$q->a({href=>("$meurlfull?page=verify&rtr=".$q->escape($router)),
		target=>"_new"},"here."));
	}
#	print $q->dump;
} else {
	# any defined pagetop stuff
	if($inhtml) {
		print "<DIV class=pagetop>";
		print expandvars($config{'routers.cgi-pagetop'}),"\n"
			if( defined $config{'routers.cgi-pagetop'} );
		if((( defined $config{'routers.cgi-mrtgpagetop'} 
			and $config{'routers.cgi-mrtgpagetop'} =~ /y/i 
			and !$interfaces{$interface}{usergraph})
			or $interfaces{$interface}{withtop} ) 
			and $interfaces{$interface}{pagetop}
		) {
			print expandvars($interfaces{$interface}{pagetop}),"\n";
		}
		print "</DIV>";
	}
	my $suffix = ( $gtype =~ /s/ ) ? "s" : "";
	$suffix .= "-" if( $gtype =~ /-/ );
	if( defined $interfaces{$interface}{suppress} ) {
		my $pat = "[".$interfaces{$interface}{suppress}."]";
		$gtype =~ s/$pat//g;
	}
	foreach my $gt ( '6','d','w','m','y' ) {
		next if ( $gtype !~ /$gt/ );
		print $q->h4($gtypes{$gt}) if((length($gtype)>1) and ($gtype!~/s/));  
		make_graph($inhtml,"$gt$suffix",$interface) ;
		print $q->br,"\n" if($inhtml and (length($gtype) > 2 or $uopts=~/s/)
			and ($gtype!~/s/));
	}

	return if(!$inhtml); # we can leave now

	print $q->br;
	print "<TABLE border=0>";
	print "<TR><TD>".langmsg(3205,"Data archived")
		.":</TD><TD>$archdate</TD></TR>\n" if($archdate and !$basetime);
	print "<TR><TD>".langmsg(3203,"Last update").": </TD><TD>"
		.longdate($lastupdate)."</TD></TR>\n" unless($basetime);
	print "<TR><TD>".langmsg(3204,"Timezone").":</TD><TD>"
		.$interfaces{$interface}{timezone}."</TD></TR>\n"
		if($interfaces{$interface}{timezone});
	print "</TABLE>\n";
	if((
#		( defined $config{'routers.cgi-percentile'}
#		and $config{'routers.cgi-percentile'} =~ /y/i )
		   $interfaces{$interface}{total}
		or $interfaces{$interface}{percentile}
		) and !$interfaces{$interface}{nodetails}
		and !$interfaces{$interface}{nolegend}
		) {
		my( $i, $pcdesc, $inarr, $outarr, $sfx );

		print "<TABLE border=0 >\n";

		# Loop through interfaces, if on userdefined graph
		foreach $curif ( $interfaces{$interface}{usergraph}?
			(@{$interfaces{$interface}{targets}}):($interface) ) {
		# Skip this if it is not an active graph
		if($interfaces{$interface}{active}) { next if(!isactive($curif)); }
		print "<TR><TD colspan=5 align=left>"
			.$q->a({href=>("$meurlfull?".optionstring({
					'if'=>$curif, 'page'=>'graph'
				} ))}, $q->i($interfaces{$curif}{desc}))
			."</TD></TR>\n"
			if($interfaces{$interface}{usergraph});

		$sfx = "";
		($legendi,$legendo,$legendx)=(langmsg(2204,"IN:"),langmsg(2205,"OUT:"),"");
		$legendi=$interfaces{$curif    }{legendi} 
			if(defined $interfaces{$curif    }{legendi});
		$legendo=$interfaces{$curif    }{legendo} 
			if(defined $interfaces{$curif    }{legendo});
		$legendx=$interfaces{$curif    }{legendx} 
			if(defined $interfaces{$curif    }{legendx});
		$legendi =~ s/ /&nbsp;/g; $legendo =~ s/ /&nbsp;/g;
		$sfx = "-" if( $gtype =~ /-/ );
		# Loop through time periods, if on multiple graphs
		foreach $i  ( qw/d w m y/ ) {
		  next if((index $gtype, $i) < 0);
		  ( $pcdesc, $inarr, $outarr ) = calc_percentile($curif,$i.$sfx,$PERCENT);
		  if($pcdesc) {
#			print "<TR>".$q->td("").$q->td($q->b($legendi))
#				.$q->td($q->b($legendo));
		    if($interfaces{$interface}{total}) {
			print "<TR>".$q->td($q->b(langmsg(2301,"Total over")." $pcdesc:"));
			print $q->td($legendi).$q->td({align=>"right"},doformat($$inarr[1],
$interfaces{$curif    }{fixunits},$interfaces{$curif    }{integer})
	.$interfaces{$curif    }{totunit}) 
	.$q->td("") if(!$interfaces{$interface}{noi});
			print $q->td($legendo).$q->td({align=>"right"},doformat($$outarr[1],
$interfaces{$curif    }{fixunits},$interfaces{$curif    }{integer})
	.$interfaces{$curif    }{totunit2})
	.$q->td("")  if(!$interfaces{$interface}{noo});
			print "</TR>\n";
		    }
		    if($interfaces{$interface}{percentile}) {
			my($pclabel);
			print "<TR>".$q->td($q->b(langmsg(2300,$PERCENT."th Percentile for")." $pcdesc:"));
			if(!$interfaces{$interface}{noi} and !$interfaces{$curif}{noi}) {
				$pclabel = "";
				$pclabel = " ("
				  .doformat(($$inarr[0]/$interfaces{$curif}{max}*100.0),1,0)
				  ."%)" if($interfaces{$curif}{percent} and $interfaces{$curif}{max});
				print $q->td($legendi).$q->td({align=>"right"},
					doformat($$inarr[0], $interfaces{$curif}{fixunits},0) 
					.$interfaces{$curif}{unit}) ;
				print $q->td($pclabel);
			  }
			  if(!$interfaces{$interface}{noo} and !$interfaces{$curif}{noo}) {
				$pclabel = "";
				$pclabel = " ("
				  .doformat(($$outarr[0]/$interfaces{$curif}{max}*100.0),1,0)
				  ."%)" 
					if($interfaces{$curif}{percent} 
						and $interfaces{$curif}{max});
				print $q->td($legendo).$q->td({align=>"right"},
					doformat($$outarr[0], $interfaces{$curif}{fixunits},0)
					.$interfaces{$curif}{unit2}) ;
				print $q->td($pclabel);
			  }
			  print "</TR>\n";
		    }
		  } else {
			print "<TR><TD>".langmsg(8004,"Error in ${PERCENT}th percentile")
			.":</TD><TD colspan=5>"
			."[".$$inarr[2]."]".$q->br
			."[".$$outarr[2]."]</TD></TR>" if($$inarr[2] or $$outarr[2]);
		  } # pcdesc
		} # foreach	timeperiod
		} # foreach interface
		print "</TABLE>\n";
	}

	print $q->br."<DIV class=pagefoot>";
	if((( defined $config{'routers.cgi-mrtgpagefoot'} 
		and $config{'routers.cgi-mrtgpagefoot'} =~ /y/ 
		and !$interfaces{$interface}{usergraph})
		or $interfaces{$interface}{withfoot})
		and $interfaces{$interface}{pagefoot}
	) {
		print expandvars($interfaces{$interface}{pagefoot}),"\n";
	}
	print expandvars($config{'routers.cgi-pagefoot'}),"\n"
		if( defined $config{'routers.cgi-pagefoot'} );
	print "</DIV><DIV class=extensions>";

	# any extensions defined for this target?
	if( defined $interfaces{$interface}{extensions} 
		and $uopts !~/s/ ) {
		my($ext, $u, $targ);
		print $q->hr,"\n";
		foreach $ext ( @{$interfaces{$interface}{extensions}} ) {
			if($seclevel<$ext->{level}) {
#				print $ext->{desc}." (".$ext->{level}.")".$q->br."\n";
				next;
			}
			$targ = "graph";
			$targ = $ext->{target} if( defined $ext->{target} );
			$u=$ext->{url};
			if(!$ext->{noopts}) {
			$u .= "?x=2" if( $u !~ /\?/ );
			$u .= "&fi=".$q->escape($router)."&ta="
				.$q->escape($interface)."&url=".$q->escape($q->url());
			$u .= "&t=".$q->escape($targ); 
			$u .= "&L=".$seclevel; 
			$u .= "&uopts=".$uopts if($uopts); 
			$u .= "&h=".$q->escape($interfaces{$interface}{hostname}) 
				if(defined $interfaces{$interface}{hostname});
			$u .= "&c=".$q->escape($interfaces{$interface}{community})
				if(defined $interfaces{$interface}{community} 
				and $ext->{insecure});
			$u .= "&ifno=".$interfaces{$interface}{ifno}
				if(defined $interfaces{$interface}{ifno});
			$u .= "&b=".$q->escape("javascript:history.back();history.back()")
				."&conf=".$q->escape($conffile);
				$u .= "&ad=$archdate" if($archdate);
			} elsif( $ext->{noopts} == 2 ) {
				$u .= "&L=$seclevel&xgtype=$gtype&xgstyle=$gstyle";  
				$u .= "&arch=$archdate" if($archdate);
			}
			print $q->img( { height=>15, width=>15,
				src=>($config{'routers.cgi-smalliconurl'}.$ext->{icon}) })
				."&nbsp;";
#			print $q->img( { height=>15, width=>15,
#				src=>($config{'routers.cgi-iconurl'}."alert-sm.gif") })
#				."&nbsp;" if($ext->{insecure});
			print $q->a( { href=>$u, target=>$targ },
					expandvars($ext->{desc})).$q->br."\n";
		}
	}

	print "</DIV><DIV class=icons>";
	# routers.cgi page footer
	if( $gstyle !~ /p/ ) {
		my( $u, $ngti, $ngto ) = ("","","");
	print $q->hr;
	print "\n",$q->a({href=>"javascript:location.reload(true)"},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}refresh$iconsuffix.gif",alt=>langmsg(5003,"Refresh"),border=>"0",width=>100,height=>20})),"\n"
		if(!$archdate);
#	print $q->a({href=>"javascript:parent.makebookmark('"
#		.$q->escape($router)."','".$q->escape($interface)
#		."','$gtype','$gstyle','$gopts','$baropts','".$q->escape($extra)."')"},
	print $q->a({href=>"$meurlfull?".optionstring({page=>"", bars=>"",
		xmtype=>"", xgstyle=>""}), target=>"_top" },
		$q->img({src=>"${config{'routers.cgi-iconurl'}}bookmark$iconsuffix.gif",alt=>langmsg(5016,"Bookmark"),border=>"0",width=>100,height=>20})), "\n";
	if( $gtype eq "6" ) { $ngto = "d"; }
	elsif( $gtype eq "d" ) { $ngto = "w"; $ngti='6' if($usesixhour); }
	elsif( $gtype eq "w" ) { $ngti = "d"; $ngto = "m"; }
	elsif( $gtype eq "m" ) { $ngti = "w"; $ngto = "y"; }
	elsif( $gtype eq "y" ) { $ngti = "m"; }
	if( $ngti ) {
		print $q->a({href=>"$meurlfull?".optionstring({xgtype=>"$ngti"}), target=>"graph"},
			$q->img({src=>"${config{'routers.cgi-iconurl'}}zoomin.gif",
			alt=>langmsg(5017,"Zoom In"),border=>"0",width=>100,height=>20})),"\n";
	}
	if( $ngto ) {
		print $q->a({href=>"$meurlfull?".optionstring({xgtype=>"$ngto"}), target=>"graph"},
			$q->img({src=>"${config{'routers.cgi-iconurl'}}zoomout.gif",
			alt=>langmsg(5018,"Zoom Out"),border=>"0",width=>100,height=>20})),"\n";
	}
#	if(!$interfaces{$interface}{usergraph}) {
	print $q->a({href=>"$meurlfull?".optionstring({page=>"csv"}), target=>"graph"},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}csv.gif",
		alt=>langmsg(5019,"CSV Download"),border=>"0",width=>100,height=>20})),"\n";
#	}
	if( defined $config{'routers.cgi-archive'} 
		and $config{'routers.cgi-archive'} =~ /[y1]/i ) {
		print $q->a({href=>"$meurlfull?".optionstring({page=>"archive"}), 
			target=>"graph"},
			$q->img({src=>"${config{'routers.cgi-iconurl'}}archive.gif",
			alt=>langmsg(5020,"Add to archive"),border=>"0",width=>100,height=>20})),"\n";
	}
	my($nuopts) = $uopts; # 3-way toggle
	if($nuopts =~ /r/) {
		$nuopts =~  s/r/R/g;
	} elsif($nuopts =~ /R/) {
		$nuopts =~  s/[rR]//g;
	} else {
		$nuopts .= 'r';
	}
	print $q->a({href=>"$meurlfull?".optionstring({uopts=>"$nuopts"}), 
		target=>"graph"},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}rescale.gif",
		alt=>langmsg(5021,"Rescale"),border=>"0",width=>100,height=>20})),"\n";

	print $q->br,"\n";

		
	} # gstyle not p
	print "</DIV>";
}
# Finish off the page (this does the ending body and html tags)
do_footer();
}

# Information on this router
sub do_info()
{
# Start off.  We use onload() and Javascript to force reload the 
# lefthand (menu) panel.
my ($javascript, $ifkey,$x, $icon);
my ($acount,$archivepat,@archive,$archives);

$javascript = make_javascript({});

start_html_ss({ -expires => "+5s",  -script => $javascript, 
	-onload => "LoadMenu()", -class=>'info' });

# Here we build up a page of info, with lotsalinks.

print $q->center($q->h2($routers{$router}{desc}))."\n";

print $q->h3(langmsg(3004,"Device Information")),"\n";

print $q->a({href=>"$meurlfull?".optionstring({page=>"graph",if=>"_summary_"}),
	target=>"graph"},
	$q->b("$router: ".$routers{$router}{shdesc}.": "
		.$routers{$router}{desc})),$q->br,"\n";
print $q->br.$q->b(langmsg(3005,"MRTG config file").": ").$routers{$router}{file}."\n";
print $q->br.$q->p("WorkDir: ".($routers{$router}{workdir}?$routers{$router}{workdir}:$config{'routers.cgi-dbpath'}))."\n";
print $q->b("Targets:").$q->br();
print "<UL>";
$ifkey = ""; # we want this later
foreach (sort byifdesc keys (%interfaces)) {
	next if(!$_); # avoid rogue records
	next if(/^__/);
	next if($interfaces{$_}{mode} =~ /^\177_AUTO/); # system created
	# count archived copies
	$archivepat = $router; $archivepat =~ s/[\?#\\\/]//g;
	$archivepat = $config{'routers.cgi-graphpath'}.$pathsep
		.$archivepat.$pathsep.$_.$pathsep."*.*";
	@archive = glob($archivepat);
	$acount = $#archive + 1;
	# now the data line
	$icon = $q->img({src=>($config{'routers.cgi-smalliconurl'}.$interfaces{$_}{icon})
		,width=>15,height=>15})." ";
	$ifkey = $_ if(!$ifkey and $interfaces{$_}{community} 
		and $interfaces{$_}{hostname});
	if( $acount == 1 ) {
		$archives = $q->br.langmsg(3300,"This target has one archived graph.");
	} elsif( $acount > 1 ) {
		$archives = $q->br.langmsg(3301,"This target has")
			." $acount ".langmsg(3302,"archived graphs.");
	} else {
		$archives = "";
	}
	if( $interfaces{$_}{usergraph} ) {
		print $q->li( $icon.$q->a( 
			{href=>"$meurlfull?".optionstring({if=>"$_"}),
			target=>"graph"},
			$interfaces{$_}{desc})." [$_] "
			.($interfaces{$_}{graphstyle}?("&lt;".$interfaces{$_}{graphstyle}."&gt;"):"")
			.($interfaces{$_}{default}?"[DEFAULT]":"")
			." \n$archives");
	} elsif( defined $interfaces{$_}{ifno} ) {
		# interface number
		print $q->li( $icon.$q->a( 
			{href=>"$meurlfull?".optionstring({if=>"$_"}),
			target=>"graph"},
			"#".$interfaces{$_}{ifno}.": ".$interfaces{$_}{desc}
		)." [".$interfaces{$_}{target}."] ".langmsg(6200,"Max")." "
			.doformat($interfaces{$_}{max},$interfaces{$_}{fixunits},1)
			.$interfaces{$_}{unit}
			." {".$interfaces{$_}{mode}."} "
			.($interfaces{$_}{default}?"[DEFAULT]":"")
			."\n$archives"),"\n";
	} elsif( defined $interfaces{$_}{ifdesc} ) {
		# interface description
		print $q->li( $icon.$q->a( 
			{href=>"$meurlfull?".optionstring({if=>"$_"}),
			target=>"graph"},
			$interfaces{$_}{shdesc}.": ".$interfaces{$_}{desc}
		)." [".$interfaces{$_}{target}."] ".langmsg(6200,"Max")." "
			.doformat($interfaces{$_}{max},$interfaces{$_}{fixunits},1)
			.$interfaces{$_}{unit}
			." {".$interfaces{$_}{mode}."} "
			.($interfaces{$_}{default}?"[DEFAULT]":"")
			."\n$archives"),"\n";
	} elsif( defined $interfaces{$_}{ipaddress} ) {
		# IP address
		print $q->li( $icon.$q->a( 
			{href=>"$meurlfull?".optionstring({if=>"$_"}),
			target=>"graph"},
			$interfaces{$_}{ipaddress}.": ".$interfaces{$_}{desc}
		)." [".$interfaces{$_}{target}."] "
				.langmsg(6200,"Max")." "
			.doformat($interfaces{$_}{max},$interfaces{$_}{fixunits},1)
				.$interfaces{$_}{unit}
			." {".$interfaces{$_}{mode}."} "
			.($interfaces{$_}{default}?"[DEFAULT]":"")
			."\n$archives"),"\n";
	} else {
		# userdefined and unknown
		print $q->li( $icon.$q->a( 
			{href=>"$meurlfull?".optionstring({if=>"$_"}),
			target=>"graph"},
			$interfaces{$_}{desc})." [".$interfaces{$_}{target}."] "
				.langmsg(6200,"Max")." "
				.doformat($interfaces{$_}{max},$interfaces{$_}{fixunits},1)
				.$interfaces{$_}{unit}
#				."(f=".$interfaces{$_}{factor}.",m=".$interfaces{$_}{mult}.")"
				." {".$interfaces{$_}{mode}."}"
				.($interfaces{$_}{graphstyle}?("&lt;".$interfaces{$_}{graphstyle}."&gt;"):"")
				.($interfaces{$_}{default}?"[DEFAULT]":"")
				."\n$archives"
			),"\n";
	}
}
print "</UL>\n";

# Can we call out to the routingtable.cgi program?
if( defined $config{'routers.cgi-routingtableurl'} 
	and ( !defined $routers{$router}{routingtable}
		or $routers{$router}{routingtable} eq "y" )) {
	if($ifkey) {
	print $q->a({target=>"_self",
		href=>($config{'routers.cgi-routingtableurl'}
		."?r=".$q->escape($interfaces{$ifkey}{hostname})
		."&h=".$q->escape($interfaces{$ifkey}{hostname})
		."&c=".$q->escape($interfaces{$ifkey}{community})
		."&url=".$q->escape($q->url())
		."&t=graph&b=javascript:".$q->escape("history.back();history.back()")
		."&conf=".$q->escape($conffile))},
		langmsg(3303,"Show routing table for this device"))." (may take some time)",
			$q->br,$q->br,"\n";
	} else {
		print langmsg(3304,"Routing table information not available."),$q->br,
			$q->br,"\n";
	}
}

# Finish off the page (this does the ending body and html tags)
do_footer();
}

############################################################################
# Export of data to CSV format -- single RRD
sub do_export()
{
	my( $start, $step, $names, $data, $line);
	my( $mstart, $mstep, $mnames, $maxdata, $mline );
	my( $rrd, @opts, $e, $d, $t, $i, $r, @dat );
	my( $thisif, $startpoint, $endpoint, $resolution );
	
	my( @allifs );

	$comma = substr( $config{'web-comma'},0,1 )
		if(defined $config{'web-comma'});
	$comma = ',' if(!$comma);
	
	eval { require RRDs; };
	if( $@ ) {
 		print "ERROR".$comma."Cannot find RRDs.pm!".$comma.$@;
		return;
	}
	if( !$interface ) {
		print langmsg(9004,"No interface selected!");
		return;
	}

	# If this is a normal one, then just one interface.  If it is a
	# userdefined, then we wil have a list of targets to process.
	@allifs = ( $interface );
	@allifs = @{$interfaces{$interface}{targets}}
		if( $interfaces{$interface}{targets} );
	
	foreach $thisif ( @allifs ) {

	# Header line
	print "\"Hostname\"$comma\"Target\"$comma\"Sample Date YMD\"$comma\"Sample Time HHMM\"$comma\"Count in seconds\"";
	if( $interfaces{$thisif}{aspercent}) {
		print "$comma\"Raw data 1\""
		if($interfaces{$thisif}{legend1} and !$interfaces{$thisif}{noi});
		print "$comma\"Raw data 2\""
		if($interfaces{$thisif}{legend2} and !$interfaces{$thisif}{noo});
	} elsif( $interfaces{$thisif}{dorelpercent} ) {
		print "$comma\"Raw data 1\"";
		print "$comma\"Raw data 2\"";
	}
	print "$comma\"".$interfaces{$thisif}{legend1}.($interfaces{$thisif}{unit}?
		(' in '.$interfaces{$thisif}{unit}):'').'"'
		if($interfaces{$thisif}{legend1} and !$interfaces{$thisif}{noi});
	print "$comma\"".$interfaces{$thisif}{legend2}.($interfaces{$thisif}{unit}?
		(' in '.$interfaces{$thisif}{unit}):'').'"'
		if($interfaces{$thisif}{legend2} and !$interfaces{$thisif}{noo});
	if( $gtype !~ /6/ ) {
	if( $interfaces{$thisif}{aspercent} ) {
		print "$comma\"Raw max data 1\""
		if($interfaces{$thisif}{legend1} and !$interfaces{$thisif}{noi});
		print "$comma\"Raw max data 2\""
		if($interfaces{$thisif}{legend2} and !$interfaces{$thisif}{noo});
	} elsif( $interfaces{$thisif}{dorelpercent} ) {
		print "$comma\"Raw max data 1\"";
		print "$comma\"Raw max data 2\"";
	}
	print "$comma\"".$interfaces{$thisif}{legend3}.($interfaces{$thisif}{unit}?
		(' in '.$interfaces{$thisif}{unit}):'').'"'
		if($interfaces{$thisif}{legend3} and !$interfaces{$thisif}{noi});
	print "$comma\"".$interfaces{$thisif}{legend4}.($interfaces{$thisif}{unit}?
		(' in '.$interfaces{$thisif}{unit}):'').'"'
		if($interfaces{$thisif}{legend4} and !$interfaces{$thisif}{noo});
	}
	print "\r\n";
	$i = $interfaces{$thisif}{shdesc};
	$r = $routers{$router}{desc};
	$r = $interfaces{$thisif}{hostname} if(!$r);
	$r = $router if(!$r);
	$r = "Unknown" if(!$r);

	$rrd = $interfaces{$thisif}{rrd};
	if($rrd and $rrdcached and $rrdcached!~/^unix:/) {
		my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
		$rrd =~ s/^$pth\/*//;
	}
	foreach ( $gtype ) {
		/y/ and do { $resolution = 3600; $startpoint = "-1y"; 
			last; };
		/m/ and do { $resolution = 1800; $startpoint = "-1month"; 
			last; };
		/w/ and do { $resolution = 300; $startpoint = "-7d"; 
			last; };
		/6/ and do { $resolution = 60*$interfaces{$thisif}{interval}; 
			$startpoint = "-6h"; last; };
		$resolution = 60*$interfaces{$thisif}{interval}; # interval
		$startpoint = "-24h"; # 1 day
	}
	$resolution = 300 if(!$resolution);

	if($basetime) {
		@opts = ( $rrd, "AVERAGE", "-e", $basetime, 
			"-s", "end".$startpoint );
	} elsif( $gtype =~ /-/ ) {
		@opts = ( $rrd, "AVERAGE", "-e", "now".$startpoint, 
			"-s", "end".$startpoint );
	} elsif( $uselastupdate ) {
		$lastupdate = RRDs::last($rrd,@rrdcached);
		$e = RRDs::error();
		if(!$lastupdate) {
			print "Error reading rrd:\n$e\n";
			return;
		}
		if($archivetime and $uselastupdate > 1 ) {
		@opts = ( $rrd, "AVERAGE", "-e", $archivetime, "-s", "end".$startpoint );
		} else {
		@opts = ( $rrd, "AVERAGE", "-e", $lastupdate, "-s", "end".$startpoint );
		}
	} else {
		@opts = ( $rrd, "AVERAGE", "-s", $startpoint );
	}

	# Fetch data
	( $start, $step, $names, $data ) = RRDs::fetch( @opts,@rrdcached );
	if( !$start or !$data ) {
		$e = RRDs::error();
		print "Error retrieving data - do you have enough stored?\n";
		print "Check that you have enough real data gathered to be able to export.\n";
		print "$e\n";
		return;
	}
	if( $gtype !~ /6/ ) {
		$opts[1] = 'MAX';
		( $mstart, $mstep, $mnames, $maxdata ) = RRDs::fetch( @opts,@rrdcached );
		# maxdata may now be null, if we dont have a MAX RRA available.
	} else {
		$maxdata = 0; # 6-hour graphs never have MAX available.
	}

	# Print data
	foreach $line ( @$data ) {
		@dat = localtime $start;
		$d = sprintf "%04d/%02d/%02d",($dat[5]+1900),($dat[4]+1),$dat[3];
		$t = sprintf "%02d:%02d",$dat[2],$dat[1]; # hh:mm
		print "\"$r\"$comma\"$i\"$comma$d$comma$t$comma$start";
		if($interfaces{$thisif}{aspercent} ) {
			printf "$comma%12.4f", ($$line[0]*$interfaces{$thisif}{mult}) 
				if(!$interfaces{$thisif}{noi});
			printf "$comma%12.4f", ($$line[1]*$interfaces{$thisif}{mult})
				if(!$interfaces{$thisif}{noo});
			printf "$comma%12.4f", 100.0*($$line[0]/$interfaces{$thisif}{max}) 
				if(!$interfaces{$thisif}{noi});
			printf "$comma%12.4f", 100.0*($$line[1]/$interfaces{$thisif}{max})
				if(!$interfaces{$thisif}{noo});
		} elsif( $interfaces{$thisif}{dorelpercent}) {
			printf "$comma%12.4f", ($$line[0]*$interfaces{$thisif}{mult});
			printf "$comma%12.4f", ($$line[1]*$interfaces{$thisif}{mult});
			printf "$comma%12.4f", 100.0*($$line[0]/$$line[1]);
		} else {
			printf "$comma%12.4f", ($$line[0]*$interfaces{$thisif}{mult}*$interfaces{$thisif}{factor}) 
				if(!$interfaces{$thisif}{noi});
			printf "$comma%12.4f", ($$line[1]*$interfaces{$thisif}{mult}*$interfaces{$thisif}{factor})
				if(!$interfaces{$thisif}{noo});
		}
		if($gtype !~ /6/) {
		  if($maxdata) {
			$mline = shift @$maxdata;
			$mline = [ 0,0 ] if(!$mline); # in case data runs out
			if($interfaces{$thisif}{aspercent} ) {
			printf "$comma%12.4f", ($$mline[0]*$interfaces{$thisif}{mult}) 
				if(!$interfaces{$thisif}{noi});
			printf "$comma%12.4f", ($$mline[1]*$interfaces{$thisif}{mult})
				if(!$interfaces{$thisif}{noo});
			printf "$comma%12.4f", 100.0*($$mline[0]/$interfaces{$thisif}{max}) 
				if(!$interfaces{$thisif}{noi});
			printf "$comma%12.4f", 100.0*($$mline[1]/$interfaces{$thisif}{max})
				if(!$interfaces{$thisif}{noo});
			} elsif( $interfaces{$thisif}{dorelpercent}) {
				printf "$comma%12.4f", ($$mline[0]*$interfaces{$thisif}{mult});
				printf "$comma%12.4f", ($$mline[1]*$interfaces{$thisif}{mult});
				printf "$comma%12.4f", 100.0*($$mline[0]/$$mline[1]);
			} else {
				printf "$comma%12.4f", ($$mline[0]*$interfaces{$thisif}{mult}*$interfaces{$thisif}{factor}) 
					if(!$interfaces{$thisif}{noi});
				printf "$comma%12.4f", ($$mline[1]*$interfaces{$thisif}{mult}*$interfaces{$thisif}{factor})
					if(!$interfaces{$thisif}{noo});
			}
		  } else {
			printf "$comma%12.4f", ($$line[0]*$interfaces{$thisif}{mult}*$interfaces{$thisif}{factor}) 
				if(!$interfaces{$thisif}{noi});
			printf "$comma%12.4f", ($$line[1]*$interfaces{$thisif}{mult}*$interfaces{$thisif}{factor})
				if(!$interfaces{$thisif}{noo});
			if($interfaces{$thisif}{aspercent}) {
				printf "$comma%12.4f", 100.0*($$line[0]/$interfaces{$thisif}{max}) 
					if(!$interfaces{$thisif}{noi});
				printf "$comma%12.4f", 100.0*($$line[1]/$interfaces{$thisif}{max})
					if(!$interfaces{$thisif}{noo});
			} # aspercent
		  } # maxdata exists
		} # not 6
		printf "\r\n";
		$start += $step;
	} # foreachline

	} # next interface in list

}
############################################################################
# Help page

sub do_help()
{
	my($vurl,$iurl);
	my($javascript);

	$javascript = make_javascript({if=>"__none",rtr=>"none"});

	start_html_ss({-script => $javascript, -onload => "LoadMenu()",
		-class=>'help' });

	$vurl = "$meurlfull?page=verify&rtr=".$q->escape($router);
	$iurl = $config{'routers.cgi-smalliconurl'};

	print $q->h1(langmsg(3006,"Information and Help"));

	print <<EOT
<h2>Updates and support</h2>
Updates to the routers.cgi script may be obtained from
<a href=$APPURL>$APPURL</a>. During development phases there may be daily 
updates, so check every so often.  Support is available via the 
<a href=$FURL>support forum</a>,
<a href=$MLURL>mailing list</a> and 
directly - check <a href=$APPURL>this link</a> for more details.
<HR>
<h2>Publications</h2>
The new MRTG/RRD/Routers2 book, 
<a href=$BURL target=_top>Using MRTG with RRDtool and Routers2</a>, can be 
obtained in dead-tree format from <A HREF=$BURL target=_top>here</a>.  
This should be able to help you to make the most of your MRTG installation, 
and also help with any installation and configuration problems!
<hr>
<h2>Online help</h2>
<UL>
<li>Diagnose configuration problems 
<a target=_new href=$vurl>here</a> (opens new window)</li>
<li>Show available link icons 
<a target=_new href=$iurl>here</a> (opens new window)</li>
</UL>
<hr>
<h2>Credits</h2>
Thanks to the following people for supporting the development of 
this software by <a target=_new href=$WLURL >
sending me a gift</a> on my Wishlist!
All listed in no particular order, in case you were wondering.
<UL>
<LI>Pall Wiberg Joensen, Faroese Telecom, Faroe Islands</li>
<li>Ben Higgins, Dovetail Internet, USA</li>
<li>Mike Bernhardt, Arsin, USA</li>
<li>EDS Europe</li>
<li>Ruedi Kehl, Manor AG, Switzerland (twice!)</li>
<li>Allied Domecq, UK</li>
<li>Rob</li>
<li>Peter Cohen, Telia, USA</li>
<li>Jay Christopherson</li>
<li>David Hares, Network One</li>
<li>Reuben Farrelly, Netfilter, Australia</li>
<li>Network Operations, Roche Diagnostics GmbH, Germany</li>
<li>Keith Johnson, UK</li>
<li>J Herrera, Brown Publishing</LI>
<li>Kristin Gorman, New York, USA</li>
<li>Inigo T Storm, ASV AG, Hamburg, Germany</li>
<li>M Williams, London, UK</li>
<li>Joseph Truong, USA</li>
<LI>Babul Mukherjee, The Montopolis Group, San Antonio, USA</li>
<li>Matevz Turk, Slovenia</li>
<li>Barry Basselgia; the most generous contributor so far</li>
<li>Gary Higgs</li>
<li>Scott Monk, USA</li>
<li>Robert Gibson, Texas, USA</li>
<li>Andrew McClure, Santa Barbara, USA</li>
<li>Innokentiy Georgeievskiy, Moscow, Russia (Twice!)</li>
<li>Kirsten Johnson</li>
<li>Matti Wiersmuller, Switzerland</li>
<li>University of Auckland, New Zealand</li>
<li>Steven Hay, Alberta, Canada.</li>
<LI>Dan Lowry, Scituate, USA</li>
<LI>Alan Dean, Prospect, USA</li>
<LI>Thomas Thong, Alameda, USA</li>
<LI>Steve McDonald, Indiana, USA</li>
<LI>Harry Edmondson, USA</li>
<LI>Saul Herbert/Hugh David, ADV Films, UK and Australia</li>
<li>Francesco Duranti, Kuwait Petroleum Italia</li>
<li>Herman Poon, Ontario, Canada</li>
<li>Peter Hall, Texas, USA</li>
<li>Casey Scott, F5 Networks, USA</li>
<li>Steve Litchfield, Georgia, USA</li>
<li>Rodrigo Schneider</li>
<li>Christopher Noyes, CT, USA</li>
<li>GroundWork Open Systems, USA</li>
<li>Ask.com, USA</li>
<li>Andrew Lewis</li>
<li>Yuriy Vlasov</li>
<li>Scott Neader</li>
<LI>Dave Diamond, USA</LI>
<LI>Timothy Graham</li>
<LI>Matthew Elmore, AL, USA</LI>
<li>Plus various generous but anonymous people</li>

</ul>
V2.0 Beta testers:
<UL>
<li>Garry Cook, MacTec Inc.</li>
<li>Ed Stalnaker, Rollins Corp, USA</li>
<li>Francesco Duranti, Kuwait Petroleum Italia</li>
<li>Neil Pike, Protech Computing</li>
<li>Brian Wilson, North Carolina State University</li>
<li>Martijn Koopsen, Energis NL</li>
</UL>
Contributors:
<UL>
<li>Ed Stalnaker (modified cfgmaker script)</li>
<li>Brian Wilson, Garry Cook, Aid Arslanagic, Andy Jezierski, Leo Artnts, James Keane, Todd Wiese, Jim Harbin (alternative icon sets)</li>
<li>Many other people for suggestions and bug reports.</li>
</UL>
Additional thanks to all the other people who have assisted by sending in
bug reports and suggestions for improvement.  Also, major thanks to 
Tobi Oetiker, the author of <a href=http://www.mrtg.org/ target=_new>MRTG</a>
and <a href=http://www.rrdtool.org/ target=_new>RRDTool</a>, without whom 
this interface would never have been created.
<hr>
<h2>Legal Jargon</h2>
This software is available under the GNU GPL.  More information is available
in the text files accompanying this software, or on the web site.  Please note
that this software is provided without any warranty, or guarantee, and you
use it at your own risk.  In no event shall myself, my employers, or the 
owner of any
web site distributing this software, be held liable for any loss or damage 
caused as a result of the use or misuse of this software or the instructions
that accompany it.
<p>
EOT
;
	do_footer();
}

# set cookies etc. for defaults.
# the way we do this is by refreshing ourself with extra parameters.
# The existence of the extra parameters causes the cookie to be set.
sub do_config()
{
	my ( $javascript, %routerdesc, $k );
	my (%langs,$langfile,$langdir,$cc);
	my ($explore);

	$javascript = make_javascript({if=>"__none",rtr=>"none"});

	start_html_ss({-script => $javascript, -onload => "LoadMenu()",
		-class=>'config' }); 
	print $q->h2(langmsg(3007,"Personal Preferences")),"\n";

	$explore = 'y';
	$explore = $config{'routers.cgi-allowexplore'}
		if( defined $config{'routers.cgi-allowexplore'} );

	if( $q->param('xset') ) {
		print $q->p($q->b(langmsg(9005,"Options have been saved."))),"\n";
	}

	# Load language definitions
	%langs = ();
	$langs{''} = langmsg(3008,"No Preference");
	if(defined $config{'web-langdir'}) { $langdir = $config{'web-langdir'} ; } 
	else { $langdir = dirname($conffile); }
	foreach $langfile ( glob( $langdir.$pathsep."lang_*.conf" ) ) {
		if( -r $langfile and $langfile =~ /lang_(.+)\.conf/ ) {
			$cc = $1;
			open LANG,"<$langfile";
			while ( <LANG> ) {
				chomp;
				if( /^\s*description\s*=\s*(.*)/ ) { $langs{$cc} = $1; last; }
			}
			close LANG;
		}
	}

	# Load routers definitions
	foreach ( keys %routers ) { $routerdesc{$_} = $routers{$_}{desc}; }
	$routerdesc{''} = langmsg(3008,"No preference");
	
	if($config{'routers.cgi-6hour'} =~ /y/i ) {
		@gorder = ( '6', @gorder ) if($gorder[0] ne "6");
	}

	print $q->p(langmsg(3107,"Options set here will persist over future invocations of this script.  Note that this uses cookies, so you must have them enabled."));

	print $q->hr;
	print "<FORM METHOD=GET ACTION=$meurlfull>\n";
	
# now a couple of hidden fields to preserve mtype and page
	print $q->hidden({ name=>"page", value=>"config", -override=>1 }),"\n",
		$q->hidden({ name=>"xmtype", value=>$mtype, -override=>1 }) ,"\n",
		$q->hidden({ name=>"xset", value=>"yes" }) ,"\n";

# Now the main fields, defrouter and defgtype.  Dropdown lists.  In a table.

	$defgstyle = $q->cookie('gstyle');
	$defgstyle = 'n' if(!$defgstyle);

	print $q->table( { -border=>0 },
		(( $explore =~ /[1y]/i )?
		$q->Tr( { -border=>"0", align=>"left" } ,
			$q->td(langmsg(3100,"Default device:") )."\n", $q->td( 
				$q->popup_menu( {name=>"defrouter", 
					values=>["",sort bydesc keys(%routers)],
					labels=>{%routerdesc}, default=>$q->cookie('router')})
			)."\n" 
		):""),
		(( $explore =~ /[1yi]/i )?
		$q->Tr( { -border=>"0", align=>"left" } ,
			$q->td(langmsg(3101,"Default target/interface:") )."\n", $q->td( 
				$q->popup_menu({ name=>"defif", values=>["",
					"__first",
					"__interface","__cpu","__memory","__summary",
					"__compact", "__incoming","__outgoing","__info",
					"__userdef" ],
					labels=>{__first=>langmsg(3012,"First target"), 
						__summary=>langmsg(3013,"Summary page"),
						__info=>langmsg(3021,"Info Page"), 
						__cpu=>langmsg(3016,"CPU performance"),
						__memory=>langmsg(3017,"Memory Usage"), 
						__userdef=>langmsg(3018,"First user graph"),
						__interface=>langmsg(3019,"First Interface target"),
						__incoming=>langmsg(3014,"Incoming Graph"), 
						__outgoing=>langmsg(3015,"Outgoing graph"),
						__compact=>langmsg(3020,"Compact Summary"),
						""=>langmsg(3008,"No preference") }, 
					default=>$q->cookie('if') })
			)."\n" 
		):""),
		$q->Tr( { -border=>"0", align=>"left" } ,
			$q->td(langmsg(3102,"Default graph type:") )."\n", $q->td( 
				$q->popup_menu({ name=>"defgtype", values=>[@gorder],
					labels=>{%gtypes}, default=>$q->cookie('gtype') })
			)."\n" 
		),
		$q->Tr( { -border=>"0", align=>"left" } ,
			$q->td(langmsg(3103,"Default graph style:") )."\n", $q->td( 
				$q->popup_menu({ name=>"defgstyle", values=>[@sorder],
					labels=>{%gstyles}, default=>"$defgstyle" })
			)."\n" 
		),
		$q->Tr( { -border=>"0", align=>"left" } ,
			$q->td(langmsg(3106,"Default language:") )."\n", $q->td( 
				$q->popup_menu({ name=>"deflang", values=>[sort keys %langs],
					labels=>{%langs}, default=>"$language" })
			)."\n" 
		),
		$q->Tr( { align=>"left" },
			$q->td(""),$q->td(
				$q->submit({ name=>"Submit", value=>langmsg(3104,"Set Defaults") })
			)."\n"
		)
	),"\n";

	print "</FORM>";

	print $q->br({clear=>"BOTH"}),"\n";

	print $q->center($q->b($q->a({target=>"_top",href=>$meurlfull},
		langmsg(3105,"Go to the current default page")))).$q->br,"\n";

	do_footer();
}

###########################
# Show an archive graph.

sub do_archive($)
{
	my( $javascript, $thisgraph, $thisgraphurl );
	my( $inhtml ) = $_[0];

	$javascript = make_javascript({archive=>$archive});

	if($inhtml) {
		start_html_ss({ -script => $javascript, -onload => "LoadMenu()" ,
#			-class=>($interfaces{$interface}{mode}?$interfaces{$interface}{mode}:'archive')
			-class=>'archive'
		}, $interfaces{$interface}{xbackground}?$interfaces{$interface}{xbackground}:"");
	}

	$thisgraphurl = $router; $thisgraphurl =~ s/[\?#\\\/]//g;
	$thisgraph = $thisgraphurl;
	$thisgraph = $config{'routers.cgi-graphpath'}.$pathsep.$thisgraph
		.$pathsep.$interface.$pathsep.$archive;
	$thisgraphurl = $config{'routers.cgi-graphurl'}.'/'.$thisgraphurl
		.'/'.$interface.'/'.$archive;

	if($inhtml) {
	print $q->h2({class=>'archive'},langmsg(3009,"Archive graph"));
	# any defined pagetop stuff
	print "<DIV class=pagetop>";
	print expandvars($config{'routers.cgi-pagetop'}),"\n"
		if( defined $config{'routers.cgi-pagetop'} );
	if( defined $config{'routers.cgi-mrtgpagetop'} 
		and $config{'routers.cgi-mrtgpagetop'} =~ /y/i 
		and $interfaces{$interface}{pagetop}
		and !$interfaces{$interface}{usergraph} ) {
		print expandvars($interfaces{$interface}{pagetop}),"\n";
	}
	print "</DIV>";
	}

	if( -f $thisgraph ) {
		if($inhtml) {
			print $q->img({ src=>$thisgraphurl, alt=>$archive }).$q->br."\n";
		} else {
			#output the graph in binmode XXX
		}
	} else {
		if($inhtml) {
			print $q->p($q->b(langmsg(3010,"This graph has been deleted.")))."\n";
		} else {
			# redirect to error
			if($opt_I) {
				print "Error: This graph has been deleted.\n";
			} else {
			print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
			}
			return;
		}
	}

	if( $inhtml and $archive =~ /(\d+)-(\d+)-(\d+)-(\d+)-(\d+)-([dwmys6]+)\./ ) {
		# try to get local formatting
		my( $dformat ) = "%c";
		$dformat = $config{'web-dateonlyformat'}
			if(defined $config{'web-dateonlyformat'});
		$dformat = $config{'web-shortdateformat'}
			if(defined $config{'web-shortdateformat'});
		if(!$dformat) {
			print $q->br, $q->p(langmsg(3200,"Archive time").": $4:$5 $3/$2/$1 ("
				.$gtypes{$6}.")");
		} else {
			print $q->br, $q->p(langmsg(3200,"Archive time").": "
				.POSIX::strftime($dformat,0,$5,$4,$3,($2-1),($1-1900))
				." (".$gtypes{$6}.")");
		}
	}
	if($inhtml) {
	print $q->br."<DIV class=pagefoot>";
	if( defined $config{'routers.cgi-mrtgpagefoot'} 
		and $config{'routers.cgi-mrtgpagefoot'} =~ /y/ 
		and $interfaces{$interface}{pagefoot}
		and !$interfaces{$interface}{usergraph}  ) {
		print expandvars($interfaces{$interface}{pagefoot}),"\n";
	}
	print expandvars($config{'routers.cgi-pagefoot'}),"\n"
		if( defined $config{'routers.cgi-pagefoot'} );
	print "</DIV>";

	print "<DIV class=icons>";
	print $q->hr."\n";
#	print $q->a({href=>"javascript:parent.makearchmark('"
#		.$q->escape($router)."','".$q->escape($interface)
#		."','".$q->escape($extra)."','$archive')"},
	print $q->a({href=>"$meurlfull?".optionstring({page=>"", bars=>"", xmtype=>"",
		archive=>"$archive", xgtype=>"", xgstyle=>""}), target=>"_top"},
		$q->img({src=>"${config{'routers.cgi-iconurl'}}bookmark.gif",
		alt=>langmsg(5016,"Bookmark"),border=>"0",width=>100,height=>20})),"\n";

	# only for Yes, not for Read
	if( $config{'routers.cgi-archive'} =~ /y/i ) {
	print $q->a( { href=>$meurlfull.'?'.optionstring({archive=>$archive,
		page=>'graph',delete=>1}) },
		$q->img({ border=>0, alt=>langmsg(5022,"Delete this graph"), width=>100, height=>20,
			src=>$config{'routers.cgi-iconurl'}."delete.gif" })).$q->br;
	}
	print "</DIV>";
	do_footer();
	} # inhtml
}

###########################
# Verification of everything.
# This is more a debug utility, really.  We display all the routers and
# interfaces, also the available icons and check the sanity of the
# routers.conf, and the graph directory.

sub yesno($)
{
	if(!$_[0]) { print $q->td({bgcolor=>"#ff0000",align=>"center",class=>"no"},"No"); }
	else { print $q->td({bgcolor=>"#00ff00",align=>"center",class=>"yes"},"Yes"); }
}
sub do_verify()
{
	my($server,$iconpath, $ipath, $confpath, $iconurl,$graphpath, $graphurl);
	my($curif, $key, $rtr);
	my($testfile, $okfile);
	my($username) = "";
	my($e,$rrdok, $rrdinfo);
	my($archroot,@days,$rrdfilename);
	my($s)="";

	$server = "localhost";
	$server = $2 if($meurl =~ /http(s?):\/\/([\w\.\-]+)\//);
	$s = "s" if($1);
	$confpath = $config{'routers.cgi-confpath'};
	$graphpath = $config{'routers.cgi-graphpath'};
	$graphurl = $config{'routers.cgi-graphurl'};
	$iconurl = $config{'routers.cgi-smalliconurl'};
	$ipath = $iconurl; $ipath =~ s#/#\\#g if($NT);
	$iconpath = $graphpath.$pathsep."..".$ipath;
	$iconpath = $graphpath.$pathsep."..".$pathsep."..".$ipath
		if(!-d $iconpath);
	$iconpath = "" if(!-d $iconpath);
	$username = $q->remote_user if($q->remote_user);

	start_html_ss({-title=>langmsg(3011,"Configuration Verification"),
		-class=>'verify'});

	print $q->h1(langmsg(3011,"Configuration Verification"));
	print $q->ul(
		$q->li($q->a({href=>"#conf"},"Check routers.conf")),
		$q->li($q->a({href=>"#files"},"Check MRTG files")),
		$q->li($q->a({href=>"#targets"},"Check MRTG targets")),
		$q->li($q->a({href=>"#icons"},"Check available icons")),
		$q->li($q->a({href=>"#settings"},"Configuration settings"))
	).$q->hr."\n";

	print $q->a({name=>"conf"},$q->h2("routers.conf check"))."\n";
	print $q->p("This will check a number of the more critical definitions in the routers.conf file, and will give you any warnings for items that are a worry.")."\n";
	print "<TABLE align=center border=1 class=verify>\n";
	print "<TR><TD>Script name</TD><TD>$myname  (Version $VERSION)</TD></TR>\n";
	print "<TR><TD>Configuration file<br>$conffile</TD>\n";
	if( -r $conffile ) { print "<TD>Exists and is readble</TD></TR>\n"; }
	else { print "<TD background=#ff0000>Unable to read file</TD></TR>\n"; }
	print "<TR><TD>Authenticated username</TD><TD>$username</TD></TR>\n"
		if($username);
	print "<TR><TD>Graphs path<br>$graphpath</TD>\n";
	if( -d $graphpath ) {
		$testfile = $graphpath.$pathsep
			."verylongfilename-------------testfile.png";
		if( open TEST, ">$testfile"  ) {
			print "<TD>Directory exists and is writeable</TD></TR>\n";
			close TEST;
			unlink $testfile;
		} else {
			print "<TD background=#ff0000>Unable to create files in directory!</TD></TR>\n"; 
		}
	} else {
		print "<TD background=#ff0000>Directory does not exist!</TD></TR>\n"; 
	}
	print "<TR><TD>Graph URL<br>$graphurl</TD>\n";
	$testfile = $graphpath.$pathsep."redsquare.png";
	unlink $testfile if( -f $testfile );
	if( open GRAPH, ">$testfile" ) {
		binmode GRAPH;
		# this generates a PNG of a red square.
		print GRAPH
"\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\017\0\0\0\017\001\003\0\0\0\001\030"
."\a\t\0\0\0\003PLTE\377\0\0\031\342\t7\0\0\0\fIDATx\234c` \001\0\0\0-\0"
."\001\305\327\300\206\0\0\0\0IEND\256B`\202";
		close GRAPH;
		print "<TD>This should show a red square --&gt;"
			.$q->img({src=>$graphurl."/redsquare.png",alt=>"Red Square",
				width=>15,height=>15})
			."&lt;--<br>\n";
		print "If it doesn't, then your graphurl does not match your graphpath.</TD></TR>\n";
	} else {
		print "<TD background=#ff0000>Unable to create test file!<br>Check your graphpath setting above.</TD></TR>\n"; 
	}

	print "<TR><TD>Icon URL<br>$iconurl</TD><TD>\n";
	print "This should show a target --&gt;"
		.$q->img({src=>$iconurl."target-sm.gif",width=>15, height=>15})
		."&lt;--<br>\n"
  		."If it doesn't, then there is a problem.</td></tr>\n";
	print "<TR><TD>MRTG files<br>Path: ".$confpath
		.$q->br."Files: ".$config{'routers.cgi-cfgfiles'}."</TD>\n";
	if( @cfgfiles ) {
		print "<TD>".($#cfgfiles + 1)." files detected OK.";
	} else {
		if(!-d $confpath) {
			print "<TD gcolor=#ff0000>Directory does not exist or is not readable!";
		} else {
			print "<TD gcolor=#ff0000>No files found that match this pattern!";
		}
	}
	print "</TD></TR>\n";
	print "<TR><TD>Perl libraries<br>RRDs, GD</TD><TD>\n";	
	eval { require RRDs; };
	if($@) { 
		print $q->b("RRDs library NOT FOUND.")." This may however not be a problem if the library path is amended by the <b>LibAdd</b> birective in the MRTG files.".$q->br;
		print $@.$q->br;
		$rrdok = 0;
	} else {
		my($v);
		# RRDTool v1.0.x reported version as 1.000xx for 1.0.xx
		# RRDTool v1.{2,3,4}.x report version as 1.abbb for 1.a.bbb
		$RRDs::VERSION =~ /(\d+)\.(\d)(\d+)/ ;
		$v = "$1.".($2 + 0).".".($3 + 0);
		print "RRDs library found OK (Version $v)<br>";
		print "You should upgrade to at least v1.0.36 to avoid problems.<BR>"
			if($RRDs::VERSION < 1.00036);
		$rrdok = 1
			if($RRDs::VERSION < 1.00036);
	}
	if( $config{'routers.cgi-stylesheet'}  ) {
		print "GD library not required as operating in StyleSheet mode<BR>\n";
	} elsif( $config{'routers.cgi-compact'} =~ /n/i ) {
		print "GD library not required as compact is disabled in routers.conf<BR>\n";
	} else {
		eval { require GD; };
		if($@) {
			print $q->b("GD library NOT FOUND.")." This would not be a problem if you had compact=no in the routers.conf.".$q->br;
			print $@;
		} else {
			print "GD library found OK";
			my $gd = new GD::Image(1,1);
			eval { print ": Ver ".$GD::VERSION."<BR>"; };
			eval { # must eval because old versions dont have 'can' or VERSION
				if( $gd->can('png') ) { print "- PNG Supported<BR>"; }
				else { print "- PNG NOT supported<BR>"; }
				if( $gd->can('gif') ) { print "- GIF Supported<BR>"; }	
				else { print "- GIF NOT supported<BR>"; }
				if( $config{'web-png'} and !$gd->can('png')) {
					print "WARNING: You have PNG enabled in the routers2.conf but your GD does not support it!<BR>";
				}
				if( !$config{'web-png'} and !$gd->can('gif')) {
					print "WARNING: You do not have PNG enabled in the routers2.conf but your GD does not support GIFs!<BR>";
				}
			};
		}
	}
	if( $config{'web-rrdcached'} or $ENV{RRDCACHED_ADDRESS} ) {
		print "Config file sets rrdcached options to ".$config{'web-rrdcached'}."<BR>" if($config{'web-rrdcached'});
		print "Environment sets rrdcached options to ".$ENV{RRDCACHED_ADDRESS}."<BR>" if($ENV{RRDCACHED_ADDRESS});
		if( $RRDs::VERSION < 1.4 ) {
			print "You cannot use rrdcached with this version of the RRD library!<BR>\n";
		} elsif( $RRDs::VERSION < 1.4999 ) {
			print "You cannot ONLY use rrdcached with UNIX sockets with this version of the RRD library!<BR>\n";
		}
		
	}
	print "</TD></TR><TR><TD>Routingtable extensions</TD><TD>";
	if(defined $config{'routers.cgi-routingtableurl'}) {
		eval { require Net::SNMP; };
		if($@) {
			print $q->b("Net::SNMP library NOT FOUND.")." This means that the routingtable extensions will NOT WORK.  You should therefore either install this package, or disable the extensions in the routers.conf.".$q->br;
			print $@;
		} else {
			print "Net::SNMP library found OK and extensions are enabled.";
		}
	} else {
		print "Routing table extensions are not enabled.";
	}
	print "</TD></TR></TABLE>\n";

	print $q->hr.$q->a({name=>"files"},$q->h2("MRTG files check"))."\n";
	print $q->p("There files are taken from the <b>cfgpath</b> and <b>cfgfiles</b> directives in the <b>[routers.cgi]</b> section of the routers.conf file.  If no files are listed below, then you should check that these definitions are correct.");
	print "confpath = ".$q->code($confpath).$q->br."\n";
	print "cfgfiles = ".$q->code($config{'routers.cgi-cfgfiles'}).$q->br."\n";

	print $q->br."<TABLE align=center border=1 class=verify>\n";
	print "<TR><TD>MRTG file name</td><td>Description</td><td>Visible</td><td>Valid</td><td>Notes</td></tr>\n";
	foreach $rtr ( keys %routers ) {
		print "<TR><TD>";
		print $q->img({src=>$iconurl.$routers{$rtr}{icon},width=>15, height=>15})." " if(defined $routers{$rtr}{icon});
		print $q->a({href=>("$meurlfull?page=verify&rtr=".$q->escape($rtr))},$rtr);

		if( $rtr !~ /^#/ ) {
		$okfile = $confpath.$pathsep.$rtr;
		$okfile =~ s/\.conf$/.ok/; $okfile =~ s/\.cfg$/.ok/;
		print "<BR><B><font color=#ff0000>No .ok file found</font></b><br>\n"
			."Have you successfully run MRTG on this file yet?" 
				if(!-f $okfile);
		}
		print "</TD><TD>".$routers{$rtr}{shdesc}."</TD>";
		yesno $routers{$rtr}{inmenu};
		yesno $routers{$rtr}{hastarget};
		print "<TD><TABLE border=0>";
		print "<TR><TD>Group:</TD><TD>".$routers{$rtr}{group}."</TD></TR>"
			if($routers{$rtr}{group});
		print "<TR><TD>Server:</TD><TD>".$routers{$rtr}{server}."</TD></TR>"
			if($routers{$rtr}{server});
		print "<TR><TD>Hostname:</TD><TD>".$routers{$rtr}{hostname}."</TD></TR>"
			if($routers{$rtr}{hostname});
		print "</TABLE></TD></TR>\n";
	}
	print "</TABLE>";

	print $q->hr.$q->a({name=>"targets"},$q->h2("MRTG targets check"))."\n";
	print "Current device: ".$q->b($router)." (".$routers{$router}{desc}.")".$q->br."\n";
	print "MRTG file: ".$q->code($routers{$router}{file}).$q->br."\n"
		if($routers{$router}{file});
	print $q->p("These targets are read from the MRTG file, and then displayed according to how they are interpreted.");
	print "<BR><TABLE border=1 align=center>\n";
	print "<TR><TD>Target<br>RRD File</TD><TD>Mode</TD><TD>In Menu</TD><TD>In Summary</TD><TD>In/Out</TD><TD>In Compact</TD><TD>Archives</TD><TD>Notes</TD></TR>\n";
	foreach $curif ( keys %interfaces ) {
		next if($interfaces{$curif}{usergraph});
		print "<TR><TD>";
		print $q->img({src=>$iconurl.$interfaces{$curif}{icon},width=>15, height=>15})." " if(defined $interfaces{$curif}{icon});
		print "$curif<br>".$interfaces{$curif}{rrd};
		if(!$rrdcached and !-r $interfaces{$curif}{rrd}) {
		print "<BR><B><font color=#ff0000>Unable to read RRD file!</font></B>"
		}
		print "</TD><TD>".$interfaces{$curif}{mode}."</TD>";
		yesno $interfaces{$curif}{inmenu};
		yesno $interfaces{$curif}{insummary};
		yesno $interfaces{$curif}{inout};
		yesno $interfaces{$curif}{incompact};
		print "<TD>";
		@days = ();
		if(defined $interfaces{$curif}{origrrd}) {
			$rrdfilename = $interfaces{$curif}{origrrd};
		} else {
			$rrdfilename = $interfaces{$curif}{rrd};
		}
		if($rrdfilename) {
			$archroot  = dirname($rrdfilename).$pathsep.'archive';
			$rrdfilename = basename($rrdfilename);
			if( defined $cachedays{$rrdfilename} ) {
				@days = @{$cachedays{$rrdfilename}};
				$debugmessage .= "fromcache(dates:$rrdfilename)\n";
			}  else {
				foreach ( sort rev findarch( $archroot,$rrdfilename ) ) {
					if( /(\d\d)(\d\d)-(\d\d)-(\d\d)/ ) { 
						push @days, "$1$2-$3-$4"; }
				}
				$cachedays{$rrdfilename} = [ @days ]; # Cache for later
				$debugmessage .= "cached[dates:$rrdfilename]\n";
			}
			print ( $#days + 1 );
			print " from ".$days[$#days] if($#days > -1);
		} else {
			print "N/A";
		}
		print "</TD><TD>";
		if($rrdok and -r $interfaces{$curif}{rrd}) {
			$rrdinfo = RRDs::info($interfaces{$curif}{rrd},@rrdcached);
			$e = RRDs::error();
			if(defined $rrdinfo and !$e) {
				print "RRD file format is legal.";
				print "<BR>Interval ".($rrdinfo->{step}/60)
					." minute(s)" if($rrdinfo->{step} != 300);
				print "<BR><B>Not in MRTG format!</B>"
					if(!defined $rrdinfo->{"ds[ds0].type"});
				print "<BR>Extended timeframe"
					if($rrdinfo->{"rra[0].rows"} > 799);
			} else {
				print $q->b("Error reading rrd:").$q->br.$e;
			}
		} else { print "N/A"; }
		print "</TD>\n";
	}
	print "</TABLE>\n";

	print $q->hr.$q->a({name=>"icons"},$q->h2("Available Icons"))."\n";
	print "The available icons should be located in the <b>rrdicons</b> directory, currently defined to be:".$q->br."\n";
	print "URL: ".$q->code("http$s://$server".$config{'routers.cgi-smalliconurl'}).$q->br;
	print "If the menu page is installed, you can get to it "
		.$q->a({href=>$config{'routers.cgi-smalliconurl'}},"here").".".$q->br."\n";
	if($iconpath and -d $iconpath ) {
		# show available icons in here
		my( $c ) = 0; my($f,$b);
		print $q->br."<TABLE border=1 align=center>\n<TR>";
		foreach $f ( glob( $iconpath.$pathsep."*-sm.gif" ) ) {
			$b = basename $f;
			$c++;
			if($c eq 5) { $c = 1; print "</TR>\n<TR>"; }
			if( -r $f ) {
			print "<TD>".$q->img({src=>($iconurl.$b), width=>15, height=>15});
			print " ".$b."</TD>";
			} else {
				print "<TD bgcolor=#ff0000>Unable to read file $b</TD>";
			}
		}
		print "</TR></TABLE>";

		# verify
		print $q->p("If the above images do not display, then you may need to correct the <b>iconurl</b> parameter in the <b>[routers.cgi]</b> section of your routers.conf file.");
	} else {
		print "Checked directory $iconpath<br>\n";
		print $q->p("Unable to locate icon files in order to list them.  This is not necessarily a problem!  If the following image does not display, then you may need to correct the <b>iconurl</b> parameter in the <b>[routers.cgi]</b> section of your routers.conf file.");
	}
	print "This should show a target --&gt;"
		.$q->img({src=>$iconurl."target-sm.gif",width=>15, height=>15});
	print "&lt;--.  If it does not, correct your <b>iconurl</b> setting."
		.$q->br."\n";

	print $q->hr.$q->a({name=>"settings"},
		$q->h2("Active Configuration Settings"))."\n";
	print $q->p("These are the active settings, after taking into account any overrides due to application name ('$myname'), extra parameters ('$extra'), or authenticated user name ('$authuser').")."\n";
	print "<UL>\n";
	foreach ( sort keys %config ) {
		if( $_ eq 'web-auth-key' ) {
		print $q->li($q->b($_)." = \"<I>not displayed</I>\"")."\n";
		} else {
		print $q->li($q->b($_)." = \"".$config{$_}."\"")."\n";
		}
	}
	print "</UL>".$q->br;
	do_footer();
}

###########################
# If we get a bad page request

sub do_bad($)
{
	start_html_ss({-title=>"routers.cgi Error",-bgcolor=>"#ffd0d0",
		-class=>'error'});
	print $q->h1(langmsg(8005,"Bad page request"));
	print $q->p("Error message was [".$_[0]."]")."\n";
	print $q->p(langmsg(8007,"Check the format of the URL parameters for the page you are requesting."))."\n";
	if(!$config{'web-paranoia'}
		or $config{'web-paranoia'}=~/[nN0]/) {
		eval { print $q->dump; };
	}
	print $q->hr.$q->small("Error message generated by routers2.cgi")."\n";
	print $q->end_html();
}

########################################################################
# MAIN CODE STARTS HERE
########################################################################
# Initialise parameters

$bn = lc basename $q->url(-absolute=>1);
$myname = $bn if($bn);

$opt_D = $opt_r = $opt_T = $opt_i = $opt_U = $opt_s = $opt_t = $opt_A = "";
$opt_I = $opt_C = $opt_a = "";
getopts('GAICD:T:r:i:s:t:a:U:');
$opt_D = $opt_r if($opt_r); $opt_T = $opt_i if($opt_i); # override

# Avoid IIS pathinfo bug
if( $^O !~ /Win/ or $q->server_software()!~/IIS|Microsoft/i ) { 
	@pathinfo = split '/',$q->path_info() if($q->path_info()); 
}

$pagetype="";
$pagetype=$q->param('page') if( defined $q->param('page') );
$pagetype=$q->param('xpage')if( defined $q->param('xpage'));# stupid persistence
$pagetype='image' if(! defined $q->param('page') 
	and $q->param('xgstyle') and ($q->param('xgstyle')=~/[AB]/));
if($myname =~ /thumbnail\.(cgi|pl)/) { $pagetype = 'image'; $defgstyle = 'A'; }
$pagetype="graphCOMMAND" if($opt_A or $opt_D); # command line archive or generate
$pagetype="imageCOMMAND" if($opt_I or $opt_G); # command line image
$pagetype="csvCOMMAND" if($opt_C); # command line CSV extract
#$pagetype="graph" if(defined $q->param('searchhost'));
$pagetype="main" if(!$pagetype);
$archive = "";
if( $q->param('archive') ){
	$archive = $q->param('archive');
}
# Deal with Authentication requests FIRST, before reading conf.
if( $pagetype eq 'login' ) {
	# generate login page
	login_page;
	print "<!--- login page requested --->\n";
	exit 0;
}
if( $pagetype eq 'logout' ) {
	# generate logout page
	logout_page;
	exit 0;
}
if( $q->param('username') ) {
	# someone is trying to log in
	if( user_verify( $q->param('username'), $q->param('password') ) ) {
		# OK
		$authuser = $q->param('username');
	} else {
		# bad login: force it again
		force_login(langmsg(1005,"Invalid username/password combination"));
		exit 0;
	}
} elsif($opt_U) {
	$authuser = $opt_U; # only via command line
} else {
	# get username from other sources
	$authuser = verify_id;
}

# get these sections from the conf file.
$extra = lc $q->param('extra') if($q->param('extra'));
readconf( 'routers.cgi','web','routerdesc','targetnames','targettitles',
	'targeticons', 'servers', 'menu' ); 
initlang(undef); # initialise the language module, if defined

# Paranoia
$pagetype="main" if($pagetype eq "verify" and $config{'web-paranoia'}
	and $config{'web-paranoia'}=~/[yY1]/);

if(defined $config{'routers.cgi-percent'} 
	and $config{'routers.cgi-percent'}=~/(\d\d?\d?)/ ) {
	$PERCENT = $1;
}

# Generate archived graphs
if($pagetype =~ /archive/) {
	$pagetype = "graph";
	$archiveme = 1 if($config{'routers.cgi-archive'}=~/[y1]/i);
}

# Allow override for broken web servers
$meurlfull = $config{'routers.cgi-myurl'} 
	if( defined $config{'routers.cgi-myurl'} );

# Now, if we have forced security, and no authuser, then force the
# login page regardless.
if( defined $config{'web-auth-required'} 
	and $config{'web-auth-required'} =~ /^[1y]/i  and !$authuser ) {
	force_login(langmsg(1006,"Authorisation is required to view these pages"));
	exit 0;
}
# otherwise, if we have an authuser, set the cookie.
if($authuser) { 
	push @cookies, generate_cookie; 
	$headeropts{-cookie} = [@cookies]; 
}

# Find out our security level
$seclevel = $config{'routers.cgi-level'} 
	if( defined $config{'routers.cgi-level'} );

# background colour (for the americans)
if ( defined $config{'routers.cgi-bgcolor'} 
	and $config{'routers.cgi-bgcolor'} =~ /(#[\da-fA-F]{6})/i ) {
	$defbgcolour = $1;
}
if ( defined $config{'routers.cgi-fgcolor'} 
	and $config{'routers.cgi-fgcolor'} =~ /(#[\da-fA-F]{6})/i ) {
	$deffgcolour = $1;
}
if ( defined $config{'routers.cgi-menufgcolor'} 
	and $config{'routers.cgi-menufgcolor'} =~ /(#[\da-fA-F]{6})/i ) {
	$menufgcolour = $1;
}
if ( defined $config{'routers.cgi-menubgcolor'} 
	and $config{'routers.cgi-menubgcolor'} =~ /(#[\da-fA-F]{6})/i ) {
	$menubgcolour = $1;
}
if ( defined $config{'routers.cgi-authfgcolor'} 
	and $config{'routers.cgi-authfgcolor'} =~ /(#[\da-fA-F]{6})/i ) {
	$authfgcolour = $1;
}
if ( defined $config{'routers.cgi-authbgcolor'} 
	and $config{'routers.cgi-authbgcolor'} =~ /(#[\da-fA-F]{6})/i ) {
	$authbgcolour = $1;
}
if ( defined $config{'routers.cgi-linkcolor'} 
	and $config{'routers.cgi-linkcolor'} =~ /(#[\da-fA-F]{6})/i ) {
	$linkcolour = $1;
}
# background colour (for the british)
if ( defined $config{'routers.cgi-bgcolour'} 
	and $config{'routers.cgi-bgcolour'} =~ /(#[\da-fA-F]{6})/i ) {
	$defbgcolour = $1;
}
if ( defined $config{'routers.cgi-fgcolour'} 
	and $config{'routers.cgi-fgcolour'} =~ /(#[\da-fA-F]{6})/i ) {
	$deffgcolour = $1;
}
if ( defined $config{'routers.cgi-menubgcolour'} 
	and $config{'routers.cgi-menubgcolour'} =~ /(#[\da-fA-F]{6})/i ) {
	$menubgcolour = $1;
}
if ( defined $config{'routers.cgi-menufgcolour'} 
	and $config{'routers.cgi-menufgcolour'} =~ /(#[\da-fA-F]{6})/i ) {
	$menufgcolour = $1;
}
if ( defined $config{'routers.cgi-authbgcolour'} 
	and $config{'routers.cgi-authbgcolour'} =~ /(#[\da-fA-F]{6})/i ) {
	$authbgcolour = $1;
}
if ( defined $config{'routers.cgi-authfgcolour'} 
	and $config{'routers.cgi-authfgcolour'} =~ /(#[\da-fA-F]{6})/i ) {
	$authfgcolour = $1;
}
if ( defined $config{'routers.cgi-linkcolour'} 
	and $config{'routers.cgi-linkcolour'} =~ /(#[\da-fA-F]{6})/i ) {
	$linkcolour = $1;
}

if( defined $config{'web-png'} and $config{'web-png'}=~/[1y]/i ) {
	$graphsuffix = "png";
}
if( defined $config{'routers.cgi-bytes'} 
	and $config{'routers.cgi-bytes'}=~/y/i ) {
	$bits = "!bytes";
	$factor = 1;
}

# Anyone giving us a cookie?
$defgstyle = $q->cookie('gstyle') if($q->cookie('gstyle'));
if( ! $defgstyle ) {
	if( $config{'routers.cgi-graphstyle'} ) {
		my( $w ); # match against all the possibilities
		if( defined $gstyles{$config{'routers.cgi-graphstyle'}} ) {
			$defgstyle = $config{'routers.cgi-graphstyle'};
		} else {
			foreach ( keys %gstyles ) {
				$gstyles{$_} =~ /^\s*(\w+)/;
				$w = lc $1;
				if( $w eq lc $config{'routers.cgi-graphstyle'}
					or $w eq $_ ) {
					$defgstyle = $_;
					last;
				}
			}
		}
	}
	$defgstyle = 'n' if(!$defgstyle);
}
$defbaropts = "Cami";
if(defined $config{'routers.cgi-bars'}) {
	$defbaropts = $config{'routers.cgi-bars'};
}
$defgopts = $q->cookie('gopts');
$defgopts = "" if(!defined $defgopts);
$defgtype = $q->cookie('gtype');
if( ! $defgtype ) {
	if( $config{'routers.cgi-graphtype'} ) {
		foreach ( @gorder ) {
			if( $_ eq $config{'routers.cgi-graphtype'} ) {
				$defgtype = $_;
				last;
			}
		}
	}
}
$defgtype = $gorder[0] if(! $defgtype);

# identify menu type
$mtype = "routers";
$mtype  = $q->param('xmtype')  if( defined $q->param('xmtype') );
if( defined $config{'routers.cgi-allowexplore'} and $mtype ne "options" ) {
	$mtype = "options"
		if($config{'routers.cgi-allowexplore'} !~ /y/ );
}

# set the current device(router) and interface...
$router = "";
$router = $defrouter = $q->cookie('router') if($q->cookie('router'));
$router = $pathinfo[1] if($pathinfo[1]);
$router = $opt_D if($opt_D); # command line
$router = $q->param('rtr') if( $q->param('rtr') );
#$router = "" if(!defined $router or $router eq "none");
$router = "" if(!defined $router);
# Only read in the routers table if (1) we need it, or (2) we are caching
if(($pagetype =~ /config/) 
	or ($pagetype =~ /menu/ and ($mtype eq "routers" or !$router))
  or(!$router and $pagetype and $pagetype !~ /help|main|head|bar/ )
  or($pagetype =~ /graph/ 
	and -r $config{'routers.cgi-confpath'}.$pathsep.$router )
  or ($pagetype =~ /verify/)
  or ($q->param('searchhost'))
  or $CACHE ) {
	read_routers();
	if ((! $router or !defined $routers{$router} ) and $router ne "none") {
		if($config{'routers.cgi-defaultrouter'}
			and ( defined $routers{$config{'routers.cgi-defaultrouter'}}
				or $config{'routers.cgi-defaultrouter'} eq 'none' )) {
			$router = $defrouter = $config{'routers.cgi-defaultrouter'};
		} else {
			$router = $defrouter = (sort bydesc keys(%routers))[0] ;
		}
	}
}

# Searching?
if( $q->param('searchhost') ) {
	my($sh) = $q->param('searchhost');
	$router = 'none'; # If not found
	foreach ( keys %routers ) {
		if( $_ =~ /^(.*[\\\/])?$sh\.[^\.\\\/]+$/i ) { $router = $_; last; }
	}
	if($router eq 'none') {
		foreach ( keys %routers ) {
			if( $_ =~ /$sh/i ) { $router = $_; last; }
			if( $routers{$_}{shdesc} =~ /$sh/i ) { $router = $_; last; }
		}
	}
}

# Do we need to redirect?
if( defined $routers{$router} and $routers{$router}{redirect} ) {
	if($pagetype =~ /graph/ or $q->param('searchhost')) { 
		# coming from search box, or wanting graph page
		# Ugly stuff to avoid XSS problems - must reload entire frameset
		my($js)="function doredirect() { parent.location = \""
			.$routers{$router}{redirect}.'?'
        	.optionstring({page=>"main",rtr=>$router})
			."\"; } ";
		print $q->header();
		print $q->start_html({-expires=>"+1s",-script=>$js,-onload=>"doredirect()"});
		print "Please wait: handing over to other cluster member";
		print $q->end_html;
		exit(0);
	}
	print $q->redirect($routers{$router}{redirect}.'?'.
		optionstring({page=>$pagetype,rtr=>$router}) );
	exit(0);
}

# Get interface information, if we need it
$defif = $q->cookie('if');
$defif = $config{'routers.cgi-defaultinterface'} 
	if(!$defif and defined $config{'routers.cgi-defaultinterface'});
$defif = $pathinfo[2] if($pathinfo[2]);
$interface = ($q->param('if'))?$q->param('if'):$defif ;
$interface = $opt_T if($opt_T); # command line
$interface = '_summary_' if($interface eq '__summary'); # backwards compatible
$interface = 'none' if($router eq 'none');
$interface = "" if(! defined $interface );
if( ( ($pagetype =~ /menu/ and $mtype ne "routers" )
	  or $pagetype =~ /csv|graph|summary|info|compact|verify|image/ )
	and $router ne "none" ) {
	if($router =~ /^#SERVER#/ ) {
		set_svr_ifs();
	} else {
		read_cfg();
	}
	$donecfg = 1; # set flag to show we have read in interfaces data
	if ( !$interface or $interface eq "__first"
		or $interface eq "__interface" or $interface eq "__memory" 
		or $interface eq "__cpu" or $interface eq "__userdef" 
		or ( $interface !~ /^__/ and !defined $interfaces{$interface} )
	) {
		if( $routers{$router}{defif} 
			and defined $interfaces{$routers{$router}{defif}}) {
			$defif = $routers{$router}{defif};
		} else {
			my( @ifs );
			@ifs = sort byifdesc keys(%interfaces);
			$defif = 'none'; 
			foreach ( @ifs ) {
				next if(!$interfaces{$_}{inmenu});
				if( $interfaces{$_}{default} ) { $defif=$_; last; }
				$defif = $_ if($defif eq 'none');
				if($interface eq "__interface" 
					and $interfaces{$_}{mode} eq "interface") 
				{ $defif = $_; last;  }
				if($interface eq "__memory" 
					and $interfaces{$_}{mode} eq "memory") 
				{ $defif = $_; last; }
				if($interface eq "__cpu" 
					and $interfaces{$_}{mode} eq "cpu") 
				{ $defif = $_; last; }
				if($interface eq "__userdef" and !$interfaces{$_}{issummary}  
					and $interfaces{$_}{usergraph} ) 
				{ $defif = $_; last; }
				if($interface eq "__usersummary" and $interfaces{$_}{issummary}  
					and $interfaces{$_}{usergraph} ) 
				{ $defif = $_; last; }
			}
		} # default specified
		$interface = $defif;
	}
} 

# Archive deletion
if( $q->param('delete') and $archive ) {
	# zap the requested archive
	my( $arch );
	$arch = $router; $arch =~ s/[\?#\/\\]//g;
	$arch = $config{'routers.cgi-graphpath'}.$pathsep.$arch.$pathsep
		.$interface.$pathsep.$archive;
	unlink $arch;
	$archive = "";
}

$gtype = $defgtype;
$gstyle = $defgstyle;
$gopts = $defgopts;
$baropts = $defbaropts;
$gtype  = $q->param('xgtype')  if( defined $q->param('xgtype') );
$gtype  = $opt_t if($opt_t);
$gstyle = $q->param('xgstyle') if( defined $q->param('xgstyle'));
$gstyle = $opt_s if($opt_s);
$gopts  = $q->param('xgopts')  if( defined $q->param('xgopts') );
$uopts  = $q->param('uopts')   if( defined $q->param('uopts')  );
$baropts= $q->param('bars')    if( defined $q->param('bars')   );
$gtype = "d" if(!$gtype);

# the graph time options
# Allow 6-hour if every RRD involved is able to do it also.
if(	defined $config{'routers.cgi-6hour'} 
	and $config{'routers.cgi-6hour'} =~ /y/i ) {
	# 6-hour mode is available.
	my($thisif);
	if($donecfg) { # have we read in the cfg files?
		if( $interface eq "__compact" ) {
			$usesixhour = 1;
			foreach $thisif ( keys %interfaces ) {
				next if(!$interfaces{$thisif}{incompact});
				if($interfaces{$thisif}{interval} > 4) {$usesixhour = 0; last;}
			}
		} elsif ( $interface and defined $interfaces{$interface}
			and $interfaces{$interface}{usergraph} ) {
			# Userdefined - all member interfaces MUST be <5
			$usesixhour = 1;
			foreach $thisif ( @{$interfaces{$interface}{targets}} ) {
				if($interfaces{$thisif}{interval} > 4) {$usesixhour = 0; last;}
			}
		} elsif( $interface and defined $interfaces{$interface}
			and $interfaces{$interface}{interval} < 5 ) {
			$usesixhour = 1;
		}
		$usesixhour = 1 if($config{'routers.cgi-6hour'} =~ /a/i ); # for 'always'
		@gorder = ( "6", @gorder ) # add it to the beginning of the list
			if($usesixhour);
	} else { # donecfg
		@gorder = ( "6", @gorder ); # Assume it's OK, fix it later
	}
}

# rrdcached support
# If we're using UNIX sockets, then we just need to force a flush of the
# relevant RRD files.  If we're using TCP sockets, then all the commands need
# to use them.
$rrdcached = "";
$rrdcached = $ENV{RRDCACHED_ADDRESS} if($ENV{RRDCACHED_ADDRESS});
$rrdcached = $config{'web-rrdcached'} if($config{'web-rrdcached'});
$rrdcached = $routers{$router}{rrdcached} 
	if($router and defined $routers{$router} and $routers{$router}{rrdcached});
if($rrdcached) {
	$debugmessage .= "RRDCached = $rrdcached, testing version...\n";
	eval{ 
		require RRDs; 
		if( $RRDs::VERSION < 1.4 ) {
			$rrdcached = ""; # no support for rrdcached in this version
		} elsif( ($rrdcached !~ /^unix:/) and ($RRDs::VERSION<1.4999) ) {
			$rrdcached = ""; # no support for rrdcached/TCP in this version
		}
	};
	$rrdcached = "" if($@); # if RRDs problem
	$debugmessage .= "RRDCached mode cancelled.\n" if(!$rrdcached);
}
# For tcp, 'fetch' and 'graph' will flush the cache; however 'last' doesnt
# Therefore we need to flush for all sockets.  For unix domain, we go
# direct for graph, fetch and last so we MUST flush the cache.
#if( $rrdcached =~ /^unix:/ ) {	
if( $rrdcached ) {	 # flush for TCP domain as well as unix domain
	# we know RRDs will be loaded by now
	if( $router and defined $routers{$router} and $interface
		and $interfaces{$interface} ) {
		my(@ifs) = ();
		my($pth) = $config{'routers.cgi-dbpath'};
		$pth = $routers{$router}{workdir} if($routers{$router}{workdir});
		$debugmessage .= "Flushing RRD files\n";
		if( defined $interfaces{$interface}{targets} ) {
			foreach ( $interfaces{$interface}{targets} ) {
				push @ifs, $interfaces{$_}{rrd};
			}
		} else { push @ifs, $interfaces{$interface}{rrd}; }
		eval {
			foreach ( @ifs ) {
				next if(!$_);
				RRDs::flushcached('--daemon',$rrdcached,$_);
			};
		};
	}
	# no longer needed as all will be done directly
	#$rrdcached = "" if( $rrdcached =~ /^unix:/ ); 
}
@rrdcached = (); 
@rrdcached = ( '--daemon',$rrdcached ) if($rrdcached);

# Should we verify that the RRA has enough data?  This would take a bit of
# extra time to do, but would prevent glitches.  However we could say that 
# anyone who switches this option on is taking the responsibility for making
# sure that the data is valid!
# Note that, if extendedtime = full, then we dont add these as we will instead
# test the RRD and add the appropriate dates into the calendar.
if( defined $config{'routers.cgi-extendedtime'}
	and $config{'routers.cgi-extendedtime'} =~ /y/i 
) {
	push @gorder, "d-","w-","m-","y-";
} elsif ( defined $config{'routers.cgi-extendedtime'}
	and $config{'routers.cgi-extendedtime'} =~ /t/i 
	and $interface and defined $interfaces{$interface}
	and $interfaces{$interface}{rrd} 
) {
	# see if we have more data available...
	eval { require RRDs; };
	if( !$@ ) {
		my( $infop ) = RRDs::info($interfaces{$interface}{rrd},@rrdcached);
		push @gorder, "d-" if( ${$infop}{"rra[0].rows"} > 799 );
		push @gorder, "w-" if( ${$infop}{"rra[1].rows"} > 799 );
		push @gorder, "m-" if( ${$infop}{"rra[2].rows"} > 799 );
		push @gorder, "y-" if( ${$infop}{"rra[3].rows"} > 799 );
	} 
}

# sanity check
#if( $gtype eq "6" and $interface !~ /^__/ and ( !$usesixhour 
#	or ($interface and defined $interfaces{$interface} 
#		and $interfaces{$interface}{interval} >= 5 ))) {
#	 $gtype = $gorder[0];
#}
if( $gtype eq "6" and $interface !~ /^_/ and !$usesixhour ) {
	 $gtype = $gorder[0];
}
if( defined $interfaces{$interface}
	and defined $interfaces{$interface}{suppress} ) {
	my($pat) = '['.$interfaces{$interface}{suppress}.']';
	$gtype = 'dwmy' if($gtype =~ /$pat/);
}
if ( ! (defined $gtypes{$gtype}) or 
	( ($interface eq "__compact" 
		or (defined $interfaces{$interface} and $interfaces{$interface}{issummary}))
		 and (length ($gtype) > 2) )) {
	$gtype = $gorder[0];
}
if( defined $config{'routers.cgi-uselastupdate'} 
	and $config{'routers.cgi-uselastupdate'} =~ /y/i ) {
	$uselastupdate = 1; # set the flag for later.
} else { $uselastupdate = 0; }
# How big is a K ? Some people prefer 1024, some prefer 1000
if( $interfaces{$interface}{kilo} ) {
	$k = $interfaces{$interface}{kilo};
	$M = $k * $k;
	$G = $M * $k;
	$T = $G * $k;
	if($k == 1000) { $ksym = 'k'; } else { $ksym = 'K'; }
} else {
  if( defined $config{'routers.cgi-usebigk'} ) {
	if( $config{'routers.cgi-usebigk'} =~ /y/i )      # yes
		{ $k = 1024; $M = $k * 1024; $G = $M * 1024; $T=$G*1024; $ksym = "K"; }
	elsif( $config{'routers.cgi-usebigk'} =~ /n/i )   # no
		{ $k = 1000; $M = 1000000; $G = $M * 1000; $T=$G*1000;$ksym = "k"; }
	elsif( $config{'routers.cgi-usebigk'} =~ /m/i )   # mixed
		{ $k = 1024; $M = 1024000; $G = $M * 1000; $T=$G*1000;$ksym = "K"; }
	else 
		{ $k = 1024; $M = 1024000; $G=$M*1000;$T=$G*1000;$ksym="K"; } # default
  } else {
	$k = 1024; $M=1024000; $G=$M*1000;$T=$G*1000;$ksym="K"; # default (mixed)
  }
}
# Here, we should consider supporting Kmg to set ksym
# Define page title and so on.
$windowtitle = $config{'routers.cgi-windowtitle'} 
	if ( defined $config{'routers.cgi-windowtitle'} );
$toptitle = $config{'routers.cgi-pagetitle'} 
	if ( defined $config{'routers.cgi-pagetitle'} );
$toptitle = "<FONT size=+3>".$q->b($windowtitle)."</FONT>" if(!$toptitle);

# Date format labels
$monthlylabel=$config{'web-weeknumber'}
	if( defined $config{'web-weeknumber'} 
	and $config{'web-weeknumber'} =~ /%[UVW]/ );
$dailylabel=$config{'web-hournumber'}
	if( defined $config{'web-hournumber'} 
	and $config{'web-hournumber'} =~ /%[a-zA-Z]/ );

# Line widths
$linewidth = $config{'routers.cgi-linewidth'}
	if( defined $config{'routers.cgi-linewidth'}
		and ($config{'routers.cgi-linewidth'}>0)
		and ($config{'routers.cgi-linewidth'}<5));

# Menu format
if( (defined $config{'routers.cgi-twinmenu'}
	and $config{'routers.cgi-twinmenu'} =~ /y/i and $uopts !~ /T/ )
	or $uopts =~ /t/ ) {
	$twinmenu = 1;
}

# Archived data
# first, clean up cache if polluted
if(defined $interfaces{$interface} and $interfaces{$interface}{origrrd}) {
	$interfaces{$interface}{rrd} = $interfaces{$interface}{origrrd};
}
$archdate = '';
$archdate = $q->param('arch') if(defined $q->param('arch'));
$archdate = $opt_a if($opt_a);
$archdate = '' if($archdate eq POSIX::strftime('%Y-%m-%d',localtime()));
$basetime = 0;
if($config{'routers.cgi-extendedtime'} and $config{'routers.cgi-extendedtime'}=~/f/i and $archdate) { 
	if($archdate=~/^(\d\d\d\d)-(\d\d)-(\d\d)/) {
		eval {
			$basetime = timelocal_nocheck(59,59,23,$3,$2-1,$1-1900);
		};
		if($@) {
			$debugmessage .= "Error in time conversion: $@\n";
		}
	}
	$basetime = time() if($basetime > time());
	$debugmessage .= "Setting base time to $basetime ($archdate)\n";
} elsif($archdate and $donecfg) { 
	# archive date, and read in cfg file, and not extendedtime=full mode
	if($archdate=~/^(\d\d\d\d)-(\d\d)-(\d\d)/) {
		eval {
			$archivetime = timelocal_nocheck(59,59,23,$3,$2-1,$1-1900);
		};
	}
	if( !$interface or !$interfaces{$interface}{rrd}){
		$debugmessage .= "Invalid target $interface!\n";
		$archdate = '';  # This interface is not valid  
	} elsif( $config{'routers.cgi-extendedtime'} and $config{'routers.cgi-extendedtime'}=~/f/i ) {
		# using extendedtime with calendar.
	} elsif( ! -d 
		(dirname($interfaces{$interface}{rrd}).$pathsep.'archive'
			.(($config{'routers.cgi-archive-mode'} and
				$config{'routers.cgi-archive-mode'}=~/hash/i )?""
				:($pathsep.$archdate)
			)
		)
	) {
		$debugmessage .= "Invalid date $archdate for target $interface!\n";
		$archdate =  ''; # this date archive is not avaiable
	} else {
		# CHANGE THE DEFINED RRD FILE(s) IF WE ARE NOT ON MENU
		if($pagetype=~/graph|csv|image|summary|compact/ ) {
			my($thisif,$dn,$bn);
			my(@candidates) = ( $interface );
#			push @candidates, @{$interfaces{$interface}{targets}}
#				if($interfaces{$interface}{usergraph}
#					or $interfaces{$interface}{issummary});
			@candidates = (keys %interfaces) 
				if($interface =~ /^__/ or $interfaces{$interface}{usergraph});
			foreach $thisif ( @candidates ) { 
				next if($thisif =~ /^_/); # skip userdefineds
				if(!$interfaces{$thisif}{origrrd}) {
					$interfaces{$thisif}{origrrd} = $interfaces{$thisif}{rrd};
				} else {
					$interfaces{$thisif}{rrd} = $interfaces{$thisif}{origrrd};
				}
				next if(!$interfaces{$thisif}{rrd});
				$dn = dirname($interfaces{$thisif}{rrd});
				$bn = basename($interfaces{$thisif}{rrd});
				$interfaces{$thisif}{rrd} = $dn.$pathsep.'archive'.$pathsep
					.(($config{'routers.cgi-archive-mode'} and
						$config{'routers.cgi-archive-mode'}=~/hash/i )?(
						makehash($bn).$pathsep.$bn.".d"
						.$pathsep.$archdate.".rrd"
					):(
						$archdate.$pathsep.$bn
					));
				if( ! -f $interfaces{$thisif}{rrd} ) {
					# if the archive doesnt exist
					$interfaces{$thisif}{rrd} = $interfaces{$thisif}{origrrd};
#					$archdate = '';
					$debugmessage .= "No archive for target $thisif on $archdate\n";
#				} else {
#					# is this a good idea?  Maybe should uselastupdate instead
#					my($a) = (stat $interfaces{$thisif}{rrd})[9];
#					$archivetime = $a if(!$archivetime) or ($a > $archivetime));
				}
			}
		}
		$uselastupdate = 2; # since we are now basing from old .rrd file
	}	
#	$debugmessage .= "Archivetime: $archivetime\nArchdate: $archdate\n";
} elsif(defined $interfaces{$interface}) {
	if($pagetype =~ /graph|csv|summary|compact/ ) {
		my($thisif);
		my(@candidates) = ( $interface );
		push @candidates, @{$interfaces{$interface}{targets}}
			if($interfaces{$interface}{usergraph});
		@candidates = (keys %interfaces) if($interface =~ /^__/);
		foreach $thisif ( @candidates ) { 
			$interfaces{$thisif}{rrd} = $interfaces{$thisif}{origrrd}
				if($interfaces{$thisif}{origrrd});
		}
	}
}

if( $opt_A ) {
	$pagetype = 'COMMAND'; $archiveme = 1; # override
	$|=1;
	print "Creating Graph...\n";
	if($opt_T) {
		# target was set
		# Archive this graph
		if( !$interface or !defined $interfaces{$interface}
			or $interface=~/^__/ or $interfaces{$interface}{issummary} ) {
			print "This target is not appropriate to archive.\n";
			print "Device/Target = [$router]/[$interface]\n";
			print "Unknown Target\n" if(!defined $interfaces{$interface});
			print "Illegal Target\n" if($interface=~/^__/);
			print "Summary Target\n" if($interfaces{$interface}{issummary});
			print "Targets:\n".(join ",",(keys %interfaces))."\n";
			print "Devices:\n".(join ",",(keys %routers))."\n";
			exit(1);
		}
		do_graph(0);
	} else {
		# Do them all, for this device
		foreach $interface ( keys %interfaces ) {
			next if($interface=~/^__/ or $interfaces{$interface}{issummary}
				or !$interfaces{$interface}{inmenu} );
			print "$interface... ";
			do_graph(0);
		}
	}
	exit(0);
}

# Start the page off
if( $pagetype =~ /graph/ and !$archive and !$archdate ) {
	my($rtime) = 1800;
	$rtime =900 if($gtype =~ /w/);
	$rtime =300 if($gtype =~ /d/);
	$rtime = 60 if($gtype =~ /6/);
	$rtime = $config{'routers.cgi-minrefreshtime'} 
		if( defined $config{'routers.cgi-minrefreshtime'}
			and $config{'routers.cgi-minrefreshtime'} > $rtime );
	$headeropts{-expires} = "+5s";
	$headeropts{-Refresh} = $rtime;
	$headeropts{-Refresh} .= "; URL=$meurlfull?".optionstring({}) if($archiveme);
	$headeropts{-head} = [] if(!$headeropts{-head});
	push @{$headeropts{-head}}, $q->meta({-http_equiv=>'Refresh',-content=>$headeropts{-Refresh}});
}
$headeropts{-target} = $pagetype if($pagetype =~ /head|menub?|graph/ );
$headeropts{-target} = "graph" 
	if( $pagetype =~ /compact|summary|help|info|config/ );
$headeropts{-target} = "_top" if ( !$pagetype );

if ( $pagetype =~ /config/ and $q->param('xset')) {
	push @cookies, $q->cookie( -name=>'gstyle', -value=>$q->param('defgstyle'), 
		-path=>$q->url(-absolute=>1), -expires=>"+10y" ) 
			if( defined $q->param('defgstyle'));
	push @cookies, $q->cookie( -name=>'gtype', -value=>$q->param('defgtype'), 
		-path=>$q->url(-absolute=>1), -expires=>"+10y" ) 
			if( defined $q->param('defgtype') );
	push @cookies, $q->cookie( -name=>'router', -value=>$q->param('defrouter'), 
		-path=>$q->url(-absolute=>1), -expires=>"+10y" ) 
			if( defined $q->param('defrouter') );
	push @cookies, $q->cookie( -name=>'if', -value=>$q->param('defif'), 
		-path=>$q->url(-absolute=>1), -expires=>"+10y" ) 
			if( defined $q->param('defif') );
	if( defined $q->param('deflang') ) {
		initlang($q->param('deflang'));
		if($q->param('deflang')) {
			push @cookies, $q->cookie( -name=>'lang', -value=>$language, 
				-path=>$q->url(-absolute=>1), -expires=>"+10y" ) ;
		} else {
			push @cookies, $q->cookie( -name=>'lang', -value=>'', 
				-path=>$q->url(-absolute=>1), -expires=>"now" ) ;
		}
	}
}
# Character sets
if(defined $config{'routers.cgi-charset'}) {
	$charset = $config{'routers.cgi-charset'};
}elsif(defined $config{'web-charset'}) {
	$charset = $config{'web-charset'};
}
if($charset) {
	$headeropts{-charset} = $charset;
	
	$headeropts{-head} = [] if(!$headeropts{-head});
	push @{$headeropts{-head}}, $q->meta({-http_equiv => 'Content-Type', 
		-content => "text/html; charset=$charset"});
}
# Are we exporting CSV?
if( $pagetype =~ /csv/ ) {
	my($fn) = "export.csv";
	$csvmime=$config{'web-csvmimetype'} if(defined $config{'web-csvmimetype'});
	$fn = $config{'web-csvmimefilename'}
		if(defined $config{'web-csvmimefilename'}) ;
	$csvmime .= "; filename=\"".$fn."\"";
	$headeropts{"-Content-Disposition"} = "filename=\"".$fn."\"";
	$headeropts{-type} = $csvmime ;
}

# The bar and image functions have to do their own headers as they may need 
# to redirect.
$headeropts{-cookie} = [@cookies] if(@cookies); 
print $q->header({ %headeropts }) if($pagetype !~ /bar|image|COMMAND/);

#
# Now, we check the passed parameters to find out what sort of page to
# serve up.  If we can't work out which one to do, then we just serve the
# index page
if($pagetype) {
	for($pagetype) {
		/head/ and do {	do_head(); last; };
		/menu/ and do { do_menu(); last; }; # matches menu and menub
		/compactcsv/ and do { do_compact(1); last; };
		/csv/ and do {
			if($interface eq "__compact") { do_compact(1);	last; } 
			last if( $interface =~ /^__/ ); # oops, this shouldnt happen
			do_export();
			last;
		};
		/image/ and do {
			if( $interface !~ /^__/ and defined $interfaces{$interface}) {
				if( $archive ) {
					do_archive(0);
				} else {
					do_graph(0);
				}
			} else {
				if($opt_I) {
					print "Interface: $interface\nError: Not defined\n";
				} else {
		print $q->redirect($config{'routers.cgi-iconurl'}."error-lg.gif");
				}
			}
			last;
		};
		/graph|archive/ and do { 
			if ( $interface eq "__info" ) {
				do_info();
			} elsif ( $interface eq "__compact" ) {
				do_compact(0);
			} elsif ( $interface eq "__none" ) {
				do_empty();
			} elsif ( $interface =~ /^__/ ) {
				do_bad("Bad target: $interface");
			} elsif ( $interfaces{$interface}{usergraph}
				and $interfaces{$interface}{issummary} ) {
				do_summary();
			} else {
				if( $archive ) {
					do_archive(1);
				} else {
					do_graph(1);
				}
			}
			last; 
		};
		/help/ and do { do_help(); last; };
		/main/ and do { do_main(); last; };
		/info/ and do { do_info(); last; };
		/summary/ and do { do_summary(); last; };
		/compact/ and do { do_compact(0); last; };
		/config/ and do { do_config(); last; };
		/bar/ and do { do_bar(); last; };
		/verify/ and do { 
			if($config{'web-paranoia'}
				and $config{'web-paranoia'}=~/[yY1]/) {
				do_bad(langmsg(8006,"You do not have authority to view the configuration"));
			last;
			}
			if( !defined $config{'routers.cgi-allowexplore'}
				or $config{'routers.cgi-allowexplore'} =~ /[1y]/i ) {
				do_verify(); last; 
			}
			do_bad(langmsg(8006,"You do not have authority to view the configuration"));
			last;
		};
		do_bad("Bad pagetype: $pagetype");
	}
} else { do_main() }

# Clean up
if($CACHE and $archdate) {
	if(defined $interfaces{$interface} 
	and defined $interfaces{$interface}{origrrd}) {
		$interfaces{$interface}{rrd} = $interfaces{$interface}{origrrd};
	}
}
exit(0);
