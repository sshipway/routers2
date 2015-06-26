#!/bin/sh
#
# migrate data to new server
#
# THIS IS AN **EXAMPLE** SHOWING HOW WE USED THE SCRIPT.
# You cannot simply run this and expect it to work. You may be merging
# locally, or not have ssh keys, or something.

MERGE=/u01/src/rrdmerge.pl

FROMDIR=/u01/rrdtool

TOHOST=mrtg2.auckland.ac.nz
USER=mrtg
TODIR=/u01/rrddata
RRDTOOL=/u01/mrtg/bin/rrdtool

cd $FROMDIR
FILES=`ls *.rrd`

############################################################################

echo `date` Starting data migration...

for rrdfile in $FILES
do
	echo `date` Processing $rrdfile
	$MERGE -q -o /tmp/merge.xml -r 12000 $FROMDIR/$rrdfile $FROMDIR/archive/*/$rrdfile.d/*.rrd
	scp /tmp/merge.xml $USER@$TOHOST:$TODIR/$rrdfile.xml
	ssh $USER@$TOHOST $RRDTOOL restore -f $TODIR/$rrdfile.xml $TODIR/$rrdfile
	ssh $USER@$TOHOST rm -f $TODIR/$rrdfile.xml
	ssh $USER@$TOHOST ls -l $TODIR/$rrdfile
done

echo `date` Data migration complete 
exit 0
