use JSON::Fast;

module RpmSpecMaker {
    multi sub generate-spec(Str $meta-text) is export {
        my $meta = from-json($meta-text);
        callwith($meta);
    }

    sub get-name($meta) is export {
        return "perl6-{ $meta<name>.subst: /'::'/, '-', :g }";
    }

    sub get-directory($package-name --> IO::Path) is export {
        return "packages/$package-name".IO;
    }

    multi sub generate-spec($meta --> Str) is export {
        my $package-name = get-name($meta);
        my $version = $meta<version> eq '*' ?? '0.1' !! $meta<version>;
        my $source-url = $meta<source-url> || $meta<support><source>;
        $meta<license> //= '';

        my $dir = get-directory($package-name);
        my $source-dir = "{$package-name}-$version";
        my $tar-name = "{$package-name}-$version.tar.xz";

        die "$dir does not exists" unless $dir.e;
        my @files = fetch-source(:$package-name, :$source-url, :$source-dir, :$dir, :$tar-name);
        my $license-file = @files.grep({$_ eq 'LICENSE' or $_ eq 'LICENCE'}).first // '';

        return fill-template(
            :$meta,
                :$package-name,
                :$version,
                :$tar-name,
                :$source-url,
                :$license-file,
            );
    }

    sub fetch-source(:$package-name!, :$source-url!, :$source-dir!, IO::Path :$dir!, :$tar-name! --> Seq) is export {
        if not $source-url {
            note "$package-name does not have a source-url!";
            return;
        }

        if $source-url.starts-with('git://') or $source-url.ends-with('.git') {
            run <git clone>, $source-url, "$dir/$source-dir" unless $dir.add($source-dir).e;
            run <tar --exclude=.git -cJf>, $tar-name, $source-dir, :cwd($dir) unless $dir.add($tar-name).e;
        }
        else {
            run 'curl', '-s', $source-url, '-o', "$dir/$tar-name" unless $dir.add($tar-name).e;
            run 'tar', 'xf', $tar-name, :cwd($dir);

            my @top-level-dirs = $dir.dir.grep(* ~~ :d);
            die "Too many top level directories: @top-level-dirs" if @top-level-dirs.elems != 1;
            my $top-level-dir = @top-level-dirs[0].basename;

            "$dir/$top-level-dir".IO.rename("$dir/$source-dir");
            run 'tar', 'cJf', $tar-name, $source-dir, :cwd($dir);
        }

        return run(<tar tf>, "$dir/$tar-name", :out).out.lines.map(*.substr($source-dir.chars + 1));

        CATCH {
            default {
                note "Failed to fetch $source-url";
                .rethrow;
            }
        }
    }

    sub provides(:$meta!) is export {
        my @provides;
        return ($meta<name>, |$meta<provides>.keys).unique.sort.map({"Provides:       perl6($_)"}).join("\n");
    }

    sub map-dependency($requires is copy) is export {
        my %adverbs = flat ($requires ~~ s:g/':' $<key> = (\w+) '<' $<value> = (<-[>]>+) '>'//)
                .map({$_<key>.Str, $_<value>.Str});
        given %adverbs<from> {
            when 'native' {
                if %adverbs<ver> {
                    my $lib = $*VM.platform-library-name($requires.IO, :version(Version.new(%adverbs<ver>)));
                    my $path = </usr/lib64 /lib64 /usr/lib /lib>.first({$_.IO.add($lib).e});
                    if $path {
                        my $proc = run '/usr/lib/rpm/find-provides', :in, :out;
                        $proc.in.say($path.IO.add($lib).resolve.Str);
                        $proc.in.close;
                        $proc.out.lines;
                    }
                    else {
                        note "Falling back to depending on the library path as I couldn't find $lib";
                        '%{_libdir}/' ~ $*VM.platform-library-name($requires.IO)
                    }
                }
                else {
                    note "Package doesn't specify a library version, so I have to fall back to depending on library path.";
                    '%{_libdir}/' ~ $*VM.platform-library-name($requires.IO)
                }
            }
            when 'bin'    { '%{_bindir}/' ~ $requires }
            default       { "perl6($requires)" }
        }
    }

    sub requires(:$meta!) is export {
        return "Requires:       perl6 >= 2016.12" if not $meta<depends>;

        my @requires = 'perl6 >= 2016.12';
        @requires.append: flat $meta<depends>.map({ map-dependency($_) })
                if $meta<depends> ~~ Positional;
        @requires.append: flat $meta<depends><runtime><requires>.map({ map-dependency($_) })
                if $meta<depends> ~~ Associative;
        return @requires.map({"Requires:       $_"}).join("\n");
    }

    sub build-requires(:$meta!) is export {
        my @requires = 'rakudo >= 2017.04.2';

        if $meta<depends> {
            @requires.append: flat $meta<depends>.map({ map-dependency($_) })
                    if $meta<depends> ~~ Positional;
            @requires.append: flat $meta<depends><build><requires>.map({ map-dependency($_) })
                    if $meta<depends> ~~ Associative;
        }

        @requires.append: flat $meta<build-depends>.map({ map-dependency($_) })
                if $meta<build-depends>;
        @requires.push: 'Distribution::Builder' ~ $meta<builder> if $meta<builder>;
        return @requires.map({"BuildRequires:  $_"}).join("\n");
    }

    sub fill-template(:$meta!, :$package-name!, :$tar-name!, :$version!, :$source-url!, :$license-file!) is export {
        my $provides = provides(:$meta);
        my $requires = requires(:$meta);
        my $build-requires = build-requires(:$meta);
        my $summary = $meta<description>;
        $summary.=chop if $summary and $summary.ends-with('.');
        my $LICENSE = $license-file ?? "\n%license $license-file" !! '';
        my $RPM_BUILD_ROOT = '$RPM_BUILD_ROOT'; # Workaround for https://rt.perl.org/Ticket/Display.html?id=127226
        q:s:to/TEMPLATE/
        #
        # spec file for package $package-name
        #
        # Copyright (c) 2017 SUSE LINUX Products GmbH, Nuernberg, Germany.
        #
        # All modifications and additions to the file contributed by third parties
        # remain the property of their copyright owners, unless otherwise agreed
        # upon. The license for this file, and modifications and additions to the
        # file, is the same license as for the pristine package itself (unless the
        # license for the pristine package is not an Open Source License, in which
        # case the license is the MIT License). An "Open Source License" is a
        # license that conforms to the Open Source Definition (Version 1.9)
        # published by the Open Source Initiative.

        # Please submit bugfixes or comments via http://bugs.opensuse.org/
        #

        Name:           $package-name
        Version:        $version
        Release:        1.1
        License:        $meta<license>
        Summary:        $summary
        Url:            $source-url
        Group:          Development/Languages/Other
        Source:         $tar-name
        BuildRequires:  fdupes
        $build-requires
        $requires
        $provides
        BuildRoot:      %{_tmppath}/%{name}-%{version}-build

        %description
        $summary

        %prep
        %setup -q

        %build

        %install
        RAKUDO_MODULE_DEBUG=1 RAKUDOE_PRECOMP_VERBOSE=1 RAKUDO_RERESOLVE_DEPENDENCIES=0 raku --ll-exception %{_datadir}/perl6/bin/install-perl6-dist \\
                --to=$RPM_BUILD_ROOT%{_datadir}/perl6/vendor \\
                --for=vendor \\
                --from=.
        %fdupes %{buildroot}/%{_datadir}/perl6/vendor

        rm -f %{buildroot}%{_datadir}/perl6/vendor/bin/*-j
        rm -f %{buildroot}%{_datadir}/perl6/vendor/bin/*-js
        find %{buildroot}/%{_datadir}/perl6/vendor/bin/ -type f -exec sed -i -e '1s:!/usr/bin/env :!/usr/bin/:' '{}' \;

        %files
        %defattr(-,root,root)
        %doc README.md$LICENSE
        %{_datadir}/perl6/vendor

        %changelog
        TEMPLATE
    }

    =begin comment
    When collecting a tar file not in git the file name may not be correct.
    To resolve this we will pack trhe file and then repack it with file name and configuration we want.
    =end comment

}
