use strict;
use warnings;
use Test::More tests => 32;
use Test::Exception;
use Log::Log4perl qw(:levels);
use t::util;

my $util = t::util->new();
my $tmp_dir = $util->temp_directory();
Log::Log4perl->easy_init({layout => '%d %-5p %c - %m%n',
                          level  => $DEBUG,
                          file   => join(q[/], $tmp_dir, 'logfile'),
                          utf8   => 1});

use_ok('npg_pipeline::function::log_files_archiver');

my $rfpath = $util->analysis_runfolder_path();
my $orfpath = $rfpath;
$orfpath =~ s/analysis/outgoing/xms;

{
  my $a  = npg_pipeline::function::log_files_archiver->new(
    run_folder        => q{123456_IL2_1234},
    runfolder_path    => $rfpath,
    recalibrated_path => $rfpath,
    id_run            => 1234,
    timestamp         => q{20090709-123456},
  );
  isa_ok ($a , q{npg_pipeline::function::log_files_archiver});

  my $da = $a->create();
  ok ($da && @{$da} == 1, 'an array with one definition is returned');
  my $d = $da->[0];
  isa_ok($d, q{npg_pipeline::function::definition});

  is ($d->created_by, q{npg_pipeline::function::log_files_archiver},
    'created_by is correct');
  is ($d->created_on, $a->timestamp, 'created_on is correct');
  is ($d->identifier, 1234, 'identifier is set correctly');
  is ($d->job_name, q{publish_illumina_logs_1234_20090709-123456},
    'job_name is correct');
  is ($d->command,
    qq{npg_publish_illumina_logs.pl --runfolder_path $orfpath --id_run 1234},
    'command is correct');
  is ($d->command_preexec, qq{[ -d '$orfpath' ]}, 'preexec command');
  ok (!$d->has_composition, 'composition not set');
  ok (!$d->excluded, 'step not excluded');
  ok (!$d->has_num_cpus, 'number of cpus is not set');
  ok (!$d->has_memory,'memory is not set');
  is ($d->queue, 'lowload', 'queue');
  is ($d->fs_slots_num, 1, 'one fs slot is set');
  ok ($d->reserve_irods_slots, 'iRODS slots to be reserved');
  lives_ok {$d->freeze()} 'definition can be serialized to JSON';

  $a  = npg_pipeline::function::log_files_archiver->new(
    run_folder        => q{123456_IL2_1234},
    runfolder_path    => $rfpath,
    recalibrated_path => $rfpath,
    id_run            => 1234,
    no_irods_archival => 1,
  );
  ok ($a->no_irods_archival, q{archival switched off});
  $da = $a->create();
  ok ($da && @{$da} == 1, 'an array with one definition is returned');
  $d = $da->[0];
  isa_ok($d, q{npg_pipeline::function::definition});
  is ($d->created_by, q{npg_pipeline::function::log_files_archiver},
    'created_by is correct');
  is ($d->created_on, $a->timestamp, 'created_on is correct');
  is ($d->identifier, 1234, 'identifier is set correctly');
  ok ($d->excluded, 'step is excluded');

  $a  = npg_pipeline::function::log_files_archiver->new(
    run_folder        => q{123456_IL2_1234},
    runfolder_path    => $rfpath,
    recalibrated_path => $rfpath,
    id_run            => 1234,
    local             => 1,
  );
  ok ($a->no_irods_archival, q{archival switched off});
  $da = $a->create();
  ok ($da && @{$da} == 1, 'an array with one definition is returned');
  $d = $da->[0];
  isa_ok($d, q{npg_pipeline::function::definition});
  is ($d->created_by, q{npg_pipeline::function::log_files_archiver},
    'created_by is correct');
  is ($d->created_on, $a->timestamp, 'created_on is correct');
  is ($d->identifier, 1234, 'identifier is set correctly');
  ok ($d->excluded, 'step is excluded');
}

1;
