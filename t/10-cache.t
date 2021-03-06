use strict;
use warnings;
use Test::More tests => 37;
use Test::Exception;
use File::Temp qw/tempdir/;
use t::dbic_util;

use st::api::lims::ml_warehouse;
use st::api::lims;

use_ok('npg_pipeline::cache');

local $ENV{http_proxy} = 'http://wibble';
local $ENV{no_proxy}   = q[];

is(join(q[ ], npg_pipeline::cache->env_vars()),
  'NPG_CACHED_SAMPLESHEET_FILE',
  'names of env. variables that can be set by the module');

my $wh_schema = t::dbic_util->new()->test_schema_mlwh('t/data/fixtures/mlwh');

my $lims_driver = st::api::lims::ml_warehouse->new(
                     mlwh_schema      => $wh_schema,
                     id_flowcell_lims => undef,
                     flowcell_barcode => 'HBF2DADXX'
                                                  );
 my @lchildren = st::api::lims->new(
                     id_flowcell_lims => undef,
                     flowcell_barcode => 'HBF2DADXX',
                     driver           => $lims_driver,
                     driver_type      => 'ml_warehouse'
                                   )->children;

local $ENV{NPG_CACHED_SAMPLESHEET_FILE} = '';

for my $type (qw/warehouse mlwarehouse/) {
  my $method = $type . '_driver_name';
  my $expected = $type eq 'mlwarehouse' ? 'ml_warehouse' : $type;
  is(npg_pipeline::cache->$method, $expected, "driver name for $type");
}

{
  my $tempdir = tempdir( CLEANUP => 1);

  my $cache = npg_pipeline::cache->new(id_run           => 12376,
                                       mlwh_schema      => $wh_schema,
                                       id_flowcell_lims => 'XXXXXXXX',
                                       cache_location   => $tempdir);
  is( $cache->lims_driver_type(), 'ml_warehouse', 'correct default driver');

  $cache = npg_pipeline::cache->new(id_run           => 12376,
                                    mlwh_schema      => $wh_schema,
                                    lims_driver_type => 'ml_warehouse',
                                    id_flowcell_lims => 'XXXXXXXX',
                                    cache_location   => $tempdir);
  throws_ok { $cache->lims }
    qr/No record retrieved for st::api::lims::ml_warehouse id_flowcell_lims XXXXXXXX/,
    'cannot retrieve lims objects';

  $cache = npg_pipeline::cache->new(id_run           => 12376,
                                    mlwh_schema      => $wh_schema,
                                    lims_driver_type => 'ml_warehouse',
                                    cache_location   => $tempdir);
  throws_ok { $cache->lims }
    qr/Neither flowcell barcode nor lims flowcell id is known/,
    'cannot retrieve lims objects';

  my $clims;

  $cache = npg_pipeline::cache->new(id_run           => 12376, 
                                    mlwh_schema      => $wh_schema,
                                    lims_driver_type => 'ml_warehouse',
                                    flowcell_barcode => 'HBF2DADXX',
                                    cache_location   => $tempdir);
  lives_ok { $clims = $cache->lims() } 'can retrieve lims objects';
  ok( $clims, 'lims objects returned');
  is( scalar @{$clims}, 2, 'two lims objects returned');
  is( $clims->[0]->driver_type, 'ml_warehouse', 'correct driver type');

  eval { require st::api::lims::warehouse; };
  SKIP: {
    skip 'Old warehouse is now obsolete', 7 if $@;

  my $oldwh_schema = t::dbic_util->new()->test_schema_wh('t/data/fixtures/wh');
  $cache = npg_pipeline::cache->new(id_flowcell_lims => '3980331130775',
                                    wh_schema        => $oldwh_schema,
                                    id_run           => 12376,
                                    lims_driver_type => 'warehouse',
                                    cache_location   => $tempdir);
  is( $cache->lims_driver_type(), 'warehouse', 'driver as set');
  lives_ok { $clims = $cache->lims() } 'can retrieve lims objects';
  ok( $clims, 'lims objects returned');
  is( scalar @{$clims}, 1, 'one lims object returned');
  is( $clims->[0]->driver_type, 'warehouse', 'correct driver type');

  $cache = npg_pipeline::cache->new(id_flowcell_lims => '9870331130775',
                                    wh_schema        => $oldwh_schema,
                                    id_run           => 12376,
                                    lims_driver_type => 'warehouse',
                                    cache_location   => $tempdir);
  throws_ok { $clims = $cache->lims() }
    qr/EAN13 barcode checksum fail for code 9870331130775/,
    'cannot retrieve lims objects';

  $cache = npg_pipeline::cache->new(id_flowcell_lims => '5260271901788',
                                    wh_schema        => $oldwh_schema,
                                    id_run           => 12376,
                                    lims_driver_type => 'warehouse',
                                    cache_location   => $tempdir);
  throws_ok { $clims = $cache->lims() }
    qr/Single tube not found from barcode 271901/,
    'cannot retrieve lims objects';
  } # end skip
}

{
  my $tempdir = tempdir( CLEANUP => 1);
  my $ss_path = join q[/],$tempdir,'ss.csv';
  my $cache = npg_pipeline::cache->new(
      id_run      => 12376,
      mlwh_schema => $wh_schema,
      lims        => \@lchildren,
      samplesheet_file_path => $ss_path);

  isa_ok($cache, 'npg_pipeline::cache');
  lives_ok { $cache->_samplesheet() } 'samplesheet generated';
  ok(-e $ss_path, 'samplesheet file exists');
}

{
  my $tempdir = tempdir( CLEANUP => 1);
  my $cache_dir = join q[/], $tempdir, 'metadata_cache_12376';
  mkdir $cache_dir;
  my $cache = npg_pipeline::cache->new(id_run         => 12376,
                                       mlwh_schema    => $wh_schema,
                                       lims           => \@lchildren,
                                       cache_location => $tempdir);
  isa_ok ($cache, 'npg_pipeline::cache');
  lives_ok {$cache->setup} 'no error creating the cache';
  ok (-e $cache_dir.'/samplesheet_12376.csv', 'samplesheet is present');

  sleep(1);
  $cache = npg_pipeline::cache->new(id_run         => 12376,
                                    mlwh_schema    => $wh_schema,
                                    lims           => \@lchildren,
                                    set_env_vars   => 1,
                                    cache_location => $tempdir);
  is ($cache->set_env_vars, 1, 'set_env_vars is set to true');
  mkdir "$tempdir/metadata_cache_12376";
  lives_ok {$cache->setup}
    'no error creating a new cache and setting env vars';
  my @messages = @{$cache->messages};
  is (scalar @messages, 1, 'one message saved') or diag explain $cache->messages;

  my $ss = join q[/], $cache_dir, 'samplesheet_12376.csv';
  is ($ENV{NPG_CACHED_SAMPLESHEET_FILE}, $ss,
    'NPG_CACHED_SAMPLESHEET_FILE is set correctly');
  is (pop @messages, qq[NPG_CACHED_SAMPLESHEET_FILE is set to $ss],
    'message about setting NPG_CACHED_SAMPLESHEET_FILE is saved');
}

$lims_driver = st::api::lims::ml_warehouse->new(
                     mlwh_schema      => $wh_schema,
                     id_run           => 12376,
                     id_flowcell_lims => 35053,
                     flowcell_barcode => 'undef'
                                               );
@lchildren = st::api::lims->new(
                     id_run           => 12376,
                     id_flowcell_lims => 35053,
                     flowcell_barcode => undef,
                     driver           => $lims_driver,
                     driver_type      => 'ml_warehouse'
                               )->children;

{
  my $tempdir = tempdir( CLEANUP => 1);
  my $cache_dir = join q[/], $tempdir, 'metadata_cache_12376';
  mkdir $cache_dir;
  local $ENV{NPG_CACHED_SAMPLESHEET_FILE} = 't/data/cache/my_samplesheet_12376.csv';
  my $cache = npg_pipeline::cache->new(id_run         => 12376,
                                       mlwh_schema    => $wh_schema,
                                       lims           => \@lchildren,
                                       set_env_vars   => 1,
                                       cache_location => $tempdir);
  lives_ok {$cache->setup();} 'no error';
  my $sh = join(q[/], $cache_dir, 'samplesheet_12376.csv');
  ok (-e $sh, 'renamed samplesheet copied');
  is ($ENV{NPG_CACHED_SAMPLESHEET_FILE}, $sh, 'NPG_CACHED_SAMPLESHEET_FILE is set');

  local $ENV{NPG_CACHED_SAMPLESHEET_FILE} = 't/data/cache/my_samplesheet_12376.csv';
  $cache = npg_pipeline::cache->new(id_run         => 12376,
                                    mlwh_schema    => $wh_schema,
                                    lims           => \@lchildren,
                                    set_env_vars   => 1,
                                    cache_location => $tempdir);
  lives_ok {$cache->setup();} 'no error';
  ok (-e $sh, 'standard samplesheet exists');
  my @moved = glob($sh . '_moved_*');
  is (scalar @moved, 1, 'moved file exists');
  is ($ENV{NPG_CACHED_SAMPLESHEET_FILE}, $sh, 'NPG_CACHED_SAMPLESHEET_FILE is set');
}

subtest 'alternative driver type: ml_warehouse_fc_cache' => sub {
  plan tests => 6;

  my $dir = tempdir( CLEANUP => 1);
  my $rs = $wh_schema->resultset('IseqProductMetric')->search({id_run => 12376});
  is($rs->count, 0, 'no product rows for run 12376');
  my $cache = npg_pipeline::cache->new(
                                    id_run            => 12376,
                                    mlwh_schema       => $wh_schema,
                                    lims_driver_type  => 'ml_warehouse_fc_cache',
                                    cache_location    => $dir);
  throws_ok { $cache->lims } qr/No record retrieved for st::api::lims::ml_warehouse_fc_cache/,
    'no records for the run - error';
  $rs->create({id_run => 12376, position => 1});
  throws_ok { $cache->lims } qr/No record retrieved for st::api::lims::ml_warehouse_fc_cache/,
    'records for the run are not linked to the LIMs table - error';
  $wh_schema->resultset('IseqProductMetric')->search({id_run => 12376})
    ->first()->update({'id_iseq_flowcell_tmp' => 20301});
  my $lims;
  lives_ok { $lims = $cache->lims } 'records retrieved';
  is (@{$lims}, 1, 'records for one lane retrieved');
  is ($lims->[0]->library_type, 'Standard', 'correct library type');
};

1;
