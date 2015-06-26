#!/usr/bin/perl
# vim:ts=4
#
# mrtg-nrpe: Get nrpe output, pure perl
#
# Steve Shipway, University of Auckland, 2004
# Incorporates code from check_nrpe
# Distribute under GPL
# Version: 2.1
#          2.2: fix parsing of line to be a bit more sensible identifying nos.
#          2.3: With caching mode!
#          2.4: Give 'unknown' in MRTG if number does not exist
#          2.5: better support for perfcounter part parsing

use strict;
use Socket;
use Getopt::Long;

my($VERSION) = "2.4";
my($ctx,$ssl) = (0,0);
my($SSL) = 1;
my($PERFEXT) = 0;
my($DEBUG) = 0;
my(%STATUS) = ( OK=>0, WARNING=>1, CRITICAL=>2, UNKNOWN=>3 );
my($status1,$rv1) = ( $STATUS{UNKNOWN}, "Not Fetched" );
my($status2,$rv2) = ( $STATUS{UNKNOWN}, "Not Fetched" );
my($MRTG) = 0; # MRTG mode or NAGIOS mode?
my(%options)=();
my($CACHETIME)=120;
my($CACHEFILE)="/var/tmp/nrpe.cache";

####################################################################
my(%cache);
sub writecache {
	open C,">$CACHEFILE";
	foreach ( keys %cache ) { 
		if( defined $cache{"$_:time"} ) {
			next if((time-$cache{"$_:time"})>$CACHETIME);
		} else {
			next if((time-$cache{$_})>$CACHETIME);
		}
		print C "$_=".$cache{$_}."\n"; 
	}
	close C;
}
sub readcache {
	my($line);
	open C,"<$CACHEFILE";
	while ( $line = <C> ) {
		chomp $line;
		$cache{$1}=$2 if( $line =~ /^([^=]+)=(.*)/ );
	}
	close C;
}
sub acache {
	my($k,$v,$s);
	$s = shift @_;
	$v = shift @_;
	$k = join ":",@_;
	$cache{$k}="$s:$v";
	$cache{"$k:time"}=time;
	print "Caching: [$k]=[$s:$v]\n" if($DEBUG);
}
sub qcache {
	my($k);
	$k = join ":",@_;
	if( defined $cache{$k} 
		and defined $cache{"$k:time"}
		and (time-$cache{"$k:time"})<$CACHETIME
		and $cache{$k} =~ /^(\d+):(.*)/ ) {
		print "Found in cache: [$1][$2]\n" if($DEBUG);
		return ( $1,$2 );
	}
	print "Cache not found.\n" if($DEBUG);
	return (-1,-1);
}
####################################################################
# make crc
my(@crctable); # array of 256 unsigned longs (4 bytes)
sub gen_crc_table {
	my($poly,$j,$i,$crc);

    $poly=0xEDB88320;
	$i = 0;
	while($i<256){
		$crc=$i;
        foreach $j ( 8,7,6,5,4,3,2,1 ){
        	if($crc & 1) {
        		$crc=($crc>>1)^$poly;
        	} else {
				$crc>>=1;
			}
        }
		$crctable[$i]=$crc & 0xFFFFFFFF;
		$i += 1;
	}
}

sub crc($$) {
	my($c) = 0;
	my($v,$n) = @_;
#	my($oc);

	gen_crc_table if(!@crctable);

	# calculate CRC here
	$c=0xFFFFFFFF; 
	# structure is short/short/long/short/char1024 == 1034 bytes
#	print "CRC[$n]:" if($DEBUG);
	foreach ( unpack ("c$n", $v)  ) {
#		$oc = $c;
		$c = ( ($c>>8) & 0x00ffffff )^$crctable[($c^$_)&0xFF];
#		printf "$_ [%X]=>[%x]\n",$oc,$c if($DEBUG);
	}
	$c ^= 0xFFFFFFFF;
#	printf "final=>[%X]\n",$c if($DEBUG);
	return $c;
}

sub dumppkt($) {
	my($v) = $_[0];	
	my($n);

	$n = length($v);
	print "Packet:\n";
	foreach ( unpack ("c$n", $v)  ) { print "$_,"; }
	print "\n";
}

# Init SSL
sub init_ssl {
	return 0 if(!$SSL); # dont have SSL
	return 0 if($ctx); # already done it
	require Net::SSLeay;
	print "Init_ssl starting\n" if($DEBUG);
	$Net::SSLeay::trace = 2 if($DEBUG);
	Net::SSLeay::load_error_strings();
	Net::SSLeay::SSLeay_add_ssl_algorithms();
	Net::SSLeay::randomize();
	$ctx = Net::SSLeay::CTX_new() 
		or return("Failed to create SSL_CTX $!");
	Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL);
#		and return("ssl_ctx_set_options: $!");
#	Net::SSLeay::CTX_set_cipher_list($ctx, "ADH")
#    	and return("ssl ctx set cipher");
	return 0;
}

sub end_ssl {
	print "end_ssl\n" if($DEBUG);
	Net::SSLeay::free ($ssl);               # Tear down connection
	Net::SSLeay::CTX_free ($ctx);
	$ssl = $ctx = 0;
}

sub end_connection {
	end_ssl() if($SSL);
	close SOCK;
}

# Connect to host, port
sub do_connect($$) {
	my($host,$port) = @_;
	my($ip,$sin,$rv);
	$port = 5666 if(!$port);
	$port = getservbyname ($port, 'tcp')  unless $port =~ /^\d+$/;
	return "Bad port [$port]" if(!$port);
	$ip = gethostbyname ($host);
	return "Bad host [$host]" if(!$ip);
	$sin  = sockaddr_in($port, $ip);
	return "sockaddr_in: $!" if(!$sin);
	print "Connecting socket to $host:$port \n" if($DEBUG);
	socket(SOCK, &AF_INET, &SOCK_STREAM, 0)  or return "socket failed: $!";
	eval {
		$SIG{ALRM} = sub { die("TIMEOUT"); };
		alarm($options{timeout});
		$rv = connect(SOCK, $sin);
		alarm(0);
	};
	return "Timeout on connect: remote daemon not running, or firewall blocking?" if($@);
	return "connect: $!" if(!$rv);
	binmode SOCK;
	select(SOCK); $|=1; select (STDOUT);   # Eliminate STDIO buffering
	if($SSL) {
		$rv = init_ssl();
		return "Init SSL: $rv" if($rv);
		print "Creating SSL object\n" if($DEBUG);
		$ssl = Net::SSLeay::new($ctx);
		if(!$ssl) {
			return("Failed to create SSL $! ".Net::SSLeay::print_errs());
		}
		print "Setting cipher list\n" if($DEBUG);
		$rv = Net::SSLeay::CTX_set_cipher_list($ctx,'ADH');
		Net::SSLeay::set_fd($ssl, fileno(SOCK));   # Must use fileno
		print "SSL connect...\n" if($DEBUG);
		eval {
			$SIG{ALRM} = sub { die("TIMEOUT"); };
			alarm($options{timeout});
			$rv = Net::SSLeay::connect($ssl);
			alarm(0);
		};
		return "SSL Timeout: maybe remote server doesn't use SSL? Try with -n" if($@);
		if($rv!=1) { return("ssl connect: ".Net::SSLeay::print_errs()); }
	}
	return 0; # OK
}

sub send_msg($) {
	my($msg) = $_[0];
	my($rv) = 0;

	dumppkt($msg) if($DEBUG);

	if($SSL) {
		$rv = Net::SSLeay::write($ssl, $msg);  # Perl knows how long $msg is
		return ("ssl write: $rv: ".Net::SSLeay::print_errs())
			if($rv) ;
	} else {
		$rv = syswrite SOCK,$msg,length($msg);
		return "syswrite: $!" if(!$rv);
	}

	return 0;
}

sub rcv_msg() {
	my($rv) = undef;
	my($n);
	if($SSL) {
		$rv = Net::SSLeay::read($ssl); # returns undef on failure
		if(!defined $rv) {
			$rv = Net::SSLeay::print_errs();
		}
	} else {
		$n = sysread SOCK,$rv,2048;
		return "" if(!$n);
	}
	return $rv;
}

sub do_request($@) {
	my($rv,$stat);
	my($cmd,@arg) = @_;
	my($resp,$req,$q,$crc,$rcrc);
	my($v,$t,$c,$r,$b,$j);

	print "Running $cmd\n" if ($DEBUG);

	$SIG{PIPE} = 'IGNORE';

	$q = "_NRPE_CHECK";
	if($cmd) { $q = join '!', $cmd, @arg; }
	# note we have to use a junk field to pad to word boundary
	$req = pack "nnNna1024n",2,1,0,0,$q,0;
	$crc = crc($req,length($req));
	$req = pack "nnNna1024n",2,1,$crc,0,$q,0;
	printf "Sending [2,1,%X,0,$q,0]\n",$crc if($DEBUG);
	send_msg($req);
	CORE::shutdown SOCK, 1;  # Half close 
	$rv = rcv_msg();
	return( $STATUS{UNKNOWN}, "Error on read: Problem with remote server?" ) 
		if(!defined $rv);
	return( $STATUS{UNKNOWN}, "No data returned: wrong SSL option, or IP address not authorised?" ) if(!$rv);
	($v,$t,$c,$r,$b,$j) = unpack "nnNna1024a2", $rv;
	printf "Received [$v,$t,%X,$r,$b]\n",$crc if($DEBUG);
	return( $STATUS{UNKNOWN}, "Bad response version $v: Upgrade your server!" ) if($v != 2);
	return( $STATUS{UNKNOWN}, "Bad response type $t: This should never happen??" ) if($t != 2);
	return( $STATUS{UNKNOWN}, "Bad response status $r: Corrupted packet?" ) 
		if($r>3 or $r<0);
	$resp = pack "nnNna1024a2",$v,$t,0,$r,$b,$j;
	$crc = crc($resp,length($resp));
	return( $STATUS{UNKNOWN}, "Bad response CRC: wrong SSL option?" ) if($crc != $c);

	$b =~ s/\0+$//;
	return($r,$b);
}

sub do_output($$$$) {
	my($stat,$msg,$statb,$msgb) = @_;
	my(@val) = ();
	my($tmsg,$v);
	my($a,$b,$aoff,$boff) = ('UNKNOWN','UNKNOWN',0,0);

	if(!$MRTG) {
		print "$msg\n";
		exit $stat;
	}

	if($stat != $STATUS{UNKNOWN}) {
		$a = 0;
		$tmsg = $msg;
		@val = ();
		if($PERFEXT and $tmsg=~/\|/) {
			$tmsg =~ s/^.*\|// ;
			while( $tmsg =~ s/^\s*\S[^=]*=(\d+\.?\d*)[s%Bc]?;\S+// ) { push @val, $1; }
		} else {
			while( $tmsg =~ s/(\W|^)(\d+\.?\d*)/\1/ ) { push @val, $2; }
		}
		$aoff = $options{offset}[0];
		$aoff = 0 if(!defined $aoff);
		if(defined $val[$aoff]) {
		$a = $val[$aoff] if($aoff <= $#val);
		} else { $a = 'UNKNOWN'; }
	}
	if($statb != $STATUS{UNKNOWN}) {
		$b = 0;
		$tmsg = $msgb;
		@val = ();
		if($PERFEXT and $tmsg=~/\|/) {
			$tmsg =~ s/^.*\|// ;
			while( $tmsg =~ s/^\s*\S[^=]*=(\d+\.?\d*)[s%Bc]?;\S+// ) { push @val, $1; }
		} else {
			while( $tmsg =~ s/(\W|^)(\d+\.?\d*)/\1/ ) { push @val, $2; }
		}
		$boff = $options{offset}[1];
		if(!defined $boff) {
			$boff = 0;
			$boff = 1 if(!defined $options{command}[1]);
		}
		if(defined $val[$boff]) {
		$b = $val[$boff] if($boff <= $#val);
		} else { $b = 'UNKNOWN'; }
	}

	print "$a\n$b\n"; # final lines

	print "\n$msg";
	print " :: $msgb" if($msg ne $msgb);
	print "\n";
	exit 0;
}

sub dohelp {
	print "Usage: check-nrpe [-d][-n][-x][-C] -H host [-p port] -c command [-a arg...]\n"
	     ."                  [-t timeout] [ -M [-o offset [-o offset]]]\n"
		."                 [ -c command2 [ -b arg ... ] [-o offset]\n";
	print "-n : no SSL\n-d : Debug mode\n-M : MRTG format output\n-o : Offset -- specify which number in output to use (from 0)\n";
	print "-x : Use perfcounter part of plugin reply (the bit after the |) instead of\n     the first part, if one exists. \n";
	print "-C : Cache the retrieved results for up to 2 minutes.\n";
}
sub doversion {
	print "Version $VERSION\n";
}
########################################################################
# MAIN

# Parse options
$Getopt::Long::autoabbrev = 0;
$Getopt::Long::ignorecase = 0;
$rv1 = GetOptions( \%options, "debug|d", "host|H=s", "port|p=i",
        "command|cmd|v|c=s@", "arg1|arg|a|l=s@", "password|P=s", "help|h",
		"mrtg|MRTG|M", "timeout|t=i", "nossl|n", "version|V",
		"offset|o=i@", "arg2|b|a2|l2=s@", "ext|x", "cache|C" );
if($options{help}) { dohelp; exit(0); }
if($options{version}) { doversion; exit(0); }
$SSL = 0 if($options{nossl});
$DEBUG = 1 if($options{debug});
$MRTG = 1 if($options{mrtg});
$PERFEXT = 1 if($options{ext});
$options{timeout} = 15 if(!$options{timeout});
$options{command} = [ '', '' ]  if(!$options{command});
$options{arg1} = [ ]  if(!$options{arg1});
$options{arg2} = [ ]  if(!$options{arg2});
$options{offset} = [ ] if(!$options{offset});
push @{$options{arg1}},@ARGV if(@ARGV);
$options{port} = 5666 if(!$options{port});
if(!$options{host}) {
	do_output($STATUS{UNKNOWN},"No host specified! -h for help",
		$STATUS{UNKNOWN}, "" ); exit(-1);
}

if($DEBUG) {
	print $options{command}[0]." ".(join " ",@{$options{arg1}})."\n";
	print $options{command}[1]." ".(join " ",@{$options{arg2}})."\n";
}

if($options{cache}) { readcache(); }
$rv1 = $rv2 = -1;
if($options{cache}) {
	($status1,$rv1)=qcache($options{host},$options{command}[0],@{$options{arg1}}); 
}
# Connect to server
if($rv1 < 0 ) {

$rv1 = $rv2 = do_connect( $options{host}, $options{port});
if($rv1) { do_output($STATUS{UNKNOWN},$rv1, $STATUS{UNKNOWN}, $rv1);  exit(-1); }

# Get response
eval {
	$SIG{ALRM} = sub { die("TIMEOUT"); };
	alarm($options{timeout});
	($status1,$rv1) = do_request($options{command}[0],@{$options{arg1}});
	alarm(0);
};
if($@) { 
	($status1,$rv1) = ($STATUS{UNKNOWN},"Timeout on query: check remote server logs");
}
end_connection;
if($options{cache}) { 
	readcache();
	acache($status1,$rv1,$options{host},$options{command}[0],@{$options{arg1}}); 
	writecache(); 
}
}

if( $options{command}[1] ) {
	$rv2 = -1;
	if($options{cache}) {
		($status2,$rv2)=qcache($options{host},$options{command}[1],@{$options{arg2}}); 
	}
	if($rv2 < 0 ) {
	$rv2 = do_connect( $options{host}, $options{port});
	if($rv2) { 
		$status2 = $STATUS{UNKNOWN};  
	} else {
		eval {
			$SIG{ALRM} = sub { die("TIMEOUT"); };
			alarm($options{timeout});
			($status2,$rv2)=do_request($options{command}[1],@{$options{arg2}});
			alarm(0);
		};
		if($@) {
			($status2,$rv2) = ($STATUS{UNKNOWN},"Timeout on query: check remote server logs");
		}
		end_connection;
		if($options{cache}) { 
			readcache();
			acache($status2,$rv2,$options{host},$options{command}[1],@{$options{arg2}}); 
			writecache(); 	
		}
	}
	} # rv2<0
} else {
	( $status2, $rv2 ) = ( $status1, $rv1 );
}

do_output( $status1, $rv1, $status2, $rv2 ); # doesn't return
exit -1;
