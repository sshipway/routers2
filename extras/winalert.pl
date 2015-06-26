#!/usr/bin/perl
# vim:ts=4
# winalert.pl
# Steve S 2004
#
# Reads a file to get a list of hosts/users to alert, and sends either a
# parameter message or a predefined one to them.
# winalert [-u user][-g group][-m message][-[1...9] parm[1..9]][-M messagetext][parm1 [parm2 [parm3]]]
# Parm4 defaults to the environment variable THRESH_DESC

# eg:
# winalert -g all -m msg1
# winalert -u steve -M "There is a big problem!"
# winalert -m msg2 -1 "mail system" -2 "12234 messages" 
# winalert -m msg2 "mail system" "12234 messages" 
#
# Conf file example:
#[winalert]
#smbclient = /usr/bin/smbclient
#[users]
#username = netbiosname
#steveshipway = sshi052
#ops = operator
#[groups]
# groupname = username, username, ....
#sysadmin = steveshipway
#ops = ops
#all = ops, steveshipway
#default = ops
#[messages]
# messagename = messagetext, possibly with %1% variables
#msg1 = There is a general problem.  Check the systems.
#msg2 = There is a problem with %1%
#msg3 = There is a problem with %1%: Monitored value at %2%
#
# If several match, then LONGEST REGEXP wins
#[message-patterns]
#msg1 = \smailhostb\s
# implied...
#default = .
#[group-patterns]
#sysadmin = \smailhosta\s
#implied...
#default = .

use strict;
use Getopt::Std;

my($CONF) = "winalert.conf";

my($debug) = 0;

my(%messages) = ();
my(%users) = ();
my(%groups) = ();
my($SMBCLIENT) = "smbclient";
my(%params) = ();
my($MSG) = "Alert";
my(@TARGETS) = ();
my(%grouppats) = ( '.'=>'default' );
my(%msgpats) = ( '.'=>'default' );

use vars qw($opt_h $opt_M $opt_m $opt_u $opt_g);
use vars qw($opt_1 $opt_2 $opt_3 $opt_4 $opt_5 $opt_6 $opt_7 $opt_8 $opt_9);

sub help {
print "winalert [-u user][-g group][-m message][-[1...9] parm[1..9]][-M messagetext][ netbiosname...]\n";
print "eg:\n";
print "winalert -g all -m msg1\n";
print "winalert -u steve -M \"There is a big problem!\"\n";
print "winalert -m msg2 -1 \"mail system\" -2 \"12234 messages\" sshi052\n";
exit 0;
}

sub parseconf {
	my($line,@line);
	my($section,$key,$arg);

	open CONF, "<$CONF" or do { 
		print "Unable to open $CONF for reading!\n"; return;
	};
	while( $line = <CONF> ) {
		next if($line =~ /^\s*#/);  # skip comments
		next if($line =~ /^\s*$/);  # skip blank
		chomp $line;
		if( $line =~ /^\s*\[(.*)\]\s*$/ ) { $section = lc $1; next; }
		next if(!$section);
		$line =~ /^\s*(\S+)\s*=\s*(.*)$/;
		($key,$arg) = ((lc $1),$2);
		next if(!$key or !$arg);
		if( $section eq "winalert" ) {
			$SMBCLIENT = $arg if($key eq "smbclient");
		} elsif($section eq "users" ) {
			if(defined $users{$key}) {
				print "Error: $key redefined in [users]\n"; next; }
			$users{$key} = $arg;
		} elsif($section eq "groups" ) {
			if(defined $groups{$key}) {
				print "Error: $key redefined in [groups]\n"; next; }
			$groups{$key} = [ split /[\s,]+/,$arg ];
		} elsif($section eq "messages" ) {
			if(defined $messages{$key}) {
				print "Error: $key redefined in [messages]\n"; next; }
			$messages{$key} = $arg;
		} elsif($section eq "message-patterns" ) {
			$msgpats{$arg} = $key;
		} elsif($section eq "group-patterns" ) {
			$grouppats{$arg} = $key;
		} else { print "Warning: bad section [$section] in $CONF\n"; }
	}

	close CONF;
}

sub bylen { return (length($b) <=> length($a)); }
# match param against message patterns
sub msgmatch($) {
	my($tocheck) = $_[0];
	my($pat,$patkey);
	return "" if(!$tocheck);
print "Called msgmatch\n" if($debug);
	foreach $pat ( sort bylen ( keys %msgpats )) {
		next if(!defined $messages{$msgpats{$pat}});
print "Checking '$tocheck' against /$pat/\n" if($debug);
		return $msgpats{$pat} if( $tocheck =~ /$pat/ );
	}
	return "";
}
sub groupmatch($) {
	my($tocheck) = $_[0];
	my($pat,$patkey);
	return "" if(!$tocheck);
print "Called groupmatch\n" if($debug);
	foreach $pat ( sort bylen ( keys %grouppats )) {
		next if(!defined $groups{$grouppats{$pat}});
print "Checking '$tocheck' against /$pat/\n" if($debug);
		return $grouppats{$pat} if( $tocheck =~ /$pat/ );
	}
	return "";
}
# Work out what message we will send
sub getmessage {
	my($s,$d);
	my($msg) = "";
	my($mkey);

	# Explicit message given?
	if($opt_M) { return $opt_M; }

	# Explicit message ID given?
	if($opt_m and defined $messages{$opt_m}) { $msg = $messages{$opt_m}; }

	# Do we have a string to compare?
	if(!$msg) {
		$mkey = msgmatch($ENV{'THRESH_DESC'});
		$mkey = msgmatch($opt_1) if(!$mkey and $opt_1);
		if($mkey and defined $messages{$mkey}) { $msg = $messages{$mkey}; }
	}

	# How about the default message ID?
	$msg = $messages{default} if(!$msg and defined $messages{default});

	# Finally, take the default.
	$msg = "There is a problem [%1%,%2%,%3%,%4%]." if(!$msg);

	# paramter processing
	foreach ( qw/1 2 3 4 5 6 7 8 9/ ) {
		$s = "\%$_\%";
		eval "\$d = \$opt_$_";
		$d = "(unknown)" if(!defined $d);
		$msg =~ s/$s/$d/g;
	}
	$msg =~ s/\\n/\n/g;
	$msg =~ s/\\t/\t/g;
	return $msg;
}

# return a list of which user/host to message
sub gettargets {
	my(@t) = ();
	my($g,$gkey);

	# Any explicitly defined users
	if( $opt_u ) {
		print "Notify User $opt_u\n";

		if(defined $users{$opt_u}) {
			push @t, $users{$opt_u};
		} else {
			print "Error: invalid user $opt_u\n";
		}
	}

	# work out from pattern.
	if(!$opt_u and !$opt_g) {
		$gkey = groupmatch($ENV{'THRESH_DESC'});
		$gkey = groupmatch($opt_1) if(!$gkey and $opt_1);
		if($gkey and defined $groups{$gkey}) { $opt_g = $gkey; }
	}
		
	# Last chance
	if(!$opt_u and !$opt_g) { $opt_g = 'default'; }

	# Work out group contents
	if( $opt_g ) {
		print "Notify Group $opt_g\n";

		if(defined $groups{$opt_g}) {
			foreach $g ( @{$groups{$opt_g}} ) {
				if(defined $users{$g}) {
					push @t, $users{$g};
				} else {
					print "Error: invalid user $g in group $opt_g\n";
				}
			}
		} else {
			print "Error: invalid group $opt_g\n";
		}
	}
	return @t;
}

sub sendto($$) {
	my($who, $what) = @_;

	return if(!$who or !$what);

	# UNIX->Windows SMB mode...
	open SMB, "|$SMBCLIENT -M $who > /dev/null " or do {
		print "Error: cannot start $SMBCLIENT\n";
		return;
	};
	print SMB "$what\n";
	close SMB;
	print "Notified $who\n";
}

##########################################################################
# MAIN CODE STARTS

parseconf;

getopts('hM:m:1:2:3:4:5:6:7:8:9:u:g:');

if( $opt_h ) { help(); exit 0; }

if( $ARGV[0] and !$opt_1 ) { $opt_1 = $ARGV[0]; }
if( $ARGV[1] and !$opt_2 ) { $opt_2 = $ARGV[1]; }
if( $ARGV[2] and !$opt_3 ) { $opt_3 = $ARGV[2]; }
if( $ENV{THRESH_DESC} and !$opt_4 ) { $opt_4 = $ENV{THRESH_DESC}; }

print "Options: [$opt_1] [$opt_2] [$opt_3] [$opt_4]\n" if($debug);
print "MPats: ".(join ",",(keys %msgpats))."\n" if($debug);
print "GPats: ".(join ",",(keys %grouppats))."\n" if($debug);
$MSG = getmessage;

@TARGETS = gettargets;

if(!@TARGETS) {
	print "No destination for the message!\n";
	exit 1;
}

foreach ( @TARGETS ) { sendto( $_, $MSG ); }

exit 0;
