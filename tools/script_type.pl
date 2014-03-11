

# check the incoming arg if it is a valid file
die "usage: $0 <script>" unless -e $ARGV[0];

# parse out the #! from the file
open F, $ARGV[0] or die;
my $sebang;
while(<F>) {

	$sebang = $_ if /^\#\!\s*/;
	last if defined $sebang;

}
close F;

my $type = 'unknown';
$type = 'sh' if $sebang =~ /sh/;
$type = 'py' if $sebang =~ /python/;
$type = 'pl' if $sebang =~ /perl/;

print $type;
