#!/usr/bin/perl
# vim:ts=4
#
# Steve Shipway 2012-2013
#
# This takes multiple RRD files, and produces XML for a single RRD
# that is a merge of the specified files.  It will try to correct and change
# intervals where required, and approximate data with the best available fill.
# Multiple DS will be consolodated and merged, and can be renamed if
# required. !!!!ALWAYS TAKE A BACKUP OF DATA FIRST!!!!
#
# This is intended to be used for merging a set of old-style MRTG/RRD archives
# to make a single new extended-RRA RRD file to work with extendedtime=full
# in Routers2.
# Example (when in WorkDir): 
#   cp target.rrd target.rrd.old
#   rrdmerge.pl -R -o target -r 12000 target.rrd archive/*/target.rrd.d/*.rrd
#
# Usage:
# rrdmerge.pl [-q][-R][-a|-D ds[=ds] ...][-o output[.xml|.rrd]][-r rows] 
#             [-i sec]
#             [-l librarypath][--debug][--version]
#             base.rrd [rrd1.rrd rrd2.rrd .... ]
#
# -q : quiet output
# -R : create RRD, not XML
# -a : preserve ALL DS, not just from base.rrd
# -D : specify name of DS to preserve (can be multiple)
# -i : specify new interval in seconds. MUST be a factor of existing
#      interval.
# -r : make new RRAs with this many rows (default is to match base.rrd)
# -o : specify output file .xml or .rrd
# base.rrd, rrd1.rrd ... : component RRDs.  MUST have same interval.
#      if RRDs have different structure, base.rrd is used as template
# -l : Specify location of RRDs.pm library if necessary
# -d : debug output
#     
# v0.2: Fix problem with DS not being available in all RRD
#       Add -l libpath option
#       Correct abbriviated options so that -d means debug and not --ds

use strict;
use Getopt::Long qw(:config no_ignore_case);
use POSIX qw(strftime);

my($VERSION) = "0.2";

my($opt_quiet,$opt_debug,$opt_rrd,$opt_allds,$opt_ds,$opt_interval,
	$opt_rows,$opt_output,$opt_help,$opt_libpath,$opt_version);
my($rv);
my($factor)=1;

my(@RRD) = ();
my(@DS)  = ();
my(@RRA) = ();
my($END) = 0;

$|=1; # do not buffer stdout
###########################################################################
sub do_version() {
    print "rrdmerge version $VERSION\n";
}
sub do_help() {
	do_version;
	print "Usage:\n";
	print "rrdmerge.pl [-q][-R][-a|-D ds[=ds] ...][-o output.xml][-r rows] \n";
	print "            [-i sec]\n";
	print "            base.rrd [rrd1.rrd rrd2.rrd .... ]\n";
	print "\n";
	print "--quiet -q    : quiet output\n";
	print "--rrd -R      : create RRD, not XML\n";
	print "--all-ds -a   : preserve ALL DS, not just from base.rrd\n";
	print "--ds -D       : specify name of DS to preserve (can be multiple)\n";
	print "--interval -i : specify new interval in seconds. MUST be a factor of existing\n";
	print "     interval.\n";
	print "--rows -r     : make new RRAs with this many rows (default is match base.rrd)\n";
	print "--output -o   : specify output file .xml or .rrd\n";
    print "--libpath -l  : specify location of the RRDs.pm Perl library\n";
    print "--debug       : Debug output (multiple times for more output)\n";
    print "--version -V  : Give program version\n";
	print "base.rrd, rrd1.rrd ... : component RRDs.\n\n";
	print "Generated XML or RRD has RRAs matching base.rrd.\n\n";
}

# Fetch the data.  Have to return reference to array of $rows values for $dsname
# asking for DS matching given RRA
sub fetch_data($$$$$$) {
	my($dsname,$cf,$resolution,$rows,$wantstart,$wantend) = @_;
	my($pdp);
	my($start,$end);
	my($fstart,$fstep,$fdsnames,$fdata);
	my(@data);
	my($availstart,$availend,$rrdfile);
	my($donestart,$doneend);
	my($dsno);

	$data[$rows-1]=undef;

	print "    Fetching values for $dsname in RRA $cf($resolution s)\n" unless($opt_quiet);

	# First, work through the available RRAs in the RRD files in order,
	# filling up the required block as available.

	$donestart = $doneend = $wantend;
	$pdp = $resolution / $RRD[0]->{step}; # Not sure about this sorting
	foreach my $rrd ( $RRD[0], sort { 
		$b->{"$cf:$pdp"} <=> $a->{"$cf:$pdp"}
	} @RRD ) {
		$pdp = $resolution / $rrd->{step};
		print "      Checking RRD ".$rrd->{name}."\n" if($opt_debug);
		print "        Resolution $resolution s = $pdp pdp\n" if($opt_debug);
		$rrdfile = $rrd->{name};
		# check that DS actually exists in this RRD
		unless(defined $rrd->{"info"}{"ds[$dsname].type"}) {
			print "        DS [$dsname] does not exist in this RRD\n" if($opt_debug);
			next;
		}
		# check for a relevant RRA
		unless(defined $rrd->{"$cf:$pdp"}) { # no relevant rra
			print "        No relevant RRA available in this RRD for [$cf:$pdp]\n" if($opt_debug);
			next;
		}
		$availend = $rrd->{lastupdate};
		$availstart = $rrd->{"$cf:$pdp"};
		$end = $donestart;
		$end = $availend if($end > $availend);
		if($end < $availstart) {
			print "        Required window end ($end) is before RRA start ($availstart)\n" if($opt_debug);
			next;
		}
		$start = $wantstart;
		$start = $availstart if($start < $availstart);
		if($start > $availend) {
			print "        Required time window ($start) is after RRA end ($availend)\n" if($opt_debug);
			next;
		}
		if($start >= $end) {
			print "        Required time window does not overlap available window\n" if($opt_debug);
			next;
		}
		# if we get here, then this RRD has a relevant RRA that can help

		print "      Fetching data CF=$cf, resolution=$resolution...\n" if($opt_debug);
		($fstart,$fstep,$fdsnames,$fdata) = RRDs::fetch($rrdfile,$cf,
			'-r',$resolution,
			'-e',$end,'-s',$start );

		# did it work?  Check the returned fstep is correct
		if($fstep != $resolution) {
			print "      RRDs::fetch returned the wrong resolution?!?\n" if($opt_debug);
			next;
		}

		# identify data offset for this DS
		$dsno = -1;
		foreach ( @$fdsnames ) {
			$dsno += 1;
			last if($$fdsnames[$dsno] eq $dsname );
		}
		if(!$$fdsnames[$dsno]) {
			print "      RRDs::fetch did not return data for the DS we wanted?!?\n" if($opt_debug);
			next;
		}
	
		# So, we can now copy in the data.
		my($idx) = ($fstart - $wantstart)/$fstep;
		if($opt_debug) {
			print "      Required time window            $wantstart - $wantend\n";
			print "      Retrieved so far window         $donestart - $doneend\n";
			print "      Available time window           $availstart - $availend\n";
			print "      Asked for time window           $start - $end\n";
			print "      Retrieved time window           $fstart - ".($fstart+($fstep*$#$fdata))."\n";
			print "      Fetched this many rows          ".$#$fdata."\n";
			print "      Data step is                    $fstep\n";
			print "      Saving data to array from index $idx\n";
		}
		foreach ( @$fdata ) { 
			$data[$idx] = $_->[$dsno]; 
			print "        $idx: ".$_->[$dsno]."\n" if($opt_debug>2);
			$idx++; }
		$donestart = $fstart if($fstart<$donestart);
		$doneend = ($fstart+($fstep*$#$fdata)) if( $doneend<($fstart+($fstep*$#$fdata)));
	}
	
	# Next, maybe try and fill in any gaps by searching?
	# Identify next best RRA
	my $origpdp = $resolution / $RRD[0]->{step};
	$pdp = 0;
	foreach ( keys %{$RRD[0]} ) {
		next unless ( /$cf:(\d+)/ );
		next if( $1 <= $origpdp );
		next if( int($1/$origpdp) != ($1/$origpdp));
		$pdp = $1;
		last;
	}
	if($pdp) {
	my($gapto) = $rows;
	my($gapfrom);
	print "    Filling in gaps...\n" if($opt_debug);
	# Maybe fill gaps by using less good RRAs and duplicating the data?
	while($pdp and $gapto>0) {
		if(defined $data[$gapto]) {
			$gapto -= 1;
			next; # skip on until we get an unknown block
		}
		$gapfrom = $gapto;
		while($gapfrom and !defined $data[$gapfrom]) { $gapfrom--; }
		$gapfrom++ if(defined $data[$gapfrom]);
		if( ($gapto - $gapfrom) < 5 ) { 
			$gapto = $gapfrom - 1;
			next; # ignore small gaps
		}
		print "      Identified unknown gap between indices $gapfrom and $gapto\n" if($opt_debug);

		# Lets see if we can find anything that might work...
			
		foreach my $rrd ( $RRD[0], sort { 
			$b->{"$cf:$pdp"} <=> $a->{"$cf:$pdp"}
		} @RRD ) {
			print "        Checking RRD ".$rrd->{name}."\n" if($opt_debug);
			print "          Resolution trying $pdp pdp\n" if($opt_debug);
			$rrdfile = $rrd->{name};
			$availend = $rrd->{lastupdate};
			$availstart = $rrd->{"$cf:$pdp"};
			if( $availstart > (($gapto*$resolution)+$wantstart)) {
				print "          Gap too early for this RRA\n" if($opt_debug);
				next;
			}
			if( $availend < (($gapfrom*$resolution)+$wantstart)) {
				print "          Gap too late for this RRA\n" if($opt_debug);
				next;
			}
			print "          Fetching data CF=$cf, resolution=".($pdp*$rrd->{step})."...\n" if($opt_debug);
			($fstart,$fstep,$fdsnames,$fdata) = RRDs::fetch($rrdfile,$cf,
				'-r',($pdp*$rrd->{step}),
				'-e',(($gapto*$resolution)+$wantstart),
				'-s',(($gapfrom*$resolution)+$wantstart));
	
			if( ($pdp*$rrd->{step}) != $fstep ) {
				print "            RRDs::fetch did not return data for requested step (asked ".($pdp*$rrd->{step})." got $fstep)\n" if($opt_debug);
				next;
			}
			# identify data offset for this DS
			$dsno = -1;
			foreach ( @$fdsnames ) {
				$dsno += 1;
				last if($$fdsnames[$dsno] eq $dsname );
			}
			if(!$$fdsnames[$dsno]) {
				print "            RRDs::fetch did not return data for the DS we wanted?!?\n" if($opt_debug);
				next;
			}
			if( ! defined $$fdata[0][$dsno] ) {
				print "            Returned data was undefined\n" if($opt_debug);
				next;
			}
			# Copy the data over the gap
			if($opt_debug) {
				print "            Retrieved time window           $fstart - ".($fstart+($fstep*$#$fdata))."\n";
				print "            Fetched this many rows          ".$#$fdata."\n";
				print "            Wanted step is                  $resolution\n";
				print "            Data step is                    $fstep\n";
				print "            Consolodation ratio is          ".($fstep/$resolution)."\n";
				print "            Saving data to array from index $gapfrom\n";
			}
			my ($idx ) = $gapfrom;
			foreach ( @$fdata ) { 
				my( $j ) = 0;
				while( $j < ($fstep/$resolution) ) {
					print "        $idx: ".$_->[$dsno]."\n" if($opt_debug>1);
					$data[$idx] = $_->[$dsno] if(!defined $data[$idx]); 
					$j++; $idx++;
					last if($idx > $gapto);
				}
				last if($idx > $gapto);
			}

			last;
		}
		$gapto = $gapfrom - 1;
	}
	} else {
		print "    No available RRA to use for fill-in.\n" if($opt_debug);
	}


	# return the data
	print "    Completed data fetch!\n" if($opt_debug);
	return \@data; # return a ref to the array
}
###########################################################################
# Main code

##################################
# process arguments
$rv = GetOptions(
	'quiet|q'=>\$opt_quiet,
	'debug|d+'=>\$opt_debug,
	'rrd|R'=>\$opt_rrd,
	'all-ds|a'=>\$opt_allds,
	'ds|D=s@'=>\$opt_ds,
	'interval|i=i'=>\$opt_interval,
	'rows|r=i'=>\$opt_rows,
	'output|o=s'=>\$opt_output,
	'help|?|h'=>\$opt_help,
    'libpath|L|l=s'=>\$opt_libpath,
	'version|V'=>\$opt_version,
);
print "Error processing arguments.\n\n" if(! $rv );
if( $opt_help or !$rv) { do_help(); exit 0; }
if( $opt_version ) { do_version(); exit 0; }
if($opt_libpath) {
	push @INC,split( /:/,$opt_libpath);
}
eval { require RRDs; };
if($@) {
	print "Unable to load RRDtool Perl library.\nPlease use -l option to specify the location of the RRDs.pm file.\n";
	print "$@\n";
	exit 1;
}
$opt_output = "output" if(!$opt_output);
$opt_output .= ".xml" if(!$opt_rrd and $opt_output !~ /\.xml$/);
$opt_output .= ".rrd" if($opt_rrd and $opt_output !~ /\.rrd$/);
print "Processing output to file $opt_output\n" if(!$opt_quiet);
if(!@ARGV) {
	print "You must give at least a base RRD to work with.\n";
	exit 1;
}
# get info on components
@RRD = ();
print "Reading structure of component RRD files...\n" unless($opt_quiet);
foreach my $rrd ( @ARGV ) {
	print "Checking $rrd\n" if($opt_debug);
	if( ! -r $rrd ) {
		print "Unable to read RRD file $rrd\n";
		exit 0;
	}
	my $rv = RRDs::info($rrd);
	my $lu = $rv->{last_update};
	$lu = (int($lu/$rv->{step})+1)*$rv->{step};
	print "  Interval is ".$rv->{step}."\n" if($opt_debug);
	print "  Last update is ".$rv->{last_update}." -> $lu\n" if($opt_debug);
	my %r = ( info=>$rv, name=>$rrd, lastupdate=>$lu, step=>$rv->{step} );
	foreach my $k ( keys %$rv ) {
		if( $k =~ /rra\[(\d+)\]\.cf/ ) {
			$r{$rv->{$k}.":".$rv->{"rra[$1].pdp_per_row"}} = 
				$lu-($rv->{"rra[$1].pdp_per_row"}*($rv->{"rra[$1].rows"}-1)*$rv->{step});
		}
		if( $k =~ /ds\[(\S+)\]\.type/ ) {
			$r{ds}=[] unless(defined $r{ds}); # for older perls
			push @{$r{ds}},$1;
		}
	}
	if($opt_debug>1) {
		print "      RRD record:\n";
		foreach ( keys %r )  {
			print "        $_ = ".$r{$_}."\n";
		}
	}
	push @RRD, \%r;
	$END = $lu if($lu>$END);
}
if(!$END) {
	print "Cannot determine base end time for new RRD.\n";
	exit 1;
}
print "New RRD will end on $END (".localtime($END).")\n" unless($opt_quiet);

##################################
# identify destination format

## destination interval
my($src_interval)=$RRD[0]->{info}->{step};
print "Source interval is $src_interval\n" if($opt_debug>1);
if(!$src_interval) {
	print "Unable to identify interval (step) on source RRD files!\n";
	exit 1;
}
#foreach ( @RRD ) {
#	if( $_->{info}->{step} != $src_interval ) {
#		print "Interval mismatch: base=${src_interval} but "
#			.$_->{name}." has ".$_->{info}->{step}.". Cannot continue.\n";
#		exit 1;
#	}
#}
$opt_interval = $src_interval if(!$opt_interval); # set default
if( $opt_interval > $src_interval ) {
	print "You cannot make the interval larger.\n";
	exit 1;
}
if( $opt_interval != $src_interval ) {
	if( ($src_interval/$opt_interval) != int($src_interval/$opt_interval) ) {
		print "The new interval MUST be a factor of the original source interval (${src_interval}).\n";
		exit 1;
	}
	print "Changing RRD interval from ${src_interval} to ${opt_interval}.\n"
		unless($opt_quiet);
	$factor = $src_interval/$opt_interval;
}

## destination DSs
print "Identifying DS for new RRD file\n" unless($opt_quiet);
if($opt_ds) {
	print "  Explicitly defined\n" if($opt_debug);
	foreach my $ds ( @$opt_ds ) {
		$ds=~/([^\s=]+)=?(\S*)/;
		my($name,$aliases) = ($1,$2);
		my($type,$hb,$min,$max);
		foreach my $rrd ( @RRD ) {
			if( defined $rrd->{info}->{"ds[$name].type"} ) {
				$type = $rrd->{info}->{"ds[$name].type"};
				$hb   = $rrd->{info}->{"ds[$name].minimal_heartbeat"};
				$min  = $rrd->{info}->{"ds[$name].min"};
				$max  = $rrd->{info}->{"ds[$name].max"};
				last;
			}
		}
		if( ! $type ) {
			print "Unable to find DS $name in any component RRD.\n";
			exit 1;
		}
		push @DS, { name=>$name, aliases=>[ split /,/,$aliases ],
			type=>$type, heartbeat=>$hb, min=>$min, max=>$max };
	}
} elsif( $opt_allds ) {
	print "  Taking all DS from all components\n" if($opt_debug);
	foreach my $rrd ( @RRD ) {
		print "Identifying all DS in ".$rrd->{name}."\n" unless($opt_quiet);
		foreach my $k ( keys %{$rrd->{info}} ) {
			if( $k =~ /ds\[(\S+)\].type/ ) { # add this DS to the list
				my($name) = $1;
				my($inlist) = 0;
				foreach (@DS) { $inlist=1 if($_->{name} eq $name); }
				push @DS, { name=>$name, aliases=>[],
					type=>$rrd->{info}->{$k}, 
					heartbeat=>$rrd->{info}->{"ds[$name].minimal_heartbeat"}, 
					min=>$rrd->{info}->{"ds[$name].min"}, 
					max=>$rrd->{info}->{"ds[$name].max"} 
				} if(!$inlist);
			}
		}
	}
} else {
	print "  Taking from primary RRD\n" if($opt_debug);
	foreach my $k ( keys %{$RRD[0]->{info}} ) {
		print "    $k\n" if($opt_debug>2);
		if( $k =~ /ds\[(\S+)\].type/ ) { # add this DS to the list
			push @DS, { name=>$1, aliases=>[],
				type=>$RRD[0]->{info}->{$k}, 
				heartbeat=>$RRD[0]->{info}->{"ds[$1].minimal_heartbeat"}, 
				min=>$RRD[0]->{info}->{"ds[$1].min"}, 
				max=>$RRD[0]->{info}->{"ds[$1].max"} 
			};
		}
	}
}
if(!@DS) {
	print "There appear to be no DSs in the new RRD!  This is not possible.\n";
	exit 1;
}
## verify that every component has at least one of these DSs? 
## XXXXXXX

## Show all DS
@DS = sort { return ($a->{name} cmp $b->{name}); } @DS;
unless( $opt_quiet ) {
	print "New RRD will have the following DSs:\n";
	foreach my $ds ( @DS ) {
		print "    ".$ds->{name}.": Type ".$ds->{type}."\n";
	}
}

## destination RRAs ( including rows ) - cf, rows, pdp_per_row, xff
my($hasbase) = 0;
foreach my $k ( keys %{$RRD[0]->{info}} ) {
	if( $k =~ /rra\[(\d+)\].cf/ ) {
		my($rranum) = $1;
		my($rows) = $RRD[0]->{info}->{"rra[$rranum].rows"};
		my($pdp) = $RRD[0]->{info}->{"rra[$rranum].pdp_per_row"};
		$rows = $opt_rows if($opt_rows);
		$hasbase = $rows if($pdp==1 and $RRD[0]->{info}->{$k} eq "AVERAGE");
		$pdp *= $factor;
		push @RRA, {
			cf=>$RRD[0]->{info}->{$k},
			rows=>$rows,
			pdp=>$pdp,
			xff=>$RRD[0]->{info}->{"rra[$rranum].xff"}
		};
	}
}
if($factor>1 and $hasbase) {
	# We should add some new RRAs here for the lowest
	# ratio.  These will be populated by multiples of the previous
	# 1pdp AVG RRAs.
	push @RRA, { cf=>"AVERAGE", rows=>$hasbase, pdp=>1 };
}
if(!@RRA) {
	print "There appear to be no RRAs in the new RRD!  This is not possible.\n";
	exit 1;
}
@RRA = sort { return ($a->{cf} cmp $b->{cf}) if($a->{cf} ne $b->{cf}); return ($a->{pdp} <=> $b->{pdp}); } @RRA;

unless($opt_quiet) {
	print "New RRD will have the following RRAs:\n";
	foreach ( @RRA ) {
		print "    ".$_->{cf}." ".$_->{pdp}." pdp, ".$_->{rows}." rows\n";
	}
}
##################################
# Output XML format

print "Creating XML file\n" unless($opt_quiet);
open XML, ">$opt_output".($opt_rrd?".xml":"") or do {
	print "Unable to create XML file: $!\n";
	exit 1;
};
## XML header
print XML "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
print XML "<!DOCTYPE rrd SYSTEM \"http://oss.oetiker.ch/rrdtool/rrdtool.dtd\">\n";
print XML "<!-- Round Robin Database Dump --><rrd>\n  <version> 0003 </version>\n";
print XML "  <step> $opt_interval </step> <!-- Seconds -->\n";
print XML "  <lastupdate> $END </lastupdate> <!-- ".strftime('%Y-%m-%d %H:%M:%S %Z',localtime($END))." -->\n";

## DS definitions

print "Exporting DS definitions\n" unless($opt_quiet);
foreach my $ds ( @DS ) {
	print XML "  <ds>\n    <name> ".$ds->{name}." </name>\n";
	print XML "    <type> ".$ds->{type}." </type>\n";
	print XML "    <minimal_heartbeat> ".$ds->{heartbeat}." </minimal_heartbeat>\n";
	print XML "    <min> ".sprintf("%e",$ds->{min})." </min>\n";
	print XML "    <max> ".sprintf("%e",$ds->{max})." </max>\n\n";

	print XML "    <!-- PDP Status -->\n";
	print XML "    <last_ds> U </last_ds>\n    <value> NaN </value>\n    <unknown_sec> 0 </unknown_sec>\n  </ds>\n";
}

## RRA contents
print "Exporting RRA data\n" unless($opt_quiet);
print XML "  <!-- Round Robin Archives -->\n";
foreach my $rra ( @RRA ) {
	print "  Exporting ".$rra->{cf}." ".$rra->{pdp}." pdp\n" unless($opt_quiet);
	print XML "  <rra>\n";
	print XML "    <cf> ".$rra->{cf}." </cf>\n";
	print XML "    <pdp_per_row> ".$rra->{pdp}." </pdp_per_row> <!-- ".($rra->{pdp} * $opt_interval)." seconds -->\n";
	print XML "    <params>\n      <xff> ".sprintf("%e",$rra->{xff})." </xff>\n    </params>\n";
	print XML "    <cdp_prep>	\n";
	foreach my $ds ( @DS ) {
		print XML "      <ds>\n";
		print XML "        <primary_value> NaN </primary_value>\n";
		print XML "        <secondary_value> NaN </secondary_value>\n";
		print XML "        <value> NaN </value>\n";
		print XML "        <unknown_datapoints> 0 </unknown_datapoints>\n";
		print XML "      </ds>\n";
	}
	print XML "    </cdp_prep>	\n";
	print XML "    <database>\n";

	my($row) = 0;
	print "    starting ".localtime($END-(($rra->{rows}-1)*$rra->{pdp}*$opt_interval))."\n"
		unless($opt_quiet);
	# Now we fetch the data for the various DS
	my(%DATA) = ();
	my($res) = ($rra->{pdp}*$opt_interval); # data resolution
	my($fend,$fstart);
	$fend = int($END/$res)*$res;
	$fstart = $fend - (($rra->{rows}-1)*$res);
	foreach my $ds ( @DS ) {
		$DATA{$ds->{name}} = fetch_data($ds->{name},
			$rra->{cf},$res,$rra->{rows},
			$fstart,$fend);
	}
	
	# Now , loop through all rows to do in this RRA.  It is based at fend.
	# However we have to do oldest first...
	my($now) = $fstart;
	while( $row < $rra->{rows}) {
		print XML "      <!-- ".strftime('%Y-%m-%d %H:%M:%S %Z',localtime($now))." / $now --><row>";
		foreach my $ds ( @DS ) {
			my($val) = $DATA{$ds->{name}}[$row];
			print XML "<v> ".((defined $val)?sprintf("%16.10e",$val):"NaN")." </v>";
		}
		print XML "</row>\n";
		$row += 1;
		$now += $res;
	}
	print XML "    </database>\n";
	print XML "  </rra>\n";
}

## Close
print XML "</rrd>\n";
close XML;

##################################
# Load in XML to make new RRD if necessary
if( $opt_rrd ) {
	print "Creating RRD files\n" unless($opt_quiet);
	$rv = RRDs::restore( $opt_output.".xml",$opt_output );
	if($rv) {
		print "Build of RRD file failed.  XML is in ${opt_output}.xml\n";
	} else {
		print "RRD file created.\n" unless($opt_quiet);
		unlink $opt_output.".xml";
	}
} 

##################################
# All done!
print "All completed OK.\n" unless($opt_quiet);
exit 0;

