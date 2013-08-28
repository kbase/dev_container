# Usage examples:

# Suitable Makefile rule
#deploy-script-wrappers:
#        $(TOOLS_DIR)/deploy-wrappers \
#                --jsonCommandsFile COMMANDS.json \
#                --irisCommandsFile COMMANDS.old.format \
#                --target $(TARGET) \
#                --devContainerToolsDir $(TOP_DIR)/tools

# Example command line to deploy to dev_container/bin, pointing cli
# scripts to in-place module scripts (important: use --nocopyScripts
# to avoid warnings about copying over same file)
# ../../tools/deploy-wrappers --jsonCommandsFile COMMANDS.json --target /kb/dev_container --devContainerToolsDir ../../tools/ --nocopyScripts --scriptTarget=\\\$KB_TOP/modules/kb_seed/scripts-er

# Omit --irisCommandsFile to use existing COMMANDS file instead

use strict;
use warnings;

use Getopt::Long;
use File::Slurp;
use File::Basename;
use File::Spec;
use JSON;
use Data::Dumper;
use File::Copy qw(copy);
use File::Path qw(make_path);

my ($jsonCommandsFile,$irisCommandsFile,$dryrun,$debug,$copyScripts,$TARGET,$DEV_TOOLS_DIR);

# default values
{
no warnings 'uninitialized';
$DEV_TOOLS_DIR="$ENV{TOP_DIR}/tools";
$DEV_TOOLS_DIR="$ENV{TOP_DIR}/tools";
$TARGET=$ENV{TARGET};
$copyScripts=1;
}

my $result=GetOptions(
	"jsonCommandsFile=s"		=>	\$jsonCommandsFile,
	"irisCommandsFile=s"		=>	\$irisCommandsFile,
	"target=s"			=>	\$TARGET,
	"devContainerToolsDir=s"	=>	\$DEV_TOOLS_DIR,
	"dryrun"			=>	\$dryrun,
	"debug+" 			=>	\$debug,
	"copyScripts!" 			=>	\$copyScripts,
);

# we need, at a minumum the COMMANDS.json file to run
die "--jsonCommandsFile required!" unless ($jsonCommandsFile);
my $commandsJson = read_file($jsonCommandsFile) or die "couldn't read $jsonCommandsFile: $!";


# parse the JSON commands file
my $json=JSON->new;
my $commands = $json->decode($commandsJson);

#extract out the list of commands and info needed by iris
my ($commands_to_deploy, $iris_command_list) = process_command_list($commands->{'cli'}->{'commands'});
my ($dep_commands_to_deploy, $iris_dep_command_list) = process_deprecated_command_list($commands->{'cli'}->{'deprecated-commands'});

#write the old style commands file if requested
# should combine these into one?
write_iris_groups($commands->{'iris'},$irisCommandsFile) if ($irisCommandsFile and !$dryrun);
write_iris_commands($iris_command_list,$iris_dep_command_list) if ($irisCommandsFile and !$dryrun);

#if TARGET is defined, then we deploy
deploy_and_wrap_commands($commands_to_deploy,$dep_commands_to_deploy,$TARGET,$DEV_TOOLS_DIR) if ($TARGET);


# we are done!
exit(0);
     
     

     


# dump iris section to COMMANDS
sub write_iris_groups {
	
	my $iris=shift;
	my $irisCommandsFile=shift;
	
	warn $irisCommandsFile;
	
	my $groupNames=$iris->{'group-names'};
	
	my $irisCommandsFileText;
	
	# write the group-names
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




# accepts the parsed json COMMANDS.json pointing to the root->cli->commands location
# returns list of commands to deploy and a list of commands for IRIS commands
sub process_command_list {
	my $commands = shift;
	
	# hash of iris commands as keys, IRIS group as values 
	my $iris_command_list = {};
	
	# list of the commands we want to deploy.  Each element is a hash {name=>, file=>, lang=>}
	my $commands_to_deploy = {};
	
	my $command_count = 0;
	foreach my $command (@$commands)
	{
#		warn Dumper($command) if ($debug);
		if ( defined($command->{'file-spec'}) && defined($command->{'lang'}) )
		{
			
			my @files = glob $command->{'file-spec'};
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
				
				if ($commands_to_deploy->{$file})
				{
					warn "warning: file $file has been specified more than once, skipping\n";
					next;
				}
				# add to the commands to deploy list
				$commands_to_deploy->{$file} = 
							{
						       'name'=>$commandname,
						       'file'=>$file,
						       'basename'=>basename($file),
						       'lang'=>$command->{'lang'}
						       };
#				push(@$commands_to_deploy,$command_summary);
			}
		}
	}
	
	warn Dumper($commands_to_deploy) if ($debug);
	return ($commands_to_deploy, $iris_command_list);
}


# accepts the parsed json COMMANDS.json, returns list of IRIS commands, list of deprecated commands
sub process_deprecated_command_list {
	my $dep_commands = shift;
	
	# hash of iris commands to be placed in group 'deprecated'
	my $iris_dep_command_list = [];
	
	# list of the commands we want to deploy.  Each element is a hash {name=>, file=>, lang=>}
	my $dep_commands_to_deploy = {};
	
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
			$dep_commands_to_deploy->{$command} = $command_summary ;
		}
	}
	
	return ($dep_commands_to_deploy, $iris_dep_command_list);
}

# given the parse, append list of each command in the old style COMMMANDS file
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

	open (IRISCOMMANDSFILE,'>>',$irisCommandsFile) or die "couldn't open $irisCommandsFile: $!";
	print IRISCOMMANDSFILE $irisCommandsFileText;
	close IRISCOMMANDSFILE;
}





# do the actual deployment
sub deploy_and_wrap_commands {
	my $commands_to_deploy = shift;
	my $dep_commands_to_deploy = shift;
	my $TARGET = shift;
	my $DEV_TOOLS_DIR = shift;
	
	# deploy all the commands requested
	foreach my $command_name (sort keys %$commands_to_deploy)
	{
		my $command=$commands_to_deploy->{$command_name};
		# 1 deploy the command by copying it over, then 2
		print "installing ".$command->{'name'}."\n";
		if(-f $command->{'file'}) {
			
			# determine the target deployment destination of the script
			my $destination;
			if ($command->{'lang'} eq 'perl') {
				$destination = "$TARGET/plbin/".$command->{'basename'};
			}
			elsif ($command->{'name'} eq 'python') {
				$destination = "$TARGET/pybin/".$command->{'basename'};
			}
			else {
				print "  skipping! cannot wrap command written in language '".$command->{'lang'}."'\n";
				next;
			}
			
			# copy the script if we need to
			if ($copyScripts) {
				if ($dryrun) {
					warn "  warning, would overwrite '".$destination."'\n" if(-f $destination);
				} else {
					warn "  warning, overwriting '".$destination."'\n" if(-f $destination);
					copy($command->{'file'},$destination) or die "copy to $destination failed: $!";
				}
			} else {
				# we are not copying scripts, so we need to point the destination to the original script
				# location.  this allows us to call the file directly from the wrapper
				$destination = File::Spec->rel2abs($command->{'file'});
			}

			
			#set up the command to wrap the script
			my $wrap_command;
			if ($command->{'lang'} eq 'perl') {
				$wrap_command = $DEV_TOOLS_DIR."/wrap_perl ".$destination." ".$TARGET."/bin/".$command->{'name'};
			}
			elsif ($command->{'name'} eq 'python') {
				$wrap_command = $DEV_TOOLS_DIR."/wrap_python ".$destination." ".$TARGET."/bin/".$command->{'name'};
			}
			
			# actually call the wrap script
			print "  ".$wrap_command."\n";
			unless ($dryrun) {
				system($wrap_command)==0 or die ("could not run $wrap_command: $!");
			}
			
		} else {
			print "  skipping! file '".$command->{'file'}."' does not exist.\n";
		}
		
		
	}
	
	
	#$command_summary = {
	#			'deprecated-name'=>$command->{'deprecated-name'},
	#			'file-name'=>$command->{'file-name'},
	#			'lang'=>$command->{'lang'}
	#			};
	#		
	#		if ( defined($command->{'new-command-name'}) ) {
	#			$command_summary->{'new-command-name'} = $command->{'new-command-name'};
	#		}
	#		
	#		if ( defined($command->{'warning-mssg'}) ) {
	#			$command_summary->{'warning-mssg'} = $command->{'warning-mssg'};
	#		}
	
	
	
	# deploy all the deprecated commands requested
	foreach my $dep_command_name (sort keys %$dep_commands_to_deploy)
	{
		my $dep_command=%$dep_commands_to_deploy->{$dep_command_name};
		# 1 deploy the command by copying it over
		print "installing deprecated command: ".$dep_command->{'deprecated-name'}."\n";
		
		if(-f $dep_command->{'file-name'}) {
			
			# determine the target deployment destination of the script
			my $destination;
			if ($dep_command->{'lang'} eq 'perl') {
				$destination = "$TARGET/plbin/".$dep_command->{'file-name'};
			}
			elsif ($dep_command->{'name'} eq 'python') {
				$destination = "$TARGET/pybin/".$dep_command->{'file-name'};
			}
			else {
				print "  skipping! cannot wrap command written in language '".$dep_command->{'lang'}."'\n";
				next;
			}
			
			# copy the script if we need to
			if ($copyScripts) {
				if ($dryrun) {
					warn "  warning, would overwrite '".$destination."'\n" if(-f $destination);
				} else {
					warn "  warning, overwriting '".$destination."'\n" if(-f $destination);
					copy($dep_command->{'file-name'},$destination) or die "copy to $destination failed: $!";
				}
			} else {
				# we are not copying scripts, so we need to point the destination to the original script
				# location.  this allows us to call the file directly from the wrapper
				$destination = File::Spec->rel2abs($dep_command->{'file-name'});
			}

			
			#set up the command to wrap the script
			my $wrap_command;
			if ($dep_command->{'lang'} eq 'perl') {
				$wrap_command = $DEV_TOOLS_DIR."/wrap_perl ".
							$destination." ".
							$TARGET."/bin/".$dep_command->{'deprecated-name'}." ".
							$dep_command->{'new-command-name'};
			}
			elsif ($dep_command->{'name'} eq 'python') {
				$wrap_command = $DEV_TOOLS_DIR."/wrap_python ".$destination." ".$TARGET."/bin/".$dep_command->{'deprecated-name'};
			}
			
			# actually call the wrap script
			print "  ".$wrap_command."\n";
			unless ($dryrun) {
				system($wrap_command)==0 or die ("could not run $wrap_command: $!");
			}
			
		} else {
			print "  --skipping! file '".$dep_command->{'file'}."' does not exist.\n";
		}
		
		
	}
	
}

# we should be able to write an undeploy command ...
sub undeploy {
	my $commands_to_deploy = shift;
	my $dep_commands_to_deploy = shift;
	my $TARGET = shift;
	
}





