#
# Wrap a perl script for execution in the development runtime environment.
#

if [ $# -ne 4 ] && [ $# -ne 3 ] && [ $# -ne 2 ] ; then
    echo "Usage: $0 source dest [newname|NONE] [mssg]" 1>&2 
    exit 1
fi

src=$1
dst=$2
newname=$3
mssg=$4

cat > $dst <<EOF
#!/bin/sh
export KB_TOP=$KB_TOP
export KB_RUNTIME=$KB_RUNTIME
export PATH=$KB_RUNTIME/bin:$KB_TOP/bin:\$PATH
export PERL5LIB=$KB_PERL_PATH

EOF

# if the developer indicated that the script is a deprecated wrapper, then add a warning
if [[ -n $newname ]]
then
    base=$(basename $dst)
    if [ "$newname" == "NONE" ]
    then
        cat >> $dst <<EOF
echo "Warning: command $base has been deprecated." >&2
EOF
    else
        cat >> $dst <<EOF
echo "Warning: command $base has been deprecated. Please use command $newname instead." >&2
EOF
    fi
fi

# if the developer requested some kind of other deprecated warning message, then display it...
if [[ -n $mssg ]]
then
    cat >> $dst <<EOF
echo "$mssg" >&2
EOF
fi


cat >> $dst <<EOF

$KB_RUNTIME/bin/perl $src "\$@"

EOF

chmod +x $dst
