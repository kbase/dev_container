#
# Wrap a perl script for execution in the development runtime environment.
#

if [ $# -ne 3 ] && [ $# -ne 2 ] ; then
    echo "Usage: $0 source dest [newname]" 1>&2 
    exit 1
fi

src=$1
dst=$2
newname=$3

cat > $dst <<EOF
#!/bin/sh
export KB_TOP=$KB_TOP
export KB_RUNTIME=$KB_RUNTIME
export PATH=$KB_RUNTIME/bin:$KB_TOP/bin:\$PATH
export PERL5LIB=$KB_PERL_PATH

EOF

if [[ -n $newname ]]
then
	base=$(basename $dst)
	cat >> $dst <<EOF
echo "Command $base has been deprecated. Please use command $newname instead." >&2
EOF

fi

cat >> $dst <<EOF

$KB_RUNTIME/bin/perl $src "\$@"

EOF

chmod +x $dst
