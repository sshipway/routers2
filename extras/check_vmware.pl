#!/usr/bin/perl
# vim:ts=4
# nagios: -epn
#
# check_vmware.pl
# Version 0.1 : Steve Shipway, The University of Auckland
#         0.2 : Change syntax, and generation of configs, better error traps
#         0.3 : Persistent sessions
#         0.4 : Correct for later versions of VI API
#         0.5 : Perfparse stats, NSCA
#         0.6, 0.7 : NSCA for CPU and Memory
#         0.8 : Parameterise all the thresholds
#         0.9 : Fix percentages for multi-CPUs, fix memactive output,
#               add helpful suggestions on critical messages
#         0.10 : Memory private usage was incorrect, active was redundant
#         0.11 : Check $totspace to prevent /0 error
#
# This script performs general checks and data extractions for monitoring
# ESX servers via the Virtual Centre API.  Output can be for MRTG or Nagios
#
# You will need to install:
#    VI Perl Toolkit (download from VMWare website)
#    Class::MethodMaker
#    SOAP::Lite
#    XML::LibXML
#     ... and all dependent modules
#    You need the latest version of HTTP::Message!
#
# TO DO:
#    swap statistics
#    network statistics (lvl 3)
#    disk activity statistics (lvl 3)
#    query tools
##########################################################################

use strict;
use VMware::VIRuntime;
use VMware::VILib;
my($VERSION) = "0.12";

##########################################################################
# Default thresholds for Nagios checks
my($WARNSPACE,$CRITSPACE) = ( 5, 3); # in GB
my($WARNCPU,$CRITCPU)     = (80,90); # percent max (VC defaults)
my($WARNMEM,$CRITMEM)     = (80,90); # percent max (VC defaults)
my($WARNFAIR,$CRITFAIR)   = (90,80); # percent min
#my($WARNACTIVE,$CRITACTIVE)=(70,80); # percent max
my($WARNREADY,$CRITREADY) = ( 5,10); # percent max (VMware recommended level)
##########################################################################
# Other configurable options
my($TIMEOUT) = 5;    # response time in secods
my($DEBUG) = 0;      # set to 1 for extra output
my($SESSIONFILE)=""; # default place to save session file
# if these 2 are set, and --nsca is given, then the external send_nsca
# will be used instead of the internal code.
my($NSCA)    = "/usr/local/nrpe/send_nsca";
my($NSCACFG) = "/usr/local/nrpe/send_nsca.cfg";
my($MAXNSCA) = 10;
my($MAXGUESTCPUS) = 4; # guests cant have more than this many CPUs
my($NEWLINE) = "<BR>"; # use \\n for nag3, <BR> for nag2
##########################################################################
##########################################################################
$Util::script_version = $VERSION;

my($isnagios) = 1; # default reporting mode
my($report,$rv,$begin,$vm);
my($mode) = 0; # different Nagios/MRTG modes
my( $havensca ) = 0;

my($perfmgr);
my(%perfkeys) = ();
my($entity);
my(@queries) = ();
my(@metricids) = ();
my($perfdata);
my($interval) = 0;
my($servicecontent);

my($MSG,$A,$B,$STATUS,$PERF) = ("","UNKNOWN","UNKNOWN",3,"|");

# Format for perfdata:
# |[<name>=<value><unit>;<warn>;<crit>;<min>;<max> ]+
# where all but name and value can be blank, and name must be quoted if it
# contains embedded spaces or symbols.

$Util::script_version = "1.0";
$|=1;
$SIG{CHLD} = sub { print "SIGCHLD\n" if($DEBUG); };

my( %opts ) = (
   guest => { type => "=s",
      help => "Name, hostname, or IP address of the Guest, if reporting for a specific guest rather than for a datacentre, cluster or host",
      required => 0,
   },
   host => { type => "=s",
      help => "Hostname of the ESX Server (optional).  Default is all.",
      required => 0,
   },
   datacenter => { type => "=s",
      help => "Name of the Datacenter (optional).  Default is all.",
      required => 0,
   },
   cluster => { type => "=s",
      help => "Name of the Cluster (optional).  Default is all.",
      required => 0,
   },
   debug => { type => ":i",
      help => "Debug level.",
      required => 0,
   },
   generate => { type => "",
      help => "Set this flag to attempt to generate configuration files for the active type",
      required => 0,
   },
   mode => { type => "=s",
      help => "Nagios (default) or MRTG",
      required => 0,
   },
   report => { type => "=s",
      help => "Report type: state (default), cpu, memory, disk, net.  With optional numerical suffix for different MRTG reports.  The suffix is only meaningful for 'cpu' and 'memory' report types.  EG: state, memory, memory2, memory3, etc.",
      required => 0,
   },
   instance => { type => "=s",
      help => "Disk or Network device name if required.  This is similar to include but more efficient if you have a single instance to select.  This only has an effect if the report is 'net' or 'disk'.",
      required => 0,
   },
   include => { type => "=s",
      help => "Exclude Disk or Network device names. Regexp, default all.  Excludes are processed after Includes.  This only has an effect if the report is 'net' or 'disk'.",
      required => 0,
   },
   exclude => { type => "=s",
      help => "Include Disk or Network device names. Regexp, default none.  Excludes are processed after Includes.  This only has an effect if the report is 'net' or 'disk'.",
      required => 0,
   },
   timeout => { type => "=i",	
       help => "Maximum number of seconds for response from VirtualCentre(defined $TIMEOUT).",
	  required => 0,
   },
   nscaserver => { type => "=s",	
       help => "Specify NSCA server name.  Default localhost",
	  required => 0,
   },
   nscastrip => { type => "=s",	
       help => "Regular expression to strip from extracted hostname before submitting to NSCA.  This is how to convert a FQDN to the Nagios hostname.  For example, this could be your site's domain name.  Default is nothing.",
	  required => 0,
   },
   tolower => { type => "",	
       help => "Force guest hostnames to all lower case before sending to NSCA.",
	  required => 0,
   },
   canon => { type => "",	
       help => "Canonicalise guest hostname before using nscastrip, tolower and sending to NSCA.",
	  required => 0,
   },
   nsca => { type => "",	
       help => "Enable NSCA mode",
	  required => 0,
   },
   warn => { type => "=i",	
       help => "Warning threshold (Currently: CPU=$WARNCPU\%, MEM=$WARNMEM\%, DISKSPACE=$WARNSPACE GB).",
	  required => 0,
   },
   crit => { type => "=i",	
       help => "Critical threshold (Currently: CPU=$CRITCPU\%, MEM=$CRITMEM\%, DISKSPACE=$CRITSPACE GB).",
	  required => 0,
   },
   warnready => { type => "=i",	
       help => "Warning threshold for CPU Ready time (Currently $WARNREADY\%).",
	  required => 0,
   },
   critready => { type => "=i",	
       help => "Critical threshold for CPU Ready time (Currently $CRITREADY\%).",
	  required => 0,
   },
#   warnactive=> { type => "=i",	
#       help => "Warning threshold for Active memory (Currently $WARNACTIVE\%).",
#	  required => 0,
#   },
#   critactive=> { type => "=i",	
#       help => "Critical threshold for Active memory (Currently $CRITACTIVE\%).",
#	  required => 0,
#   },
	
);

#########################################################################
# Error handler
sub dounknown($) {
	my($msg) = $_[0];
	Util::trace(1, "$msg\n");
	Util::disconnect();
	if($isnagios) {
		print "UNKNOWN: $msg$PERF\n";
		exit 3;
	}
	print "UNKNOWN\nUNKNOWN\n\nERROR: $msg\n";
	close NSCAPROC if($havensca);
	exit 0;
}
sub doerror($) {
	my($msg) = $_[0];
	Util::trace(1, "$msg\n");
	Util::disconnect();
	if($isnagios) {
		print "ERROR: $msg$PERF\n";
		exit 2;
	}
	print "UNKNOWN\nUNKNOWN\n\nERROR: $msg\n";
	close NSCAPROC if($havensca);
	exit 0;
}
sub canonical($) {
	my($host) = $_[0];
	my($nscastrip);

	print "Processing [$host]\n" if($DEBUG);

	if( Opts::option_is_set('canon') ) {	
		# DNS magic: canonicalise the hostname, if we can
		my ( $lhname, $aliases, $addrtype, $length,  @addrs)
            = gethostbyname( $host );
		print "Canonicalised $host -> $lhname\n" 
			if($DEBUG and $lhname and ($host ne $lhname));
		$host = $lhname if($lhname);
	}

	if( Opts::option_is_set('nscastrip') ) {
		$nscastrip = Opts::get_option('nscastrip');
		print "Stripping [$nscastrip]\n" if($DEBUG);
		$host =~ s/$nscastrip//i;
	}
	$host =~ s/\.$//;
	$host = lc $host if(Opts::option_is_set('tolower'));

	return $host;
}
#########################################################################
# NSCA client
sub sendnsca($$$$) {
	my($h,$s,$stat,$text) = @_;
	my($DEVNULL) = " >/dev/null 2>&1 ";
	
	$DEVNULL = "" if($DEBUG or $^O=~/Win/);

	if(!$havensca) {
		my($NSCAHOST)="localhost";
		if( ! -x $NSCA or ! -r $NSCACFG ) {
			print "Cannot run $NSCA or cannot read $NSCACFG\n" if($DEBUG);
			return;
		}
		if( Opts::option_is_set('nscaserver') ) {
			$NSCAHOST = Opts::get_option('nscaserver');
		}
		open NSCAPROC,"|$NSCA -H $NSCAHOST -c $NSCACFG $DEVNULL" or do {
			print "Cannot run: $NSCA -H $NSCAHOST -c $NSCACFG\n" if($DEBUG);
			return;
		};
	}
	print "Sending NSCA message.\n" if($DEBUG);
	print NSCAPROC "$h\t$s\t$stat\t$text\n";
	$havensca += 1;
	if($havensca > $MAXNSCA) { close NSCAPROC; $havensca = 0; }
}
#########################################################################
# Option processing
sub validate() {
	my($valid) = 1;
	if (Opts::option_is_set('instance')) {
		if (Opts::option_is_set('report')) {
      		if(Opts::get_option('report') !~ /disk|net/ ) {
				Util::trace(1, "You can only specify an instance if reporting on 'disk' or 'net'.\n" );
				$valid = 0;
				dounknown("You can only specify an instance if reporting on 'disk' or 'net'.");
			}
		} else {
			Util::trace(1, "You can only specify an instance if reporting on 'disk' or 'net'.\n" );
			$valid = 0;
			dounknown("You can only specify an instance if reporting on 'disk' or 'net'.");
		}
	}
#	if (Opts::option_is_set('guest')) {
#		if ( Opts::option_is_set('host') or 
#			Opts::option_is_set('datacenter') or
#			Opts::option_is_set('cluster')) {
#			Util::trace(1, "\nYou cannot specify a guest name in conjunction with host, datacenter or cluster." );
#			$valid = 0;
#		}
#	}

	return $valid;
}

#########################################################################
sub getalarms($) {
	my($mo) = $_[0];
	my($rv) = "";	
	my($stat) = 0;
	my($s);
	my($aentity,$alarm);
	my($tas);
	my($withnsca) = Opts::option_is_set('nsca');
	my($nscahost,$nscaservice) = ("","");
	my($nscastatus) = 0;

	$tas = $mo->triggeredAlarmState;
	return(0,"") if(!$tas);
	foreach my $a (@$tas) {
		$s = $a->overallStatus->val;
		next unless($s eq 'red' or $s eq 'yellow');
		$stat = 1 if($s eq 'yellow' and $stat < 1);
		$stat = 2 if($s eq 'red' and $stat < 2);
		$aentity = Vim::get_view(mo_ref=>$a->entity);
		$alarm  = Vim::get_view(mo_ref=>$a->alarm );
		$rv .= " $NEWLINE " if($rv);
		$rv .= "[".$aentity->name."] "
			.$alarm->info->name." is ".$a->overallStatus->val;
		if( $withnsca ) {
			# obtain FQDN of host	
			if($DEBUG){print "Type=".(ref $aentity)."\n";}
			$nscahost = "";
			if( (ref $aentity) eq 'VirtualMachine' ) {
				$nscahost = $aentity->guest->hostName;
			}
			$nscahost = $aentity->name if(!$nscahost);
			$nscahost = canonical($nscahost);
			# deduce servicedesc
			if( $alarm->info->name =~ /\s(\S+)\s+usage/i ) {
				$nscaservice = "VMware: Alarms: $1";
			} else { $nscaservice = "VMware: Alarms"; }
			# send NSCA alert
			if($a->overallStatus->val eq 'red') { $nscastatus=2; }
			elsif($a->overallStatus->val eq 'yellow') { $nscastatus=1; }
			elsif($a->overallStatus->val eq 'green') { $nscastatus=0; }
			else { $nscastatus=3; }
			print "NSCA: [$nscahost/$nscaservice] is $nscastatus\n" if($DEBUG);
			sendnsca($nscahost,$nscaservice,$nscastatus,
				$alarm->info->name." is ".$a->overallStatus->val );
		}
	}

	return ($stat,$rv);
}

#########################################################################
sub getcounters($) {
	my($type) = $_[0];
	# we need to identify which counter is which
	my $perfCounterInfo = $perfmgr->perfCounter;
	print "Identifying perfcounter IDs\n" if($DEBUG>1);
	foreach ( @$perfCounterInfo ) {
		next if($_->groupInfo->key !~ /$type/); # optimise
		if($_->rollupType->val =~ /average|summation|latest/) {
			$perfkeys{$_->groupInfo->key.":".$_->nameInfo->key}=$_->key;
			$perfkeys{$_->key} = $_->groupInfo->key.":".$_->nameInfo->key;
		}
	}
}
sub getinterval() {
	# We try to get the interval closest to 5min (the normal polling
	# interval for MRTG)
	print "Retrieving interval data...\n" if($DEBUG>1);
	my $hi = $perfmgr->historicalInterval;
	foreach (@$hi) {
		$interval = $_->samplingPeriod if(!$interval);
		if($_->samplingPeriod == 300) { $interval = 300; last; }
	}
	print "Selected interval is: $interval\n" if($DEBUG);
}
sub makequery() {
	@queries = ();
	foreach my $e ( @$entity ) {
		if($DEBUG) {	
			if( defined $e->{value} ) {
				print "Creating query for MORef ".$e->{value}."\n" ;
			} else {
				print "Creating query for ".$e->name."\n" ;
			}
		}
		my $perfquery;
		my (@t) = gmtime(time-300); # 5 mins ago
		my $start = sprintf("%04d-%02d-%02dT%02d:%02d:00Z",
			(1900+$t[5]),(1+$t[4]),$t[3],$t[2],$t[1]);
		@t = gmtime(time);
		my $end   = sprintf("%04d-%02d-%02dT%02d:%02d:00Z",
			(1900+$t[5]),(1+$t[4]),$t[3],$t[2],$t[1]);
		print "Start time: $start\nEnd time  : $end\n" if($DEBUG);
		$perfquery = PerfQuerySpec->new(entity => $e,
			metricId => \@metricids, intervalId => $interval,
			startTime => $start, endTime => $end );
		push @queries,$perfquery;
	}
}
sub runquery() {
	print "Retrieving data...\n" if($DEBUG);
	eval { $perfdata = $perfmgr->QueryPerf(querySpec => \@queries); };
	if ($@) {
		if (ref($@) eq 'SoapFault') {
			if (ref($@->detail) eq 'InvalidArgument') {
				print "Error: $@\n" if($DEBUG);
				print "Error: ".$@->detail."\n" if($DEBUG);
				$MSG="Perf stats not available : Increase Perf logging level to 2 or higher.";
				$STATUS=3;
				return 1;
        		}
		}
		my($msg) = $@; $msg =~ s/^[\n\s]*//; $msg =~ s/\n/$NEWLINE/g;
		if($msg =~ /SOAP Fault/i) {
			print "Error: $msg\n" if($DEBUG);
#			dounknown("CPU Perf stats not available : Increase Perf logging level to 2 or higher.");
			$MSG="Perf stats not available : Increase Perf logging level to 2 or higher.";
			$STATUS=3;
			return 1;
		}
#		dounknown("Error: $msg");
		$MSG="Error: $msg";
		$STATUS=3;
		return 1;
	}
	if(! @$perfdata) {
#		dounknown("Perf stats not available at required interval (300s) or invalid instance.");
		$MSG="Perf stats not available at required interval (300s) or invalid instance.";
		$STATUS=3;
		return 1;
	}
	return 0;
}

#########################################################################
# Various reporting modes

# CPU report: either for avg of hosts(s) or for a VM
# For nagios mode, we check ready time as well as cpu.
# For mrtg mode, we give percentage use and ready time
# MRTG: vm : 
sub cpureport() {
	my(%results) = ();
	my(%rcount) = ();
	my($mycpus) = 0;

	print "Retrieving PerfMgr data\n" if($DEBUG);
	$perfmgr = Vim::get_view(mo_ref =>$servicecontent->perfManager)
		if(!$perfmgr);
		
	getinterval();

	# now we have the polling interval, we need to 
	# identify the things to retrieve
	if($vm) {
		$entity = $vm; # actually a list of refs
	} elsif( Opts::option_is_set('host') ) {
		$entity = $begin; # actually a list of refs
	} else {
		print "Retrieving list of hosts...\n" if($DEBUG);
#		$entity = Vim::find_entity_views (view_type => 'HostSystem',
#			begin_entity => @$begin);
		my @e = ();
		my $view_type = 'HostSystem';
		print "Making new propertyspec\n" if($DEBUG);
		my $property_spec = PropertySpec->new(all => 0,
			type => $view_type->get_backing_type(), pathSet => []
		);
		print "Making new filterspec from ".(ref $view_type)."\n" if($DEBUG);
		my $property_filter_spec =
			$view_type->get_search_filter_spec(@$begin, [$property_spec]);
		print "Retrieving vim_service\n" if($DEBUG);
		my $service = Vim::get_vim_service();
		print "Retrieving properties from ".(ref $service)."\n" if($DEBUG);
		my $obj_contents = $service->RetrieveProperties(
				_this => $servicecontent->propertyCollector,
				specSet => $property_filter_spec);
		print "Checking faults on ".(ref $obj_contents)."\n" if($DEBUG);
		my $result = Util::check_fault($obj_contents);
		foreach ( @$result ) { push @e, $_->obj; }
		$entity = \@e;
	}
	if($DEBUG) {
		print "Processing entities:\n";
		foreach my $ee ( @$entity ) { 
			if( defined $ee->{value} ) {
				print " ".$ee->{value}."\n" ;
			} else {
				print "  ".$ee->name."\n" ;
			}
		}
	}

	# we need to identify which is the CPU usage counter.
	getcounters('cpu|cluster|mem');

	# now we know the counter numbers (although they may not be active!)
	# which we retrieve depends on if we're monitoring hosts(s) or a VM
	# hosts we get cpu:usage, cpu:usagemhz
	# vms we get cpu:usage, cpu:{used,ready,system,wait}
	# if in MRTG mode, we get other stats as well.

	# we can probably optimise this in MRTG mode to only get the ones
	# we want to graph this time
	foreach ( qw/cpu:usage mem:usage cpu:usagemhz/ ) {
		push @metricids, PerfMetricId->new (counterId => $perfkeys{$_},
			instance => '' )
			if(defined $perfkeys{$_});
	}
	if($vm) {
		foreach my $k ( qw/cpu:used cpu:ready cpu:system cpu:wait/ ) {
			# We're asking for data for 4 vCPUs, although probably only
			# 1 of them will actually be there and return data.
			foreach my $vcpu ( 1..$MAXGUESTCPUS ) {
				if(defined $perfkeys{$k}) {
					push @metricids, PerfMetricId->new (
						counterId => $perfkeys{$k}, instance => ($vcpu-1)) ;
				}
			}
		}
	} else {
		foreach ( qw/rescpu:actav5 clusterServices:cpufairness clusterServices:memfairness/ ) {
			push @metricids, PerfMetricId->new (counterId => $perfkeys{$_},
				instance => '') if(defined $perfkeys{$_});
		}
	}
	foreach ( @metricids ) {
		print $_->counterId.": ".$perfkeys{$_->counterId}."("
			.$_->instance.")\n" if($DEBUG>1);
		$rcount{$_} = 0;
		$results{$_} = 0;
	}
	
	makequery();
	return if(runquery());

	print "Perfstats retrieved...\n" if($DEBUG);
	my($idx) = 0;
	foreach my $pd (@$perfdata) {
		if($DEBUG) {
			if( defined $queries[$idx]->entity->{value} ) {
				print "Results for ".$queries[$idx]->entity->{value}."\n" 
			} else {
				print "Results for ".$queries[$idx]->entity->name."\n" 
			}
		}
		my $time_stamps = $pd->sampleInfo;
		my $values = $pd->value;
		next if(!$time_stamps or !$values);
		my $nval = $#$time_stamps;
		next if($nval<0);
		print "Perfdata object: ".$time_stamps->[$nval]->timestamp."\n" if($DEBUG);
		foreach my $v (@$values) {
			print $perfkeys{$v->id->counterId}."=".$v->value->[$nval]."\n"
				if($DEBUG>1);
			$rcount{$v->id->counterId} += 1;
			$results{$v->id->counterId} += $v->value->[$nval];
		}
		$idx+=1;
	}
	# Now, we have a total of the various statistics.  Some may need
	# to be averages, some can remain totals.  Basically, the %ages
	# need to be averaged and the rest can remain as totals.
	foreach ( qw/rescpu:actav5 clusterServices:cpufairness clusterServices:memfairness mem:usage cpu:usage/ ) {
		next if(!defined $results{$perfkeys{$_}});
		$results{$perfkeys{$_}} /= $rcount{$perfkeys{$_}} 
			if($rcount{$perfkeys{$_}});
	}	
	# also, usage is a special case
	$results{$perfkeys{'cpu:usage'}} /= 100 
		if(defined $results{$perfkeys{'cpu:usage'}});
	$results{$perfkeys{'mem:usage'}} /= 100 
		if(defined $results{$perfkeys{'mem:usage'}});
	if($vm) {
		# These are in milliseconds total per interval
		# we also divide by the number of CPUs to get the percentage...
		# we convert to percentages by % = value/ncpus/interval/1000*100%
		# sys + wait + ready + used = 100%
		foreach ( qw/cpu:used cpu:ready cpu:system cpu:wait/ ) {
			next if(!defined $results{$perfkeys{$_}});
			print "Perf $_ = ".$results{$perfkeys{$_}}
				." interval=".($interval*10)
				." count=".$rcount{$perfkeys{$_}}."\n" if($DEBUG>1);
			$results{$perfkeys{$_}} /= ($interval*10);
			$results{$perfkeys{$_}} /= $rcount{$perfkeys{$_}} 
				if($rcount{$perfkeys{$_}});
		}
		$mycpus = $rcount{$perfkeys{'cpu:used'}} 
			if($rcount{$perfkeys{'cpu:used'}});
	}
	
	# Finally, we have all the results!  Now we have to do some thresholding
	# for Nagios, or get the correct values for MRTG
	# At this point, we could be looking at data for a host, a group of hosts,
	# or a guest.
	if($isnagios) {
		my($cpuavg) = $results{$perfkeys{'cpu:usage'}};
		if(defined $cpuavg) {
			$PERF .= "cpu=$cpuavg\%;$WARNCPU;$CRITCPU;0;100 ";
		} else {
			$PERF .= "cpu=;$WARNCPU;$CRITCPU;0;100 ";
		}
		if(!defined $cpuavg) {
			$STATUS = 3;
			$MSG = "CPU usage is unknown?";
		} elsif($cpuavg > $CRITCPU) {
			$STATUS = 2;
			$MSG = "CRIT: CPU usage at ".(int($cpuavg*100)/100)."\% (need more CPU allocation?)";
		} elsif($cpuavg > $WARNCPU) {
			$STATUS = 1;
			$MSG = "WARN: CPU usage at ".(int($cpuavg*100)/100)."\%";
		} else {
			$STATUS = 0;
			$MSG = "CPU usage at ".(int($cpuavg*100)/100)."\%";
		}
		if($vm) {
			$MSG .= "$NEWLINE Guest CPUs: $mycpus" if($mycpus);
			if( defined $results{$perfkeys{'cpu:used'}} ) {
				my $cpuu = int($results{$perfkeys{'cpu:used'}}*100)/100;
				my $cpur = int($results{$perfkeys{'cpu:ready'}}*100)/100;
				my $cpus = int($results{$perfkeys{'cpu:system'}}*100)/100;
				$PERF .= "ready=$cpur\%;$WARNREADY;$CRITREADY;0;100 ";
				$PERF .= "user=$cpuu\%;;;0;100 ";
				$PERF .= "sys=$cpus\%;;;0;100 ";
				if( $cpur > $CRITREADY ) {
					$STATUS = 2;
					$MSG .= "$NEWLINE CRIT: Ready time is $cpur\% (Cluster is overloaded, or guest has too much I/O)";
				} elsif( $cpur > $WARNREADY ) {
					$STATUS = 1 if($STATUS < 1);
					$MSG .= "$NEWLINE WARN: Ready time is $cpur\%";
#				} else {
				}
					$MSG .= "$NEWLINE CPU stats: Used/System/Ready = $cpuu\%/$cpus\%/$cpur\%";
			} else {
				$MSG .= "$NEWLINE No detailed CPU statistics available (raise logging level to 2)";
			}
		} else {
			my $cpufair = int($results{$perfkeys{'clusterServices:cpufairness'}}*100)/100;
			$PERF .= "fair=$cpufair;$WARNFAIR;$CRITFAIR;0; " if($cpufair);
			if( !$cpufair ) {	
				$MSG .= "$NEWLINE (No CPU fairness data)";
			} elsif( $cpufair < $CRITFAIR ) {	
				$MSG .= "$NEWLINE CRIT: CPU Fairness at $cpufair\% (check DRS or rebalance guest allocation in cluster)";
				$STATUS = 2;
			} elsif( $cpufair < $WARNFAIR ) {
				$MSG .= "$NEWLINE WARN: CPU Fairness at $cpufair\%";
				$STATUS = 1 if($STATUS < 1);
			} else { $MSG .= "$NEWLINE CPU Fairness at $cpufair\%"; }
			if($#$entity>0) {
				# multiple hosts
				my(@f) = (); my($avgf)=0;
				my($sdf) = 0;
				foreach ( @$entity ) { 
					next if(defined $_->{value}); # its a moref
					$avgf += $_->summary->quickStats->distributedCpuFairness;
					push @f,$_->summary->quickStats->distributedCpuFairness; 	
				}
				if($#f > -1) {
					$avgf /= ( $#f + 1 );
					foreach (@f) { $sdf += ($_-$avgf)*($_-$avgf); }
					$sdf = sqrt($sdf)/1000;
					$MSG .= "$NEWLINE Distributed fairness SD is ".(int($sdf*100)/100);
				}
			}
		}
	} else {
		$A = $results{$perfkeys{'cpu:usage'}};
		$B = $results{$perfkeys{'mem:usage'}};
		$A = "UNKNOWN" if(!defined $A);
		$B = "UNKNOWN" if(!defined $B);
		$MSG = "Avg CPU usage: ".(int($A*100)/100)
			."\%, Avg Memory usage: ".(int($B*100)/100)."\%";
		if($mode == 1) {
			if($vm) {
				$A = $results{$perfkeys{'cpu:used'}};
				$B = $results{$perfkeys{'cpu:ready'}};
				$A = "UNKNOWN" if(!defined $A);
				$B = "UNKNOWN" if(!defined $B);
				$MSG = "CPU Used: ".(int($A*100)/100)
					."\%, Ready: ".(int($B*100)/100)."\%";
			} else {
				$A = $results{$perfkeys{'clusterServices:cpufairness'}};
				$B = $results{$perfkeys{'clusterServices:memfairness'}};
				$A = "UNKNOWN" if(!defined $A);
				$B = "UNKNOWN" if(!defined $B);
				$MSG = "CPU fairness: ".(int($A*100)/100)
					."\%, MEM fairness: ".(int($B*100)/100)."\%";
			}
		} elsif($mode == 2) {
			if($vm) {
				$A = $results{$perfkeys{'cpu:system'}};
				$B = $results{$perfkeys{'cpu:wait'}};
				$A = "UNKNOWN" if(!defined $A);
				$B = "UNKNOWN" if(!defined $B);
				$MSG = "CPU System: ".(int($A*100)/100)
					."\%, Wait: ".(int($B*100)/100)."\%";
			} 
		}
	}
}


# Memory report: either for hosts(s) or for a VM
sub memreport() {
	my(%results) = ();
	my(%rcount) = ();

	print "Running memory report\n" if($DEBUG);
	print "Retrieving PerfMgr data\n" if($DEBUG);
	$perfmgr = Vim::get_view(mo_ref => $servicecontent->perfManager)
		if(!$perfmgr);

	getinterval();

	# now we have the polling interval, we need to 
	# identify the things to retrieve
	if($vm) {
		$entity = $vm; # actually a list of refs
	} elsif( Opts::option_is_set('host') ) {
		$entity = $begin; # actually a list of refs
	} else {
		print "Retrieving list of hosts...\n" if($DEBUG);
#		$entity = Vim::find_entity_views (view_type => 'HostSystem',
#			begin_entity => @$begin);
		my @e = ();
		my $view_type = 'HostSystem';
		print "Making new propertyspec\n" if($DEBUG);
		my $property_spec = PropertySpec->new(all => 0,
			type => $view_type->get_backing_type(), pathSet => []
		);
		print "Making new filterspec from ".(ref $view_type)."\n" if($DEBUG);
		my $property_filter_spec =
			$view_type->get_search_filter_spec(@$begin, [$property_spec]);
		print "Retrieving vim_service\n" if($DEBUG);
		my $service = Vim::get_vim_service();
		print "Retrieving properties from ".(ref $service)."\n" if($DEBUG);
		my $obj_contents = $service->RetrieveProperties(
				_this => $servicecontent->propertyCollector,
				specSet => $property_filter_spec);
		print "Checking faults on ".(ref $obj_contents)."\n" if($DEBUG);
		my $result = Util::check_fault($obj_contents);
		foreach ( @$result ) { push @e, $_->obj; }
		$entity = \@e;
	}
	if($DEBUG) {
		print "Processing entities:\n";
		foreach my $ee ( @$entity ) { 
			if( defined $ee->{value} ) {
				print " ".$ee->{value}."\n" ;
			} else {
				print "  ".$ee->name."\n" ;
			}
		}
	}

	getcounters('mem|cluster|cpu');

	# now we know the counter numbers (although they may not be active!)
	# which we retrieve depends on if we're monitoring hosts(s) or a VM
	# we can probably optimise this in MRTG mode to only get the ones
	# we want to graph this time
	foreach ( qw/cpu:usage mem:usage/ ) {
		push @metricids, PerfMetricId->new (counterId => $perfkeys{$_},
			instance => '' )
			if(defined $perfkeys{$_});
	}
	if($vm) {
		foreach ( qw/mem:granted mem:vmmemctl mem:active mem:shared mem:swapped mem:overhead mem:consumed mem:zero/ ) {
			push @metricids, PerfMetricId->new (counterId => $perfkeys{$_},
				instance => '' )
				if(defined $perfkeys{$_});
		}
	} else {
		foreach ( qw/clusterServices:memfairness clusterServices:cpufairness mem:swapused/ ) {
			push @metricids, PerfMetricId->new (counterId => $perfkeys{$_},
				instance => '' )
				if(defined $perfkeys{$_});
		}
	}
	foreach ( @metricids ) {
		print $_->counterId.": ".$perfkeys{$_->counterId}."("
			.$_->instance.")\n" if($DEBUG>1);
		$rcount{$_} = 0;
		$results{$_} = 0;
	}
	
	makequery();
	return if(runquery());

	print "Perfstats retrieved...\n" if($DEBUG);
	my($idx) = 0;
	foreach my $pd (@$perfdata) {
		if($DEBUG) {
			if(defined $queries[$idx]->entity->{value}) {
				print "Results for ".$queries[$idx]->entity->{value}."\n";
			} else {
				print "Results for ".$queries[$idx]->entity->name."\n";
			}
		}
		my $time_stamps = $pd->sampleInfo;
		my $values = $pd->value;
		next if(!$time_stamps or !$values);
		my $nval = $#$time_stamps;
		next if($nval<0);
		print "Perfdata object: ".$time_stamps->[$nval]->timestamp."\n" if($DEBUG);
		foreach my $v (@$values) {
			print $perfkeys{$v->id->counterId}."=".$v->value->[$nval]."\n"
				if($DEBUG>1);
			$rcount{$v->id->counterId} += 1;
			$results{$v->id->counterId} += $v->value->[$nval];
		}
		$idx+=1;
	}
	# Now, we have a total of the various statistics.  Some may need
	# to be averages, some can remain totals.  Basically, the %ages
	# need to be averaged and the rest can remain as totals.
	foreach ( qw/clusterServices:cpufairness clusterServices:memfairness cpu:usage mem:usage/ ) {
		next if(!defined $results{$perfkeys{$_}});
		$results{$perfkeys{$_}} /= $rcount{$perfkeys{$_}} 
			if($rcount{$perfkeys{$_}});
	}	
	# also, usage is a special case as it is in hundredths of a %
	$results{$perfkeys{'mem:usage'}} /= 100 
		if(defined $results{$perfkeys{'mem:usage'}});
	$results{$perfkeys{'cpu:usage'}} /= 100 
		if(defined $results{$perfkeys{'cpu:usage'}});
	foreach ( qw/mem:granted mem:vmmemctl mem:active mem:shared mem:swapped mem:overhead mem:consumed/ ) {
		next if(!defined $results{$perfkeys{$_}});
		$results{$perfkeys{$_}} *=  1024;
	}
	
	# Finally, we have all the results!  Now we have to do some thresholding
	# for Nagios, or get the correct values for MRTG
	# At this point, we could be looking at data for a host, a group of hosts,
	# or a guest.
	if($isnagios) {
		my($memavg) = int($results{$perfkeys{'mem:usage'}}*100)/100;
		if(defined $memavg) {	
			$PERF.="mem=$memavg\%;$WARNMEM;$CRITMEM;0;100 ";
		} else {
			$PERF.="mem=;$WARNMEM;$CRITMEM;0;100 ";
		}
		if(!defined $memavg) {
			$STATUS = 3;
			$MSG = "Memory usage is unknown?";
		} elsif($memavg > $CRITMEM) {
			$STATUS = 2;
			$MSG = "CRIT: Memory usage at $memavg\% (Insufficient memory for ESX server or Guest)";
		} elsif($memavg > $WARNMEM) {
			$STATUS = 1;
			$MSG = "WARN: Memory usage at $memavg\%";
		} else {
			$STATUS = 0;
			$MSG = "Memory usage at $memavg\%";
		}
		if($vm) {
			# here we check for swap activity, vmmemctl and swapped too high
			my($actvpc,$pvtpc,$shrpc,$balloonpc,$swappc) = (0,0,0,0,0);
			my($configmem) = 0;
			foreach my $v ( @$vm ) {
				$configmem += $v->runtime->maxMemoryUsage;
			}
			$MSG .= "$NEWLINE GuestMemory: $configmem MB" if($configmem);
			$configmem *= 1024*1024;
			if($configmem) {
				$balloonpc = int($results{$perfkeys{'mem:vmmemctl'}}/$configmem*10000)/100;
				$swappc = int($results{$perfkeys{'mem:swapped'}}/$configmem*10000)/100;
				$pvtpc = int(($configmem-$results{$perfkeys{'mem:vmmemctl'}}-$results{$perfkeys{'mem:swapped'}}-$results{$perfkeys{'mem:shared'}})/$configmem*10000)/100;
				$pvtpc = 0 if($pvtpc<0);
				$shrpc = int($results{$perfkeys{'mem:shared'}}/$configmem*10000)/100;
				$MSG .= "$NEWLINE Memory split pvt/shr/bal/swp = $pvtpc\%/$shrpc\%/$balloonpc\%/$swappc\%";
#				$actvpc = int($results{$perfkeys{'mem:active'}}/$configmem*10000)/100;
				$MSG .= "$NEWLINE Maybe guest has too much memory?" if($balloonpc>5 and $memavg<25);
				$PERF.="balloon=$balloonpc\%;;;0;100 ";
				$PERF.="swap=$swappc\%;;;0;100 ";
				$PERF.="private=$pvtpc\%;;;0;100 ";
				$PERF.="shared=$shrpc\%;;;0;100 ";
# usage = active/total x 100% so we already have this
#				$PERF.="active=$actvpc\%;$WARNACTIVE;$CRITACTIVE;0;100 ";
#				if($actvpc > $CRITACTIVE) {
#					$STATUS = 2;
#					$MSG .= "$NEWLINE CRIT: Memory activity at $actvpc\% (need more memory in guest)";
#				} elsif	($actvpc > $WARNACTIVE) {
#					$STATUS = 1 if($STATUS<1);
#					$MSG .= "$NEWLINE WARN: Memory activity at $actvpc\%";
#				} else {
#					$MSG .= "$NEWLINE Memory activity at $actvpc\%";
#				}
			} else {
				$MSG .= "$NEWLINE No detailed Memory stats available (raise logging level to 2)";
			}
		} else {
			my $memfair = int($results{$perfkeys{'clusterServices:memfairness'}}*100)/100;
			$PERF.="fair=$memfair;$WARNFAIR;$CRITFAIR;0; " if($memfair);
			if( !$memfair ) {	
				$MSG .= "$NEWLINE (No MEM fairness data)";
			} elsif( $memfair < $CRITFAIR ) {	
				$MSG .= "$NEWLINE CRIT: MEM Fairness at $memfair\% (Check DRS or manually rebalance cluster)";
				$STATUS = 2;
			} elsif( $memfair < $WARNFAIR ) {
				$MSG .= "$NEWLINE WARN: MEM Fairness at $memfair\%";
				$STATUS = 1 if($STATUS < 1);
			} else { $MSG .= "$NEWLINE MEM Fairness at $memfair\%"; }
			if($#$entity>0) {
				# multiple hosts
				my(@f) = (); my($avgf)=0;
				my($sdf) = 0;
				foreach ( @$entity ) { 
					next if(defined $_->{value}); # its a moref
					$avgf += $_->summary->quickStats->distributedMemoryFairness;
					push @f,$_->summary->quickStats->distributedMemoryFairness; 	
				}
				if($#f > -1) {
					$avgf /= ( $#f + 1 );
					foreach (@f) { $sdf += ($_-$avgf)*($_-$avgf); }
					$sdf = sqrt($sdf)/1000;
					$MSG .= "$NEWLINE Distributed fairness SD is ".(int($sdf*100)/100);
				}
			}
		}
	} else { ###  MRTG mode...
		$B = $results{$perfkeys{'cpu:usage'}};
		$A = $results{$perfkeys{'mem:usage'}};
		$A = "UNKNOWN" if(!defined $A);
		$B = "UNKNOWN" if(!defined $B);
		$MSG = "Avg Memory usage: ".(int($A*100)/100)
			."\%, Avg CPU usage: ".(int($B*100)/100)."\%";
		if($mode == 1) {
			if($vm) {
				$A = $results{$perfkeys{'mem:active'}};
				$B = $results{$perfkeys{'mem:granted'}};
				$A = "UNKNOWN" if(!defined $A);
				$B = "UNKNOWN" if(!defined $B);
				$MSG = "Memory active: ".(int($A/1024000))
					."MB, from granted: ".(int($B/1024000))."MB";
			} else {
				$A = $results{$perfkeys{'clusterServices:cpufairness'}};
				$B = $results{$perfkeys{'clusterServices:memfairness'}};
				$A = "UNKNOWN" if(!defined $A);
				$B = "UNKNOWN" if(!defined $B);
				$MSG = "CPU fairness: ".(int($A*100)/100)
					."\%, MEM fairness: ".(int($B*100)/100)."\%";
			}
		} elsif($mode == 2) {
			if($vm) {	
				$A = $B = "UNKNOWN";
				$A = $results{$perfkeys{'mem:consumed'}}/$results{$perfkeys{'mem:granted'}}*100 if($results{$perfkeys{'mem:granted'}});
				$B = $results{$perfkeys{'mem:shared'}}/$results{$perfkeys{'mem:granted'}}*100 if($results{$perfkeys{'mem:granted'}});
				$A = "UNKNOWN" if(!defined $A);
				$B = "UNKNOWN" if(!defined $B);
				$MSG = "Memory private: ".(int($A*100)/100)
					."\%, shared: ".(int($B*100)/100)."\%";
			} 
		} elsif($mode == 3) {
			if($vm) {	
				$A = $B = "UNKNOWN";
				$A = $results{$perfkeys{'mem:vmmemctl'}}/$results{$perfkeys{'mem:granted'}}*100 if($results{$perfkeys{'mem:granted'}});
				$B = $results{$perfkeys{'mem:swapped'}}/$results{$perfkeys{'mem:granted'}}*100 if($results{$perfkeys{'mem:granted'}});
				$A = "UNKNOWN" if(!defined $A);
				$B = "UNKNOWN" if(!defined $B);
				$MSG = "Memory balloon: ".(int($A*100)/100)
					."\%, swapped: ".(int($B*100)/100)."\%";
			} 
		}
	}
}

# Disk space report
sub diskreport() {
	my($totspace,$freespace);
	my($disks);
	my(@dsa) = ();
	my($instance,$include,$exclude) = ('','','');
	my($cnt) = 0;

	print "Running disk report\n" if($DEBUG);
	$instance = Opts::get_option('instance') 
		if(Opts::option_is_set('instance'));
	$include  = Opts::get_option('include') 
		if(Opts::option_is_set('include'));
	$exclude  = Opts::get_option('exclude') 
		if(Opts::option_is_set('exclude'));
	print "Identifying datastores...\n" if($DEBUG);
	foreach(@$begin) {
		print "N=".$_->name."\n" if($DEBUG);
		eval {
			push @dsa,@{$_->datastore} if(defined $_->datastore);
		};	
		if($@) {
			my $children;
			my( $r ) = $_->childEntity;
			print "Identifying children for ".$_->name."\n" if($DEBUG);
			$children = Vim::get_views( mo_ref_array => $r );
			foreach  (@$children) {
				print " N=".$_->name."\n" if($DEBUG);
				push @dsa,@{$_->datastore} if(defined $_->datastore);
			}
		}
	}
	print "Extracting disks\n" if($DEBUG);
	$disks = Vim::get_views( mo_ref_array => \@dsa );
	if(!@$disks) {
		if($instance) {
			dounknown("Disk instance $instance not found.");
		} elsif($include or $exclude) {
			dounknown("No matching disk instances found.");
		} else {
			dounknown("No datastores found.");
		}
	}
	$MSG = ""; $STATUS = 0; $totspace = $freespace = 0;
	foreach my $ds ( @$disks ) {
		print "Checking ".$ds->info->name."\n" if($DEBUG>1);
		next if($instance and $ds->info->name ne $instance);
		next if($include and $ds->info->name !~ /$include/);
		next if($exclude and $ds->info->name =~ /$exclude/);
		$cnt+=1;
		if($isnagios) {
			$totspace = $ds->summary->capacity;
			$freespace = $ds->summary->freeSpace;
			if($freespace < $CRITSPACE*1024000000) {
				$STATUS = 2;
				$MSG .= "$NEWLINE " if($MSG);
				$MSG .= "[C] ".$ds->info->name.": ".int($freespace/1024000)
					.($totspace?
					("MB (".(int($freespace/$totspace*1000)/10)."\%) free")
					:"");
			} elsif($freespace < $WARNSPACE*1024000000) {
				$STATUS = 1 if($STATUS<2);
				$MSG .= "$NEWLINE " if($MSG);
				$MSG .= "[W] ".$ds->info->name.": ".int($freespace/1024000)
					.($totspace?
					("MB (".(int($freespace/$totspace*1000)/10)."\%) free")
					:"");
			}
		} else {
			$totspace += $ds->summary->capacity;
			$freespace += $ds->summary->freeSpace;
			print "So far: ".int($totspace/1024000000)."GB ".$ds->info->name."\n" if($DEBUG);
		}
	}
	if(!$cnt) {
		if($instance) { dounknown("Disk instance $instance not found."); }
		dounknown("No matching disk instances found.");
	}
	if($isnagios) {		
		$MSG = "All filesystems within parameters" if(!$MSG);
		$PERF .= "free=$freespace;;;0; total=$totspace;;;0; ";
	} else {
		# For MRTG, we show space used, so that the peak is more meaningful
		($A,$B) = (($totspace-$freespace),$totspace);
		$MSG = "All datastores: ".int($A/1024000000)."GB used from ".int($totspace/1024000000)."GB";
	}
}

# Network interface report
sub netreport() {
}

# State report
sub statereport() {	
	my($numup) = 0;
	my($totvms) = 0;
	my(@errs) = ();
	my(@statobj) = ();
	print "Running state report\n" if($DEBUG);
	if(!$vm) {
		if(!$isnagios) {
			print "Extracting VMs\n" if($DEBUG);
			$vm = Vim::find_entity_views (view_type => 'VirtualMachine',
				begin_entity => @$begin);
		}
		push @statobj,@$begin;
	} else {	
		push @statobj,@$vm;
	}
	$STATUS = 0;
	if($isnagios) {
		if($vm) {
			# we're checking a VM, so need to check if it is up
			foreach my $v (@$vm) {
				if( $v->runtime->powerState->val ne 'poweredOn' ) {
					$MSG .= "$NEWLINE " if($MSG);
					$MSG .= "Guest ".$v->name." is "
						.$v->runtime->powerState->val;
					$STATUS = 2;
				}
			}
		}
		print "Checking alarms...\n" if($DEBUG);
		foreach ( @statobj ) {
			my($s,$rv) = getalarms($_);
			$STATUS = $s if($s>$STATUS);
 			if($rv) { $MSG.="$NEWLINE " if($MSG); $MSG.=$rv; }
		}
		if(!$MSG) { $MSG = "No alarms detected."; }
	} else {
		print "Processing...\n" if($DEBUG);
		foreach my $v ( @$vm ) {
			print "\rProcessing ".$v->name if ($DEBUG);
			$totvms += 1;
			$numup += 1 if( $v->runtime->powerState->val eq 'poweredOn' );
		}
		print "\rDone.                        \n" if($DEBUG);
		($A,$B)=($numup,$totvms);
		$MSG = "$numup guests from $totvms are running";
	}
	print "$MSG\n" if($DEBUG);
}
#########################################################################
# Generate appropriate configuration files?
sub makenagioscfg() {
	my($cmdopt) = "";
	my($hostobj) = "VMWARE";
	my($address) = "put your VirtualCentre IP address in here";
	my($alias) = "";

	print <<_END_
# This is an autogenerated Nagios configuration file
# You may wish to modify it before using!
#
# This is an example of the required checkcommand definition:
#define command {
#	command_name check_vmware
#	command_line \$USER1\$/check_vmware --mode=nagios --config=\$USER1\$/vmware.cfg \$ARG1\$
#}
#
# You also need to have a service template called 'generic-service'
#
# The vmware.cfg file must contain the necessary lines to define your
# VirtualCentre server and authentication parameters:
#VI_PASSWORD=secretpassword
#VI_SERVER=vmware-vc-server.auckland.ac.nz
#VI_USERNAME=adminuser
#
_END_
;

	# Now, if we have a guest defined, then we output a guest
	# configuration. Similarly for host and farm.
	if ( Opts::option_is_set('guest') ) {
		$cmdopt .= "--guest=\"".Opts::get_option('guest')."\" ";
		$hostobj = Opts::get_option('guest');
	} 
	if ( Opts::option_is_set('datacenter') ) {
		$cmdopt .= "--datacenter=\"".Opts::get_option('datacenter')."\" ";
		$hostobj = Opts::get_option('datacenter');
		$alias = "VMWare datacentre ".Opts::get_option('datacenter');
	} 
	if ( Opts::option_is_set('cluster') ) {
		$cmdopt .= "--cluster=\"".Opts::get_option('cluster')."\" ";
		$hostobj = Opts::get_option('cluster');
		$alias = "VMWare cluster ".Opts::get_option('cluster');
	} 
	if ( Opts::option_is_set('host') ) {
		$cmdopt .= "--host=\"".Opts::get_option('host')."\" ";
		$hostobj = Opts::get_option('host');
		$alias = "VMWare server ".Opts::get_option('host');
		$address = Opts::get_option('host');
	}

	if ( Opts::option_is_set('guest') ) {
		print <<_END_
# Check guest status
define service {
    use                  generic-service
    host_name            $hostobj
    service_description  VMWare: Status
    check_command        check_vmware!$cmdopt --report=status
}
# Check guest memory
define service {
    use                  generic-service
    host_name            $hostobj
    service_description  VMWare: Memory
    check_command        check_vmware!$cmdopt --report=memory
}
# Check guest CPU
define service {
    use                  generic-service
    host_name            $hostobj
    service_description  VMWare: CPU
    check_command        check_vmware!$cmdopt --report=cpu
}
_END_
;
	} else {
		print <<_END_
# Dummy Host object for the datacenter/cluster, or ESX server host object
define host {
    use                  generic-host
    host_name            $hostobj
	alias                $alias
    address              $address
}
# Check host/cluster/datacenter status
define service {
    use                  generic-service
    host_name            $hostobj
    service_description  VMWare: Status
    check_command        check_vmware!$cmdopt --report=status
}
# Check host/cluster/datacenter memory
define service {
    use                  generic-service
    host_name            $hostobj
    service_description  VMWare: Memory
    check_command        check_vmware!$cmdopt --report=memory
}
# Check host/cluster/datacenter CPU
define service {
    use                  generic-service
    host_name            $hostobj
    service_description  VMWare: CPU
    check_command        check_vmware!$cmdopt --report=cpu
}
# Check host/cluster/datacenter disk space
define service {
    use                  generic-service
    host_name            $hostobj
    service_description  VMWare: Datastores
    check_command        check_vmware!$cmdopt --report=disk
}
_END_
;
	}
}
sub makemrtgcfg() {
	my($cmdopt) = "";
	my($hostobj);

	print <<_END_
# This is an autogenerated MRTG configuration file
# You may wish to modify it before using!
#
# The vmware.cfg file must contain the necessary lines to define your
# VirtualCentre server and authentication parameters:
#VI_PASSWORD=secretpassword
#VI_SERVER=vmware-vc-server.auckland.ac.nz
#VI_USERNAME=adminuser
#
_END_
;	
	$cmdopt = "--config=/usr/local/etc/vmware.cfg ";

	# Now, if we have a guest defined, then we output a guest
	# configuration. Similarly for host and farm.
	if ( Opts::option_is_set('guest') ) {
		$cmdopt .= "--guest=\"".Opts::get_option('guest')."\" ";
		$hostobj = Opts::get_option('guest');
	} 
	if ( Opts::option_is_set('datacenter') ) {
		$cmdopt .= "--datacenter=\"".Opts::get_option('datacenter')."\" ";
		$hostobj = Opts::get_option('datacenter');
	} 
	if ( Opts::option_is_set('cluster') ) {
		$cmdopt .= "--cluster=\"".Opts::get_option('cluster')."\" ";
		$hostobj = Opts::get_option('cluster');
	} 
	if ( Opts::option_is_set('host') ) {
		$cmdopt .= "--host=\"".Opts::get_option('host')."\" ";
		$hostobj = Opts::get_option('host');
	}

	if ( Opts::option_is_set('guest') ) {
		print <<_END_
# VMWare guest
# graph the CPU and Memory usage figures, plus detailed memory breakdown
# You may wish to add a --config= option to the check_vmware.pl call
# Resources graph 
Target[$hostobj-res-vm]: `check_vmware.pl --mode=mrtg --report=cpu $cmdopt`
Title[$hostobj-res-vm]: $hostobj Resource Usage
MaxBytes[$hostobj-res-vm]: 100
PageTop[$hostobj-res-vm]: null
LegendI[$hostobj-res-vm]: cpu:
LegendO[$hostobj-res-vm]: mem:
Options[$hostobj-res-vm]: gauge growright 
Ylegend[$hostobj-res-vm]: percent
ShortLegend[$hostobj-res-vm]: %
Legend1[$hostobj-res-vm]: CPU utilisation
Legend2[$hostobj-res-vm]: Memory utilisation
Legend3[$hostobj-res-vm]: Peak CPU utilisation
Legend4[$hostobj-res-vm]: Peak memory utilisation
routers.cgi*ShortDesc[$hostobj-res-vm]: VM: Resources
routers.cgi*Options[$hostobj-res-vm]: fixunit nototal nopercent
routers.cgi*Icon[$hostobj-res-vm]: chip-sm.gif
routers.cgi*InMenu[$hostobj-res-vm]: yes
routers.cgi*InCompact[$hostobj-res-vm]: yes
routers.cgi*InSummary[$hostobj-res-vm]: yes
# Detail CPU graph
Target[$hostobj-cpu-vm]: `check_vmware.pl --mode=mrtg --report=cpu1 $cmdopt`
Title[$hostobj-cpu-vm]: $hostobj CPU Usage
MaxBytes[$hostobj-cpu-vm]: 100
PageTop[$hostobj-cpu-vm]: null
LegendI[$hostobj-cpu-vm]: used:
LegendO[$hostobj-cpu-vm]: ready:
Options[$hostobj-cpu-vm]: gauge growright 
Ylegend[$hostobj-cpu-vm]: percent
ShortLegend[$hostobj-cpu-vm]: %
Legend1[$hostobj-cpu-vm]: Used time
Legend2[$hostobj-cpu-vm]: Ready time
Legend3[$hostobj-cpu-vm]: Peak used
Legend4[$hostobj-cpu-vm]: Peak ready
routers.cgi*ShortDesc[$hostobj-cpu-vm]: VM: CPU
routers.cgi*Options[$hostobj-cpu-vm]: fixunit nototal nopercent
routers.cgi*Icon[$hostobj-cpu-vm]: chip-sm.gif
routers.cgi*InMenu[$hostobj-cpu-vm]: yes
routers.cgi*InCompact[$hostobj-cpu-vm]: yes
routers.cgi*InSummary[$hostobj-cpu-vm]: yes

# Memory active graph
Target[$hostobj-mem-active]: `check_vmware.pl --mode=mrtg --report=memory1 $cmdopt`
Title[$hostobj-mem-active]: $hostobj Active Memory
MaxBytes[$hostobj-mem-active]: 100000000000
PageTop[$hostobj-mem-active]: null
LegendI[$hostobj-mem-active]: active:
LegendO[$hostobj-mem-active]: memory:
Options[$hostobj-mem-active]: gauge growright dorelpercent
Ylegend[$hostobj-mem-active]: percent
ShortLegend[$hostobj-mem-active]: %
Legend1[$hostobj-mem-active]: Active memory
Legend2[$hostobj-mem-active]: Total memory
Legend3[$hostobj-mem-active]: Peak active memory
Legend4[$hostobj-mem-active]: Peak total memory
routers.cgi*ShortDesc[$hostobj-mem-active]: VM: Act Mem
routers.cgi*Options[$hostobj-mem-active]: fixunit nototal nopercent 
routers.cgi*Icon[$hostobj-mem-active]: chip-sm.gif
routers.cgi*InMenu[$hostobj-mem-active]: yes
routers.cgi*InCompact[$hostobj-mem-active]: yes
routers.cgi*InSummary[$hostobj-mem-active]: yes

# Detailed Memory graph
Target[$hostobj-mem-ps]: `check_vmware.pl --mode=mrtg --report=memory2 $cmdopt`
Title[$hostobj-mem-ps]: $hostobj Memory Usage
MaxBytes[$hostobj-mem-ps]: 100
PageTop[$hostobj-mem-ps]: null
LegendI[$hostobj-mem-ps]: pvt:
LegendO[$hostobj-mem-ps]: shr:
Options[$hostobj-mem-ps]: gauge growright 
Ylegend[$hostobj-mem-ps]: percent
ShortLegend[$hostobj-mem-ps]: %
Legend1[$hostobj-mem-ps]: Private memory
Legend2[$hostobj-mem-ps]: Shared memory
Legend3[$hostobj-mem-ps]: Peak private memory
Legend4[$hostobj-mem-ps]: Peak shared memory
routers.cgi*ShortDesc[$hostobj-mem-ps]: VM: Memory (pvt/shr)
routers.cgi*Options[$hostobj-mem-ps]: fixunit nototal nopercent
routers.cgi*Icon[$hostobj-mem-ps]: chip-sm.gif
routers.cgi*InMenu[$hostobj-mem-ps]: no
routers.cgi*InCompact[$hostobj-mem-ps]: yes
routers.cgi*InSummary[$hostobj-mem-ps]: no
routers.cgi*Graph[$hostobj-mem-ps]: $hostobj-vmem

Target[$hostobj-mem-bs]: `check_vmware.pl --mode=mrtg --report=memory3 $cmdopt`
Title[$hostobj-mem-bs]: $hostobj Memory Usage
MaxBytes[$hostobj-mem-bs]: 100
PageTop[$hostobj-mem-bs]: null
LegendI[$hostobj-mem-bs]: bal:
LegendO[$hostobj-mem-bs]: swp:
Options[$hostobj-mem-bs]: gauge growright 
Ylegend[$hostobj-mem-bs]: percent
ShortLegend[$hostobj-mem-bs]: %
Legend1[$hostobj-mem-bs]: Balloon memory
Legend2[$hostobj-mem-bs]: Swapped memory
Legend3[$hostobj-mem-bs]: Peak balloon memory
Legend4[$hostobj-mem-bs]: Peak swapped memory
routers.cgi*ShortDesc[$hostobj-mem-bs]: VM: Memory (bal/swp)
routers.cgi*Options[$hostobj-mem-bs]: fixunit nototal nopercent
routers.cgi*Icon[$hostobj-mem-bs]: chip-sm.gif
routers.cgi*InMenu[$hostobj-mem-bs]: no
routers.cgi*InCompact[$hostobj-mem-bs]: yes
routers.cgi*InSummary[$hostobj-mem-bs]: no
routers.cgi*Graph[$hostobj-mem-bs]: $hostobj-vmem

routers.cgi*Desc[$hostobj-vmem]: $hostobj Memory Usage
routers.cgi*ShortDesc[$hostobj-vmem]: VM: Memory
routers.cgi*Icon[$hostobj-vmem]: chip-sm.gif
routers.cgi*InMenu[$hostobj-vmem]: yes
routers.cgi*InSummary[$hostobj-vmem]: yes
routers.cgi*GraphStyle[$hostobj-vmem]: stack
_END_
;
	} else {
		# For now we do the default, but really we should set up some
		# combined graphs for all hosts if datacenter or cluster is set
		print <<_END_
# VMWare datacenter/cluster/host
# You may wish to add a --config= directive to the command
# Graph CPU and Memory usage figures
# plus fairness figures
# And datastore (disk) space figures
# And count of active guests

# Resources graph 
Target[$hostobj--res-cl]: `check_vmware.pl --mode=mrtg --report=cpu $cmdopt`
Title[$hostobj--res-cl]: $hostobj Resource Usage
MaxBytes[$hostobj--res-cl]: 100
PageTop[$hostobj--res-cl]: null
LegendI[$hostobj--res-cl]: cpu:
LegendO[$hostobj--res-cl]: mem:
Options[$hostobj--res-cl]: gauge growright 
Ylegend[$hostobj--res-cl]: percent
ShortLegend[$hostobj--res-cl]: %
Legend1[$hostobj--res-cl]: CPU utilisation
Legend2[$hostobj--res-cl]: Memory utilisation
Legend3[$hostobj--res-cl]: Peak CPU utilisation
Legend4[$hostobj--res-cl]: Peak memory utilisation
routers.cgi*ShortDesc[$hostobj--res-cl]: VM: Resources
routers.cgi*Options[$hostobj--res-cl]: fixunit nototal nopercent
routers.cgi*Icon[$hostobj--res-cl]: chip-sm.gif
routers.cgi*InMenu[$hostobj--res-cl]: yes
routers.cgi*InCompact[$hostobj--res-cl]: yes
routers.cgi*InSummary[$hostobj--res-cl]: yes

# VMs active
Target[$hostobj--vm-actv]: `check_vmware.pl --mode=mrtg --report=status $cmdopt`
Title[$hostobj--vm-actv]: $hostobj Active Guests
MaxBytes[$hostobj--vm-actv]: 100000
PageTop[$hostobj--vm-actv]: null
LegendI[$hostobj--vm-actv]: active :
LegendO[$hostobj--vm-actv]: defined:
Options[$hostobj--vm-actv]: gauge growright integer
Ylegend[$hostobj--vm-actv]: Guests
ShortLegend[$hostobj--vm-actv]: &nbsp;
Legend1[$hostobj--vm-actv]: Active guests
Legend2[$hostobj--vm-actv]: Defined guests
Legend3[$hostobj--vm-actv]: Peak active guests
Legend4[$hostobj--vm-actv]: Peak defined guests
routers.cgi*ShortDesc[$hostobj--vm-actv]: VM: Guests
routers.cgi*Options[$hostobj--vm-actv]: fixunit nototal nopercent nomax
routers.cgi*Icon[$hostobj--vm-actv]: server-sm.gif
routers.cgi*InMenu[$hostobj--vm-actv]: yes
routers.cgi*InCompact[$hostobj--vm-actv]: yes
routers.cgi*InSummary[$hostobj--vm-actv]: yes

# Datastores
Target[$hostobj--vm-ds]: `check_vmware.pl --mode=mrtg --report=disk $cmdopt`
Title[$hostobj--vm-ds]: $hostobj Datastores
MaxBytes[$hostobj--vm-ds]: 1000000000000000
PageTop[$hostobj--vm-ds]: null
LegendI[$hostobj--vm-ds]: used :
LegendO[$hostobj--vm-ds]: total:
Options[$hostobj--vm-ds]: gauge growright dorelpercent
Ylegend[$hostobj--vm-ds]: Percent
ShortLegend[$hostobj--vm-ds]: %
Legend1[$hostobj--vm-ds]: Space used
Legend2[$hostobj--vm-ds]: Space available
Legend3[$hostobj--vm-ds]: Peak space used
Legend4[$hostobj--vm-ds]: Peak space available
routers.cgi*ShortDesc[$hostobj--vm-ds]: VM: Datastores
routers.cgi*Options[$hostobj--vm-ds]: fixunit nototal nopercent 
routers.cgi*Icon[$hostobj--vm-ds]: disk-sm.gif
routers.cgi*InMenu[$hostobj--vm-ds]: yes
routers.cgi*InCompact[$hostobj--vm-ds]: yes
routers.cgi*InSummary[$hostobj--vm-ds]: yes

_END_
;
	}
}
#########################################################################
# MAIN

Opts::add_options(%opts);
Opts::parse();
if( Opts::option_is_set('debug') ) {
	$DEBUG=Opts::get_option('debug');
	$DEBUG=1 if(!$DEBUG);
}
$mode = 0;
if( Opts::option_is_set('mode') ) {
	if( Opts::get_option('mode') =~ /mrtg/i ) {
		$isnagios = 0;
		$mode = $1 if( Opts::get_option('mode') =~ /(\d+)/i ); # historical
	}
} 
Opts::validate(\&validate);
print "Starting.\n" if($DEBUG);
$report = Opts::get_option('report');
$mode = $1 if( $report =~ /(\d+)/i );

if( Opts::option_is_set('generate') ) {
	# generate config mode!
	if($isnagios) { makenagioscfg(); } else { makemrtgcfg(); }
	exit 0;
}


#if( Opts::option_is_set('warnactive') ) {
#	$WARNACTIVE = Opts::get_option('warnactive');
#	if($WARNACTIVE<1 or $WARNACTIVE>99) { 
#		print "Usage: 0<warnactive<100\%\n"; exit 3; }
#}
#if( Opts::option_is_set('critactive') ) {
#	$CRITACTIVE = Opts::get_option('critactive');
#	if($CRITACTIVE<$WARNACTIVE or $CRITACTIVE>99) { 
#		print "Usage: warnactive<critactive<100\%\n"; exit 3; }
#}
if( Opts::option_is_set('warnready') ) {
	$WARNREADY = Opts::get_option('warnready');
	if($WARNREADY<1 or $WARNREADY>99) { 
		print "Usage: 0<warnready<100\%\n"; exit 3; }
}
if( Opts::option_is_set('critready') ) {
	$CRITREADY = Opts::get_option('critready');
	if($CRITREADY<$WARNREADY or $CRITREADY>99) { 
		print "Usage: warnready<critready<100\%\n"; exit 3; }
}
if( Opts::option_is_set('warn') ) {
	if($report =~ /cpu/) {
		$WARNCPU = Opts::get_option('warn');
		if($WARNCPU<1 or $WARNCPU>99) { 
			print "Usage: 0<warn<100\%\n"; exit 3; }
	} elsif($report =~ /mem/ ) {
		$WARNMEM = Opts::get_option('warn');
		if($WARNMEM<1 or $WARNMEM>99) { 
			print "Usage: 0<warn<100\%\n"; exit 3; }
	} elsif($report =~ /disk|data/ ) {
		$WARNSPACE = Opts::get_option('warn');
		if($WARNSPACE<0) { print "Usage: warn >= 0GB\n"; exit 3; }
	}
}
if( Opts::option_is_set('crit') ) {
	if($report =~ /cpu/) {
		$CRITCPU = Opts::get_option('crit');
		if($CRITCPU<$WARNCPU or $CRITCPU>99) { 
			print "Usage: warn<crit<100\%\n"; exit 3; }
	} elsif($report =~ /mem/ ) {
		$CRITMEM = Opts::get_option('crit');
		if($CRITMEM<$WARNMEM or $CRITMEM>99) { 
			print "Usage: warn<crit<100\%\n"; exit 3; }
	} elsif($report =~ /disk|data/ ) {
		$CRITSPACE= Opts::get_option('crit');
		if($CRITSPACE>$WARNSPACE or $CRITSPACE<0) { 
			print "Usage: warn > crit >= 0GB\n"; exit 3; }
	}
}


if(Opts::option_is_set('savesessionfile')) {
	$SESSIONFILE=Opts::get_option('savesessionfile');
}
if(Opts::option_is_set('sessionfile')) {
	$SESSIONFILE=Opts::get_option('sessionfile');
}
if( $SESSIONFILE and -f $SESSIONFILE 
	and ( ! -w $SESSIONFILE or ! -r $SESSIONFILE ) ) {
	dounknown("Unable to read/write session file $SESSIONFILE");
}

# First, connect to VI
if($SESSIONFILE and -f $SESSIONFILE) {
	my(@s) = stat $SESSIONFILE;
	if( (time-$s[9])>1200 ) {
		# session file is >20mins old, lets reconnect
		unlink $SESSIONFILE;
		print "Expiring old session file\n" if($DEBUG);
	}
}
if($SESSIONFILE and -f $SESSIONFILE) {
	# load the saved session instead
	print "Loading session file\n" if($DEBUG);
	Vim::load_session(session_file=>$SESSIONFILE);
} else {
	print "Connecting\n" if($DEBUG);
	eval {
		$SIG{ALRM} = sub { die('TIMEOUT'); };
		alarm($TIMEOUT);
		Util::connect();
		alarm(0);
	};
	if($@) {
		dounknown("No response from VirtualCentre server") if($@ =~ /TIMEOUT/);
		dounknown("You need to upgrade HTTP::Message!") if($@ =~ /HTTP::Message/);
		dounknown("Login to VirtualCentre server failed: $@.");
	}
	print "Connected\n" if($DEBUG);
}
if($DEBUG) {
	my $si_moref = ManagedObjectReference->new(type => 'ServiceInstance',
                                              value => 'ServiceInstance');
	my $si_view = Vim::get_view(mo_ref => $si_moref);
	print "Server Time : ". $si_view->CurrentTime()."\n";
}

$servicecontent = Vim::get_service_content();

# Now, try and work out the 'begin' entity - host>cluster>datacenter>top
# @$begin is a list of the base to search in.
if ( Opts::option_is_set('datacenter') ) {
	my($dc) = Opts::get_option('datacenter');
	$begin = Vim::find_entity_views (view_type => 'Datacenter',
		filter => {name => $dc });
	unless (@$begin) { dounknown("Datacenter '$dc' not found."); }
#	if ($#{$begin} != 0) { doerror("Datacenter <$dc> not unique."); }
} else {
#	@$begin = ( $servicecontent->rootFolder );
	@$begin = ( Vim::get_view( mo_ref=>$servicecontent->rootFolder ));
}
if(!@$begin) {
	dounknown("Unable to obtain root folder");
}
if ( Opts::option_is_set('cluster') ) {
	my($cl) = Opts::get_option('cluster');
	$begin = Vim::find_entity_views (view_type => 'ClusterComputeResource',
		begin_entity => @$begin,
		filter => {name => $cl });
	unless (@$begin) { dounknown("Cluster '$cl' not found."); }
#	if ($#{$begin} != 0) { doerror("Cluster <$cl> not unique."); }
}
if ( Opts::option_is_set('host') ) {
	my($ho) = Opts::get_option('host');
	$begin = Vim::find_entity_views (view_type => 'HostSystem',
		begin_entity => @$begin,
		filter => {name => $ho });
	unless (@$begin) { dounknown("Host system '$ho' not found."); }
#	if ($#{$begin} != 0) { doerror("Host system <$ho> not unique."); }
}

# Do we need to identify a VM?
if ( Opts::option_is_set('guest') ) {
	my($gu) = Opts::get_option('guest');
	print "Trying to locate $gu\n" if($DEBUG);
	$vm = Vim::find_entity_views (view_type => 'VirtualMachine',
		begin_entity => @$begin,
		filter => {name => $gu });
	unless(@$vm) {
		print "Now trying as hostname...\n" if($DEBUG);
		$vm = Vim::find_entity_views (view_type => 'VirtualMachine',
			begin_entity => @$begin,
			filter => { 'guest.hostName' => qr/$gu/i });
		foreach ( @$vm ) { # we may have several with same hostname
			print "Guest is ".$_->runtime->powerState->val."\n" if($DEBUG);
			if($_->runtime->powerState->val eq 'poweredOn') {
				@$vm = ( $_ ); # Just keep the active one
				last;
			}
		}
	}
	unless(@$vm) {
		print "Now trying as IP address...\n" if($DEBUG);
		$vm = Vim::find_entity_views (view_type => 'VirtualMachine',
			begin_entity => @$begin,
			filter => { 'guest.ipAddress' => $gu });
#			filter => { 'guest.net[0].ipAddress' => $gu });
		foreach ( @$vm ) { # we may have several with same IP address
			print "Guest is ".$_->runtime->powerState->val."\n" if($DEBUG);
			if($_->runtime->powerState->val eq 'poweredOn') {
				@$vm = ( $_ ); # Just keep the active one
				last;
			}
		}
	}
	unless(@$vm) { 	
		if(!$report or $report =~ /state/i) {
			doerror("Guest '$gu' not found."); 
		} 
		dounknown("Guest '$gu' not found."); 
	}
}

# Right, now we know where to start from.  Possibly this is identifying
# a unique host, but not necessarily. We may also have a VM but not 
# necessarily.

print "Report type requested is [$report]\n" if($DEBUG);
print "Base is ".$begin->[0]->name."\n"  if($DEBUG);
#foreach ( keys %{$begin->[0]} ) {
#	print $_." = ".$begin->[0]{$_}."\n";
#}
#exit 0;

# Now, if we DONT have a guest set, but DO have nsca set, and are using
# Nagios mode plus a report type of CPU or MEM then we're going to query 
# ALL the guests and feed the results back in via NSCA
#


# Now, depending on what we're asking for, call a different function
if($report =~ /cpu/i) {
	if($isnagios and !$vm and Opts::option_is_set('nsca')) {
		my($guestname,$glist);
		# loop through ALL guests in this host/farm
		print "Finding full list of guests\n" if($DEBUG);
		$glist = Vim::find_entity_views (view_type => 'VirtualMachine',
			begin_entity => @$begin );
		foreach my $v ( @$glist ) {
			next if( $v->runtime->powerState->val ne 'poweredOn' );
			@$vm = ( $v );
			$MSG = ""; $STATUS=0;
			$guestname = $v->guest->hostName;
			$guestname = $v->name if(!$guestname);
			$guestname =~ s/^\s+//;
			$guestname =~ s/\s+.*$//; next if(!$guestname);
			$guestname = canonical($guestname);
	
			print "Looping for $guestname\n" if($DEBUG);

			cpureport();

			$MSG = "All OK" if(!$MSG);
			print "\n$guestname is [$STATUS] $MSG\n\n" if($DEBUG);
			sendnsca($guestname,"VMware: Resources: CPU",$STATUS,$MSG) if($STATUS<3);
			%perfkeys = (); @metricids = (); @queries = ();
		}
		$PERF = "|"; $MSG = ""; $STATUS=0; $vm = 0;
		print "*** Now running the real report...\n" if($DEBUG);
	}
	cpureport();
} elsif($report =~ /mem/i) {
	if($isnagios and !$vm and Opts::option_is_set('nsca')) {
		my($guestname,$glist);
		# loop through ALL guests in this host/farm
		print "Finding full list of guests\n" if($DEBUG);
		$glist = Vim::find_entity_views (view_type => 'VirtualMachine',
			begin_entity => @$begin );
		foreach my $v ( @$glist ) {
			next if( $v->runtime->powerState->val ne 'poweredOn' );
			@$vm = ( $v );
			$MSG = ""; $STATUS=0;
			$guestname = $v->guest->hostName;
			$guestname = $v->name if(!$guestname);
			$guestname =~ s/^\s+//;
			$guestname =~ s/\s+.*$//; next if(!$guestname);
			$guestname = canonical($guestname);
	
			print "Looping for $guestname\n" if($DEBUG);

			memreport();

			$MSG = "All OK" if(!$MSG);
			print "\n$guestname is [$STATUS] $MSG\n\n" if($DEBUG);
			sendnsca($guestname,"VMware: Resources: Memory",$STATUS,$MSG) if($STATUS<3);
			%perfkeys = (); @metricids = (); @queries = ();
		}
		$PERF = "|"; $MSG = ""; $STATUS=0; $vm = 0;
		print "*** Now running the real report...\n" if($DEBUG);
	}
	memreport();
} elsif($report =~ /dis[ck]|datastore/i) {
	diskreport();
} elsif($report =~ /net/i) {
	netreport();
} else { # state
	statereport();
}

# Now disconnect from VI
if(Opts::option_is_set('savesessionfile')) {
	Vim::save_session(session_file=>Opts::get_option('savesessionfile'));
} else {
	print "Disconnecting...\n" if($DEBUG);
	Util::disconnect();
}

# clean up
if($havensca) { print "Closing NSCA connection\n" if($DEBUG); close NSCAPROC; }
$PERF="" if($PERF eq '|'); # no perf stats

# And output the status
if($isnagios) {
	print "Exiting with status ($STATUS)\n" if($DEBUG);
	print "$MSG$PERF\n";
	exit($STATUS);
}

print "$A\n$B\n\n$MSG\n";
exit 0;
