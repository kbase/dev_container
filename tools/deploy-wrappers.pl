use strict;
use warnings;

use Getopt::Long;
use File::Slurp;
use File::Basename;
use JSON;
use Data::Dumper;
use File::Copy qw(copy);

my ($jsonCommandsFile,$irisCommandsFile,$dryrun,$debug,$scriptTarget,$TARGET,$DEV_TOOLS_DIR);

my $result=GetOptions(
	"jsonCommandsFile=s"		=>	\$jsonCommandsFile,
	"irisCommandsFile=s"		=>	\$irisCommandsFile,
	"target=s"			=>	\$TARGET,
	"scriptTarget=s"		=>	\$scriptTarget,
	"devContainerToolsDir=s"	=>	\$DEV_TOOLS_DIR,
	"dryrun"			=>	\$dryrun,
	"debug" 			=>	\$debug,
);

die "--jsonCommandsFile required!" unless ($jsonCommandsFile);

$DEV_TOOLS_DIR="$ENV{TOP_DIR}/tools" unless ($DEV_TOOLS_DIR);
$TARGET=$ENV{TARGET} unless ($TARGET);
$scriptTarget="$TARGET/plbin/" unless ($scriptTarget);

my $commandsJson = read_file($jsonCommandsFile) or die "couldn't read $jsonCommandsFile: $!";

my $json=JSON->new;

my $commands = $json->decode($commandsJson);

#print Dumper($commands);
#warn $commands->{cli}{'deprecated-commands'}[0]{iris};

#print_iris_commands($commands->{'iris'},$irisCommandsFile) if ($irisCommandsFile);


my ($commands_to_deploy, $iris_command_list) = process_command_list($commands->{'cli'}->{'commands'});
my ($dep_commands_to_deploy, $iris_dep_command_list) = process_deprecated_command_list($commands->{'cli'}->{'deprecated-commands'});

write_iris_commands($iris_command_list,$iris_dep_command_list) if ($irisCommandsFile and !$dryrun);

deploy_and_wrap_commands($commands_to_deploy,$dep_commands_to_deploy,$TARGET,$DEV_TOOLS_DIR);


# dump iris section to COMMANDS
# wrap cli commands
# wrap deprecated cli commands

sub print_iris_commands {
	
	my $iris=shift;
	my $irisCommandsFile=shift;
	
	warn $irisCommandsFile;
	
	my $groupNames=$iris->{'group-names'};
	my $commandSets=$iris->{'command-sets'};
	my $commands=$iris->{'commands'};
	
	my $irisCommandsFileText;
	
	# write the group-names
	foreach my $groupName (@$groupNames)
	{
		warn Dumper($groupName);
		$irisCommandsFileText.=join "\t",'#group-name',$groupName->{'group-name'},$groupName->{'description'};
		$irisCommandsFileText.="\n";
	}
	
	# write the command-sets
	foreach my $commandSet (@$commandSets)
	{
		warn Dumper($commandSet);
		$irisCommandsFileText.=join "\t",'#command-set',$commandSet->{'pattern'},$commandSet->{'group-name'};
		$irisCommandsFileText.="\n";
		
		
		open(FIND, "-|", "find", $commandSet->{'pattern'}, "-type", "f") or die "cannot open find: $!";
		my @files = <FIND>;
		chomp @files;
		@files = grep { ! m,^\./\.git/, } @files;
		print Dumper(@files)."\n";
		
		
	}
	
	# write individual commands
	foreach my $command (@$commands)
	{
		warn Dumper($command);
		$irisCommandsFileText.=join "\t",$command->{'command-name'},$command->{'group-name'};
		$irisCommandsFileText.="\n";
	}
	
	
	open (IRISCOMMANDSFILE,'>',$irisCommandsFile) or die "couldn't open $irisCommandsFile: $!";
	print IRISCOMMANDSFILE $irisCommandsFileText;
	close IRISCOMMANDSFILE;
} # end sub print_iris_commands




# accepts the parsed json COMMANDS.json pointing to the root->cli->commands location
# returns list of commands to deploy and a list of commands for IRIS commands
sub process_command_list {
	my $commands = shift;
	
	# hash of iris commands as keys, IRIS group as values 
	my $iris_command_list = {};
	
	# list of the commands we want to deploy.  Each element is a hash {name=>, file=>, lang=>}
	my $commands_to_deploy = [];
	
	my $command_count = 0;
	foreach my $command (@$commands)
	{
		warn "------------\n" if ($debug);
		if ( defined($command->{'file'}) && defined($command->{'lang'}) )
		{
			
			my @files = glob $command->{'file'};
			foreach my $file (@files)
			{
				warn $file."\n" if ($debug);
				print STDERR "Warning: $file is not a regular file\n" unless (-f $file);
				
				# extract out the command name
				my $commandname = basename($file);
				$commandname =~ s/\.[^.]+$//;
				warn $commandname."\n" if ($debug);
				
				# add to the iris list if a group-name was defined
				if(defined($command->{'iris-group-name'}))
				{
					$iris_command_list->{$commandname} = $command->{'iris-group-name'};
				}
				
				# add to the commands to deploy list
				my $command_summary = {
						       'name'=>$commandname,
						       'file'=>$file,
						       'basename'=>basename($file),
						       'lang'=>$command->{'lang'}
						       };
				push(@$commands_to_deploy,$command_summary);
			}
		}
	}
	
	return ($commands_to_deploy, $iris_command_list);
}


# accepts the parsed json COMMANDS.json, returns list of IRIS commands, list of 
sub process_deprecated_command_list {
	my $dep_commands = shift;
	
	# hash of iris commands to be placed in group 'deprecated'
	my $iris_dep_command_list = [];
	
	# list of the commands we want to deploy.  Each element is a hash {name=>, file=>, lang=>}
	my $dep_commands_to_deploy = [];
	
	my $command_count = 0;
	foreach my $command (@$dep_commands)
	{
		warn "------------\n" if ($debug);
		if ( defined($command->{'deprecated-name'}) && defined($command->{'file-name'}) && defined($command->{'lang'}) )
		{
			if($command->{'deploy-to-iris'})
			{
				push(@$iris_dep_command_list,$command->{'deprecated-name'});
			}
			
			# should probably do some more error checking here...
			print STDERR "Warning: ".$command->{'file-name'}." is not a regular file\n" unless (-f $command->{'file-name'});
			
			my $command_summary = {
				'deprecated-name'=>$command->{'deprecated-name'},
				'file-name'=>$command->{'file-name'},
				'lang'=>$command->{'lang'}
				};
			
			if ( defined($command->{'new-command-name'}) ) {
				$command_summary->{'new-command-name'} = $command->{'new-command-name'};
			}
			
			if ( defined($command->{'warning-mssg'}) ) {
				$command_summary->{'warning-mssg'} = $command->{'warning-mssg'};
			}
			push(@$dep_commands_to_deploy,$command_summary);
		}
	}
	
	return ($dep_commands_to_deploy, $iris_dep_command_list);
}

# given the parse, write the old style COMMMANDS file
sub write_iris_commands {
	my $iris_command_list = shift;
	my $iris_dep_command_list = shift;
	
	my $irisCommandsFileText = '';
	
	# write individual commands
	foreach my $command (keys %$iris_command_list)
	{
		warn Dumper($command) if ($debug);
		$irisCommandsFileText.=join "\t",$command,$iris_command_list->{$command};
		$irisCommandsFileText.="\n";
	}
	foreach my $command (@$iris_dep_command_list)
	{
		warn Dumper($command) if ($debug);
		$irisCommandsFileText.=join "\t",$command,'deprecated';
		$irisCommandsFileText.="\n";
	}
	
	if ($debug) {
		print "\n^^^^^^^^^^^^^^^^^^^^^^^^^\n";
		print $irisCommandsFileText."\n";
		return $irisCommandsFileText;
	}

	open (IRISCOMMANDSFILE,'>',$irisCommandsFile) or die "couldn't open $irisCommandsFile: $!";
	print IRISCOMMANDSFILE $irisCommandsFileText;
	close IRISCOMMANDSFILE;
}



# when we call make with no targets, we need to put script wrappers in the dev_container/bin
# directory so that it is available to other modules.  Thus, we need to be able to call
# this script and wrap commands without installing them anywhere.
sub wrap_commands_only {
	my $commands_to_deploy = shift;
	my $dep_commands_to_deploy = shift;
	my $TARGET = shift;
	my $DEV_TOOLS_DIR = shift;
	
}


#
sub deploy_and_wrap_commands {
	my $commands_to_deploy = shift;
	my $dep_commands_to_deploy = shift;
	my $TARGET = shift;
	my $DEV_TOOLS_DIR = shift;
	
	# de
	foreach my $command (@$commands_to_deploy)
	{
		# 1 deploy the command by copying it over, then 2
		print "installing ".$command->{'name'}."\n";
		if(-f $command->{'file'}) {
			
			if ($command->{'lang'} eq 'perl') {
				my $destination = $scriptTarget.$command->{'basename'};
				print "  warning, overwriting: '".$destination."'\n" if(-f $destination);
				unless ($dryrun) {
					copy($command->{'file'},$destination) or die "copy failed: $!";
				}
				# call wrap perl here!!  but how do we find where it is installed-- it is defined
				# as a makefile flag
				my $wrap_command = $DEV_TOOLS_DIR."/wrap_perl ".$destination." ".$TARGET."/bin/".$command->{'name'};
				print $wrap_command."\n";
				unless ($dryrun) {
					system($wrap_command)==0 or die ("could not run $wrap_command: $!");
				}
				
			}
			#elsif ($command->{'name'} eq 'python') {
				
			#}
			else {
				print "  --skipping! cannot wrap command written in language '".$command->{'lang'}."'\n";
			}
			
			
			
		} else {
			print "  --skipping! file '".$command->{'file'}."' does not exist.\n";
		}
		
		
	}
	
	
	
}

# we should be able to write an undeploy command ...
sub undeploy {
	my $commands_to_deploy = shift;
	my $dep_commands_to_deploy = shift;
	my $TARGET = shift;
	
}





