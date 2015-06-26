#!/usr/bin/perl -w
# vim:ts=4
# pdfreport.cgi
#
# This is a routers2.cgi plugin extension
# This generates a pdf format report, and places it into the middle window.
# This requires HTMLDOC to be installed. ( www.htmldoc.org for source )

use strict;
use CGI;
use File::Basename; # for dirname()
use FileHandle;
require 5.006;

# Configure here
my( $HTMLDOC ) = "/usr/bin/htmldoc"; # location of htmldoc executable
my( $ROUTERSCGI ) = "/u01/www/cgi-bin/routers2.cgi"; # location of routers2.cgi
my( $WORKDIR ) = "/tmp";             # temporary work directory
my( $WEBROOT ) = "/u01/www/html";    # docroot for your web server
my( $CONFPATH ) = "/u01/mrtg/conf";  # default path for cfg files
my( $VERSION ) = "1.6";
my( $DWMY ) = "my";                  # set to dw for short term graphs

# Variables
my( $device, $community, $targetwindow, $target, $file, $backurl )
	= ( "","public","graph","","","");
my( $conffile, %config );
my( $routersurl );
my( $q ) = new CGI;
my( %headeropts );
my( %targets );
my( $REQ ) = 1;
my( $archdate ) = "";
my( $thishost ) = $q->url();
$thishost =~ /http:\/\/([^\/]+)\//;
$thishost = $1;

#######################################################################
# Make an error page
sub errorpage {
	%headeropts = ( -expires=>"now" );
	$headeropts{'-target'} = $targetwindow if($targetwindow);
	print $q->header(%headeropts);
	print $q->start_html;
	print $q->h1("ERROR");
	print $q->p($q->b($_[0]))."\n";
	print $q->p("An error was detected.");
	print $q->hr.$q->end_html();
}

#######################################################################
# read routers2.conf
# We need to do this in order to locate the confpath
sub readconf() {
	%config = ();
	$config{'routers.cgi-confpath'} = $CONFPATH;
}

#######################################################################
# Read the MRTG .cfg file
# We need to identify Targets and Graphs that do not have InMenu=no
sub readcfgfile($) {
	my( $cfgfile ) = $_[0];
	my($fd);

	$fd = new FileHandle ;

    if(! $fd->open( "<$cfgfile" )) {
		errorpage("Unable to open $cfgfile"); exit 0; 
	}

	while( <$fd> ) {
		if( /^\s*Target\s*\[(\S+)\]\s*:/i ) {
			$targets{$1} = 1; next;
		}
		if( /^\s*routers2?\.cgi\*Graph\s*\[\S+\]\s*:\s*(\S+)/i ) {
			$targets{"_$1"} = 1; next;
		}
		if( /^\s*routers2?\.cgi\*InMenu\s*\[(\S+)\]\s*:\s*(\S+)/i ) {
			my( $k, $v ) = ( $1, $2 );
			if( $k eq "_" and $v =~ /[n0]/i ) { $REQ=2; next; } # ugly
			$k = "_$k" if(! defined $targets{$k});
			next if(! defined $targets{$k});
			if( $v =~ /[n0]/i ) { $targets{$k} = 0; } 
			else { $targets{$k} = 2; }
			next;
		}
		if( /^\s*Include\s*:\s*(\S+)/i ) {
			my $f = $1;
			$f = (dirname $cfgfile).'/'.$f if($f !~ /^\//);
			&readcfgfile($f);
			next;
		}
	}
	close $fd;
}

sub readcfg() {
	my( $cfgfile );

	$cfgfile = $config{'routers.cgi-confpath'}.'/'.$file;
	%targets = ();
	readcfgfile($cfgfile);
}

#######################################################################
# Generate the PDF and output it
sub makepdf {
	my( @files );
	my( $cmd, $targ );
	my( $tdir, $tfile, $qs, $line, $TMPFILE );
	my( $i );

	# create tempoary work path
	$tdir = "$WORKDIR/report-$$";
	mkdir $tdir or do { errorpage("Cannot create work directory"); return; };

	# Identify the targets
	$ENV{'QUERY_STRING'} = "";
	foreach $targ ( keys %targets ) {
		next if($targets{$targ}<$REQ); # not in menu
		next if($target and ($target ne $targ));
	# For each target, generate the HTML by calling routers2.cgi interactively
	# Store the html in a temporary file
	# Use special gstyle 'l2p' to get long, double height, PDAmode (no buttons)
	# Use uopts=s to suppress extra junk and add in line breaks
		$qs = "nomenu=1&page=graph&xgtype=$DWMY&xgstyle=l2p&rtr=$file&if=$targ&uopts=s";
		$qs .= "&arch=$archdate" if($archdate);
		$ENV{QUERY_STRING} = $qs;
		$ENV{REMOTE_USER} = $q->remote_user();
		$ENV{AUTHENTICATE_UID} = $q->remote_user();
		$cmd = "$ROUTERSCGI -U '".$q->remote_user()
			.($archdate?" -a $archdate":"")
			."' -D '$file' -T '$targ' -t $DWMY -s l2p '$qs' "
			."> $tdir/$targ.html.0";
		system( $cmd );
		# Strip the header from the output
		open IN, "<$tdir/$targ.html.0" or next;
		open OUT, ">$tdir/$targ.html";
		$i = 0;
		while ( <IN> ) { $i = 1 if(/<BODY/i); print OUT if($i); }
		close IN; close OUT; 
		unlink "$tdir/$targ.html.0";
		push @files, "$tdir/$targ.html";
	}

	# Set up the command line parameters for htmldoc
	# Force certain environment thingies
	$ENV{TMPDIR} = $tdir if(!$ENV{TMPDIR});
	$ENV{TMP} = $tdir if(!$ENV{TMP});
	# lose existing parameters
	# undef $ENV{'QUERY_STRING'} if(defined $ENV{'QUERY_STRING'}); 
	$TMPFILE = "$tdir/report.$$.pdf";
	$ENV{HTMLDOC_NOCGI} = 1;
	$cmd = "$HTMLDOC --size a4 --webpage --no-links --no-strict --color -t pdf --quiet --path $WEBROOT --outfile $TMPFILE ".(join " ",@files)." > $TMPFILE.err 2>&1";
	system( $cmd );
	open PDF,"<$TMPFILE"; binmode PDF;
	$line = <PDF>;
	if( $line !~ /^\%PDF/ ) { # no magic number - must be some error output
		print $q->header(-expires=>'now', -type=>'text/plain');
		print "ERRORS DETECTED IN HTMLDOC\n\n$cmd\n\n";
		open ERR,"<$TMPFILE.err";
		while ( <ERR> ) { print; }
		close ERR;
		print "\n\n";
		print $line;
		while( <PDF> ) { print; }
		close PDF;
		return;
	}
	close PDF;

	print $q->header(-expires=>'now', -type=>'application/pdf');
	open PDF,"<$TMPFILE";
	binmode PDF; binmode STDOUT;
	while ( <PDF> ) { print; }
	close PDF;

	# clean up
	unlink $TMPFILE;
	unlink "$TMPFILE.err";
	unlink @files;
	rmdir $tdir;
}

#######################################################################
# Create the wrapper frame
sub mypage()
{
	my($host);
	my( $javascript ) = "function RefreshMenu()
	{
	var mwin; var uopts;
	mwin = parent.menu;
	uopts = 'T';
	if( parent.menub ) { mwin = parent.menub; uopts = 't'; }
	mwin.location = '".$routersurl."?if=__none&rtr="
		.$q->escape($file)."&page=menu&xmtype=options&uopts='+uopts;
	}
	RefreshMenu();
	";

	# Headers
	%headeropts = ( -expires=>"now" );
	$headeropts{'-target'} = $targetwindow if($targetwindow);
	print $q->header(%headeropts);

	# First the header
	print "<HTML><HEAD><TITLE>routers.cgi PDF report plugin</TITLE>\n";
	print "</HEAD><SCRIPT language=JavaScript><!--\n$javascript\n// --></SCRIPT>\n";
	# We create a special frameset:
	print "<FRAMESET border=0 marginwidth=0 marginheight=0 >";
	$file = '' if(!$file);
	$conffile = '' if(!$conffile);
	$routersurl = '/cgi-bin/routers2.cgi' if(!$routersurl);
#	print "<FRAME name=debug src=".$q->url
#		."?P=2&fi=".$q->escape($file)
#		."&conf=".$q->escape($conffile)
#		."&url=".$q->escape($routersurl).">";
	print "<FRAME name=pdfreportembed src=".$q->url
		."?P=1&fi=".$q->escape($file)
		."&ta=".$q->escape($target)
		."&conf=".$q->escape($conffile)
		.($archdate?("&ad=".$q->escape($archdate)):"")
		."&dwmy=".$q->escape($DWMY)
		."&url=".$q->escape($routersurl).">";
	print "</FRAMESET>\n";
	print "<!-- rtr=$file if=$target ad=$archdate -->\n";
	print "</HTML>\n";

}
sub debugpage {
	print $q->header(-expires=>'now', -type=>'text/plain');
	print "rtr=$file\ntgt=$target\n";
}

#######################################################################

# Process parameters
$file   = $q->param('fi') if(defined $q->param('fi'));
$target = $q->param('ta') if(defined $q->param('ta'));
$archdate = $q->param('ad') if(defined $q->param('ad'));
$archdate = $q->param('arch') if(defined $q->param('arch'));
$targetwindow = $q->param('t') if(defined $q->param('t'));
$conffile = $q->param('conf') if(defined $q->param('conf'));
$routersurl = $q->param('url') if(defined $q->param('url'));
$routersurl = "http://$thishost/cgi-bin/routers2.cgi" if(!$routersurl);
$DWMY = $q->param('dwmy') if(defined $q->param('dwmy'));

# Are we the wrapper, or the actual?
if( $q->param('P') ) {
	# actual
	readconf(); # find out where the confpath is
	readcfg();  # read the MRTG .cfg file
	if($q->param('P') > 1 ) {
		debugpage();
	} else {
		makepdf();
	}
} else {
	# wrapper
	mypage();
}

# End
exit(0);
