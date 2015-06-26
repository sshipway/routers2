#!/usr/bin/perl
#
# extension.pl
#
# This is a harness for creating routers.cgi extension scripts.  You should
# make the necessary changes and add your page generation code in the
# subroutine mypage()
#
# *** IF YOU ARE NOT FAMILIAR WITH PROGRAMMING IN PERL, THEN LEAVE NOW ***
#
# As it stands, this script will only print out the current parameters.
#
# See the routers.cgi documentation for how to link this script in to your
# MRTG .cfg files.
# Remember that the SNMP community string is passed as a parameter to this
# script, and be aware of the security implications of this.
#
# If you use style sheets, you probably want to also parse the routers2.conf
# file and get the stylesheet parameter, and pass it to the start_html
#
# Steve Shipway May 2002
#
# PUBLIC DOMAIN SOFTWARE
# This source code is released freely into the public domain.  You are free
# to use it for whatever you wish, however you wish.  Any routers.cgi
# extensions written based on this framework are your property - you may 
# release them as public domain, GPL, or even sell them commercially if
# you should so wish.  Of course, my routers.cgi software still remains GPL.
#

use strict;
use CGI;

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
	my( $javascript ) = "function RefreshMenu()
	{
	var mwin; var uopts;
	mwin = parent.menu;
	uopts = 'T';
	if( parent.menub ) { mwin = parent.menub; uopts = 't'; }
	mwin.location = '".$routersurl."?if=__none&rtr="
		.$q->escape($file)."&page=menu&xmtype=options&uopts='+uopts;
	}";

	print $q->start_html({-title=>"Example Extension",
		-class=>'extension',
		-script=>$javascript, -onLoad=>"RefreshMenu()"});

	print $q->h1("Example Extension");

	print "Config File: $conffile".$q->br."\n" if($conffile);
	print "Device: $device".$q->br."\n" if($device);
	print "File: $file".$q->br."\n" if($file);
	print "Target: $target".$q->br."\n" if($target);
	print "Community: $community".$q->br."\n" if($community);
	print "routers.cgi: $routersurl".$q->br."\n" if($routersurl);

	print $q->hr."Go back with ".$q->a({href=>$backurl},$backurl)
		if($backurl);

	print $q->hr.$q->small("Example routers.cgi extension page")."\n";
	print $q->end_html();
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
# retrieve information such as the confpath parameter, or to read the
# MRTG file $file and retrieve the configuration for target $target

# HTTP headers
%headeropts = ( -expires=>"now" );
$headeropts{'-target'} = $targetwindow if($targetwindow);
print $q->header(%headeropts);

# Make the page
mypage();

# End
exit(0);
