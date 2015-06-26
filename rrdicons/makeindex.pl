#!perl
#
# make the index page for the icons
#

my($n,$i);
my(@icons);


@icons = glob('*-sm.gif');

print "<HTML><HEAD><TITLE>Link icons</TITLE></HEAD>\n";
print "<BODY><H1>routers.cgi Link Icons</h1>\n";
print "<P>These are the icons available for use in the routers.cgi program for links.  Use these as directed in the routers.cgi documentation.</p>\n";

print "<TABLE border=1>\n";
$n=0;
foreach $i ( sort @icons ) {
	print "<TR>" if( $n < 1 );
	print "<TD align=center><IMG src=$i alt=$i width=15 height=15><BR>$i</TD>\n";

	$n++;
	if($n > 5) { $n = 0; print "</TR>\n"; }
}
print "</TR>";

print "</TABLE>\n<BR>\n<HR>\n<SMALL>Steve Shipway </small></body></HTML>\n";
exit(0);
