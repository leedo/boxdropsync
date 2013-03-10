package App::Boxdropsync;

use v5.10;
use AnyEvent;
use AnyEvent::Util ();
use Mac::FSEvents;
use File::Which ();
use URI::Escape ();

our $VERSION = "0.01";

sub new {
  my ($class, %args) = @_;

  # required 
  die "local option is required"  unless defined $args{local};
  die "remote option is required" unless defined $args{remote};

  # setup defaults
  $args{interval} = 60            unless defined $args{interval};
  $args{log} = "/dev/null"        unless defined $args{log};
  $args{opts} = "-a -q --delete"  unless defined $args{opts};

  my $rsync = File::Which::which("rsync");
  die "rsync not found in path"   unless defined $rsync;
  
  $args{local} =~ s/^~/$ENV{HOME}/;

  # make sure all paths end with /
  for (qw/local remote screenshots url/) {
    $args{$_} = "$args{$_}/" unless $args{$_} =~ m{/$};
  }

  bless {
    local    => $args{local},
    remote   => $args{remote},
    url      => $args{url},
    opts     => [split " ", $args{opts}],
    interval => $args{interval},
    log      => $args{log},
    rsync    => $rsync,
    cv       => AE::cv,
    cmds     => [],
    screenshots => $args{screenshots},
  }, $class;
}

sub log {
  my ($self, $line) = @_;
  open my $fh, ">>", $self->{log} or die $!;
  print $fh "$line\n";
}

sub run {
  my $self = shift;

  $self->log("syncing $self->{local} to $self->{remote}");
  $self->log("logging to $self->{log}");

  my $fs = $self->{fs} = Mac::FSEvents->new({
    path    => $self->{local},
    latency => 1,
  });

  $self->{io} = AE::io $fs->watch, 0, sub {
    () for $fs->read_events;
    $self->{pushing} = 1;
    $self->rsync($self->{local}, $self->{remote},
      cb => sub { $self->{pushing} = 0 }
    );
  };

  $self->screenshots if $self->{screenshots};

  $self->{t} = AE::timer 0, $self->{interval}, sub {
    return if $self->{pushing}; # don't pull changes while pushing
    $self->rsync($self->{remote}, $self->{local}); # reverse
  };

  for (qw/TERM INT QUIT/) {
    $self->log("shutting down");
    $self->{s} = AE::signal $_ => sub { $self->{cv}->end };
  }

  $self->{cv}->begin;
  $self->{cv}->recv;
}

sub screenshots {
  my ($self, $event) = @_;
  my $dir = "$ENV{HOME}/Desktop";

  $self->log("syncing screenshots from $dir to $self->{screenshots}");

  my $fs = $self->{ss_fs} = Mac::FSEvents->new({
    path    => $dir,
    latency => 1,
  });

  $self->{ss_io} = AE::io $fs->watch, 0, sub {
    () for $fs->read_events;
    # wait a second so files are written
    my $t; $t = AE::timer 1, 0, sub {
      undef $t;
      opendir my $dh, $dir;
      while (my $file = readdir $dh) {
        next unless $file =~ m{^Screen Shot[^/]+\.png};
        $self->scp("$dir/$file", $self->{screenshots},
          cb => sub {
            unlink "$dir/$file";
            $self->run_cmd(["say", "paste it!"]);
          }
        );
        my $copy = $self->{url} . URI::Escape::uri_escape($file);
        $self->run_cmd(["pbcopy"], stdin => \$copy);
      }
    };
  };
}

sub run_cmd {
  my ($self, $command, %args) = @_;

  $self->{cv}->begin;
  $self->log("running " . join " ", @$command);

  my $cv = AnyEvent::Util::run_cmd $command,
    "<" => ($args{stdin} || "/dev/null"),
    "1>" => $self->{log},
    "2>" => $self->{log};

  $cv->cb(sub {
    $args{cb}->() if $args{cb};
    $self->{cv}->end;
    $self->{cmds} = [ grep { $_ != $cv } @{$self->{cmds}} ];
    $self->log("$command->[0] complete");
  });

  push @{$self->{cmds}}, $cv;
}

sub scp {
  my ($self, $source, $dest, %args) = @_;
  $self->run_cmd([ 'scp', $source, $dest ], %args);
}

sub rsync {
  my ($self, $source, $dest, %args) = @_;
  $self->run_cmd([ 'rsync', @{$self->{opts}}, $source, $dest ], %args);
}

1;
