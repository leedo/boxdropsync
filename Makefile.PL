use 5.010001;

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'App::Boxdropsync',
  VERSION_FROM => 'lib/App/Boxdropsync.pm',
  ABSTRACT     => 'Dropbox replacement',
  AUTHOR       => 'Lee Aylward <lee@laylward.com>',
  LICENSE      => 'artistic_2',
  PREREQ_PM    => {
    "AnyEvent"      => 0,
    "Mac::FSEvents" => 0,
    "File::Which"   => 0,
  },
  META_MERGE   => {
    requires  => {perl => '5.010001'},
    no_index => {directory => ['t']}
  },
  EXE_FILES => ['bin/boxdropsync'],
  test => {TESTS => 't/*.t'}
);
