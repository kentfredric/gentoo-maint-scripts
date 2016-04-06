package My::Git::Wrapper;
use strict;
use warnings;

use File::chdir;
use Git::Wrapper            ();
use Git::Wrapper::Exception ();
use parent 'Git::Wrapper';

sub RUN_DIRECT {
    my ( $self, $cmd, @args ) = @_;
    my ( $parts, $stdin ) = Git::Wrapper::_parse_args( $cmd, @args );
    my (@cmd) = ( $self->git, @{$parts} );
    local $CWD = $self->dir unless $cmd eq 'clone';
    system(@cmd);
    if ($?) {
        die Git::Wrapper::Exception->new(
            output => [],
            error  => [],
            status => $? >> 8,
        );
    }
    return $?;
}

1;
