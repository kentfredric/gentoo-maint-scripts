#!/usr/bin/env perl
# ABSTRACT: Find Dependencies

use strict;
use warnings;

use Perl::PrereqScanner;
use Path::Iterator::Rule;
use Module::Metadata;
use Gentoo::Util::VirtualDepend;
use Path::Tiny qw( path );
my $sc =
  Perl::PrereqScanner->new(
    extra_scanners => [qw( Class::Load Module::Runtime Module::Load )], );
my $dir = $ARGV[0] || '.';

my $rule = Path::Iterator::Rule->new();
$rule->skip_vcs;
$rule->file;
$rule->perl_file;
my $it = $rule->iter($dir);

my $deps = {};
my $dirs = {};
while ( my $file = $it->() ) {
    *STDERR->print("Scanning $file\n");
    my $root = path($file)->absolute->relative( $ARGV[0] )->stringify;
    $root =~ s/\/.*$//;
    if ( path($root)->is_file ) {
        $root = $ARGV[0];
    }
    my $prereqs = $sc->scan_file($file)->as_string_hash;
    for my $module ( keys %{$prereqs} ) {
        $dirs->{$root}->{$module} = $file;
        $deps->{$module}->{ path($file)->parent } = $file;
    }
}
my $provided      = Module::Metadata->provides( dir => 'lib', version => 2 );
my $test_provided = Module::Metadata->provides( dir => '.',   version => 2 );
my $vdep          = Gentoo::Util::VirtualDepend->new();

sub grade_module {
    my ($module) = @_;
    if ( $vdep->has_module_override($module) ) {
        my $mod = $vdep->get_module_override($module);
        if ( $mod =~ /^virtual\/perl-(.*$)/ ) {
            return [ 'virtual', $1, $module ];
        }
        return [ 'override', $mod, $module ];
    }
    if ( $provided->{$module} ) {
        return [ 'provided', 'runtime', $module ];
    }
    if ( $test_provided->{$module} ) {
        return [ 'provided', 'test', $module ];
    }
    if ( $vdep->module_is_perl($module) ) {
        return [ 'perl', $module ];
    }
    return [ 'prereq', $module ];
}

sub color_module {
    my ($module) = @_;

    my $override = '';

    my $grade = grade_module($module);
    if ( 'virtual' eq $grade->[0] ) {
        my $modname = $module;
        $modname =~ s/::/-/g;
        if ( $grade->[1] eq $modname ) {
            $override = colored( ['green'], ' =>(v)' );
        }
        else {
            $override = colored( ['green'], ' =>[' . $grade->[1] . ']' );
        }
    }
    if ( 'override' eq $grade->[0] ) {
        $override = q{[} . $grade->[1] . q{]};
    }

    if ( 'provided' eq $grade->[0] ) {
        if ( 'runtime' eq $grade->[1] ) {
            return colored( ['magenta'], $module );
        }
        if ( 'test' eq $grade->[1] ) {
            return colored( ['red'], $module );
        }
    }
    if ( 'perl' eq $grade->[0] ) {
        return colored( ['green'], $module ) . $override;
    }
    return $module . $override;
}
my $grade_order = {
    provided => 7,
    perl     => 6,
    virtual  => 3,
    override => 3,
    prereq   => 3,
};

sub sort_modules {
    my ( $left, $right ) = @_;
    my $grade_left  = grade_module($left);
    my $grade_right = grade_module($right);

    if ( $grade_order->{ $grade_left->[0] } ==
        $grade_order->{ $grade_right->[0] } )
    {

        if (    $grade_left->[0] eq 'provided'
            and $grade_left->[1] eq $grade_right->[1] )
        {
            return $grade_left->[2] cmp $grade_right->[2];
        }
        if (    $grade_left->[0] =~ /virtual|override/
            and $grade_right->[0] =~ /virtual|override/ )
        {
            if ( $grade_left->[1] eq $grade_right->[1] ) {
                return $grade_left->[2] cmp $grade_right->[2];
            }
        }
        return $grade_left->[1] cmp $grade_right->[1];
    }
    return $grade_order->{ $grade_left->[0] }
      <=> $grade_order->{ $grade_right->[0] };
}
use Term::ANSIColor qw( colored colorstrip );
for my $dir ( sort keys %{$dirs} ) {
    printf "%s: %s\n", colored( ['green'], $dir ),
      wrap_modules(
        map { color_module($_) }
        sort { sort_modules( $a, $b ) } keys %{ $dirs->{$dir} }
      );
}

sub wrap_modules {
    my (@modules) = @_;
    my (@lines);
    my $MAX_WRAP   = 78;
    my $first_line = 0;
    my (@line_tokens);
    while (@modules) {
        push @lines, '  ' x !!( $first_line++ ) . shift @modules;
        next;
        while ( length colorstrip( join q[, ], @line_tokens ) < $MAX_WRAP
            and @modules )
        {
            push @line_tokens, shift @modules;
        }
        push @lines,
          ( '  ' x !!( $first_line++ ) ) . ( join q[, ], @line_tokens );
        @line_tokens = ();
    }
    return join qq[,\n], @lines;
}
