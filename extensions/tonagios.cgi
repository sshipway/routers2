#!/usr/bin/perl
#
# tonagios.cgi
#
# This is a routers2.cgi plugin extension, that relays to Nagios.

use strict;
use CGI;

# configure here: Nagios status.cgi URL (or use extinfo.cgi instead)
my( $NAGIOS ) = "http://nagios.auckland.ac.nz/nagios/cgi-bin/status.cgi";
# This is chopped from the end of the configuration filename
my( $TRUNCATE ) = "\.(cfg|conf)?";
# Alternative examples
# my( $TRUNCATE ) = "(\.auckland\.ac\.nz)?\.(cfg|conf)?";


# Variables
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

	# Who is it for?
	$host = $device; 
	if(!$host) {
		$host = $file;
		$host =~ s/\.(cfg|conf)$//; $host =~ s/^.*\///;
	}	
	$host =~ s/$TRUNCATE$//;

	# First the header
	print "<HTML><HEAD><TITLE>routers.cgi Nagios redirect plugin</TITLE>\n";
	print "</HEAD><SCRIPT language=JavaScript><!--\n$javascript\n// --></SCRIPT>\n";
	# We create a special frameset:
	print "<FRAMESET border=0 marginwidth=0 marginheight=0>";
	print "<FRAME name=nagiosembed src=$NAGIOS?host=$host&noheader>";

	print "</FRAMESET></HTML>\n";

}

#######################################################################

# Process parameters
$device = $q->param('h') if(defined $q->param('h'));
$file   = $q->param('fi') if(defined $q->param('fi'));
$target = $q->param('ta') if(defined $q->param('ta'));
$community = $q->param('c') if(defined $q->param('c'));
$backurl = $q->param('b') if(defined $q->param('b'));
$targetwindow = $q->param('t') if(defined $q->param('t'));
$conffile = $q->param('conf') if(defined $q->param('conf'));
$routersurl = $q->param('url') if(defined $q->param('url'));
$routersurl = "http://$thishost/cgi-bin/routers2.cgi" if(!$routersurl);

# At this point, you may wish to add code to parse the $conffile file, and
# retrieve information shuch as the confpath parameter, or to read the
# MRTG file $file and retrieve the configuration for target $target

# HTTP headers
%headeropts = ( -expires=>"now" );
$headeropts{'-target'} = $targetwindow if($targetwindow);
print $q->header(%headeropts);

# Make the page
mypage();

# End
exit(0);
