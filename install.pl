#!/usr/bin/perl
############################################################################
# vim:ts=4
# Perl script to install .cgi
#
# v1.4 : should work under UNIX or NT
#      : changed to support MRTG-Bundle upgrades (different location def)
# v1.5 : Change dir to our dir for File Manager clickers
# v1.6 : Improve instruction wording
# v1.7 : Add check to not overwrite .css file on upgrade
# v1.8 : Fix install to not overwrite .gif files or .css (really)
# v1.9 : Add JSCal2 install
#
############################################################################

use strict;
use File::Basename; # for OS Filesystems specific stuff
use Term::ReadLine; # For user input - should work under Perl and ActivePerl
use File::Copy;     # To copy the files of course
use Sys::Hostname;  # To work out our URL
use Env qw(PATH);

my ($APP) = "routers2";
my ($VERSION) = "v2.24beta1";
my ($EMAIL) = 'steve@steveshipway.org';
my ($WEB) = 'http://www.steveshipway.org/software';

my ($rrddir, $mrtgdir, $docroot, $cgibin, $perlpath ) = ("","","","","");
my ($mrtgfilespec, $conffile) = ("","");
my ($rrddrive) = "";
my ($rl) = new Term::ReadLine('user input');
my ($rv);
my ($UNIX,$NT,$APACHE,$IIS,$BUNDLE) = (0,0,0,0,0);
my ($PS) = "/";
my (@ntdrives) = ("C");
my ($useextensions) = 0;
my ($usecompact) = 0;
my ($usecache) = 0;
my ($usejscal) = 0;
my ($usebigk) = "";
my ($usepagetop) = "";
my ($hassnmp) = 1;
my ($canmail) = "yes";
my ($hasgd) = 0;
my ($auth) = "";
my ($authopt) = "";
my ($authcontext) = "";

############################################################################
# Check for existence of certain libraries.
sub libcheck()
{
	my($retval);

	eval { require 'RRDs.pm'; };
	if($@) {
		print "WARNING: You do not have the RRDs Perl libraries installed into the site_perl\ndirectory correctly.\n";
		print "$APP.cgi will probably not run properly until these libraries are correctly\n";
		print "installed.  Go to http://www.rrdtool.org/ for more details.\n";
		print "Note that this MAY not be a problem if they are located by the LibAdd directive\nin the MRTG .cfg files.\n";
		print "If you have already installed RRDTool, then make sure you do the necessary\nadditional Perl Library install.\n";
		$retval = ask("Continue","y");
		if( $retval =~ /n/ ) {
			print "OK, please check your RRD installation and try again.\n";
			exit 0;
		}
	} else {
		print "RRDs library found correctly.\n";
		if( $RRDs::VERSION < 1.00029 ) {
			print "However, it is too old a version.  You must upgrade to at least version 1.0.29\nin order to avoid a known bug.\n";
			$retval = ask("Continue","n");
			if( $retval =~ /n/ ) {
				print "OK, please upgrade your RRD installation and try again.\n";
				exit 0;
			}
		}
	}
	eval { require GD; };
	if($@) {
		print "WARNING: You do not have the GD Perl libraries installed correctly.\n";
		print "$APP.cgi will still run, but the Compact Summary display will not work.\n";
		print "Download the GD libraries from CPAN.org if required.\n";
		print "NT Users should use PPM to collect GD from ActiveState, or download the ppd\npackage from www.steveshipway.org (see instructions in online forum).\n";
		print "UNIX users should note that they need the GD.pm Perl library IN ADDITION to\nthe libgd.so C library.\n";
		$retval = ask("Continue","y");
		if( $retval =~ /n/ ) {
			print "OK, please check your GD installation and try again.\n";
			exit 0;
		}
		$hasgd = 0;
	} else { print "GD libraries found correctly.\n"; $hasgd = 1; }
	eval { require Time::Zone; };
	if($@) {
		print "WARNING: You do not have the Time::Zone library installed.\nThis is not a big problem, so don't worry.\n";
		print "This will only be a potential problem if you are using multiple time zones and\nyour operating system does not support the TZ environment variable.\n";
		print "If you wish to obtain this package, visit CPAN.org or use PPM\n";
	} else { print "Time::Zone library found correctly.\n"; }
	eval { require Net::SNMP; };
	if($@) {
		print "WARNING: You do not have the Net::SNMP library installed.\n";
		print "This library is required if you wish to use the routingtable extension.\n";
		print "$APP.cgi will run correctly without this package, however.\n";
		print "If you wish to obtain this package, visit CPAN.org or use PPM\n";
			$hassnmp = 0;
	} else { print "Net::SNMP library found correctly.\n"; $hassnmp = 1; }
}

############################################################################
# Ask the user a question. 1st param: prompt, 2nd param: default answer.
sub ask($$)
{
	my($p, $d) = @_;
	my($rv,$prompt);

	$prompt = $p;
	$prompt .= " [$d]" if($d);
	$prompt .= "? ";
	do {
		$rv = $rl->readline($prompt);
		if( $rv =~ /^quit/i ) {
			print "\nOK, lets not go any further then.\n";
			exit 0;
		}
		$rv = $d if($d and !$rv);
	} while(!$rv);
	return $rv;
}
############################################################################
sub locate_paths()
{
	my( @paths, $go, $cfile );
	my( $defdocroot, $defcgibin, $defrrddir,$defmrtgdir, $defperlpath,
		$defconffile  ) = ("","","","","","");
	my( $webconffile, $f, $p, $d );

	print "\n0. Attempting to identify your OS and web server...\n";
	if( $^O =~ /Win/ or $^O =~ /DOS/i ) { $NT=1; $PS="\\"; } 
	elsif( $^O =~ /[ui]x/i or $^O =~ /Sun/i or $^O =~ /Sol/i ) { $UNIX = 1; }
	print "   - I think you are running under NT.\n" if( $NT );
	print "   - I think you are running under UNIX.\n" if( $UNIX );
	print "   - I'm not sure what your OS is, but I'll assume it is some flavour of UNIX.\n" if( !$UNIX and !$NT );
	if( $NT ) {
		$BUNDLE = 1 if( -f 'C:\mrtg\wwwroot\index.cgi' );
		print "   - I think you have the Open Innovations MRTG Bundle install.\n" if($BUNDLE);
		$defperlpath="perl.exe";
		print "\n   I need to know which drives to check.  If you only have one disk partition,\n   or if you are not sure, take the default.  Separate drive letters with\n   spaces.\n";
		$rv = ask("   Drives to check","C");
		@ntdrives = split " ",$rv;
		# Check for Apache, then IIS
		@paths = ( "\\Apache\\conf", "\\Apache Group\\Apache\\conf", "\\Program Files\\Apache Group\\Apache\\conf", "\\Program Files\\Apache\\conf" );
		foreach (@paths) {
			foreach $d ( @ntdrives ) {
				if( -d "$d:$_" ) { $APACHE="$d:$_"; last; }
			}
		}
		if(!$APACHE) {
			@paths = ( "\\Inetpub", "\\www" );
			foreach (@paths) {
				foreach $d ( @ntdrives ) {
					if( -d "$d:$_" ) { $IIS="$d:$_"; last; }
				}
			}
		}
	} else {
		# Check for apache
		@paths = ( "/etc/httpd/conf", "/usr/local/apache/conf", "/usr/apache/conf", "/etc/apache", "/usr/local/etc/apache/conf", "/usr/local/share/apache" );
		foreach (@paths) {
			if( -d $_ ) { $APACHE=$_; last; }
		}
	}
	print "   - I think you have Apache installed in \n     $APACHE\n" 
		if($APACHE);
	print "   - I think you have IIS installed in \n     $IIS\n" 
		if($IIS);
	# Now, we need to identify the default cgibin, docroot
	if($APACHE) {
		# we need to read the httpd.conf file, and find the DocumentRoot and
		# ScriptAlias directives.
		foreach $f ( "httpd.conf", "srm.conf", "access.conf" ) {
			$webconffile = $APACHE.$PS.$f; 
			if( open HTTP, "<".$webconffile ) {
				while ( <HTTP> ) {
					chomp;
					if( !$defdocroot and  /^\s*DocumentRoot\s+"?([^"]+)"?/i ) 
						{ $defdocroot = $1; }
					if( !$defcgibin 
						and /^\s*ScriptAlias\s+(\S+)\s+"?([^"]+)"?/i ){ 
						$p = $2;
						$defcgibin = $p if($1 =~ /cgi/); 
					}
					last if($defcgibin and $defdocroot);
				}
				close HTTP;
			}
			last if($defcgibin and $defdocroot);
		} # foreach
		$defcgibin =~ s#/#\\#g if($NT);
		$defdocroot =~ s#/#\\#g if($NT);
	} elsif($IIS) {
		$defdocroot = $IIS."\\wwwroot";
		$defcgibin = $IIS."\\wwwroot\\cgi-bin";
	}
	if($BUNDLE) { # Detect MRTGBundle
		$defdocroot = "C:\\mrtg\\wwwroot";
		$defcgibin = "C:\\mrtg\\wwwroot";
	}
	$defdocroot = "" if(! -d $defdocroot);
	$defcgibin  = "" if(! -d $defcgibin );

	####docroot####
	print "\n1. Web server document root directory.\n";
	print "   This is the full path of the base document directory of your web server.\n";
	do {
		$docroot = ask("   Document root",$defdocroot);
		print "[$docroot] is not a valid directory.\n" if(! -d $docroot);
	} while( ! -d $docroot );

	####cgibin####
	print "\n2. Web server CGI directory.\n";
	print "   This is the full path of the directory where your web server keeps the \n   CGI scripts.\n";
	do {
		$cgibin = ask("   CGI directory",$defcgibin);
		$cgibin =~ s/[\\\/]+/$PS/ge;
		print "[$cgibin] is not a valid directory.\n" if(! -d $cgibin);
	} while( ! -d $cgibin );

	####mrtg####
	# try and locate the MRTG directory in likely places
	if( $NT ) {
		@paths = ();
		push @paths, "c:\\mrtg\\mrtg\\bin"; # MRTGBundle install location
		foreach $d ( @ntdrives ) {
			push @paths, glob("$d:\\mrtg*\\conf*");
			push @paths, glob("$d:\\Program Files\\mrtg*\\conf*");
		}
	} else {
		@paths = glob("/usr/local/lib/mrtg*/conf*"); 
		push @paths, glob("/usr/local/mrtg*/conf*");
		push @paths, glob("/usr/lib/mrtg*/conf*");
		push @paths, glob("/usr/mrtg*/conf*");
	}
	foreach ( @paths ) { if( -d ) { $defmrtgdir = $_; last } }
	print "\n3. MRTG config file directory.\n";
	print "   This is the full path of the directory where your MRTG configuration files \n   are kept\n";
	do {
		$mrtgdir = ask("   MRTG config directory",$defmrtgdir);
		print "[$mrtgdir] is not a valid directory.\n" if(! -d $mrtgdir);
	} while( ! -d $mrtgdir );

	####mrtg filespec####
	print "\n4. MRTG config files.\n";
	print "   This is the wildcarded filename format for your MRTG configuration files.\n";
	print "   Use a '*' to mean 'any characters' - for example, '*.cfg' or '*/*.conf'.\n";
	do {
		$mrtgfilespec = ask("   MRTG files","*.cfg");
		@paths = glob("$mrtgdir$PS$mrtgfilespec");
		print "WARNING: No files found matching '$mrtgdir$PS$mrtgfilespec'\n" 
			if($#paths < 0);
	} while(!$mrtgfilespec);
	# find where the RRD files are likely to be from the first MRTG conf file
	if($NT) { $defrrddir = 'C:\tmp'; } else { $defrrddir = "/tmp"; }
	foreach $cfile ( glob("$mrtgdir$PS$mrtgfilespec") ) {
		if( open MRTG,$cfile ) {
			while( <MRTG> ) {
				chomp;
				if( /^\s*WorkDir\s*:\s+(\S+)/i ) { $defrrddir = $1; last; }
			}	
			close MRTG;
		}
		last if($defrrddir);
	}
	$defrrddir =~ s/[\\\/]$//; # remove trailing path separators

	####rrd####
	print "\n5. RRD Database directory.\n";
	print "   This is the full path of the directory where your .rrd files are kept\n";
	do {
		$rrddir = ask("   RRD directory",$defrrddir);
		print "[$rrddir] is not a valid directory.\n" if(! -d $rrddir);
	} while( ! -d $rrddir );

	####perl#####
	if( $NT ) {
		@paths = split /;/,$PATH ;
		$p = "PERL.EXE"
	} else {
		@paths = split /:/,$PATH ;
		$p = "perl";
	}
	# assume perl is in the current path, and look for it
	foreach ( @paths ) { if( -f $_.$PS.$p ) { $defperlpath=$_.$PS.$p; last; }}
	$defperlpath =~ s/\\\\|\/\//$PS/eg;
	print "\n6. Perl executable.\n";
	print "   This is the full pathname of the Perl executable file.\n";
	do {
		$perlpath  = ask("   Perl executable",$defperlpath);
		$perlpath =~ s/\\\\|\/\//$PS/ge;
		print "[$perlpath] is not a valid file.\n" if(! -f $perlpath);
	} while( ! -f $perlpath );
	
	####conf file###
	$defconffile = $rrddir.$PS.$APP.".conf";
	$defconffile = "C:\\mrtg\\mrtg\\bin\\$APP.conf"
		if( -f "C:\\mrtg\\mrtg\\bin\\$APP.conf" ); # MRTGBundle install again
	print "\n7. $APP.cgi configuration file\n";
	print "   This is the file that will hold the $APP.cgi configuration.  Unless you\n";
	print "   have a reason to move it, stick with the default.\n";
	print "   If this file already exists, I will ask before overwriting it!\n";
	$conffile = ask("   Configuration file",$defconffile);

}

############################################################################
sub choose_options()
{
	my($reply,$defgd);

	if ( $hassnmp ) {
		print "   Net::SNMP Perl library is detected.\n";
		print "1. You can optionally activate the 'routingtable' SNMP extensions.  Note that\n";
		print "   this has security implications and can reveal your SNMP community string.\n";
		print "   If this is a concern then answer NO.\n";
		$reply = ask("   Activate routingtable extensions","no");
		$useextensions = 1 if($reply =~ /y/i);
	} else {
		print "1. Net::SNMP does not appear to be installed.  Routing table extensions\n   have been disabled.\n";
		print "   If you subsequently install Net::SNMP, then you can enable the extensions\n";
		print "   in the $APP.conf file.\n";
	}
	$usecompact = 0;
	if ( $hasgd ) {
		print "\n   GD Perl Library is detected.\n";
		print "2. The Compact Summary pages will be enabled.\n";
		$usecompact = 1;
	} else {
		print "\n2. GD does not appear to be installed.  This is required for the compact\n";
		print "   summary screen to work.  If you intend to install it later, answer YES.\n";
		print "   Otherwise, answer NO.\n";
		$reply= ask("   Activate Compact Summary screen","no");
		$usecompact = 1 if($reply =~ /y/i);

	}

	print "\n3. How big should 1K and 1M be?  This is the 'usebigk' parameter from the\n   $APP.conf file.  You have three options - 'yes', 'no' and 'mixed'.\n";
	print "   yes   -> 1K=1024, 1M=1024x1024\n";
	print "   no    -> 1K=1000, 1M=1000x1000\n";
	print "   mixed -> 1K=1024, 1M=1024x1000\n";
	do {
	 	$reply = ask("   'usebigk' option","mixed");
	} while( $reply!~/[ynm]/i );
	$usebigk = "yes" if($reply=~/y/i);
	$usebigk = "no" if($reply=~/n/i);
	$usebigk = "mixed" if($reply=~/m/i);
	
	print "\n4. Do you want to use authentication?  You can always enable this later if\n   you change your mind.  There are other options available in the\n   configuration file as well, so you should check.  If you are unsure, select\n   the default.\n";
	print "   none -> do not use any additional authentication (default)\n";
	print "   http -> use web server's own authentication, if available\n";
	print "   shib -> use shibboleth authentication\n";
	print "   ldap -> use ldap/ldaps authentication\n";
	print "   file -> use a password file (not recommended)\n";
	do {
	 	$reply = ask("   auth option","none");
	} while( $reply!~/^[hnlfs]/i );
	$auth = "" if($reply=~/^n/i);
	$auth = "ldap" if($reply=~/^l/i);
	$auth = "shib" if($reply=~/^s/i);
	$auth = "http" if($reply=~/^h/i);
	$auth = "file" if($reply=~/^f/i);
	if( $auth eq "ldap" ) {
		print "\n4a. What is the ldap server host name?\n";
		do {
			$reply = ask("   host name","");
		} while(!$reply);
		$authopt=$reply;
		print "\n4b. What is the ldap context to check?\n";
		do {
			$reply = ask("   LDAP context","");
		} while(!$reply);
		$authcontext=$reply;
	}
	if( $auth eq "file" ) {
		$authopt = $rrddir.$PS."passwd.txt";
	}
	# caching? ##
	print "\n5. Caching option\n";
	print "   $APP has support for fast CGI utilities such as speedycgi and mod_perl.\n";
 	print "   It achieves this by data caching between invocations.\n";
	print "   This can dramatically improve performance on systems with a large\n";
	print "   number of .cfg files, however it slows performance if you do not have\n";
	print "   these features.  If you are unsure, answer NO.\n";
	print "   Valid answers: no, modperl, speedycgi\n";
	do {
   	$reply = ask("   Caching option","no");
	} while( $reply !~ /no|speedycgi|modperl/i );
	$usecache = 0;
	$usecache = 1 if( $reply =~ /modperl/i);
	$usecache = 2 if( $reply =~ /speedycgi/i);

	print "\n6. Do you want me to install JSCal2?\n   This is required to use the 'full' extendedtime option, with a popup\n   calendar.  This is covered by the LGPL; for more licensing details you\n   should check on the JSCal website.  You do not need this unless you intend\n   to use extra-long RRD files and Full extendedtime option.\n";
	do {
	 	$reply = ask("   Install JSCal2","yes");
	} while( $reply!~/[yn]/i );
	$usejscal = 1 if($reply=~/y/i);
	
	print "\n7. Can I attempt to send an email to the author to let him know that the\n   software has been installed?  This will only give your routers.cgi version,\n   Perl version, and Operating System version.\n";
	do {
	 	$reply = ask("   Can I mail","no");
	} while( $reply!~/[yn]/i );
	$canmail = "yes" if($reply=~/y/i);
	$canmail = "no" if($reply=~/n/i);

	
}
############################################################################
sub install_software()
{
my( $escconffile,$go, $appconf, $installfile );

if($usejscal) {
 mkdir($docroot.$PS."JSCal2",0755) if ( ! -d $docroot.$PS."JSCal2" );
 foreach my $p ( qw#js js/lang css css/gold css/img css/matrix css/steel css/win2k# ) {
  mkdir($docroot.$PS."JSCal2".$PS.$p,0755) if ( ! -d $docroot.$PS."JSCal2".$PS.$p );
  foreach my $f ( glob("JSCal2${PS}${p}${PS}*") ) {
   next if(-d $f);
   print "$f -> ".$docroot.$PS.$f."            \r" ;
   copy($f,$docroot.$PS.$f) if(!-f $docroot.$PS.$f);
  }
 }
}

# copy GIFs to  $docroot/rrdicons
mkdir($docroot.$PS."rrdicons",0755) if ( ! -d $docroot.$PS."rrdicons" );
foreach ( glob("rrdicons".$PS."*.gif"), "rrdicons".$PS."index.html" ) {
	print "$_ -> ".$docroot.$PS.$_."            \r" ;
	copy( $_, $docroot.$PS.$_ ) if( ! -f $docroot.$PS.$_ );
}
if( -f $docroot.$PS."rrdicons".$PS."routers2.css" ) {
	print "WARNING: CSS file already exists!                                             \n         Maybe you want to preserve your existing configuration?\n";
	$rv = ask("Overwrite existing file","no");
	if( $rv =~ /^y/i ) {
		rename( $docroot.$PS."rrdicons".$PS."routers2.css", 
			$docroot.$PS."rrdicons".$PS."routers2.css.old" );
		print "Copying CSS file                                                           \r" ;
		copy( $docroot.$PS."rrdicons".$PS."routers2.css" ,
			$docroot.$PS."rrdicons".$PS."routers2.css.bak" );
		copy( "rrdicons".$PS."routers2.css", 
			$docroot.$PS."rrdicons".$PS."routers2.css" );
	}
} else {
	print "Copying CSS file           \r" ;
	copy( "rrdicons".$PS."routers2.css", $docroot.$PS."rrdicons".$PS."routers2.css" );
}

# copy $APP.cgi to $cgibin, changing perl path on line 1 and webdev.conf
$installfile="$cgibin$PS$APP.cgi";
#$installfile=$cgibin.$PS."index.cgi";
print "$APP.cgi.pl -> $installfile     \r";
if ( -f $installfile ) {
	print "Renaming old version of script...                               \r";
	unlink "old-$installfile" if( -f "old-$installfile");
	rename ("$installfile", "old-$installfile");
}
if( ! open CGI, ">$installfile" ) {
	print "ERROR: Cannot create the $installfile file!      \n";
	exit 1;
}
if( ! open SCR, "<$APP.cgi.pl" ) {
	close CGI;
	print "ERROR: Cannot read the $APP.cgi.pl file!                         \n";
	exit 1;
}
$escconffile = $conffile;
$escconffile =~ s/\\/\\\\/g if($NT);
while ( <SCR> ) {
	if(( $usecache == 2 ) and /^#!.*perl/ ) {
		print CGI "#!speedy -- -t 3600 -r 500 -g none\n"; next;
	}
	if( $perlpath and /^#!.*perl/ ) {
		print CGI "#!$perlpath\n"; next;
	}
	if( /^\s*my\s*\(\s*\$conffile\s*\)/ ) {
		print CGI 'my ($conffile) = "'.$escconffile."\";\n"; next;
	}
	print CGI;
}
close SCR;
close CGI;
chmod 0555, $installfile if ( !$NT );
if($NT and $IIS) {
	my($installpl);
	$installpl = $installfile; $installpl =~ s/\.cgi$/\.pl/;
	if ( -f $installpl ) {
	print "Renaming old version of script...                               \r";
		unlink "old-$installpl" if( -f "old-$installpl");
		rename ($installpl, "old-$installpl");
	}
	print "Duplicating .cgi filename to .pl for IIS users...               \r";
	copy($installfile,$installpl);
}
if($BUNDLE) {
	# MRTG Bundle install
	my($bundlecgi);
	$bundlecgi = 'C:\mrtg\wwwroot\index.cgi';
	if ( -f $bundlecgi ) {
		print "Renaming old version of index.cgi...                         \r";
		unlink "old-$bundlecgi" if( -f "old-$bundlecgi");
		rename ($bundlecgi, "old-$bundlecgi");
	}
	print "Copying from cgi-bin to wwwroot/index.cgi...                    \r";
	copy($installfile,$bundlecgi);
}

# copy routingtable.cgi if enabled and it exists
if( $useextensions ) {
	if( open SCR, "<extensions/routingtable.cgi" ) {
		print "routingtable.cgi.pl -> $cgibin${PS}routingtable.cgi         \r";
		if( ! open CGI, ">".$cgibin.$PS."routingtable.cgi" ) {
			print "ERROR: Cannot create the routingtable.cgi file!               \n";
			exit 1;
		}
		while ( <SCR> ) {
			if( $perlpath and /^#!.*perl/ ) {
				print CGI "#!$perlpath\n";
				next;
			}
			print CGI;
		}
		close CGI;
		close SCR;
		if($NT and $IIS) {
			print "Duplicating .cgi filename to .pl for IIS users...            \n";
		copy("$cgibin$PS"."routingtable.cgi","$cgibin$PS"."routingtable.pl");
		}
	}
}

# create graphs dir $docroot/graphs, with correct perms
if ( ! -d $docroot.$PS."graphs" ) {
	print "Creating directory ".$docroot.$PS."graphs                \r";
	mkdir($docroot.$PS."graphs",0777);
	if($UNIX) { 
		print "Setting perm 0777 on graphs dir.                              \r";
		chmod 0777,$docroot.$PS."graphs"; }
	if($NT) { 
		my( $dir, %ntrights );
		print "Setting rights Everyone:FULL_CONTROL on graphs dir.                \r";
		eval { require Win32::FileSecurity; };
		if( $@ ) {
			print "Your version of Perl does not have Win32::FileSecurity.\nUnable to set graph directory permissions.\n";
		} else {
		$dir = Win32::FileSecurity::MakeMask( qw( FULL GENERIC_ALL ) );
		Win32::FileSecurity::Get( $docroot.$PS."graphs", \%ntrights );
		$ntrights{"Everyone"} = $dir ;
			eval { Win32::FileSecurity::Set( $docroot.$PS."graphs", \%ntrights ); };
		}
	}
}

if($APACHE) {
	# copy htaccess file 
	print "htaccess -> $docroot${PS}graphs                     \r";
	if($NT) {
		copy("htaccess", $docroot.$PS."graphs".$PS."htaccess") ;
	} else {
		copy("htaccess", $docroot.$PS."graphs".$PS.".htaccess") ;
	}
}

# create $APP.conf file in $mrtgdir
$appconf = $APP.".conf";
if( -f $conffile ) {
	print "WARNING: $conffile already exists!                                 \n         Maybe you want to preserve your existing configuration?\n";
	$rv = ask("Overwrite existing file","no");
	if( $rv !~ /^y/i ) {
		$appconf = $conffile;
		$conffile = $conffile.".new" ;
		print "Writing new configuration to $conffile\n";
	} else {
		copy( $conffile, "$conffile.bak" );
	}
}
if( $conffile ) {
if( ! open DEF, "<".$appconf ) {
	close CONF;
	print "ERROR: Cannot read the $APP.conf file!                            \n";
	print "Check permissions, and that you have extracted the $APP.conf file.\n";
	exit 1;
}
if( ! open CONF, ">".$conffile ) {
	print "ERROR: Cannot create the $APP configuration file!                 \n";
	print "Check available space and permissions, and reinstall.\n";
	exit 1;
}
print "Creating $conffile...                                                \n";
while ( <DEF> ) {
	if( /^\s*NT\s*=/ ) { print CONF "NT = $NT\n"; next; }
	if( /^\s*backurl\s*=/ ) { print CONF "backurl = /\n"; next; }
	if( /^\s*dbpath\s*=/ ) { print CONF "dbpath = $rrddir\n"; next; }
	if( /^\s*graphpath\s*=/ ) { print CONF "graphpath = $docroot${PS}graphs\n"; next; }
	if( /^\s*graphurl\s*=/ ) { print CONF "graphurl = /graphs\n"; next; }
	if( /^\s*iconurl\s*=/ ) { print CONF "iconurl = /rrdicons/\n"; next; }
	if( /^\s*confpath\s*=/ ) { print CONF "confpath = $mrtgdir\n"; next; }
	if( /^\s*cfgfiles\s*=/ ) { print CONF "cfgfiles = $mrtgfilespec\n"; next; }
	if( /^\s*usebigk\s*=/ and $usebigk ) { print CONF "usebigk = $usebigk\n"; next; }
	if( /auth-required\s*=/ and $auth ) { 
		if( $auth eq 'shib' ) { print CONF "authrequired = shib\n"; next;  }
		print CONF "authrequired = yes\n"; next; 
	}
	if( /ldap-server\s*=/ and $auth eq "ldap" ) { print CONF "ldap-server = $authopt\n"; next; }
	if( /ldap-context\s*=/ and $auth eq "ldap" ) { print CONF "ldap-context = $authcontext\n"; next; }
	if( /htpasswd-file\s*=/ and $auth eq "file" ) { print CONF "htpasswd-file = $authopt\n"; next; }
	if( /^#?\s*cache\s*=/ and $usecache ) { print CONF "cache = yes\n"; next; }
	if( /compact\s*=/ ) {
		if(!$usecompact) { print CONF "compact = no\n";  }
		else { print CONF "compact = yes\n"; }
		next;
	}
	if( /^.*routingtableurl\s*=/ ) { 
		print CONF "# Uncomment this if you have Net::SNMP installed and want to use the\n# routing table extensions\n# " if(!$useextensions);
		print CONF "routingtableurl = /cgi-bin/routingtable.cgi\n"; 
		next; }
	print CONF;
}

close CONF;
close DEF;
} else {
	print "I was unable to create the $APP.conf file for some reason.\nYou should attempt to do it by hand from the example in the install directory.\n";
}

}

############################################################################
sub install_notes()
{
	if($IIS) {
		print "* IIS users should set the Cache Expiry time to 5 mins for\n";
		print "  $docroot\\graphs\n";
	}
	if($APACHE) {
		print "* Apache users should make sure that mod_expires is loaded and enabled\n";
		print "* Apache should also be configured with 'AllowOverride: All' for the directory\n";
		print "  $docroot${PS}graphs\n";
	}
	if($NT) {
		print "* You should make sure that the Web server process can write to the path\n";
		print "  $docroot\\graphs\n";
		print "* ActivePerl users should make sure their web server will run Perl CGI scripts\n";
	}
	if($auth) {
		print "* You should check the authentication configuration in the configuration\n";
		print "  file and make sure the settings are correct.\n";
	}
	print "* You may wish to tighten the rights granted on the graphs directory\n";
	print "  $docroot${PS}graphs\n";
	if(!$usecache) {
		my(@cfgfiles);
		@cfgfiles = glob("$mrtgdir$PS$mrtgfilespec");
		if($#cfgfiles > 100) {
			print "* WARNING: You have a large number of CFG files.  This will slow performance,\n  unless you use mod_perl, speedycgi, or enable the 'optimise' option in the \n  routers2.conf configuration file.\n";
		}
	print "* You will get much better performance if you use mod_perl under Apache or\n  speedycgi (unix).  This caches the config file data for added speed.\n";
	}
	if($usejscal) {
		print "* You have installed the JSCal2 library from Dynarch.com.  This has different\n  license requirements: See http://dynarch.com/ for details.  You may be\n  required to purchase a license for its use.\n"
	}
	print "* If you wish to add support for other languages, download the language pack\n  from http://www.steveshipway.org/software\n";
	print "* Please consider rewarding the author by buying me a DVD from my Amazon.co.uk\n  wishlist.  See http://www.steveshipway.org/software/wishlist\n";
	print "* The MRTG/RRD/Routers2 book is available from Lulu with many tips and\n  techniques to help you.  See http://www.steveshipway.org/book\n";
}

############################################################################

sub execmessage($$$)
{
	my($msg, $fh);
	my($prog,$subj,$dest) = @_;
	my($ret);

	$ret = system( "echo 'Subject: $subj\n\n$subj:$^O:$]:$VERSION'|$prog -U -- $dest");
	if($ret) {
		$ret &= 0xff;
		$ret >>= 8;
		print "$prog returned code $ret.  Looks like I can't send an email after all.\n";
		return;
	}
	print "Message sent using sendmail.  Thankyou!\n";
}

sub sendmessage($$)
{
	my($msg, $fh);
	my($subj,$dest) = @_;

    $msg = new Mail::Send;
    $msg->to($dest);
    $msg->subject($subj);

    $fh = $msg->open;
    print $fh "$subj:$^O:$]:$VERSION";
    $fh->close;      
	print "Message sent using MAPI.  Thankyou!\n";
}

sub mailme()
{

	eval { require Mail::Send; };
	if($@) {
		my($s,$sendmail);
		print "No Mail::Send available, trying sendmail instead.\n";
		foreach $s ( '/usr/bin/sendmail','/usr/sbin/sendmail',
'/u	sr/lib/sendmail','/etc/sendmail','/bin/sendmail' ) {
			if( -x $s) { $sendmail = $s; last;}
		}
		if( $sendmail ) {
			eval { execmessage($sendmail,"$APP install $VERSION",$EMAIL); };
		} else {
			print "Can't find any sendmail executable...\n";
			print "Oh well, I cant send it after all. Thanks anyway!\n";
		}
	} else {
		eval { sendmessage("$APP install $VERSION",$EMAIL); };
	}
}

############################################################################
# MAIN CODE STARTS HERE
############################################################################

print "\n";
print "This program attempts to install the $APP.cgi package, located in\n";
print "the current directory.  It will attempt to identify system settings,\n";
print "but you must confirm the locations guessed, or give the correct\n";
print "information.\n";
print "At any point, you can answer 'quit' to abort the installation.\n";
print "Depending on your Perl implementation, you may also have line editing\n";
print "and history capability.\n";
print "Default answers are in square brackets before the prompt.\n";

$rv = ask("Continue","yes");
if($rv!~/^y/i) {
	print "OK, lets not go any further then.\n";
	exit 0;
}

# Change dir -- for people using file mangler under Windows
my($d) = $0;
$d =~ s/[\\\/]?install\.pl$// if($d);
if(-d $d) {
	print "Source directory is $d\n";
	chdir($d);
}

print "Checking Perl libraries...\n";
libcheck();

print "\nFINDING OUT ABOUT YOUR SYSTEM\n";
locate_paths;

print "\nASKING OPTIONS\n";
choose_options;

print "\nINSTALLING SOFTWARE\n\n";
print "Perl is     : $perlpath\n";
print "MRTG files  : $mrtgdir$PS$mrtgfilespec\n";
print "RRD files   : $rrddir\n";
print "Doc root    : $docroot\n";
print "CGI bin     : $cgibin\n";
print "Config file : $conffile ";
print "(already exists)" if( -f $conffile );
print "\n";
print "Routingtable: ACTIVE\n" if($useextensions);
print "Routingtable: INACTIVE\n" if(!$useextensions);
print "Compact page: DISABLED\n" if(!$usecompact);
print "Compact page: ENABLED\n" if($usecompact);
print "Caching     : DISABLED\n" if(!$usecache);
print "Caching     : mod_perl\n" if($usecache == 1);
print "Caching     : speedycgi\n" if($usecache == 2);
print "JSCal2      : ".($usejscal?"INSTALL":"NO")."\n";
print "'usebigk'   : $usebigk\n";
if($auth) {
	print "Auth option : $auth\n";
	if($auth eq "file" ) {
		print "   File     : $authopt\n";
	}
	if($auth eq "ldap"  ) {
		print "   Server   : $authopt\n";
		print "   Context  : $authcontext\n";
	}
} else {
	print "Auth option : NONE\n";
}
print "Mail Steve  : $canmail\n";
#print "PageTop/Foot: $usepagetop\n";
print "Other options can be set later by modifying the Config file\n";

$rv = ask("Continue to install","no");
if($rv!~/^y/i) {
	print "OK, lets not go any further then.\n";
	exit 0;
}
install_software;

mailme if($canmail=~/y/);

print "\n\n** ALL COMPLETE **\n\n";
print "You should now be able to run the software, although you may need to\n";
print "make sure you have your web server running.\n";
if(!$BUNDLE) {
print "To access the frontend, point your favourite web browser at the URL:\n";
if( $NT and $IIS ) {
	print "    http://".hostname()."/cgi-bin/".$APP.".pl\n";
} else {
	print "    http://".hostname()."/cgi-bin/".$APP.".cgi\n";
}
print "(This assumes you have your web server configured on this host port 80)\n";
}
print "\nSee http://www.steveshipway.org/software/wishlist for information on\n";
print "how to say 'thanks' for this free software by sending me a gift!\n";
print "\nSee http://www.steveshipway.org/book to obtain a copy of the MRTG/RRD/Routers2\nbook with advanced tips and techniques!\n\n";
print "See http://www.steveshipway.org/software to check for updates and patches!\n\n";
install_notes;
$rv = ask("All done","yes") if($NT);
exit 0;
