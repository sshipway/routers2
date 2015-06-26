#!/usr/bin/perl -w
#
# This counts the number of in-use ports on the dial-in router.
#
# Data returned in MRTG format.

use Net::SNMP;
use Getopt::Std;

my($mesg) = 'Port query tool';
my($inuse) = 'U';
my($allports) = 'U';

my($OID) = '1.3.6.1.2.1.2.2.1.8'; # ifoperstatus
my($TIMEOUT) = 8;
my($from,$to) = (0,99999);
my($snmp,$resp,$snmperr);
my($hostname) = 'localhost';
my($community) = 'public';
use vars qw($opt_H $opt_s $opt_e $opt_h $opt_c $opt_t $opt_d $opt_v);

sub dohelp {
	print "Usage: mrtg-portsinuse [-d][-h][-s num -e num][-H host][-c community]\n";
	print "Return count of ACTIVE ports and count of Disabled/unknown ports.\n";
	print "Specify interface start and end range with -s -e, else all ports.\n";
	exit 0;
}

sub fetchdata {

	print "(fetching)\n" if($opt_d);

	($snmp,$snmperr) = Net::SNMP->session( -hostname=>$hostname,
		-community=>$community, -timeout=>$TIMEOUT );
	if($snmperr) {
		print "($snmperr)\n" if($opt_d);
		$mesg = "Error: $snmperr";
		$resp = 0;
		return;
	}

	$resp = $snmp->get_table( -baseoid=>$OID);

	if(!$resp) {
		$mesg = "No data retrieved from $hostname! ".$snmp->error();
	}

	$snmp->close;
}

sub countinuse {
	my($c) = 0;
	my($a) = 0;

	print "(counting)\n" if($opt_d);

	if(!$resp) {
		print "(No data!)\n" if($opt_d);
		$mesg = "No data retrieved.";
		return ('U','U') ;
	}

	foreach my $k ( keys %$resp ) {
		$ifno = -1;
		$ifno = $1 if($k =~ /\.(\d+)$/);
		next if(( $ifno < $from )or( $ifno > $to ));
		$c += 1 if( $resp->{$k} == 1 );
		$a += 1 if( $resp->{$k} > 2 );
	}

	return ($c,$a);
}

###########################################################################
getopts('hH:c:t:dv:s:e:');
$hostname = $opt_H if($opt_H);
$community = $opt_c if($opt_c);
$from = $opt_s if($opt_s);
$to   = $opt_e if($opt_e);

dohelp if($opt_h);

#print "Debug = $opt_d\n";

$mesg = "Port query tool: $hostname";
fetchdata;
($inuse,$allports) = countinuse() if($resp);

print "$inuse\n$allports\n\n$mesg\n";
exit 0;
