use strict;
use warnings;

use Getopt::Long;
use File::Slurp;
use JSON;
use Data::Dumper;

my ($jsonCommandsFile,$irisCommandsFile);

my $result=GetOptions(
	"jsonCommandsFile=s"	=>	\$jsonCommandsFile,
	"irisCommandsFile=s"	=>	\$irisCommandsFile,
);

die "--jsonCommandsFile required!" unless ($jsonCommandsFile);

my $commandsJson = read_file($jsonCommandsFile) or die "couldn't read $jsonCommandsFile: $!";

my $json=JSON->new;

my $commands = $json->decode($commandsJson);

#print Dumper($commands);
#warn $commands->{cli}{'deprecated-commands'}[0]{iris};

print_iris_commands($commands->{'iris'},$irisCommandsFile) if ($irisCommandsFile);

# dump iris section to COMMANDS
# wrap cli commands
# wrap deprecated cli commands

sub print_iris_commands {

my $iris=shift;
my $irisCommandsFile=shift;

warn $irisCommandsFile;

my $groupNames=$iris->{'group-names'};
my $commandSets=$iris->{'command-sets'};

my $irisCommandsFileText;

foreach my $groupName (@$groupNames)
{
	warn Dumper($groupName);
	$irisCommandsFileText.=join "\t",'#group-name',$groupName->{'group-name'},$groupName->{'description'};
	$irisCommandsFileText.="\n";
}

open (IRISCOMMANDSFILE,'>',$irisCommandsFile) or die "couldn't open $irisCommandsFile: $!";
print IRISCOMMANDSFILE $irisCommandsFileText;
close IRISCOMMANDSFILE;
} # end sub print_iris_commands

