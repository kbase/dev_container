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
use JSON;
use Data::Dumper;
use File::Copy qw(copy);
use File::Path qw(make_path);

my ($jsonCommandsFile,$irisCommandsFile,$dryrun,$debug,$scriptTarget,$copyScripts,$TARGET,$DEV_TOOLS_DIR);

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
	"scriptTarget=s"		=>	\$scriptTarget,
	"devContainerToolsDir=s"	=>	\$DEV_TOOLS_DIR,
	"dryrun"			=>	\$dryrun,
	"debug+" 			=>	\$debug,
	"copyScripts!" 			=>	\$copyScripts,
);

die "--jsonCommandsFile required!" unless ($jsonCommandsFile);

warn $TARGET;
# need to set this here, in case $TARGET was specified command-line
$scriptTarget="$TARGET/plbin/" unless ($scriptTarget);

my $commandsJson = read_file($jsonCommandsFile) or die "couldn't read $jsonCommandsFile: $!";

my $json=JSON->new;

my $commands = $json->decode($commandsJson);

my ($commands_to_deploy, $iris_command_list) = process_command_list($commands->{'cli'}->{'commands'});
my ($dep_commands_to_deploy, $iris_dep_command_list) = process_deprecated_command_list($commands->{'cli'}->{'deprecated-commands'});

# should combine these into one?
write_iris_groups($commands->{'iris'},$irisCommandsFile) if ($irisCommandsFile and !$dryrun);
write_iris_commands($iris_command_list,$iris_dep_command_list) if ($irisCommandsFile and !$dryrun);

deploy_and_wrap_commands($commands_to_deploy,$dep_commands_to_deploy,$TARGET,$DEV_TOOLS_DIR);


# dump iris section to COMMANDS
# wrap cli commands
# wrap deprecated cli commands

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

	open (IRISCOMMANDSFILE,'>>',$irisCommandsFile) or die "couldn't open $irisCommandsFile: $!";
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
	
	foreach my $command_name (keys %$commands_to_deploy)
	{
		my $command=$commands_to_deploy->{$command_name};
		# 1 deploy the command by copying it over, then 2
		print "installing ".$command->{'name'}."\n";
		if(-f $command->{'file'}) {
			
			if ($command->{'lang'} eq 'perl') {
				my $destination = $scriptTarget.$command->{'basename'};
				if ($copyScripts and !$dryrun) {
					warn "  warning, overwriting '".$destination."'\n" if(-f $destination);
					copy($command->{'file'},$destination) or die "copy to $destination failed: $!";
				} elsif ($dryrun) {
					warn "  warning, would overwrite '".$destination."'\n" if(-f $destination);
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





