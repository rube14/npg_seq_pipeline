package npg_pipeline::executor::wr;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;
use File::Slurp;
use JSON;
use Readonly;
use English qw(-no_match_vars);
use Math::Random::Secure qw(irand);
use Try::Tiny;

use npg_pipeline::runfolder_scaffold;

extends 'npg_pipeline::executor';

with 'npg_pipeline::executor::options' => {
  -excludes => [qw/ no_sf_resource
                    no_bsub
                    no_array_cpu_limit
                    array_cpu_limit/ ]
};

our $VERSION = '0';

Readonly::Scalar my $VERTEX_GROUP_DEP_ID_ATTR_NAME => q[wr_group_id];
Readonly::Scalar my $DEFAULT_MEMORY                => 2000;
Readonly::Scalar my $VERTEX_JOB_PRIORITY_ATTR_NAME => q[job_priority];
Readonly::Scalar my $WR_ENV_LIST_DELIM             => q[,];
Readonly::Array  my @ENV_VARS_TO_PROPAGATE         =>
              qw/PATH PERL5LIB CLASSPATH NPG_CACHED_SAMPLESHEET_FILE/;

=head1 NAME

npg_pipeline::executor::wr

=head1 SYNOPSIS

=head1 DESCRIPTION

Submission of pipeline function definitions for execution by
L<wr workflow runner|https://github.com/VertebrateResequencing/wr>.

=cut

=head1 SUBROUTINES/METHODS

=cut

##################################################################
############## Public methods ####################################
##################################################################

=head2 execute

Creates and submits wr jobs for execution.

=cut

override 'execute' => sub {
  my $self = shift;

  my $action = 'defining';
  try {
    foreach my $function ($self->function_graph4jobs()
                               ->topological_sort()) {
      $self->_process_function($function);
    }
    $action = 'saving';
    my $json = JSON->new->canonical;
    $self->save_commands4jobs(
         map { $json->encode($_) } # convert every wr definition to JSON
         map { @{$_} }             # expand arrays of wr definitions        
         values %{$self->commands4jobs()}
                               );
    $action = 'submitting';
    $self->_submit();
  } catch {
    $self->logcroak(qq[Error $action wr jobs: $_]);
  };

  return;
};

##################################################################
############## Private methods ###################################
##################################################################

sub _process_function {
  my ($self, $function) = @_;

  my $g = $self->function_graph4jobs;
  #####
  # Need dependency group ids of upstream functions in order to set correctly
  # dependencies between wr jobs
  #
  my @depends_on = ();
  if (!$g->is_source_vertex($function)) {
    @depends_on = $self->dependencies($function, $VERTEX_GROUP_DEP_ID_ATTR_NAME);
    if (!@depends_on) {
      $self->logcroak(qq["$function" should depend on at least one job]);
    }
  }

  my $group_id = $self->_definitions4function($function, @depends_on);
  if (!$group_id) {
    $self->logcroak(q[Group dependency id should be returned]);
  }

  $g->set_vertex_attribute($function, $VERTEX_GROUP_DEP_ID_ATTR_NAME, $group_id);

  return;
}

sub _definitions4function {
  my ($self, $function_name, @depends_on) = @_;

  my $definitions = $self->function_definitions()->{$function_name};
  my $group_id = join q[-], $function_name, $definitions->[0]->identifier(), irand();
  my $outgoing_flag = $self->future_path_is_in_outgoing($function_name);
  my $log_dir = $self->log_dir4function($function_name);
  if ($outgoing_flag) {
    $log_dir = npg_pipeline::runfolder_scaffold->path_in_outgoing($log_dir);
  }

  foreach my $d (@{$definitions}) {
    my $wr_def = $self->_definition4job($function_name, $log_dir, $d);
    if (@depends_on) {
      $wr_def->{'deps'} = \@depends_on;
    }
    $wr_def->{'dep_grps'} = [$group_id];
    my @report_group = ($d->identifier(), $function_name);
    if ($self->has_job_name_prefix()) {
      unshift @report_group, $self->job_name_prefix();
    }
    $wr_def->{'rep_grp'}  = join q[-], @report_group;
    push @{$self->commands4jobs()->{'function_name'}}, $wr_def;
  }

  return $group_id;
}

sub _definition4job {
  my ($self, $function_name, $log_dir, $d) = @_;

  my $def = {};

  $def->{'memory'} = $d->has_memory() ? $d->memory() : $DEFAULT_MEMORY;
  $def->{'memory'} .= q[M];

  # priority needs to be a number, rather than string, in JSON for wr,hence the addition
  $def->{'priority'} = 0 + $self->function_graph4jobs->get_vertex_attribute(
                           $function_name, $VERTEX_JOB_PRIORITY_ATTR_NAME);

  if ($d->has_num_cpus()) {
    use warnings FATAL => qw(numeric);
    $def->{'cpus'} = int $d->num_cpus()->[0];
  }

  my $log_file = sub {
    my $log_name = join q[-], $function_name, $d->created_on(),
      $d->has_composition() ? $d->composition()->freeze2rpt () : $d->identifier();
    $log_name   .= q[.out];
    return join q[/], $log_dir, $log_name;
  };

  $def->{'cmd'} = join q[ ], q[(], $d->command(), q[)], q[2>&1], q[|], q[tee], q["]. $log_file->() . q["];

  return $def;
}

sub _wr_add_command {
  my $self = shift;

  # If needed, in future, these options can be passed from the command line
  # or read from a conf. file.

  # Explicitly pass the pipeline's environment to jobs
  my @env_list = ();
  foreach my $var_name (sort @ENV_VARS_TO_PROPAGATE) {
    my $value = $ENV{$var_name};
    if (defined $value && $value ne q[]) {
      push @env_list, "${var_name}=${value}";
    }
  }
  my $stack = join $WR_ENV_LIST_DELIM, @env_list;

  my @common_options = (
          '--cwd'        => '/tmp',
          '--disk'       => 0,
          '--override'   => 2,
          '--retries'    => 0,
          '--env'        => q['] . $stack . q['],
                       );

  return join q[ ], qw/wr add/,
                    @common_options,
                    '-f', $self->commands4jobs_file_path();
}

sub _submit {
  my $self = shift;

  my $cmd = $self->_wr_add_command();
  $self->info(qq[Command to use with wr: $cmd]);
  if ($self->interactive) {
    $self->info(q[Interactive mode, commands not added to wr]);
  } else {
    if (system($cmd) == 0) {
      $self->info(q[Commands successfully added to wr]);
    } else {
      my $e = $CHILD_ERROR || q[];
      $self->logcroak(qq[Error $e running "$cmd"]);
    }
  }
  return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item Moose

=item MooseX::StrictConstructor

=item namespace::autoclean

=item Readonly

=item English

=item JSON

=item Math::Random::Secure

=item Try::Tiny

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

=over

=item Marina Gourtovaia

=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2018 Genome Research Ltd.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
