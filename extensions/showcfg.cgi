#!/usr/bin/perl
#
# showcfg.cgi
#
# Just show the corresponding .cfg file.
# SECURITY RISK! This will obviously display the SNMP community strings
# in your .cfg file!  This is intended more for demo use than live use!
#

use strict;
use CGI;

# Variables
my( $confpath ) = "/home/stevesh/public_html/mrtg/conf/";
my( $device, $community, $targetwindow, $target, $file, $backurl )
	= ( "","public","graph","","","");
my( $conffile );
my( $routersurl );
my( $q ) = new CGI;
my( %headeropts );
my( $thishost ) = $q->url();
$thishost =~ /http:\/\/([^\/]+)\//;
$thishost = $1;

#######################################################################
# Put your page generation code in here.  HTTP headers already produced.
# The Javascript linked in the start_html function manages the side menu(s).
# Although the javascript is not required, it makes the menus update 
# correctly after this option has been selected.

sub mypage()
{
	my( $javascript ) = "function RefreshMenu()
	{
	var mwin; var uopts;
	mwin = parent.menu;
	uopts = 'T';
	if( parent.menub ) { mwin = parent.menub; uopts = 't'; }
	mwin.location = '".$routersurl."?if=__none&rtr="
		.$q->escape($file)."&page=menu&xmtype=options&uopts='+uopts;
	}";

	print $q->start_html({-title=>$file,
		-script=>$javascript, -onLoad=>"RefreshMenu()"});

	print $q->h1($file);

	print "<TABLE width=100% border=1 cellspacing=0><TR><TD>\n";
	if(open CFG, "<$confpath$file") {
		print "\n<PRE>\n";
		while ( <CFG> ) { print; }
		print "</PRE>\n";
		close CFG;
	} else {
		print "<FONT color=#ff0000>Unable to open the file.</FONT>\n";
	}
	print "</TD></TR></TABLE>\n";

	print $q->hr.$q->small("MRTG configuration file")."\n";
	print $q->end_html();
}

#######################################################################

# Process parameters
$file   = $q->param('fi') if(defined $q->param('fi'));
$targetwindow = $q->param('t') if(defined $q->param('t'));
$conffile = $q->param('conf') if(defined $q->param('conf'));
$routersurl = $q->param('url') if(defined $q->param('url'));
$routersurl = "http://$thishost/cgi-bin/routers2.cgi" if(!$routersurl);

# HTTP headers
%headeropts = ( -expires=>"now" );
$headeropts{'-target'} = $targetwindow if($targetwindow);
print $q->header(%headeropts);

# Make the page
mypage();

# End
exit(0);
