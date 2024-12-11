use MONKEY-SEE-NO-EVAL;

class File::Ignore {
    class Rule {
        grammar Parser {
            token TOP {
                [ $<negated>='!' ]?
                [ $<leading>='/' ]?
                <path-part>+ % '/'
                [ $<trailing>='/' ]?
            }

            proto token path-part { * }
            token path-part:sym<**>      { <sym> }
            token path-part:sym<matcher> {
                :my $*FINAL;
                <matcher>+ {}
                [<?before '/'? $> { $*FINAL = True }]?
            }

            proto token matcher    { * }
            token matcher:sym<*>   { <sym> }
            token matcher:sym<?>   { <sym> }
            token matcher:sym<[]>  { '[' [$<negate>='!']? <( <-[\]]>+ )> ']' }
            token matcher:sym<lit> { <-[/*?[]>+ }
        }

        class RuleCompiler {
            method TOP($/) {
                make Rule.new(
                    pattern => EVAL('/' ~
                                    ($<leading> ?? '^' !! '') ~
                                    $<path-part>.map(*.ast).join(' ')  ~
                                    '<?before "/" | $> /'),
                    negated => ?$<negated>,
                    directory-only => ?$<trailing>
                );
            }

            method path-part:sym<matcher>($/) {
                make $<matcher>.map(*.ast).join(' ') ~ ($*FINAL ?? "" !! " '/'");
            }

            method path-part:sym<**>($/) {
                make Q{[ <-[/]>+ [ '/' | $ ] ]*};
            }

            method matcher:sym<*>($/) {
                make '<-[/]>*';
            }

            method matcher:sym<?>($/) {
                make '<-[/]>';
            }

            method matcher:sym<[]>($/) {
                make '<' ~
                    ($<negate> ?? '-' !! '') ~
                    '[' ~
                    $/.subst('\\', '\\\\', :g).subst(/. <( '-' )> ./, '..', :g) ~
                    ']-[/]>';
            }

            method matcher:sym<lit>($/) {
                make "'$/.subst('\\', '\\\\', :g).subst('\'', '\\\'', :g)'";
            }
        }

        has Regex $.pattern;
        has Bool $.directory-only;
        has Bool $.negated;

        method parse(Str() $rule) {
            with Parser.parse($rule, :actions(RuleCompiler)) {
                .ast;
            }
            else {
                die "Could not parse ignore rule $rule";
            }
        }
    }

    has Rule @!rules;

    submethod BUILD(:@rules!) {
        @!rules = @rules.map({ Rule.parse($_) });
    }

    method parse(Str() $ignore-spec) {
        File::Ignore.new(rules => $ignore-spec.lines.grep(* !~~ /^ [ '#' | \s*$ ]/))
    }

    method ignore-file(Str() $path) {
        my $seeking-negation = False;
        for @!rules {
            if $seeking-negation {
                next unless .negated;
                $seeking-negation = False if .pattern.ACCEPTS($path);
            }
            else {
                next if .directory-only | .negated;
                $seeking-negation = True if .pattern.ACCEPTS($path);
            }
        }
        $seeking-negation
    }

    method ignore-directory(Str() $path) {
        my $seeking-negation = False;
        for @!rules {
            if $seeking-negation {
                next unless .negated;
                $seeking-negation = False if .pattern.ACCEPTS($path);
            }
            else {
                next if .negated;
                $seeking-negation = True if .pattern.ACCEPTS($path);
            }
        }
        $seeking-negation
    }

    method ignore-path(Str() $path) {
        return True if self.ignore-file($path);
        my @parts = $path.split('/');
        for @parts.produce(* ~ "/" ~ *) {
            return True if self.ignore-directory($_);
        }
        False
    }

    method walk(Str() $path) {
        sub recurse($path, $prefix) {
            for dir($path) {
                my $target = "$prefix$_.basename()";
                when .d {
                    unless self.ignore-directory($target) {
                        recurse($_, "$target/");
                    }
                }
                default {
                    unless self.ignore-file($target) {
                        take $target;
                    }
                }
            }
        }
        gather recurse($path, '');
    }
}

=begin pod

=head1 NAME

File::Ignore - Parsing and application of .gitignore-style ignore files

=head1 SYNOPSIS

=begin code :lang<raku>

use File::Ignore;

my $ignores = File::Ignore.parse: q:to/IGNORE/
  # Output
  *.[ao]
  build/**

  # Editor files
  *.swp
  IGNORE

for $ignores.walk($some-dir) {
    say "Did not ignore file $_";
}

say $ignores.ignore-file('src/foo.c');      # False
say $ignores.ignore-file('src/foo.o');      # True
say $ignores.ignore-directory('src');       # False
say $ignores.ignore-directory('build');     # True

=end code

=head1 DESCRIPTION

Parses ignore rules, of the style found in C<.gitignore> files, and allows
files and directories to be tested against the rules. Can also walk a
directory and return all files that are not ignored.

=head1 USAGE

=head2 Pattern syntax

The following pattern syntax is supported for matching within a path segment
(that is, between slashes):

=begin table

?       Matches any character in a path segment
*       Matches zero or more characters in a path segment
[abc]   Character class; matches a, b, or c
[!0]    Negated character class; matches anything but 0
[a-z]   Character ranges inside of character classes

=end table

Additionally, C<**> is supported to match zero or more path segments. Thus, the
rule C< a/**/b> will match C<a/b>, C<a/x/b>, C<a/x/y/b>, etc.

=head2 Construction

The C<parse> method can be used in order to parse rules read in from an ignore
file. It breaks the input up in to lines, and ignores lines that start with a
C<#>, along with lines that are entirely whitespace.

=begin code :lang<raku>

my $ignores = File::Ignore.parse(slurp('.my-ignore'));
say $ignores.WHAT; # File::Ignore

=end code

Alternatively, C<File::Ignore> can be constructed using the C<new> method and
passing in an array of rules:

=begin code :lang<raku>

my $ignores = File::Ignore.new(rules => <*.swp *.[ao]>);

=end code

This form treats everything it is given as a rule, not applying any comment or
empty line syntax rules.

=head2 Walking files with ignores applied

The C<walk> method takes a path as a C<Str> and returns a C<Seq> of paths in that
directory that are not ignored. Both C<.> and C<..> are excluded, as is usual
with the Raku C<dir> function.

=head2 Use with your own walk logic

The C<ignore-file> and C<ignore-directory> methods are used by C<walk> in order
to determine if a file or directory should be ignored. Any rule that ends in
a C</> is considered as only applying to a directory name, and so will not be
considered by C<ignore-file>. These methods are useful if you need to write
your own walking logic.

There is an implicit assumption that this module will be used when walking
over directories to find files. The key implication is that it expects a
directory will be tested with C<ignore-directory>, and that programs will
not traverse the files within that directory if the result is C<True>. Thus:

=begin code :lang<raku>

my $ignores = File::Ignore.new(rules => ['bin/']);
say $ignores.ignore-directory('bin');

=end code

Will, unsurprisingly, produce C<True>. However:

=begin code :lang<raku>

my $ignores = File::Ignore.new(rules => ['bin/']);
say $ignores.ignore-file('bin/x');

=end code

Will produce C<False>, since no ignore rule explicitly ignores that file. Note,
however, that a rule such as C<bin/**> would count as explicitly ignoring the
file (but would not ignore the C<bin> directory itself).

=head2 Using File::Ignore in non-walk scenarios

Sometimes it is desirable to apply the ignore rules against an existing list
of paths. For example, a C<find> command run on a remote server produces a set
of paths. Calling C<ignore-file> on each of these will not work reliably,
thanks to the assumption that it will never be asked about files in a directory
that would be ignored by C<ignore-directory>.

The C<ignore-path> method not only checks that a file should be ignored, but
also checks if any of the directories making up the path should be ignored.
This means it is safe to apply it to a simple list of paths, in a non-walk
scenario.

=begin code :lang<raku>

    my $ignores = File::Ignore.new(rules => ['bin/']);
    say $ignores.ignore-file('bin/x');  # False
    say $ignores.ignore-path('bin/x');  # True

=end code

=head2 Negation

A rule can be negated by placing a C<!> before it. Negative rules are ignored
until a file or directory matches a positive rule. Then, only negative rules
are considered, to see if it is then un-ignored. If a matching negative rule
is found, positive rules continue to be searched.

Therefore, these two rules:

=begin code

foo/bar/*
!foo/bar/ok

=end code

Would ignore everything in C<foo/bar/> except C<ok>. However:

=begin code

!foo/bar/ok
foo/bar/*

=end code

Would not work because the negation comes before the ignore. Further, negated
file ignores cannot override directory ignores, so:

=begin code

foo/bar/
!foo/bar/ok

=end code

Would also not work; the trailing C<*> is required.

=head2 Thread safety

Once constructed, a C<File::Ignore> object is immutable, and thus it is safe to
use an instance of it concurrently (for example, to call C<walk> on the same
instance in two threads). Construction, either through C<new> or C<parse>, is
also thread safe.

=head1 AUTHOR

Jonathan Worthington

=head1 COPYRIGHT AND LICENSE

Copyright 2016 - 2017 Jonathan Worthington

Copyright 2024 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
