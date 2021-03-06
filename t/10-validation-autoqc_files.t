use strict;
use warnings;
use Test::More tests => 14;
use Log::Log4perl;
use Moose::Meta::Class;
use WTSI::NPG::iRODS;

Log::Log4perl::init_once('./t/log4perl_test.conf');

use_ok('npg_pipeline::validation::autoqc_files');

my $qc  = Moose::Meta::Class->create_anon_class(roles => [qw/npg_testing::db/])
                            ->new_object()->create_test_db(q[npg_qc::Schema]);
my $logger = Log::Log4perl->get_logger('dnap');

# These tests do not access iRODS, but we'd better be on a safe side
local $ENV{'IRODS_ENVIRONMENT_FILE'} =
  $ENV{'WTSI_NPG_iRODS_Test_IRODS_ENVIRONMENT_FILE'} || 'DUMMY_VALUE';
my $irods = WTSI::NPG::iRODS->new(strict_baton_version => 0, logger => $logger);

my $validator = npg_pipeline::validation::autoqc_files->new
       (id_run         => 1234,
        irods          => $irods,
        logger         => $logger,
        collection     => '/test/collection',
        skip_checks    => [qw/adaptor samtools_stats+phix+human/],
        file_extension => q[cram],
        _qc_schema     => $qc);

isa_ok($validator, 'npg_pipeline::validation::autoqc_files');

my $expected = {'adaptor' => [], 'samtools_stats' => [qw/phix human/]};
is_deeply($validator->_parse_excluded_checks(), $expected, 'excluded checks parsed correctly');

$validator = npg_pipeline::validation::autoqc_files->new
       (id_run         => 1234,
        irods          => $irods,
        logger         => $logger,
        collection     => '/test/collection',
        file_extension => q[cram],
        _qc_schema     => $qc);
is_deeply($validator->_parse_excluded_checks(), {}, 'excluded checks not set');

is($validator->_query_to_be_skipped(
  {'check' => 'pig'}, $expected), 0, 'no skip');
is($validator->_query_to_be_skipped(
  {'check' => 'pig', 'subset' => 'phix'}, $expected), 0, 'no skip');
is($validator->_query_to_be_skipped(
  {'check' => 'adaptor'}, $expected), 1, 'skip');
is($validator->_query_to_be_skipped(
  {'check' => 'adaptor', 'subset' => 'all'}, $expected), 1, 'skip');
is($validator->_query_to_be_skipped(
  {'check' => 'adaptor'}, {}), 0, 'no skip');
is($validator->_query_to_be_skipped(
  {'check' => 'samtools_stats'}, $expected), 0, 'no skip');
is($validator->_query_to_be_skipped(
  {'check' => 'samtools_stats', 'subset' => 'target'}, $expected), 0, 'no skip');
is($validator->_query_to_be_skipped(
  {'check' => 'samtools_stats', 'subset' => 'phix'}, $expected), 1, 'skip');
is($validator->_query_to_be_skipped(
  {'check' => 'samtools_stats', 'subset' => 'human'}, $expected), 1, 'skip');
is($validator->_query_to_be_skipped(
  {'check' => 'samtools_stats', 'subset' => 'human'}, {}), 0, 'no skip');

1;
