#!/usr/bin/perl

# grabber for fetching data from mirobots

# Copyright 2018 Michael Schlenstedt, michael@loxberry.de
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

##########################################################################
# Modules
##########################################################################

use LoxBerry::System;
use LoxBerry::Log;
use JSON qw( decode_json ); 
use File::Copy;
use Getopt::Long;
use LoxBerry::IO;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = "0.0.1";

#my $cfg             = new Config::Simple("$home/config/system/general.cfg");
#my $lang            = $cfg->param("BASE.LANG");
#my $installfolder   = $cfg->param("BASE.INSTALLFOLDER");
#my $miniservers     = $cfg->param("BASE.MINISERVERS");
#my $clouddns        = $cfg->param("BASE.CLOUDDNS");

my $cfg         = new Config::Simple("$lbpconfigdir/mirobot2lox.cfg");
my $getdata     = $cfg->param("MAIN.GETDATA");
my $udpport     = $cfg->param("MAIN.UDPPORT");
my $ms          = $cfg->param("MAIN.MS");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new ( 	name => 'MiRobo2Lox-NG',
			filename => "$lbplogdir/mirobot2lox.log",
			append => 1,
);

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

if ($log->loglevel() eq "7") {
	LOGSTART "MiRobo2Lox-NG GRABBER process started";
	LOGDEB "This is $0 Version $version";
}

# Exit if fetching is not active
if ( !$getdata ) {
	LOGWARN "Fetching data is not active. Exit.";
	&exit;
}

LOGINF "Fetching Data from Robots";

# Clean HTML
open (F,">$lbplogdir/robotsdata.txt");
	print F "";
close (F);

for (my $i=1; $i<6; $i++) {

	if ( !$cfg->param("ROBOT$i" . ".ACTIVE") ) {
		LOGINF "Robot $i is not active - skipping...";
		next;
	}

	my $ip = $cfg->param( "ROBOT$i" . ".IP");
	my $token = $cfg->param( "ROBOT$i" . ".TOKEN");

	LOGINF "Fetching Status Data for Robot $i...";
	LOGINF "$lbpbindir/mirobo_wrapper.sh $ip $token status none 2";
	my $json = `$lbpbindir/mirobo_wrapper.sh $ip $token status none 2`;
	my $djson1 = decode_json( $json );
	
	# Unknown state
	if ( $djson1->{'state'} > 14 ) {
		$djson1->{'state'} = "16";
	}
	
	# Unknown error
	if ( $djson1->{'error_code'} > 20 ) {
		$djson1->{'error_code'} = "21";
	}

	# If batt is fully charged in Dock, set state to 15
	if ( $djson1->{'state'} eq "8" && $djson1->{'battery'} eq "100" ) {
		$djson1->{'state'} = "15";
	}

	LOGINF "Fetching Consumables Data for Robot $i...";
	LOGINF "$lbpbindir/mirobo_wrapper.sh $ip $token consumable_status none 2";
	$json = `$lbpbindir/mirobo_wrapper.sh $ip $token consumable_status none 2`;
	my $djson2 = decode_json( $json );

	# Now
	my $thuman = localtime();
	my $t = time();

	# UDP
	if ( $cfg->param("MAIN.SENDUDP") ) {
		my %data_to_send;
		$data_to_send{'now_human'} = $thuman;
		$data_to_send{'now'} = $t;
		$data_to_send{'state_code'} = $djson1->{'state'};
		$data_to_send{'state_txt'} = $L{"GRABBER.STATE$djson1->{'state'}"};
		$data_to_send{'map_present'} = $djson1->{'map_present'};
		$data_to_send{'in_cleaning'} = $djson1->{'in_cleaning'};
		$data_to_send{'fan_power'} = $djson1->{'fan_power'};
		$data_to_send{'msg_seq'} = $djson1->{'msg_seq'};
		$data_to_send{'battery'} = $djson1->{'battery'};
		$data_to_send{'msg_ver'} = $djson1->{'msg_ver'};
		$data_to_send{'clean_time'} = $djson1->{'clean_time'};
		$data_to_send{'dnd_enabled'} = $djson1->{'dnd_enabled'};
		$data_to_send{'clean_area'} = $djson1->{'clean_area'};
		$data_to_send{'error_code'} = $djson1->{'error_code'};
		$data_to_send{'error_txt'} = $L{"GRABBER.ERROR$djson1->{'error_code'}"};
		$data_to_send{'main_brush_work_time'} = $djson2->{'main_brush_work_time'};
		$data_to_send{'sensor_dirty_time'} = $djson2->{'sensor_dirty_time'};
		$data_to_send{'side_brush_work_time'} = $djson2->{'side_brush_work_time'};
		$data_to_send{'filter_work_time'} = $djson2->{'filter_work_time'};
	
		my $response = LoxBerry::IO::msudp_send($ms, $udpport, "MiRobot$i", %data_to_send);
		if (! $response) {
			LOGERR "Error sending UDP data from Robot$i to MS$ms";
    		} else {
			LOGINF "Sending UDP data from Robot$i to MS$ms successfully.";
		}
	}

	# HTML
	open (F,">>$lbplogdir/robotsdata.txt");
		print F "MiRobot$i: now_human=$thuman\n";
		print F "MiRobot$i: now=$t\n";
		print F "MiRobot$i: state_code=$djson1->{'state'}\n";
		print F "MiRobot$i: state_txt=" . $L{"GRABBER.STATE$djson1->{'state'}"} . "\n";
		print F "MiRobot$i: map_present=$djson1->{'map_present'}\n";
		print F "MiRobot$i: in_cleaning=$djson1->{'in_cleaning'}\n";
		print F "MiRobot$i: fan_power=$djson1->{'fan_power'}\n";
		print F "MiRobot$i: msg_seq=$djson1->{'msg_seq'}\n";
		print F "MiRobot$i: battery=$djson1->{'battery'}\n";
		print F "MiRobot$i: msg_ver=$djson1->{'msg_ver'}\n";
		print F "MiRobot$i: clean_time=$djson1->{'clean_time'}\n";
		print F "MiRobot$i: dnd_enabled=$djson1->{'dnd_enabled'}\n";
		print F "MiRobot$i: clean_area=$djson1->{'clean_area'}\n";
		print F "MiRobot$i: error_code=$djson1->{'error_code'}\n";
		print F "MiRobot$i: error_txt=" . $L{"GRABBER.ERROR$djson1->{'error_code'}"} . "\n";
		print F "MiRobot$i: main_brush_work_time=$djson2->{'main_brush_work_time'}\n";
		print F "MiRobot$i: sensor_dirty_time=$djson2->{'sensor_dirty_time'}\n";
		print F "MiRobot$i: side_brush_work_time=$djson2->{'side_brush_work_time'}\n";
		print F "MiRobot$i: filter_work_time=$djson2->{'filter_work_time'}\n";
	close (F);

	# VTI
	my %data_to_vti;
	$data_to_vti{"MiRobot$i state"} = $L{"GRABBER.STATE$djson1->{'state'}"};
	$data_to_vti{"MiRobot$i error"} = $L{"GRABBER.ERROR$djson1->{'error_code'}"};
	my $response = LoxBerry::IO::mshttp_send_mem($ms, %data_to_vti);

}

# End
&exit;
exit;


# SUB: Exit
sub exit
{
	if ($log->loglevel() eq "7") {
		LOGEND "Exit. Bye.";
	}
	exit;
}