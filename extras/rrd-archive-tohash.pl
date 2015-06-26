#!/usr/bin/perl
#
# Move rrd files into hash-named subdirs.

use strict;
my($date,$k,$rrdfile);

#################################
# For RRD archives: make 2chr subdir name from filename
sub makehash($) {
    my($x);
# This is more balanced
    $x = unpack( '%8C*',$_[0] );
# This is easier to follow
#   $x = substr($_[0],0,2);
    return $x;
}

my($path) = $ARGV[0];
if ( ! -d $path ) {
	print "Usage: $0 <archivepath>\n";
	exit 1;
}
chdir($path);
foreach $date (glob("*-*-*")) {
	print "Date: $date\n";
	chdir("$path/$date");
	foreach $rrdfile (glob("*.rrd")) {
		$k = makehash($rrdfile);
		if(! -d "$path/$k" ) { mkdir("$path/$k"); }
		if(! -d "$path/$k/$rrdfile.d" ) { mkdir("$path/$k/$rrdfile.d"); }
		rename ( $rrdfile, "$path/$k/$rrdfile.d/$date.rrd" );
		print "$rrdfile         \r"
	}
	print "                                                               \r";
}

exit 0;

