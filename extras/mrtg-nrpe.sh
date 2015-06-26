#!/bin/sh
# vim:ts=4
#
# mrtg-nrpe: version 0.3
#
# Collect data from remote nrpe agent on server, for MRTG
#
# Usage:  mrtg-nrpe [-n] -H hostname -v command [-l arg] [-o offset]

AGENT=/u01/mrtg/plugins/check_nrpe
HOST=
CNTA=
CNTB=
MULT=1
ARGA=
ARGB=
OFFA=
OFFB=
NRPEOPTS=

# Parse arguments
while [ $# -gt 0 ]
do
	f="$1"
	o="$2"
	shift
	case "$f" in
		-H|-h|-s)		HOST=$o
				shift
			;;
		-v|-c)		if [ "$CNTA" != "" ]
				then
					CNTB="$o"
				else
					CNTA="$o"
				fi
				shift
			;;
		-l|-a)	if [ "$ARGA" != "" -o "$CNTB" != "" ]
				then
					ARGB="-a $o"
				else
					ARGA="-a $o"
				fi
				shift
			;;
		-m)		MULT=$o
				shift
			;;
		-o)		if [ "$OFFA" != "" -o "$ARGB" != "" -o "$CNTB" != "" ]
				then
					OFFB="$o"
				else
					OFFA="$o"
				fi
				shift
			;;
		-x)		NRPEOPTS="$NRPEOPTS $o"
				shift
			;;
		-n)		NRPEOPTS="$NRPEOPTS --no-ssl"
			;;
		-d)		DEBUG=1
			;;
		*)		echo "Usage:  mrtg-nrpe [-n][-x opts] -H hostname -v counter [-l arg][-o offset] [-v counter [-l arg][-o offset]]"
				echo "Eg: mrtg-nrpe -H myserver -v check_disk -l /"
				exit 1
			;;
	esac
done
[ "$OFFA" != "" ] || OFFA=1
[ "$OFFB" != "" ] || OFFB=$OFFA
if [ "$HOST" = "" -o "$CNTA" = "" ]
then
	echo "Usage:  mrtg-nrpe [-n][-x opts] -H hostname -v counter [-l arg][-o offset] [-v counter [-l arg][-o offset]]"
	echo "Eg: mrtg-nrpe -H myserver -v check_disk -l /"
	exit 1
fi

#echo "CNT($CNTA,$CNTB) ARG($ARGA,$ARGB) OFF($OFFA,$OFFB)"
# Call script : 0=OK, 1=Warn, 2=Critical/timeout, 3=ERROR
XRVA=`$AGENT -t 20 -H $HOST $NRPEOPTS -c "$CNTA" $ARGA`
RCA=$?
[ `echo "$XRVA" | egrep -c timeout` -ne 0 ] && RCA=4
if [ $RCA -gt 2 ]
then
	RVA="UNKNOWN"
	LAST="$XRVA"
else
	RVA=`echo "$XRVA" |sed 's/[a-zA-Z%='"'"':,\/\(\)_[-]/ /g'|awk '{print $'"$OFFA}"`
fi
if [ "$CNTB" != "" ]
then
	XRVB=`$AGENT -t 20 -H $HOST $NRPEOPTS -c "$CNTB" $ARGB`
	RCB=$?
	[ `echo "$XRVB" | egrep -c timeout` -ne 0 ] && RCB=4
	if [ $RCB -gt 2 ]
	then
		RVB="UNKNOWN"
		LAST="$XRVB"
	else
		RVB=`echo "$XRVB" |sed 's/[a-zA-Z%='"'"':,\/\(\)_[-]/ /g'|awk '{print $'"$OFFB}"`
	fi
elif [ "$OFFB" != "" ]
then
	RVB=`echo "$XRVA" |sed 's/[a-zA-Z%='"'"':,\/\(\)_[-]/ /g'|awk '{print $'"$OFFB}"`
else
	RVB="$RVA"
fi
if [ "$LAST" == "" ]
then
LAST="$HOST NRPE Client $CNTA:$CNTB"
fi

if [ "$RVB" = "" ]
then
	RVB="UNKNOWN"
	LAST="$XRVB"
fi
if [ "$RVA" = "" ]
then
	RVA="UNKNOWN"
	LAST="$XRVA"
fi
case "$XRVA" in
	*Error*)
		LAST="$XRVA"
		;;	
	*timeout*)
		LAST="$XRVA"
		;;
esac
if [ "$DEBUG" = 1 ]
then
	LAST="$XRVA"
fi

# Output data
echo $RVA
echo $RVB
echo
echo $LAST
exit 0
