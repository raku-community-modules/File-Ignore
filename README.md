[![Actions Status](https://github.com/raku-community-modules/File-Ignore/actions/workflows/linux.yml/badge.svg)](https://github.com/raku-community-modules/File-Ignore/actions) [![Actions Status](https://github.com/raku-community-modules/File-Ignore/actions/workflows/macos.yml/badge.svg)](https://github.com/raku-community-modules/File-Ignore/actions) [![Actions Status](https://github.com/raku-community-modules/File-Ignore/actions/workflows/windows.yml/badge.svg)](https://github.com/raku-community-modules/File-Ignore/actions)

NAME
====

File::Ignore - Parsing and application of .gitignore-style ignore files

SYNOPSIS
========

```raku
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
```

DESCRIPTION
===========

Parses ignore rules, of the style found in `.gitignore` files, and allows files and directories to be tested against the rules. Can also walk a directory and return all files that are not ignored.

USAGE
=====

Pattern syntax
--------------

The following pattern syntax is supported for matching within a path segment (that is, between slashes):

<table class="pod-table">
<tbody>
<tr> <td>?</td> <td>Matches any character in a path segment</td> </tr> <tr> <td>*</td> <td>Matches zero or more characters in a path segment</td> </tr> <tr> <td>[abc]</td> <td>Character class; matches a, b, or c</td> </tr> <tr> <td>[!0]</td> <td>Negated character class; matches anything but 0</td> </tr> <tr> <td>[a-z]</td> <td>Character ranges inside of character classes</td> </tr>
</tbody>
</table>

Additionally, `**` is supported to match zero or more path segments. Thus, the rule `a/**/b` will match `a/b`, `a/x/b`, `a/x/y/b`, etc.

Construction
------------

The `parse` method can be used in order to parse rules read in from an ignore file. It breaks the input up in to lines, and ignores lines that start with a `#`, along with lines that are entirely whitespace.

```raku
my $ignores = File::Ignore.parse(slurp('.my-ignore'));
say $ignores.WHAT; # File::Ignore
```

Alternatively, `File::Ignore` can be constructed using the `new` method and passing in an array of rules:

```raku
my $ignores = File::Ignore.new(rules => <*.swp *.[ao]>);
```

This form treats everything it is given as a rule, not applying any comment or empty line syntax rules.

Walking files with ignores applied
----------------------------------

The `walk` method takes a path as a `Str` and returns a `Seq` of paths in that directory that are not ignored. Both `.` and `..` are excluded, as is usual with the Raku `dir` function.

Use with your own walk logic
----------------------------

The `ignore-file` and `ignore-directory` methods are used by `walk` in order to determine if a file or directory should be ignored. Any rule that ends in a `/` is considered as only applying to a directory name, and so will not be considered by `ignore-file`. These methods are useful if you need to write your own walking logic.

There is an implicit assumption that this module will be used when walking over directories to find files. The key implication is that it expects a directory will be tested with `ignore-directory`, and that programs will not traverse the files within that directory if the result is `True`. Thus:

```raku
my $ignores = File::Ignore.new(rules => ['bin/']);
say $ignores.ignore-directory('bin');
```

Will, unsurprisingly, produce `True`. However:

```raku
my $ignores = File::Ignore.new(rules => ['bin/']);
say $ignores.ignore-file('bin/x');
```

Will produce `False`, since no ignore rule explicitly ignores that file. Note, however, that a rule such as `bin/**` would count as explicitly ignoring the file (but would not ignore the `bin` directory itself).

Using File::Ignore in non-walk scenarios
----------------------------------------

Sometimes it is desirable to apply the ignore rules against an existing list of paths. For example, a `find` command run on a remote server produces a set of paths. Calling `ignore-file` on each of these will not work reliably, thanks to the assumption that it will never be asked about files in a directory that would be ignored by `ignore-directory`.

The `ignore-path` method not only checks that a file should be ignored, but also checks if any of the directories making up the path should be ignored. This means it is safe to apply it to a simple list of paths, in a non-walk scenario.

```raku
    my $ignores = File::Ignore.new(rules => ['bin/']);
    say $ignores.ignore-file('bin/x');  # False
    say $ignores.ignore-path('bin/x');  # True
```

Negation
--------

A rule can be negated by placing a `!` before it. Negative rules are ignored until a file or directory matches a positive rule. Then, only negative rules are considered, to see if it is then un-ignored. If a matching negative rule is found, positive rules continue to be searched.

Therefore, these two rules:

    foo/bar/*
    !foo/bar/ok

Would ignore everything in `foo/bar/` except `ok`. However:

    !foo/bar/ok
    foo/bar/*

Would not work because the negation comes before the ignore. Further, negated file ignores cannot override directory ignores, so:

    foo/bar/
    !foo/bar/ok

Would also not work; the trailing `*` is required.

Thread safety
-------------

Once constructed, a `File::Ignore` object is immutable, and thus it is safe to use an instance of it concurrently (for example, to call `walk` on the same instance in two threads). Construction, either through `new` or `parse`, is also thread safe.

AUTHOR
======

Jonathan Worthington

COPYRIGHT AND LICENSE
=====================

Copyright 2016 - 2017 Jonathan Worthington

Copyright 2024 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

